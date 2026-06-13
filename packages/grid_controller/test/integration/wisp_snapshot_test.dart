@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/hermetic_workspace.dart';

/// The wisp/template snapshot-inclusion witness (the hermetic half of the
/// SQL-vs-CLI inclusion contract; the live half is the equivalence canary in
/// `sql_cli_equivalence_test.dart`).
///
/// **Snapshot semantics (both capture paths):** the COMPLETE graph — issues ∪
/// wisps, all statuses, including infra/template/gate-typed beads. Ephemeral
/// beads live in the separate `wisps`/`wisp_dependencies` tables (beads
/// internal/storage/dolt/ephemeral_routing.go) and `bd export` excludes them
/// — and templates — without `--all` (cmd/bd/export.go:96-126), so the M2
/// contract surfaces built on the snapshot (wispClosed detection,
/// closedWispCount, findByIdempotencyKey, validPendingNextWisp) all depend on
/// the inclusion proven here.
///
/// Pours an ephemeral wisp subtree exactly per the A15 recipe
/// (grid_reconciler/tool/wisp_pour_spike.sh): `bd cook --mode=runtime` →
/// graph plan whose root carries `parent_id` + `metadata.idempotency_key`
/// with gate-typed (speculative) child steps → `bd create --graph
/// --ephemeral`. Then asserts the CLI-path snapshot sees the whole subtree,
/// a `bd cook --persist` template proto, and the wisp root after close
/// (closed but still visible).
void main() {
  late HermeticWorkspace ws;
  late BdCliService bd;
  late ProcessBdRunner runner;
  late CliSnapshotReader reader;

  setUp(() async {
    ws = await HermeticWorkspace.create(prefix: 'grid_it_wisp_');
    runner = ProcessBdRunner(workspaceRoot: ws.rootPath);
    bd = BdCliService(runner);
    reader = CliSnapshotReader(bd);
  });

  tearDown(() => ws.dispose());

  test('an A15-poured ephemeral wisp subtree, a template proto, and a closed '
      'wisp are all visible in the CLI-path GraphSnapshot', () async {
    // --- the convergence root (a permanent bead; gc parents each
    // iteration's wisp under it) ---------------------------------------
    final rootId = await bd.create(
      title: 'Convergence: mol-converge-probe',
      type: IssueType.task,
      priority: 1,
    );
    final key = 'converge:$rootId:iter:1';

    // --- A15 step 1: resolve the formula (cook is read-only here) ------
    final formulaPath = p.join(ws.rootPath, 'mol-converge-probe.json');
    File(formulaPath).writeAsStringSync(
      jsonEncode({
        'formula': 'mol-converge-probe',
        'description': 'wisp snapshot inclusion witness',
        'version': 1,
        'type': 'workflow',
        'phase': 'vapor',
        'vars': {
          'target': {'description': 'what to converge on', 'default': 'io'},
        },
        'steps': [
          {
            'id': 'work',
            'title': 'iterate on {{target}}',
            'type': 'task',
            'priority': 1,
          },
          {
            'id': 'evaluate',
            'title': 'evaluate {{target}}',
            'type': 'task',
            'priority': 1,
            'needs': ['work'],
          },
        ],
      }),
    );
    final cook = await runner.run([
      'cook',
      formulaPath,
      '--mode=runtime',
      '--var',
      'target=tron',
      '--json',
    ]);
    expect(cook.exitCode, 0, reason: 'bd cook failed: ${cook.stderr}');
    final cooked = BdEnvelope.parse(cook.stdout).dataMap;
    final steps = (cooked['steps'] as List).cast<Map<String, dynamic>>();
    expect(steps, hasLength(2));

    // --- A15 step 2: build the graph plan — root with parent_id +
    // metadata.idempotency_key, steps poured as ready-excluded type `gate`
    // (the speculative shape) with the real type under gc.deferred_type ---
    final plan = {
      'commit_message': 'pour wisp $key',
      'nodes': [
        {
          'key': 'wisp',
          'title': 'Convergence wisp iter 1',
          'type': 'epic',
          'parent_id': rootId,
          'metadata': {'idempotency_key': key},
        },
        for (final step in steps)
          {
            'key': step['id'],
            'title': step['title'],
            'type': 'gate',
            'priority': step['priority'] ?? 2,
            'parent_key': 'wisp',
            'metadata': {'gc.deferred_type': step['type'] ?? 'task'},
          },
      ],
      'edges': [
        for (final step in steps)
          for (final need in (step['needs'] as List? ?? const []))
            {'from_key': step['id'], 'to_key': need, 'type': 'blocks'},
      ],
    };
    final planPath = p.join(ws.rootPath, 'plan.json');
    File(planPath).writeAsStringSync(jsonEncode(plan));

    // --- A15 step 3: pour atomically (one transaction) -----------------
    final pour = await runner.run([
      'create',
      '--graph',
      planPath,
      '--ephemeral',
      '--json',
      '--actor',
      'grid-controller',
    ]);
    expect(pour.exitCode, 0, reason: 'wisp pour failed: ${pour.stderr}');
    final ids = (BdEnvelope.parse(pour.stdout).dataMap['ids'] as Map)
        .cast<String, dynamic>();
    final wispId = ids['wisp'] as String;
    final stepIds = [ids['work'] as String, ids['evaluate'] as String];

    // --- a template proto (excluded from export without --all) ---------
    final persist = await runner.run([
      'cook',
      formulaPath,
      '--persist',
      '--json',
      '--actor',
      'grid-controller',
    ]);
    expect(
      persist.exitCode,
      0,
      reason: 'bd cook --persist failed: ${persist.stderr}',
    );
    final protoId =
        BdEnvelope.parse(persist.stdout).dataMap['proto_id'] as String;

    // --- the snapshot must contain ALL of it ----------------------------
    final snapshot = await reader.read();

    final wisp = snapshot.bead(wispId);
    expect(
      wisp,
      isNotNull,
      reason:
          'the poured ephemeral wisp root must appear in the snapshot — '
          'without it findByIdempotencyKey/closedWispCount are built on '
          'beads that are not there',
    );
    expect(wisp!.ephemeral, isTrue);
    expect(wisp.metadata['idempotency_key'], key);

    for (final stepId in stepIds) {
      final step = snapshot.bead(stepId);
      expect(
        step,
        isNotNull,
        reason:
            'gate-typed (speculative) step $stepId must appear — '
            'bd children hides it, the snapshot is the only enumeration',
      );
      expect(step!.ephemeral, isTrue);
      expect(step.issueType, IssueType.gate);
      expect(step.metadata['gc.deferred_type'], 'task');
    }

    // The parent-child edges: wisp → convergence root, steps → wisp.
    final edges = snapshot.dependencies
        .map((d) => '${d.issueId}->${d.dependsOnId} ${d.type.wire}')
        .toSet();
    expect(
      edges,
      contains('$wispId->$rootId parent-child'),
      reason:
          'the wisp root must carry its parent-child edge to the '
          'convergence root (the findByIdempotencyKey child scan walks it)',
    );
    for (final stepId in stepIds) {
      expect(edges, contains('$stepId->$wispId parent-child'));
    }

    // The persisted template proto is part of the complete graph too.
    expect(
      snapshot.bead(protoId),
      isNotNull,
      reason:
          'a bd cook --persist template proto must appear in the snapshot '
          '(--all lifts the default template exclusion, export.go:115)',
    );

    // --- close the wisp (steps first, then root) and re-read ------------
    for (final stepId in stepIds) {
      await bd.close(stepId, reason: 'convergence: iteration closed');
    }
    await bd.close(wispId, reason: 'convergence: closing root');

    final after = await reader.read();
    final closedWisp = after.bead(wispId);
    expect(
      closedWisp,
      isNotNull,
      reason:
          'a CLOSED wisp must remain visible (snapshot = all statuses) — '
          'closedWispCount/deriveIterationCount depend on it',
    );
    expect(closedWisp!.isClosed, isTrue);
    expect(closedWisp.ephemeral, isTrue);
    expect(closedWisp.metadata['idempotency_key'], key);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
