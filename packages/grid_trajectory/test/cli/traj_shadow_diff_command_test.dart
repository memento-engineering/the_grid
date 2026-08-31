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
  Future<List<ShadowMismatch>> compare({
    required String sessionId,
    required List<TrajectoryEnvelope> records,
    int? round,
  }) async {
    compared.add('$sessionId/${records.length}/${round ?? '-'}');
    return mismatches.where((row) => row.sessionId == sessionId).toList();
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
        out: out.add,
        err: out.add,
      );
      final text = out.join('\n');
      expect(code, 0);
      expect(text, contains('[nonAtomicCrash]'));
      expect(text, contains('0 unexplained'));
      expect(text, contains('operator adjudicates'));
    });
  });
}
