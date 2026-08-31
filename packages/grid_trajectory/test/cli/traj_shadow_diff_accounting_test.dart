/// The round-disqualification gating (stage1-wiring §2.5/§3): a run whose
/// append accounting is dirty — or simply absent — cannot mint a clean round,
/// however clean the comparison itself came out.
library;

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

const String _session = 'tranquility-5xk';

class _AgreeingCompare implements ShadowCompare {
  const _AgreeingCompare([this.mismatches = const []]);

  final List<ShadowMismatch> mismatches;

  @override
  Set<String> get comparableFields => const {'status', 'outcome'};

  @override
  String? get unavailableReason => null;

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async => ShadowCompareResult(mismatches);
}

TrajectoryEnvelope _row(int seq) => envelope(
  recordType: 'attempt.note',
  family: TrajectoryFamily.attempt,
  seq: seq,
  sessionId: _session,
  payload: {'body': 'n$seq', 'channel': 'operator', 'note_ordinal': seq},
);

Future<(int, String)> _run({
  ShadowRunAccounting? accounting,
  ShadowAccountingSource? accountingFor,
  ShadowCompare compare = const _AgreeingCompare(),
}) async {
  final out = <String>[];
  final code = await runTrajShadowDiff(
    gridHome: '/grid',
    open: openerFor(TrajectoryOpened(ScriptedReader([_row(1)]))),
    compare: compare,
    accounting: accounting,
    accountingFor: accountingFor,
    out: out.add,
    err: out.add,
  );
  return (code, out.join('\n'));
}

void main() {
  group('the disqualification rule', () {
    test('zero drops is the clean round', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 0, mode: 'live'),
      );
      expect(code, 0);
      expect(text, contains('append accounting: dropped: 0, suppressed: 0'));
      expect(text, contains('— clean'));
      expect(text, contains('one clean run toward the criterion'));
    });

    test('ANY dropped append disqualifies a zero-mismatch run', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 1),
      );
      // Not a blocked cut — nothing diverged — but emphatically not a clean
      // round: the drop is a record the comparison could not have missed.
      expect(code, 0);
      expect(text, contains('DISQUALIFYING (1 dropped append)'));
      expect(text, contains('does NOT count toward the 3-clean-round'));
      expect(text, isNot(contains('one clean run')));
    });

    test('suppressed appends disqualify on the same grounds', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(
          dropped: 0,
          suppressed: 4,
          mode: 'halted',
        ),
      );
      expect(code, 0);
      expect(text, contains('4 suppressed appends'));
      expect(text, contains('the recorder was latched'));
      expect(text, isNot(contains('one clean run')));
    });

    test('both counters are named in one reason', () async {
      final (_, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 2, suppressed: 3),
      );
      expect(text, contains('2 dropped and 3 suppressed appends'));
    });

    test('UNKNOWN accounting does not count either', () async {
      final (code, text) = await _run();
      expect(code, 0);
      expect(text, contains('append accounting: UNKNOWN'));
      expect(text, contains('--dropped'));
      expect(text, isNot(contains('one clean run')));
    });

    test('an unexplained mismatch still BLOCKS, whatever the '
        'accounting says', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 9),
        compare: const _AgreeingCompare([
          ShadowMismatch(
            sessionId: _session,
            field: 'outcome',
            legacyValue: 'failed',
            foldValue: 'succeeded',
            seq: 12,
          ),
        ]),
      );
      expect(code, 1);
      expect(text, contains('BLOCKED'));
    });

    test('named gaps are counted by class in the report', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 0),
        compare: const _AgreeingCompare([
          ShadowMismatch(
            sessionId: _session,
            field: 'presence',
            legacyValue: 'present',
            foldValue: null,
            seq: null,
            classification: ShadowMismatchClass.nonAtomicCrash,
          ),
          ShadowMismatch(
            sessionId: _session,
            stepPath: 'build',
            field: 'step_attempt',
            legacyValue: 'ran',
            foldValue: null,
            seq: 4,
            classification: ShadowMismatchClass.stopRacesSpawn,
          ),
          ShadowMismatch(
            sessionId: _session,
            stepPath: 'review',
            field: 'step_attempt',
            legacyValue: 'ran',
            foldValue: null,
            seq: 5,
            classification: ShadowMismatchClass.stopRacesSpawn,
          ),
        ]),
      );
      expect(code, 0);
      expect(
        text,
        contains('named gaps: non_atomic_crash 1, stop_races_spawn 2'),
      );
      // The step lane's coordinate has a column of its own once a lane that
      // keys on it produced a row.
      expect(text, contains('step_path'));
      expect(text, contains('build'));
      expect(text, contains('operator adjudicates'));
    });
  });

  group('the accounting SOURCE seam', () {
    test('a composed source sees the parsed grid home', () async {
      final homes = <String>[];
      final (code, text) = await _run(
        accountingFor: (gridHome) async {
          homes.add(gridHome);
          return const ShadowRunAccounting(dropped: 0, epoch: 7);
        },
      );
      expect(code, 0);
      expect(homes, ['/grid']);
      expect(text, contains('epoch: 7'));
      expect(text, contains('one clean run'));
    });

    test("the operator's flag outranks the source", () async {
      final (_, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 5),
        accountingFor: (_) async => const ShadowRunAccounting(dropped: 0),
      );
      expect(text, contains('5 dropped appends'));
    });

    test('a source returning null leaves accounting unknown', () async {
      final (_, text) = await _run(accountingFor: (_) async => null);
      expect(text, contains('append accounting: UNKNOWN'));
    });
  });

  group('the flag surface', () {
    CommandRunner<int> runner() => CommandRunner<int>('grid', 'test')
      ..addCommand(
        TrajCommand(open: openerFor(const TrajectoryNotBootstrapped('absent'))),
      );

    test('--dropped 0 is accepted — asserting a clean round is the '
        'point', () async {
      expect(
        await runner().run([
          'traj',
          'shadow-diff',
          '--state-workspace',
          '/tmp',
          '--dropped',
          '0',
        ]),
        0,
      );
    });

    test('a negative --dropped is refused', () async {
      expect(
        await runner().run([
          'traj',
          'shadow-diff',
          '--state-workspace',
          '/tmp',
          '--dropped',
          '-1',
        ]),
        64,
      );
    });

    test('a non-numeric --suppressed is refused', () async {
      expect(
        await runner().run([
          'traj',
          'shadow-diff',
          '--state-workspace',
          '/tmp',
          '--suppressed',
          'lots',
        ]),
        64,
      );
    });
  });
}
