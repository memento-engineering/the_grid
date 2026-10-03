/// `traj shadow-diff` — the Stage 0 skeleton: it must run clean against an
/// empty or absent log and state exactly what it cannot compare yet, and it
/// must block a stage cut the moment a strategy reports an unexplained
/// mismatch.
library;

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

/// A Stage-1-shaped strategy: it declares comparable fields and returns
/// whatever the test scripts.
class _ScriptedCompare implements ShadowCompare {
  _ScriptedCompare(this.mismatches);

  final List<ShadowMismatch> mismatches;
  final List<String> compared = [];

  @override
  Set<String> get comparableFields => const {'status', 'outcome'};

  @override
  String? get unavailableReason => null;

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
    ShadowCorroboration corroboration = const ShadowCorroboration.none(),
  }) async {
    compared.add(
      '$sessionId/${records.records.length}/${round ?? '-'}'
      '${records.isComplete ? '' : '/CUT'}',
    );
    if (!records.isComplete) {
      return const ShadowCompareResult.incomplete('the stream was cut');
    }
    return ShadowCompareResult(
      mismatches.where((row) => row.sessionId == sessionId).toList(),
    );
  }
}

TrajectoryEnvelope _note(String sessionId, int seq) => envelope(
  recordType: 'attempt.note',
  family: TrajectoryFamily.attempt,
  seq: seq,
  sessionId: sessionId,
  payload: {'body': 'n$seq', 'channel': 'operator', 'note_ordinal': seq},
);

void main() {
  group('argument parsing', () {
    CommandRunner<int> runner() => CommandRunner<int>('grid', 'test')
      ..addCommand(
        TrajCommand(open: openerFor(const TrajectoryNotBootstrapped('absent'))),
      );

    test('refuses a missing grid home', () async {
      expect(await runner().run(['traj', 'shadow-diff']), 64);
    });

    test('refuses a positional session id — sessions ride --session', () async {
      expect(
        await runner().run([
          'traj',
          'shadow-diff',
          'tranquility-5xk',
          '--state-workspace',
          '/tmp',
        ]),
        64,
      );
    });

    test('refuses a non-numeric --round', () async {
      expect(
        await runner().run([
          'traj',
          'shadow-diff',
          '--state-workspace',
          '/tmp',
          '--round',
          'latest',
        ]),
        64,
      );
    });

    test('accepts repeated --session', () async {
      expect(
        await runner().run([
          'traj',
          'shadow-diff',
          '--state-workspace',
          '/tmp',
          '--session',
          'a',
          '--session',
          'b',
        ]),
        0,
      );
    });
  });

  group('nothing to compare yet', () {
    test('an absent database runs clean and says why', () async {
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(
          const TrajectoryNotBootstrapped(
            'trajectory database not found at 127.0.0.1:51156/trajectory — '
            'stage 0 not bootstrapped',
          ),
        ),
        out: out.add,
        err: out.add,
      );
      final text = out.join('\n');
      expect(code, 0);
      expect(text, contains('stage 0 not bootstrapped'));
      expect(text, contains('cannot compare yet: no legacy dual-write'));
      expect(text, contains('never shadowable'));
      expect(text, contains('does NOT count toward the 3-clean-round'));
    });

    test('an empty log runs clean and claims no clean round', () async {
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(TrajectoryOpened(ScriptedReader(const []))),
        out: out.add,
        err: out.add,
      );
      final text = out.join('\n');
      expect(code, 0);
      expect(text, contains('no sessions in the log'));
      expect(text, contains('compares: nothing yet'));
      expect(text, contains('nothing compared'));
      // The Stage 0 default must never be read as a clean comparison round.
      expect(text, isNot(contains('one clean run')));
    });

    test('a populated log still compares nothing under the Stage 0 '
        'strategy', () async {
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(
          TrajectoryOpened(
            ScriptedReader([_note('tranquility-5xk', 1), _note('tg-b', 2)]),
          ),
        ),
        out: out.add,
        err: out.add,
      );
      expect(code, 0);
      expect(out.join('\n'), contains('scope: tranquility-5xk, tg-b'));
      expect(out.join('\n'), contains('nothing compared'));
    });

    test('an unreachable server is a refusal', () async {
      final out = <String>[];
      final err = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(const TrajectoryUnavailable('refused')),
        out: out.add,
        err: err.add,
      );
      expect(code, 1);
      expect(err.single, contains('refused'));
    });
  });

  group('with an injected strategy', () {
    test('scopes to --session and threads the round through', () async {
      final compare = _ScriptedCompare([]);
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(
          TrajectoryOpened(
            ScriptedReader([_note('tranquility-5xk', 1), _note('tg-b', 2)]),
          ),
        ),
        compare: compare,
        // A clean round needs BOTH statements: the comparison agreed AND no
        // append went missing (§3). The accounting is the second one.
        accounting: const ShadowRunAccounting(dropped: 0, suppressed: 0),
        sessions: const ['tranquility-5xk'],
        round: 3,
        out: out.add,
        err: out.add,
      );
      expect(code, 0);
      expect(compare.compared, ['tranquility-5xk/1/3']);
      expect(out.join('\n'), contains('one clean run toward the criterion'));
      expect(out.join('\n'), contains('compares: outcome, status'));
    });

    test('an unexplained mismatch blocks the cut and exits 1', () async {
      final compare = _ScriptedCompare([
        const ShadowMismatch(
          sessionId: 'tranquility-5xk',
          field: 'outcome',
          legacyValue: 'failed',
          foldValue: 'succeeded',
          seq: 1421,
        ),
      ]);
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(
          TrajectoryOpened(ScriptedReader([_note('tranquility-5xk', 1)])),
        ),
        compare: compare,
        out: out.add,
        err: out.add,
      );
      final text = out.join('\n');
      expect(code, 1);
      // The report is keyed exactly as §9 orders it.
      expect(text, contains('session'));
      expect(text, contains('legacy_value'));
      expect(text, contains('fold_value'));
      expect(text, contains('failed'));
      expect(text, contains('succeeded'));
      expect(text, contains('1421'));
      expect(text, contains('[unexplained]'));
      expect(text, contains('BLOCKED'));
    });

    test('an allow-listed mismatch is reported but does not block', () async {
      final compare = _ScriptedCompare([
        const ShadowMismatch(
          sessionId: 'tranquility-5xk',
          field: 'outcome',
          legacyValue: 'failed',
          foldValue: null,
          seq: null,
          classification: ShadowMismatchClass.nonAtomicCrash,
        ),
      ]);
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(
          TrajectoryOpened(ScriptedReader([_note('tranquility-5xk', 1)])),
        ),
        compare: compare,
        accounting: const ShadowRunAccounting(dropped: 0, suppressed: 0),
        out: out.add,
        err: out.add,
      );
      final text = out.join('\n');
      expect(code, 0);
      // The wire token is snake_case, matching the DDL vocabulary.
      expect(text, contains('[non_atomic_crash]'));
      expect(text, contains('0 unexplained'));
      expect(text, contains('operator adjudicates'));
    });
  });

  group('with a strategy FACTORY (the grid_cli composition seam)', () {
    List<TrajectoryEnvelope> lifecycle(String sessionId) => [
      envelope(
        recordType: 'attempt.session.started',
        family: TrajectoryFamily.attempt,
        seq: 1,
        sessionId: sessionId,
        workBeadId: 'tg-9abc',
        grantId: '01J8GRANT00000000000000001',
        payload: const {'rig': 'operator', 'model': 'molecule'},
      ),
      envelope(
        recordType: 'attempt.terminal',
        family: TrajectoryFamily.attempt,
        seq: 2,
        sessionId: sessionId,
        attemptId: '01J8ATTEMPT000000000000002',
        outcome: TerminalOutcome.succeeded,
      ),
    ];

    test(
      'default scope excludes open and boot-voided legacy sessions',
      () async {
        const completed = 'tranquility-completed';
        const open = 'tranquility-live';
        const voided = 'tranquility-voided';
        final out = <String>[];
        final code = await runTrajShadowDiff(
          gridHome: '/grid/home',
          open: openerFor(
            TrajectoryOpened(
              ScriptedReader([
                ...lifecycle(completed),
                _note(open, 3),
                _note(voided, 4),
              ]),
            ),
          ),
          compare: CompositeShadow([
            AttemptLifecycleShadow(
              _LegacyById(const {
                completed: LegacySessionView(
                  sessionId: completed,
                  workBeadId: 'tg-9abc',
                  closed: true,
                  completed: true,
                ),
                open: LegacySessionView(
                  sessionId: open,
                  workBeadId: 'tg-live',
                  closed: false,
                ),
                voided: LegacySessionView(
                  sessionId: voided,
                  workBeadId: 'tg-voided',
                  closed: true,
                  voided: true,
                ),
              }),
            ),
          ]),
          accounting: const ShadowRunAccounting(dropped: 0, suppressed: 0),
          out: out.add,
          err: out.add,
        );
        final text = out.join('\n');
        expect(code, 0);
        expect(text, contains('scope: $completed'));
        expect(text, isNot(contains('tranquility-live')));
        expect(text, isNot(contains('tranquility-voided')));
        expect(text, contains('skipped in-flight: 1 session'));
        expect(text, contains('skipped voided: 1 session'));
        expect(text, contains('0 mismatches over 1 session'));
        expect(text, contains('does NOT count toward the 3-clean-round'));
        expect(text, isNot(contains('one clean run')));
        expect(text, isNot(contains('named gaps:')));
      },
    );

    test('--session explicitly compares an open legacy session', () async {
      const open = 'tranquility-live';
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid/home',
        open: openerFor(TrajectoryOpened(ScriptedReader([_note(open, 1)]))),
        compare: AttemptLifecycleShadow(
          _LegacyById(const {
            open: LegacySessionView(
              sessionId: open,
              workBeadId: 'tg-live',
              closed: false,
            ),
          }),
        ),
        accounting: const ShadowRunAccounting(dropped: 0, suppressed: 0),
        sessions: const [open],
        out: out.add,
        err: out.add,
      );
      final text = out.join('\n');
      // The open session's presence row has nothing to join, so it is
      // unexplained (tg-ilug) and blocks — the point here is the SCOPE.
      expect(code, 1);
      expect(text, contains('scope: $open'));
      expect(
        text,
        contains('[unexplained — no corroboration: no attempt to join'),
      );
      expect(text, contains('1 mismatch, 1 unexplained'));
      expect(text, isNot(contains('skipped in-flight:')));
      expect(text, isNot(contains('skipped voided:')));
    });

    test('the factory sees the parsed grid home and outranks the fixed '
        'strategy', () async {
      final homes = <String>[];
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid/home',
        open: openerFor(
          TrajectoryOpened(ScriptedReader(lifecycle('tranquility-5xk'))),
        ),
        compare: _ScriptedCompare([]),
        compareFor: (gridHome) async {
          homes.add(gridHome);
          return AttemptLifecycleShadow(
            _AgreeingLegacy('tranquility-5xk', 'tg-9abc'),
          );
        },
        accounting: const ShadowRunAccounting(dropped: 0, suppressed: 0),
        out: out.add,
        err: out.add,
      );
      expect(code, 0);
      expect(homes, ['/grid/home']);
      final text = out.join('\n');
      expect(text, contains('strategy: AttemptLifecycleShadow'));
      expect(text, contains('one clean run toward the criterion'));
    });

    test('a real divergence through the factory blocks the cut', () async {
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid/home',
        open: openerFor(
          TrajectoryOpened(ScriptedReader(lifecycle('tranquility-5xk'))),
        ),
        compareFor: (_) async => AttemptLifecycleShadow(
          _AgreeingLegacy('tranquility-5xk', 'tg-OTHER'),
        ),
        out: out.add,
        err: out.add,
      );
      expect(code, 1);
      final text = out.join('\n');
      expect(text, contains('work_bead_id'));
      expect(text, contains('BLOCKED'));
    });

    test('a truncated read is reported INCOMPLETE and does not count as a '
        'clean run', () async {
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid/home',
        open: openerFor(
          TrajectoryOpened(
            ScriptedReader(
              lifecycle('tranquility-5xk'),
              truncateCompleteReadsAt: 1,
            ),
          ),
        ),
        compareFor: (_) async => AttemptLifecycleShadow(
          _AgreeingLegacy('tranquility-5xk', 'tg-9abc'),
        ),
        out: out.add,
        err: out.add,
      );
      final text = out.join('\n');
      // Not a mismatch — so not a blocked cut — but emphatically not the
      // clean run the old code would have minted off a folded prefix.
      expect(code, 0);
      expect(text, contains('INCOMPLETE: tranquility-5xk'));
      expect(text, contains('does NOT count toward the 3-clean-round'));
      expect(text, isNot(contains('one clean run')));
    });

    test('a factory degrade (no ledger beside the log) stays a clean '
        'non-counting run', () async {
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid/home',
        open: openerFor(
          TrajectoryOpened(ScriptedReader(lifecycle('tranquility-5xk'))),
        ),
        compareFor: (_) async => const UncomparableShadow(),
        out: out.add,
        err: out.add,
      );
      expect(code, 0);
      expect(out.join('\n'), contains('nothing compared'));
    });
  });

  group('tg-ul2v — the unshadowable class and the non-atomic-crash '
      'allow-list, in the existing typed report', () {
    ShadowMismatch crash(String sessionId, String field, int seq) =>
        ShadowMismatch(
          sessionId: sessionId,
          field: field,
          legacyValue: 'closed',
          foldValue: null,
          seq: seq,
          classification: ShadowMismatchClass.nonAtomicCrash,
          basis: 'attempt a-$sessionId: started without exit, started@$seq',
        );

    Future<(int, String)> run(
      List<ShadowMismatch> rows, {
      NonAtomicCrashAllowList? allowList,
    }) async {
      final out = <String>[];
      final code = await runTrajShadowDiff(
        gridHome: '/grid',
        open: openerFor(
          TrajectoryOpened(ScriptedReader([_note('tranquility-5xk', 1)])),
        ),
        compare: _ScriptedCompare(rows),
        accounting: const ShadowRunAccounting(dropped: 0, suppressed: 0),
        allowList: allowList,
        out: out.add,
        err: out.add,
      );
      return (code, out.join('\n'));
    }

    test('a legacy_carrier_retired row is PRINTED with its key and basis but '
        'never sampled as a mismatch', () async {
      final (code, text) = await run([
        const ShadowMismatch(
          sessionId: 'tranquility-5xk',
          stepPath: 'tg-ersi.5/review/route',
          field: 'step_state',
          legacyValue: 'gated',
          foldValue: 'pending',
          seq: 4411,
          classification: ShadowMismatchClass.legacyCarrierRetired,
          basis: 'cut discipline retired the step bead rearm write',
        ),
      ]);
      expect(code, 0);
      // The typed report keeps every key §9 orders it by.
      expect(text, contains('tg-ersi.5/review/route'));
      expect(text, contains('gated'));
      expect(text, contains('pending'));
      expect(text, contains('4411'));
      expect(
        text,
        contains(
          '[legacy_carrier_retired — cut discipline retired the step bead '
          'rearm write]',
        ),
      );
      expect(text, contains('unshadowable: legacy_carrier_retired 1'));
      expect(text, contains('0 mismatches over 1 session'));
      expect(text, contains('(1 unshadowable, not sampled)'));
      expect(text, isNot(contains('named gaps')));
      expect(text, isNot(contains('BLOCKED')));
    });

    test('an unexplained row beside an unshadowable one still counts — the '
        'class hides nothing else', () async {
      final (code, text) = await run([
        const ShadowMismatch(
          sessionId: 'tranquility-5xk',
          field: 'step_state',
          legacyValue: 'pending',
          foldValue: 'running',
          seq: 1,
          classification: ShadowMismatchClass.legacyCarrierRetired,
        ),
        const ShadowMismatch(
          sessionId: 'tranquility-5xk',
          field: 'outcome',
          legacyValue: 'failed',
          foldValue: 'succeeded',
          seq: 2,
        ),
      ]);
      expect(code, 1);
      expect(text, contains('1 mismatch, 1 unexplained'));
    });

    test('NonAtomicCrashAllowList opens ONE adjudication per session and '
        'ignores every other class', () {
      final list = NonAtomicCrashAllowList();
      final first = list.admit([
        crash('s1', 'status', 1),
        crash('s1', 'outcome', 2),
        crash('s2', 'status', 3),
        const ShadowMismatch(
          sessionId: 's3',
          field: 'status',
          legacyValue: 'closed',
          foldValue: 'open',
          seq: 4,
          classification: ShadowMismatchClass.lostAppend,
        ),
      ]);
      expect(first.opened.map((a) => a.sessionId), ['s1', 's2']);
      expect(first.joined, isEmpty);
      expect(list.adjudicationFor('s1')!.rows, hasLength(2));
      expect(list.adjudicationFor('s3'), isNull);
      expect(NonAtomicCrashAllowList.name, 'non-atomic-crash allow-list');

      // A later admission in the SAME process never re-opens s1.
      final second = list.admit([
        crash('s1', 'held', 5),
        crash('s4', 'status', 6),
      ]);
      expect(second.opened.map((a) => a.sessionId), ['s4']);
      expect(second.joined, {'s1': 1});
      expect(list.adjudicationFor('s1')!.rows, hasLength(3));
      expect(list.sessions, 3);
    });

    test('the verb prompts ONCE per session within a run, and a second run '
        'through the same list does not re-prompt', () async {
      final allowList = NonAtomicCrashAllowList();
      final rows = [
        crash('tranquility-5xk', 'status', 10),
        crash('tranquility-5xk', 'outcome', 11),
        crash('tranquility-5xk', 'held', 12),
      ];

      final (firstCode, first) = await run(rows, allowList: allowList);
      expect(firstCode, 0);
      // Three crash rows, one session, ONE prompt.
      expect('adjudicate ONCE'.allMatches(first), hasLength(1), reason: first);
      expect(
        first,
        contains(
          'non-atomic-crash allow-list: adjudicate ONCE — tranquility-5xk '
          '(3 rows); basis: attempt a-tranquility-5xk: started without exit',
        ),
      );
      // Every row is still in the typed report.
      expect('[non_atomic_crash'.allMatches(first), hasLength(3));

      final (secondCode, second) = await run(rows, allowList: allowList);
      expect(secondCode, 0);
      expect(second, isNot(contains('adjudicate ONCE')));
      expect(
        second,
        contains(
          'non-atomic-crash allow-list: already adjudicated this process — '
          'tranquility-5xk (+3 rows, not re-prompted)',
        ),
      );
      expect(allowList.adjudicationFor('tranquility-5xk')!.rows, hasLength(6));
    });

    test('the VERB threads its held list through every run it makes', () async {
      final allowList = NonAtomicCrashAllowList();
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(
          TrajShadowDiffCommand(
            open: openerFor(
              TrajectoryOpened(ScriptedReader([_note('tranquility-5xk', 1)])),
            ),
            compare: _ScriptedCompare([crash('tranquility-5xk', 'status', 10)]),
            allowList: allowList,
          ),
        );
      const args = [
        'shadow-diff',
        '--state-workspace',
        '/tmp',
        '--dropped',
        '0',
        '--suppressed',
        '0',
      ];
      expect(await runner.run(args), 0);
      expect(allowList.sessions, 1);
      expect(allowList.adjudicationFor('tranquility-5xk')!.rows, hasLength(1));
      // The second run of the SAME verb joins the open adjudication.
      expect(await runner.run(args), 0);
      expect(allowList.sessions, 1);
      expect(allowList.adjudicationFor('tranquility-5xk')!.rows, hasLength(2));
    });

    test('the list is scoped to its INSTANCE: a fresh list (a new process) '
        'prompts again — nothing persists across a bounce', () async {
      final rows = [crash('tranquility-5xk', 'status', 10)];
      final (_, first) = await run(rows, allowList: NonAtomicCrashAllowList());
      final (_, second) = await run(rows, allowList: NonAtomicCrashAllowList());
      expect(first, contains('adjudicate ONCE'));
      expect(second, contains('adjudicate ONCE'));
    });
  });
}

/// A legacy reader with one scripted view per session id.
class _LegacyById implements LegacySessionReader {
  const _LegacyById(this.views);

  final Map<String, LegacySessionView> views;

  @override
  Future<LegacySessionView?> sessionView(String sessionId) async =>
      views[sessionId];
}

/// A legacy reader that agrees with the folded lifecycle except for the work
/// bead it is scripted with.
class _AgreeingLegacy implements LegacySessionReader {
  _AgreeingLegacy(this.sessionId, this.workBeadId);

  final String sessionId;
  final String workBeadId;

  @override
  Future<LegacySessionView?> sessionView(String id) async => id == sessionId
      ? LegacySessionView(
          sessionId: sessionId,
          workBeadId: workBeadId,
          closed: true,
          completed: true,
        )
      : null;
}
