/// `traj show` — argument refusals, typed rendering, and the graceful
/// absence paths.
library;

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

void main() {
  CommandRunner<int> runnerWith(TrajectoryOpen open) =>
      CommandRunner<int>('grid', 'test')
        ..addCommand(TrajCommand(open: openerFor(open)));

  group('argument parsing', () {
    test('the group alone is a usage refusal, never a silent no-op', () async {
      // args refuses a subcommand-less group before run() is reached (the bin
      // maps UsageException to 64); run() carries the same answer for a
      // runner that dispatches differently.
      final runner = runnerWith(const TrajectoryNotBootstrapped('absent'));
      await expectLater(runner.run(['traj']), throwsA(isA<UsageException>()));
      final group = runner.commands['traj']!;
      expect(await group.run(), 64);
    });

    test('show refuses a missing id and a second id', () async {
      final runner = runnerWith(const TrajectoryNotBootstrapped('absent'));
      expect(
        await runner.run(['traj', 'show', '--state-workspace', '/tmp']),
        64,
      );
      expect(
        await runner.run([
          'traj',
          'show',
          'tg-a',
          'tg-b',
          '--state-workspace',
          '/tmp',
        ]),
        64,
      );
    });

    test('show refuses a missing grid home', () async {
      final runner = runnerWith(const TrajectoryNotBootstrapped('absent'));
      expect(await runner.run(['traj', 'show', 'tg-a']), 64);
    });

    test('--grid-home is an accepted spelling of --state-workspace', () async {
      final runner = runnerWith(const TrajectoryNotBootstrapped('absent'));
      expect(
        await runner.run(['traj', 'show', 'tg-a', '--grid-home', '/tmp']),
        0,
      );
    });

    test('--limit must be a positive integer', () async {
      final runner = runnerWith(const TrajectoryNotBootstrapped('absent'));
      expect(
        await runner.run([
          'traj',
          'show',
          'tg-a',
          '--state-workspace',
          '/tmp',
          '--limit',
          '0',
        ]),
        64,
      );
    });
  });

  group('rendering', () {
    Future<List<String>> show(
      List<TrajectoryEnvelope> rows, {
      String subject = 'tranquility-5xk',
      int limit = defaultReadLimit,
    }) async {
      final out = <String>[];
      final code = await runTrajShow(
        gridHome: '/grid',
        subject: subject,
        open: openerFor(TrajectoryOpened(ScriptedReader(rows))),
        limit: limit,
        out: out.add,
        err: out.add,
      );
      expect(code, 0);
      return out;
    }

    test('renders a typed row: type, instant, correlation, payload', () async {
      final lines = await show([
        envelope(
          recordType: 'attempt.session.started',
          family: TrajectoryFamily.attempt,
          seq: 12,
          sessionId: 'tranquility-5xk',
          workBeadId: 'tg-9abc',
          grantId: '01J8GRANT00000000000000001',
          payload: const {'rig': 'operator', 'model': 'molecule'},
        ),
      ]);
      final text = lines.join('\n');
      expect(text, contains('1 record:'));
      expect(text, contains('attempt.session.started'));
      expect(text, contains('2026-08-31T09:14:02Z'));
      expect(text, contains('bead=tg-9abc'));
      expect(text, contains('session=tranquility-5xk'));
      expect(text, contains('rig=operator  model=molecule'));
      // Legible, not a JSON dump.
      expect(text, isNot(contains('{"rig"')));
    });

    test('renders the terminal outcome on the header line', () async {
      final lines = await show([
        envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          seq: 40,
          sessionId: 'tranquility-5xk',
          attemptId: '01J8ATTEMPT0000000000000001',
          outcome: TerminalOutcome.unknown,
          unknownReason: 'crash',
        ),
      ]);
      expect(lines[1], startsWith('     40  '));
      expect(lines[1], contains('attempt.terminal'));
      expect(lines[1], contains('unknown (crash)'));
      expect(lines[2], contains('attempt=01J8ATTEMPT0000000000000001'));
    });

    test('an unregistered (type, version) renders as opaque', () async {
      final lines = await show([
        envelope(
          recordType: 'attempt.not.a.real.type',
          family: TrajectoryFamily.attempt,
          typeVersion: 9,
          sessionId: 'tranquility-5xk',
          payload: const {'whatever': 1},
        ),
      ]);
      final text = lines.join('\n');
      expect(text, contains('opaque attempt.not.a.real.type v9'));
      expect(text, contains('no decoder registered'));
      expect(text, contains('payload keys: whatever'));
    });

    test('a row its own decoder refuses renders as opaque, with the '
        'failure', () async {
      // ck_grant_link's link is the envelope grant_id; without it the
      // registered decoder throws and the codec falls back to opaque.
      final lines = await show([
        envelope(
          recordType: 'attempt.session.started',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-5xk',
          payload: const {'rig': 'operator', 'model': 'molecule'},
        ),
      ]);
      final text = lines.join('\n');
      expect(text, contains('opaque attempt.session.started v1'));
      expect(text, contains('decode failed'));
    });

    test('rows are rendered in the order the reader yields them', () async {
      final lines = await show([
        envelope(
          recordType: 'attempt.note',
          family: TrajectoryFamily.attempt,
          seq: 1,
          sessionId: 'tranquility-5xk',
          payload: const {
            'body': 'first',
            'channel': 'operator',
            'note_ordinal': 1,
          },
        ),
        envelope(
          recordType: 'attempt.note',
          family: TrajectoryFamily.attempt,
          seq: 2,
          sessionId: 'tranquility-5xk',
          payload: const {
            'body': 'second',
            'channel': 'operator',
            'note_ordinal': 2,
          },
        ),
      ]);
      final text = lines.join('\n');
      expect(text.indexOf('first'), lessThan(text.indexOf('second')));
    });

    test('an empty subject says so instead of printing a header', () async {
      final lines = await show(const [], subject: 'tg-nothing');
      expect(lines, ['traj show tg-nothing — no trajectory records.']);
    });

    test('a full window names the --limit that stopped it', () async {
      final lines = await show([
        envelope(
          recordType: 'attempt.note',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-5xk',
          payload: const {
            'body': 'x',
            'channel': 'operator',
            'note_ordinal': 1,
          },
        ),
      ], limit: 1);
      expect(lines.last, contains('stopped at --limit 1'));
    });
  });

  group('graceful absence', () {
    test('an unbootstrapped grid home is reported and exits 0', () async {
      final out = <String>[];
      final err = <String>[];
      final code = await runTrajShow(
        gridHome: '/grid',
        subject: 'tg-a',
        open: openerFor(
          const TrajectoryNotBootstrapped(
            'trajectory database not found at 127.0.0.1:51156/trajectory — '
            'stage 0 not bootstrapped',
          ),
        ),
        out: out.add,
        err: err.add,
      );
      expect(code, 0);
      expect(err, isEmpty);
      expect(out.single, contains('stage 0 not bootstrapped'));
      expect(out.single, contains('127.0.0.1:51156/trajectory'));
    });

    test('an unreachable server is a refusal on stderr', () async {
      final out = <String>[];
      final err = <String>[];
      final code = await runTrajShow(
        gridHome: '/grid',
        subject: 'tg-a',
        open: openerFor(
          const TrajectoryUnavailable('127.0.0.1:51156/trajectory: refused'),
        ),
        out: out.add,
        err: err.add,
      );
      expect(code, 1);
      expect(out, isEmpty);
      expect(err.single, contains('refused'));
    });

    test('the reader is always closed', () async {
      final reader = ScriptedReader([
        envelope(
          recordType: 'attempt.note',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-5xk',
          payload: const {
            'body': 'x',
            'channel': 'operator',
            'note_ordinal': 1,
          },
        ),
      ]);
      await runTrajShow(
        gridHome: '/grid',
        subject: 'tranquility-5xk',
        open: openerFor(TrajectoryOpened(reader)),
        out: (_) {},
        err: (_) {},
      );
      expect(reader.closed, isTrue);
    });
  });
}
