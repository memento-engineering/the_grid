import 'dart:convert';

import 'package:grid_cli/src/gate_command.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

/// Offline proofs for `grid gate` (committee-gate ls + resolve) — Fakes, not
/// mocks, no live state, no real `bd`, NO writes to any live store. The DoD:
///
///  1. **ls** lists every OPEN `type=gate` bead (with session / node / reason),
///     ignores CLOSED gates and non-gate beads, and prints a clear empty line —
///     performing ZERO writes;
///  2. **resolve** closes the named gate THROUGH the chokepoint carrying
///     `--actor grid-controller`, and refuses (non-zero exit, ZERO writes) when
///     the id is (a) not found, (b) not `type=gate`, (c) already closed, or
///     (d) not owned by the state substation.
void main() {
  group('grid gate ls', () {
    test('lists the OPEN gates and ignores closed gates + non-gate beads',
        () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'code/agent',
            reason: 'gating-F: Validation Plan failed'),
        _gate('tgdog-g2', blocks: 'tgdog-s2', node: 'code/verify',
            reason: 'grade spread >= 3'),
        // a CLOSED (already-resolved) gate — must NOT appear.
        _gate('tgdog-g0', blocks: 'tgdog-s0', node: 'code/agent',
            reason: 'old', closed: true),
        // a non-gate bead — must NOT appear.
        Bead(id: 'tgdog-w7', title: 'work', issueType: IssueType.task),
      ]);
      final out = <String>[];

      final code = await runGateLs(
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: out.add,
        err: out.add,
      );

      expect(code, 0);
      final text = out.join('\n');
      expect(text, contains('2 open gates'));
      expect(text, contains('tgdog-g1'));
      expect(text, contains('tgdog-s1'));
      expect(text, contains('code/agent'));
      expect(text, contains('gating-F: Validation Plan failed'));
      expect(text, contains('tgdog-g2'));
      expect(text, contains('grade spread >= 3'));
      // The closed gate + the non-gate bead are absent.
      expect(text, isNot(contains('tgdog-g0')));
      expect(text, isNot(contains('tgdog-w7')));
      // ls performs NO writes — only the `export` read reached the store.
      expect(store.writes, isEmpty);
    });

    test('prints a clear empty line when there are no open gates', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g0', blocks: 'tgdog-s0', node: 'code/agent',
            reason: 'old', closed: true),
      ]);
      final out = <String>[];

      final code = await runGateLs(
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: out.add,
        err: out.add,
      );

      expect(code, 0);
      expect(out.join('\n'), contains('no open gates'));
      expect(store.writes, isEmpty);
    });
  });

  group('grid gate resolve', () {
    test('closes the named gate through the chokepoint (--actor grid-controller)',
        () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'code/agent',
            reason: 'gating-F'),
      ]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        stateSubstation: 'tgdog',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      expect(out.join('\n'), contains('closed gate tgdog-g1'));
      // Exactly one write — a `bd close` on the gate, carrying the actor and the
      // resolve reason.
      final closes = store.writes.where((c) => c.first == 'close').toList();
      expect(closes, hasLength(1));
      final close = closes.single;
      expect(close, containsAllInOrder(['close', 'tgdog-g1']));
      expect(close, containsAllInOrder(['--actor', 'grid-controller']));
      expect(close.join(' '), contains('resolved via grid gate resolve'));
    });

    test('requires --state-workspace (refused, exit 64, no read, no write)',
        () async {
      final errs = <String>[];
      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        // No --state-workspace and no workspace override → refused.
        out: (_) {},
        err: errs.add,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('--state-workspace is required'));
    });

    test('refuses (non-zero, ZERO writes) when the id is NOT FOUND', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'code/agent', reason: 'x'),
      ]);
      final errs = <String>[];

      final code = await runGateResolve(
        gateId: 'tgdog-nope',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('no bead "tgdog-nope"'));
      expect(store.writes, isEmpty);
    });

    test('refuses (non-zero, ZERO writes) when the id is NOT a type=gate bead',
        () async {
      final store = _FakeStateStore([
        Bead(id: 'tgdog-w7', title: 'work', issueType: IssueType.task),
      ]);
      final errs = <String>[];

      final code = await runGateResolve(
        gateId: 'tgdog-w7',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('not a gate'));
      expect(store.writes, isEmpty);
    });

    test('refuses (non-zero, ZERO writes) when the gate is already CLOSED',
        () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'code/agent',
            reason: 'x', closed: true),
      ]);
      final errs = <String>[];

      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('already closed'));
      expect(store.writes, isEmpty);
    });

    test('refuses (non-zero, ZERO writes) when the gate is NOT OWNED', () async {
      final store = _FakeStateStore([
        // an OPEN gate owned by a FOREIGN substation (prefix + marker `other`).
        _gate('other-g1', blocks: 'other-s1', node: 'code/agent',
            reason: 'x', substation: 'other'),
      ]);
      final errs = <String>[];

      final code = await runGateResolve(
        gateId: 'other-g1',
        stateSubstation: 'tgdog', // we own tgdog, NOT other.
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('not owned by state substation'));
      expect(store.writes, isEmpty);
    });
  });

  // The tg-i08 ruling verb + the fail-closed-F re-gate-loop guard.
  group('grid gate resolve — ruling + re-gate-loop guard (tg-i08)', () {
    test('REFUSES plain resolve (64, ZERO writes) on a gate whose feeding lane '
        'still grades F — naming the lane + its transport provenance', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'tg-1/review/route',
            reason: 'critic test-coverage failed'),
        _session('tgdog-s1', workBead: 'tg-1', results: const {
          'tg-1/review/test-coverage': {
            'grade': 'F',
            'transport': 'no parseable verdict via file or envelope',
          },
        }),
      ]);
      final errs = <String>[];

      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );

      expect(code, 64);
      final text = errs.join('\n');
      expect(text, contains('RE-GATE'));
      expect(text, contains('tg-1/review/test-coverage'));
      expect(text, contains('no parseable verdict via file or envelope'));
      expect(text, contains('--grade'));
      // The guaranteed-no-op loop never touched the store.
      expect(store.writes, isEmpty);
    });

    test('--grade <lane>=<A> --rationale writes the operator ruling through the '
        'chokepoint THEN closes the gate', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'tg-1/review/route',
            reason: 'critic test-coverage failed'),
        _session('tgdog-s1', workBead: 'tg-1', results: const {
          'tg-1/review/test-coverage': {'grade': 'F', 'transport': 'fail-closed'},
        }),
      ]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        grades: const ['test-coverage=A'],
        rationale: 'critic cd\'d; verdict was A — transport F false gate',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      expect(out.join('\n'),
          contains('ruled tg-1/review/test-coverage → grade A'));

      // A ruling `update` on the SESSION bead carrying the corrected grade +
      // operator-ruling transport + rationale.
      final updates = store.writes.where((c) => c.first == 'update').toList();
      final ruling = updates.firstWhere(
        (c) => c.contains('tgdog-s1') && c.join(' ').contains('operator-ruling'),
      );
      final meta = _metadataOf(ruling);
      expect(meta['grid.result.tg-1/review/test-coverage.grade'], 'A');
      expect(meta['grid.result.tg-1/review/test-coverage.transport'],
          'operator-ruling');
      expect(meta['grid.result.tg-1/review/test-coverage.rationale'],
          contains('transport F false gate'));
      // Then the gate closes through the chokepoint.
      final closes = store.writes.where((c) => c.first == 'close').toList();
      expect(closes, hasLength(1));
      expect(closes.single, containsAllInOrder(['close', 'tgdog-g1']));
      expect(closes.single, containsAllInOrder(['--actor', 'grid-controller']));
    });

    test('once ruled to a passing grade the lane is no longer a re-gate cause '
        '— the resolve is NOT refused', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'tg-1/review/route',
            reason: 'critic1 F'),
        _session('tgdog-s1', workBead: 'tg-1', results: const {
          'tg-1/review/critic1': {'grade': 'F'},
        }),
      ]);
      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        grades: const ['critic1=B'],
        rationale: 'false gate',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: (_) {},
      );
      expect(code, 0);
      expect(store.writes.where((c) => c.first == 'close'), hasLength(1));
    });

    test('--grade REQUIRES --rationale (refused 64, ZERO writes)', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'tg-1/review/route',
            reason: 'x'),
        _session('tgdog-s1', workBead: 'tg-1', results: const {
          'tg-1/review/critic1': {'grade': 'F'},
        }),
      ]);
      final errs = <String>[];
      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        grades: const ['critic1=A'],
        // no rationale
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('requires --rationale'));
      expect(store.writes, isEmpty);
    });

    test('--grade with a non-A–F letter is refused (64, ZERO writes)', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'tg-1/review/route',
            reason: 'x'),
      ]);
      final errs = <String>[];
      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        grades: const ['critic1=Z'],
        rationale: 'why',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('not a grade A–F'));
      expect(store.writes, isEmpty);
    });

    test('a PARTIAL ruling that leaves another feeding lane at F is refused '
        '(64, ZERO writes)', () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'tg-1/review/route',
            reason: 'two critics F'),
        _session('tgdog-s1', workBead: 'tg-1', results: const {
          'tg-1/review/critic1': {'grade': 'F'},
          'tg-1/review/critic2': {'grade': 'F'},
        }),
      ]);
      final errs = <String>[];
      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        grades: const ['critic1=A'], // critic2 left at F
        rationale: 'ruled only one',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: errs.add,
      );
      expect(code, 64);
      final text = errs.join('\n');
      expect(text, contains('still grade F'));
      expect(text, contains('tg-1/review/critic2'));
      expect(store.writes, isEmpty);
    });

    test('a non-committee gate (no feeding lane grades) still resolves plainly',
        () async {
      final store = _FakeStateStore([
        _gate('tgdog-g1', blocks: 'tgdog-s1', node: 'tg-1/code/agent',
            reason: 'validation plan failed'),
        // a session with NO F-graded sibling of the parked node.
        _session('tgdog-s1', workBead: 'tg-1', results: const {}),
      ]);
      final code = await runGateResolve(
        gateId: 'tgdog-g1',
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: (_) {},
        err: (_) {},
      );
      expect(code, 0);
      expect(store.writes.where((c) => c.first == 'close'), hasLength(1));
    });
  });

  group('grid gate ls — re-gate visibility (tg-i08)', () {
    test('a refreshed (re-gated) gate shows a reset age + a re-gated Nx marker',
        () async {
      final store = _FakeStateStore([
        Bead(
          id: 'tgdog-g1',
          title: 'grid gate tgdog-s1@tg-1/review/route',
          issueType: IssueType.gate,
          status: BeadStatus.open,
          createdAt: DateTime.utc(2026, 7, 1, 12), // birth: days ago
          metadata: {
            'rig': 'tgdog',
            'blocks': 'tgdog-s1',
            'node': 'tg-1/review/route',
            'reason': 're-gate: critic F again',
            'regate_count': '3',
            'regated_at': DateTime.utc(2026, 7, 7, 11, 59).toIso8601String(),
          },
        ),
      ]);
      final out = <String>[];
      final code = await runGateLs(
        workspaceOverride: _workspace(),
        bdOverride: BdCliService(store),
        out: out.add,
        err: out.add,
        now: DateTime.utc(2026, 7, 7, 12), // 1m after the last re-gate
      );
      expect(code, 0);
      final text = out.join('\n');
      expect(text, contains('re-gated 3x'));
      // The age is measured from `regated_at` (1m ago), NOT `createdAt` (days).
      expect(text, contains('age 1m'));
      expect(text, isNot(contains('age 6d')));
    });
  });
}

/// The `--metadata <json>` payload of a recorded `bd update` argv, decoded.
Map<String, dynamic> _metadataOf(List<String> argv) {
  final i = argv.indexOf('--metadata');
  if (i < 0 || i + 1 >= argv.length) return const {};
  return jsonDecode(argv[i + 1]) as Map<String, dynamic>;
}

/// A the_grid-owned `type=session` bead carrying the per-node [results]
/// (`grid.result.<node>.<field>`) the route re-reads — the substrate the ruling
/// verb corrects and the re-gate-loop guard inspects.
Bead _session(
  String id, {
  required String workBead,
  Map<String, Map<String, String>> results = const {},
  String substation = 'tgdog',
}) =>
    Bead(
      id: id,
      title: 'grid session',
      issueType: IssueType.session,
      status: BeadStatus.open,
      metadata: {
        'rig': substation,
        'work_bead': workBead,
        for (final node in results.entries)
          for (final field in node.value.entries)
            'grid.result.${node.key}.${field.key}': field.value,
      },
    );

/// A direct/embedded state-store workspace (no real `.beads/` on disk needed —
/// the bd runner is faked).
BeadsWorkspace _workspace() => BeadsWorkspace(
      root: '/fake/tgdog',
      mode: DoltMode.direct,
      database: 'tgdog',
      gtRoot: null,
      endpoint: null,
    );

/// Builds an OPEN (or [closed]) `type=gate` bead carrying the D-7 block linkage,
/// stamped with the owned substation marker exactly as `StationBeadWriter`
/// mints it.
Bead _gate(
  String id, {
  required String blocks,
  required String node,
  required String reason,
  String substation = 'tgdog',
  bool closed = false,
}) =>
    Bead(
      id: id,
      title: 'grid gate $blocks@$node',
      issueType: IssueType.gate,
      status: closed ? BeadStatus.closed : BeadStatus.open,
      createdAt: DateTime.utc(2026, 6, 29, 12),
      metadata: {
        'rig': substation,
        'blocks': blocks,
        'node': node,
        'reason': reason,
      },
    );

/// A fake [BdRunner] over a fixed set of staged beads (Fakes, not mocks): the
/// `export` read returns the staged beads as JSONL (the snapshot read path);
/// mutations return a canned envelope and are recorded so a test can assert that
/// a refused resolve performed ZERO writes.
class _FakeStateStore implements BdRunner {
  _FakeStateStore(this._beads);

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
      // `bd export --all` emits RAW JSONL (one issue object per line).
      final jsonl = _beads.map((b) => jsonEncode(b.toJson())).join('\n');
      return Future<BdResult>.value(
        BdResult(exitCode: 0, stdout: jsonl, stderr: ''),
      );
    }
    // create/update/close/delete/batch — a canned id envelope.
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
