@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/hermetic_workspace.dart';

/// Criterion 6 (PDR §6.6): the controller never writes over SQL and never
/// touches `.beads/hooks/` (gc owns those files).
///
/// Two structural witnesses over a full create/update/close lifecycle run
/// against a real `bd` binary in a hermetic workspace:
///
/// 1. **No SQL writes, ever.** The lifecycle is driven entirely through the
///    [GridRuntimeFactory] / [CliSnapshotReader] read path and the
///    [BdCliService] mutation path. In embedded mode the factory resolves no
///    Dolt endpoint, so there is no SQL connection to write through at all —
///    and [BdCliService] holds no Dolt dependency by construction (it cannot
///    emit a SQL string). We assert the read path is [ReadPath.cli] (no SQL
///    socket opened) and that the lifecycle still converges through bd alone.
///
/// 2. **No `.beads/hooks/` mutation.** Snapshot the size, mtime, and content
///    hash of every file under `<temp>/.beads/hooks/` before and after a full
///    controller run + mutations; assert byte-identical.
void main() {
  test(
    'a full lifecycle uses the CLI read path only — no SQL write socket opened',
    () async {
      final ws = await HermeticWorkspace.create(prefix: 'grid_it_nosql_');
      addTearDown(ws.dispose);

      // The factory chooses the read path from the workspace mode. Embedded
      // (direct) mode → CLI path, no Dolt pool, so there is no SQL connection
      // at all — writes-over-SQL is structurally impossible here.
      final bundle = await GridRuntimeFactory.build(workspace: ws.workspace);
      addTearDown(bundle.shutdown);
      expect(
        bundle.readPath,
        ReadPath.cli,
        reason:
            'embedded workspace must use the bd CLI read path (no SQL '
            'socket) — SQL writes are impossible when no SQL connection exists',
      );

      await bundle.runtime.start();

      // Drive a full create → update → close lifecycle through bd only.
      final bd = BdCliService(ProcessBdRunner(workspaceRoot: ws.rootPath));
      final id = await bd.create(
        title: 'sark',
        type: IssueType.task,
        priority: 2,
      );
      await bd.update(id, priority: 1, title: 'sark (commander)');
      await bd.close(id, reason: 'derezzed');

      // Converge the controller and confirm it observed the lifecycle entirely
      // through the CLI path.
      await bundle.runtime.requery();
      final bead = bundle.runtime.bead(id);
      expect(bead, isNotNull);
      expect(bead!.isClosed, isTrue);
      expect(bead.title, 'sark (commander)');
      expect(bead.priority, 1);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'BdCliService is structurally SQL-free across the full mutation surface',
    () async {
      // A controller-level witness complementing the unit-level proof: every
      // argv this service builds for the create/update/close/dep/batch surface
      // is a bd subcommand — never a SQL verb. (The service holds no Dolt
      // dependency; it cannot connect to or write SQL.)
      final bd = BdCliService(ProcessBdRunner(workspaceRoot: '/tmp'));
      final argvs = <List<String>>[
        bd.createArgs(title: 't', type: IssueType.task, priority: 1),
        bd.updateArgs('id', title: 'x', status: BeadStatus.inProgress),
        bd.closeArgs('id', reason: 'done'),
        bd.depAddArgs('a', 'b', DependencyType.blocks),
        bd.batchArgs(),
        bd.readyArgs(),
        bd.exportArgs(),
        bd.queryArgs('status:open'),
      ];
      const sqlVerbs = {
        'insert',
        'update',
        'delete',
        'replace',
        'merge',
        'call',
        'drop',
        'alter',
        'create', // SQL DDL CREATE — distinct from bd's `create` subcommand…
      };
      for (final argv in argvs) {
        // …so we only flag SQL verbs that appear *after* the bd subcommand,
        // never the leading subcommand token itself.
        final head = argv.first;
        expect(
          head,
          isNot(contains(';')),
          reason: 'no statement batching in a bd subcommand',
        );
        for (final token in argv.skip(1)) {
          final lowered = token.toLowerCase();
          expect(
            sqlVerbs.contains(lowered),
            isFalse,
            reason: 'bd argv "$argv" must carry no SQL verb token',
          );
        }
        // The subcommand itself is a known bd verb, never raw SQL.
        expect(
          head,
          isIn(<String>[
            'create',
            'update',
            'close',
            'dep',
            'batch',
            'ready',
            'export',
            'query',
          ]),
        );
      }
    },
  );

  test(
    'a full controller run + mutations leaves .beads/hooks/ byte-identical',
    () async {
      final ws = await HermeticWorkspace.create(prefix: 'grid_it_hooks_');
      addTearDown(ws.dispose);

      final before = _snapshotDir(ws.hooksDir);
      expect(
        before,
        isNotEmpty,
        reason: 'bd init installs hook scripts — sanity check the fixture',
      );

      // Build and start a real runtime, then run a full create/update/close
      // lifecycle through bd. None of this may touch the gc-owned hooks.
      final bundle = await GridRuntimeFactory.build(workspace: ws.workspace);
      addTearDown(bundle.shutdown);
      await bundle.runtime.start();

      final bd = BdCliService(ProcessBdRunner(workspaceRoot: ws.rootPath));
      final a = await bd.create(
        title: 'clu',
        type: IssueType.task,
        priority: 1,
      );
      final b = await bd.create(
        title: 'tron',
        type: IssueType.task,
        priority: 1,
      );
      // a depends-on b → a is blocked until b closes. Close in dependency order
      // (b first) so the close path exercises a real blocker-resolution edge.
      await bd.depAdd(a, b);
      await bd.update(a, priority: 2);
      await bd.close(b, reason: 'derezzed');
      await bd.close(a, reason: 'isolated');
      await bundle.runtime.requery();

      final after = _snapshotDir(ws.hooksDir);
      expect(
        after,
        equals(before),
        reason:
            'the_grid must never modify, add, or remove any file under '
            '.beads/hooks/ (gc owns them)',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

/// A `relativePath → _FileWitness` map of every regular file under [dir],
/// recursively. Captures size, mtime, and the exact bytes so a touch, a
/// rewrite, an addition, or a removal all surface as a map inequality (the
/// custom equality runs an FNV-1a content digest plus a length check — no
/// external hashing dependency needed).
Map<String, _FileWitness> _snapshotDir(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) return const {};
  final out = <String, _FileWitness>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: dir);
    final stat = entity.statSync();
    final bytes = entity.readAsBytesSync();
    out[rel] = _FileWitness(
      size: stat.size,
      mtimeMicros: stat.modified.microsecondsSinceEpoch,
      contentDigest: _fnv1a(bytes),
      contentLength: bytes.length,
    );
  }
  return out;
}

/// A size + mtime + content witness with value equality, so two snapshot maps
/// compare structurally under `equals(before)`.
class _FileWitness {
  const _FileWitness({
    required this.size,
    required this.mtimeMicros,
    required this.contentDigest,
    required this.contentLength,
  });

  final int size;
  final int mtimeMicros;
  final int contentDigest;
  final int contentLength;

  @override
  bool operator ==(Object other) =>
      other is _FileWitness &&
      other.size == size &&
      other.mtimeMicros == mtimeMicros &&
      other.contentDigest == contentDigest &&
      other.contentLength == contentLength;

  @override
  int get hashCode =>
      Object.hash(size, mtimeMicros, contentDigest, contentLength);

  @override
  String toString() =>
      'size=$size mtime=$mtimeMicros len=$contentLength digest=$contentDigest';
}

/// FNV-1a 64-bit over [bytes]. Combined with the explicit length check it gives
/// a byte-identity witness without pulling in a crypto dependency.
int _fnv1a(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;
  for (final byte in bytes) {
    hash = (hash ^ byte) & mask;
    hash = (hash * prime) & mask;
  }
  return hash;
}
