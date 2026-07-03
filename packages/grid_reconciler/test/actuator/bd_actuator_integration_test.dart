@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_reconciler/src/actuator/bd_actuator.dart';
import 'package:grid_reconciler/src/convergence/convergence_metadata.dart';
import 'package:grid_reconciler/src/convergence/idempotency_key.dart';
import 'package:grid_reconciler/src/convergence/reconciler_action.dart';
import 'package:grid_reconciler/src/projections/convergence.dart';
import 'package:grid_reconciler/src/reducer/reduce_result.dart';
import 'package:test/test.dart';

/// A real persistent-pour round-trip against a hermetic `bd init` workspace
/// (embedded mode — no server, no creds, never the live tg). Proves the A15
/// correction end-to-end: a convergence pour through [BdActuator] lands in the
/// **`issues`** table (PERSISTENT), not the ephemeral `wisps` table, and that a
/// second apply of the same idempotency key ADOPTS the existing wisp rather
/// than pouring a duplicate.
///
/// Self-skips when `bd` is not on PATH (mirrors beads_dart's hermetic
/// integration suite). NEVER touches a live workspace.
void main() {
  late Directory root;
  late BdCliService bd;

  setUpAll(() {
    final probe = Process.runSync('bd', ['version']);
    if (probe.exitCode != 0) {
      // ignore: avoid_print
      print('bd not usable — skipping persistent-pour integration test');
    }
  });

  setUp(() async {
    root = Directory(
      (await Directory.systemTemp.createTemp(
        'grid_actuator_it_',
      )).resolveSymbolicLinksSync(),
    );
    final init = await Process.run(
      'bd',
      ['init', '--prefix', 'gactit'],
      workingDirectory: root.path,
      environment: {...Platform.environment, 'BD_JSON_ENVELOPE': '1'},
      includeParentEnvironment: false,
      runInShell: false,
    );
    if (init.exitCode != 0) {
      await root.delete(recursive: true);
      fail('bd init failed: ${init.stderr}\n${init.stdout}');
    }
    bd = BdCliService(ProcessBdRunner(workspaceRoot: root.path));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// A CLI-export-based live idempotency probe: re-reads the whole workspace
  /// (`bd export --all`) and scans the parent's children for the key. This is
  /// the hermetic-mode stand-in for the SQL probe (no server here); it is
  /// genuinely live (a fresh read each call), which is all the find-before-pour
  /// contract requires.
  Future<String?> exportProbe(String parentId, String key) async {
    final snapshot = await bd.exportAll();
    final childIds = {
      for (final dep in snapshot.dependencies)
        if (dep.type == DependencyType.parentChild &&
            dep.dependsOnId == parentId)
          dep.issueId,
    };
    for (final bead in snapshot.beads) {
      if (!childIds.contains(bead.id)) continue;
      if (bead.metadata[wispIdempotencyKeyField] == key) return bead.id;
    }
    return null;
  }

  /// Builds the Convergence value the actuator needs. The hermetic `bd init`
  /// workspace does not register the `convergence` custom type, so the root is
  /// a plain `task` bead here and `Convergence.project` (which requires the
  /// type) cannot run — we hand-build the projection instead. The pour path
  /// only reads `wisps` for activation/burn (neither applies to a fresh
  /// visible pour), so an empty wisp list is sufficient.
  Future<Convergence> project(String rootId) async {
    final snapshot = await bd.exportAll();
    final root = snapshot.beads.singleWhere((b) => b.id == rootId);
    return Convergence(
      id: root.id,
      title: root.title,
      status: root.status,
      metadata: ConvergenceMetadata.decode(root.metadata),
    );
  }

  test(
    'a BdActuator pour is PERSISTENT (lands in issues) and re-pour adopts',
    () async {
      // The convergence root (a permanent task bead gc parents wisps under).
      final rootId = await bd.create(
        title: 'Convergence: integration probe',
        type: IssueType.task,
        priority: 1,
      );
      final key = idempotencyKey(rootId, 1);

      // A minimal vapor formula on disk, cooked at pour time.
      final formula = File('${root.path}/mol-it.formula.json');
      await formula.writeAsString('''
{
  "formula": "mol-it",
  "version": 1,
  "type": "workflow",
  "phase": "vapor",
  "vars": { "target": { "default": "tron" } },
  "steps": [
    { "id": "work", "title": "iterate on {{target}}", "type": "task", "priority": 1 }
  ]
}
''');

      final actuator = BdActuator(bd, exportProbe);

      // A direct (visible, non-speculative) iterate-style pour via the
      // pourSpeculative action with speculative:false would activate; use a
      // visible pour through the iterate path instead so the wisp is directly
      // queryable.
      final action =
          ReconcilerAction.pourSpeculative(
                convergenceBeadId: rootId,
                pour: WispPour(
                  parentBeadId: rootId,
                  formula: formula.path,
                  idempotencyKey: key,
                  iteration: 1,
                  vars: const {'target': 'tron'},
                ),
              )
              as PourSpeculativeAction;

      final out1 = await actuator.apply(
        ReduceResult.one(action),
        await project(rootId),
      );
      final wispId = out1.pouredWispId;
      expect(wispId, isNotNull);

      // PERSISTENT: the poured wisp is a committed issues row, NOT ephemeral.
      final snapshot = await bd.exportAll();
      final wisp = snapshot.beads.singleWhere((b) => b.id == wispId);
      expect(
        wisp.ephemeral,
        isFalse,
        reason: 'A15: a convergence pour is persistent (no --ephemeral)',
      );
      expect(wisp.metadata[wispIdempotencyKeyField], key);
      // pending_next_wisp was recorded on the root.
      final rootBead = snapshot.beads.singleWhere((b) => b.id == rootId);
      expect(rootBead.metadata[ConvergenceFields.pendingNextWisp], wispId);

      // Re-apply the SAME key: find-before-pour ADOPTS, no duplicate.
      final out2 = await actuator.apply(
        ReduceResult.one(action),
        await project(rootId),
      );
      expect(out2.pouredWispId, wispId, reason: 'idempotency adoption');

      final after = await bd.exportAll();
      final keyed = after.beads
          .where((b) => b.metadata[wispIdempotencyKeyField] == key)
          .toList();
      expect(keyed, hasLength(1), reason: 'no duplicate wisp for the same key');
    },
    skip: _bdMissing() ? 'bd not on PATH' : null,
  );
}

bool _bdMissing() {
  try {
    return Process.runSync('bd', ['version']).exitCode != 0;
  } on Object {
    return true;
  }
}
