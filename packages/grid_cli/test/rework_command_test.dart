import 'dart:convert';

import 'package:grid_cli/grid_cli.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// Offline proofs for `grid rework` (tg-x1j) — Fakes, not mocks, no live
/// state, no real `bd`, NO writes to any live store. The DoD:
///
///  1. rework on a positively-closed bead re-keys `work_bead` to
///     `bead#rN` through the chokepoint and reports round N (a);
///  2. an OPEN, ACTIVELY-RUNNING session refuses LOUD, zero writes (b);
///  3. an OPEN session PARKED AT A GATE (nothing running) is safe to rework
///     (the v2 gate-resolve transition's trigger) — proceeds;
///  4. the ~3-round cap refuses LOUD, zero writes (c);
///  5. --note lands on the WORK bead (a separate workspace/store) under a
///     ROUND N header (d).
void main() {
  group('grid rework — v1 acceptance', () {
    test('(a) a positively-closed session re-keys + reports round 1', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', closed: true),
      ]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      expect(out.join('\n'), contains('round 1'));
      expect(out.join('\n'), contains('tgdog-s1'));
      final updates = state.writes.where((c) => c.first == 'update').toList();
      expect(updates, hasLength(1));
      expect(updates.single, containsAllInOrder(['update', 'tgdog-s1']));
      expect(
        updates.single,
        containsAllInOrder(['--actor', 'grid-controller']),
      );
      final metaIdx = updates.single.indexOf('--metadata');
      final meta =
          jsonDecode(updates.single[metaIdx + 1]) as Map<String, dynamic>;
      expect(meta, {'work_bead': 'tg-9#r1'});
    });

    test(
      '(b) an OPEN, actively-running session refuses LOUD (zero writes)',
      () async {
        final state = _FakeStore([
          _session('tgdog-s1', workBead: 'tg-9', running: true),
        ]);
        final errs = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          out: (_) {},
          err: errs.add,
        );

        expect(code, isNonZero);
        expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
        expect(state.writes, isEmpty);
      },
    );

    test('(b) an OPEN session with no cursor at all (freshly spawning) '
        'refuses LOUD (zero writes)', () async {
      final state = _FakeStore([_session('tgdog-s1', workBead: 'tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
      expect(state.writes, isEmpty);
    });

    test('an OPEN session parked at a gate (nothing running) proceeds — '
        'the v2 gate-resolve transition\'s trigger', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', gated: true),
      ]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      final updates = state.writes.where((c) => c.first == 'update').toList();
      expect(updates, hasLength(1));
      final metaIdx = updates.single.indexOf('--metadata');
      final meta =
          jsonDecode(updates.single[metaIdx + 1]) as Map<String, dynamic>;
      expect(meta, {'work_bead': 'tg-9#r1'});
    });

    test('(c) the ~3-round cap refuses LOUD (zero writes)', () async {
      final state = _FakeStore([
        _session('tgdog-r1', workBead: 'tg-9#r1', closed: true),
        _session('tgdog-r2', workBead: 'tg-9#r2', closed: true),
        _session('tgdog-r3', workBead: 'tg-9#r3', closed: true),
        _session('tgdog-cur', workBead: 'tg-9', closed: true),
      ]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('cap 3'));
      expect(state.writes, isEmpty);
    });

    test(
      'round numbering: an existing #r1 makes the next rework round 2',
      () async {
        final state = _FakeStore([
          _session('tgdog-r1', workBead: 'tg-9#r1', closed: true),
          _session('tgdog-cur', workBead: 'tg-9', closed: true),
        ]);
        final out = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          out: out.add,
          err: (_) {},
        );

        expect(code, 0);
        expect(out.join('\n'), contains('round 2'));
        final updates = state.writes.where((c) => c.first == 'update').toList();
        final metaIdx = updates.single.indexOf('--metadata');
        final meta =
            jsonDecode(updates.single[metaIdx + 1]) as Map<String, dynamic>;
        expect(meta, {'work_bead': 'tg-9#r2'});
      },
    );

    test(
      'requires --state-workspace (refused, exit 64, zero writes)',
      () async {
        final errs = <String>[];
        final code = await runRework(
          beadId: 'tg-9',
          out: (_) {},
          err: errs.add,
        );
        expect(code, 64);
        expect(errs.join('\n'), contains('--state-workspace is required'));
      },
    );

    test('refuses (non-zero, zero writes) when no session is found', () async {
      final state = _FakeStore([]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-nope',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('no session found'));
      expect(state.writes, isEmpty);
    });

    test(
      'refuses (non-zero, zero writes) on more than one current session',
      () async {
        final state = _FakeStore([
          _session('tgdog-a', workBead: 'tg-9', closed: true),
          _session('tgdog-b', workBead: 'tg-9', closed: true),
        ]);
        final errs = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          out: (_) {},
          err: errs.add,
        );

        expect(code, isNonZero);
        expect(errs.join('\n'), contains('ambiguous'));
        expect(state.writes, isEmpty);
      },
    );
  });

  group('grid rework — (d) --note lands on the WORK bead', () {
    test('appends the finding under a ROUND N header, into the WORK '
        'workspace (a SEPARATE store from the state workspace)', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', closed: true),
      ]);
      final work = _FakeStore([
        Bead(id: 'tg-9', title: 'work', issueType: IssueType.task),
      ]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        note: 'the committee rejected on validation_plan drift',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      // The state store gets exactly the re-key write.
      expect(state.writes.where((c) => c.first == 'update'), hasLength(1));
      // The WORK store gets exactly one append-notes write, on the WORK bead.
      final workUpdates = work.writes
          .where((c) => c.first == 'update')
          .toList();
      expect(workUpdates, hasLength(1));
      expect(workUpdates.single, containsAllInOrder(['update', 'tg-9']));
      final noteIdx = workUpdates.single.indexOf('--append-notes');
      expect(noteIdx, greaterThan(-1));
      final note = workUpdates.single[noteIdx + 1];
      expect(note, contains('ROUND 1'));
      expect(note, contains('the committee rejected on validation_plan drift'));
    });

    test('--note without a discoverable work workspace refuses LOUD before '
        'any write (the re-key never happens half-done)', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', closed: true),
      ]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        note: 'a finding',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        workspacePath: '/definitely/not/a/beads/workspace',
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('--workspace'));
      expect(state.writes, isEmpty);
    });
  });
}

/// A direct/embedded workspace (no real `.beads/` on disk needed — the bd
/// runner is faked).
BeadsWorkspace _ws(String database) => BeadsWorkspace(
  root: '/fake/$database',
  mode: DoltMode.direct,
  database: database,
  gtRoot: null,
  endpoint: null,
);

/// Builds a `type=session` bead carrying the `work_bead` linkage, optionally
/// closed, and optionally carrying a per-node cursor entry (`running` or
/// `gated`, mutually exclusive in these tests) at a fixed nodePath.
Bead _session(
  String id, {
  required String workBead,
  bool closed = false,
  bool running = false,
  bool gated = false,
}) => Bead(
  id: id,
  title: 'grid session $workBead',
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  createdAt: DateTime.utc(2026, 7, 3, 12),
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBead,
    if (running) ...nodeStateMetadata('$workBead/agent', StepState.running),
    if (gated) ...nodeStateMetadata('$workBead/route', StepState.gated),
  },
);

/// A fake [BdRunner] over a fixed set of staged beads (Fakes, not mocks): the
/// `export` read returns the staged beads as JSONL; mutations return a canned
/// envelope and are recorded so a test can assert a refusal performed ZERO
/// writes.
class _FakeStore implements BdRunner {
  _FakeStore(this._beads);

  final List<Bead> _beads;
  final List<List<String>> calls = <List<String>>[];

  /// Every recorded invocation that is NOT the `export` read — i.e. the writes.
  List<List<String>> get writes =>
      calls.where((c) => c.isNotEmpty && c.first != 'export').toList();

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    final cmd = args.isNotEmpty ? args.first : '';
    if (cmd == 'export') {
      final jsonl = _beads.map((b) => jsonEncode(b.toJson())).join('\n');
      return Future<BdResult>.value(
        BdResult(exitCode: 0, stdout: jsonl, stderr: ''),
      );
    }
    final id = args.length >= 2 ? args[1] : '';
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{"id":"$id"}}',
        stderr: '',
      ),
    );
  }
}
