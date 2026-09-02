/// `traj committee-report` — argv refusals, the operator table, the one JSON
/// object, and the unbootstrapped-home exit.
library;

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';
import 'committee_report_fold_test.dart' show fixtureRows;

CommandRunner<int> _runner(
  TrajectoryOpen open, {
  List<UsageSample>? fallback,
}) => CommandRunner<int>('grid', 'test')
  ..addCommand(
    TrajCommand(
      open: openerFor(open),
      usageFallback: fallback == null ? null : (_) => fallback,
    ),
  );

void main() {
  group('argument parsing', () {
    CommandRunner<int> runner() =>
        _runner(const TrajectoryNotBootstrapped('absent'));

    test('refuses a missing grid home', () async {
      expect(await runner().run(['traj', 'committee-report']), 64);
    });

    test('refuses a positional argument', () async {
      expect(
        await runner().run([
          'traj',
          'committee-report',
          'tg-aaa',
          '--state-workspace',
          '/tmp',
        ]),
        64,
      );
    });

    test('refuses a non-ISO --since', () async {
      expect(
        await runner().run([
          'traj',
          'committee-report',
          '--state-workspace',
          '/tmp',
          '--since',
          'yesterday',
        ]),
        64,
      );
    });

    test('refuses a non-numeric --epoch', () async {
      expect(
        await runner().run([
          'traj',
          'committee-report',
          '--state-workspace',
          '/tmp',
          '--epoch',
          'latest',
        ]),
        64,
      );
    });
  });

  group('open dispositions', () {
    test('an unbootstrapped home is a STATE — reported, exit 0', () async {
      final lines = <String>[];
      final code = await runTrajCommitteeReport(
        gridHome: '/tmp',
        open: openerFor(const TrajectoryNotBootstrapped('stage 0 absent')),
        usageFallback: (_) => const [],
        out: lines.add,
      );
      expect(code, 0);
      expect(lines.single, contains('stage 0 absent'));
    });

    test('an unreachable server is a refusal — exit 1', () async {
      final errors = <String>[];
      final code = await runTrajCommitteeReport(
        gridHome: '/tmp',
        open: openerFor(const TrajectoryUnavailable('connection refused')),
        usageFallback: (_) => const [],
        err: errors.add,
      );
      expect(code, 1);
      expect(errors.single, contains('connection refused'));
    });

    test('the reader is closed even on the happy path', () async {
      final reader = ScriptedReader(fixtureRows());
      await runTrajCommitteeReport(
        gridHome: '/tmp',
        open: openerFor(TrajectoryOpened(reader)),
        usageFallback: (_) => const [],
        out: (_) {},
      );
      expect(reader.closed, isTrue);
    });
  });

  group('output', () {
    test(
      'the table carries lanes, gate causes, and per-bead dollars',
      () async {
        final lines = <String>[];
        final code = await runTrajCommitteeReport(
          gridHome: '/tmp',
          open: openerFor(TrajectoryOpened(ScriptedReader(fixtureRows()))),
          usageFallback: (_) => const [],
          out: lines.add,
        );
        expect(code, 0);
        final text = lines.join('\n');
        expect(text, contains('readiness-hold'));
        expect(text, contains('coherence'));
        expect(text, contains('tg-aaa'));
        expect(text, contains(r'$18.00'));
      },
    );

    test('--json emits ONE object', () async {
      final lines = <String>[];
      final code = await runTrajCommitteeReport(
        gridHome: '/tmp',
        open: openerFor(TrajectoryOpened(ScriptedReader(fixtureRows()))),
        usageFallback: (_) => const [],
        asJson: true,
        out: lines.add,
      );
      expect(code, 0);
      final decoded = jsonDecode(lines.join('\n'));
      expect(decoded, isA<Map<String, Object?>>());
      final report = decoded as Map<String, Object?>;
      expect(report['truncated'], isFalse);
      expect((report['gate_causes']! as Map)['critic-f'], 1);
      final lanes = report['lanes']! as List;
      expect(lanes, hasLength(5));
      final beads = report['beads']! as List;
      expect((beads.first as Map)['bead'], 'tg-aaa');
      expect((beads.first as Map)['rounds'], 2);
    });

    test('--telemetry-root folds fallback samples through the seam', () async {
      final lines = <String>[];
      await runTrajCommitteeReport(
        gridHome: '/tmp',
        open: openerFor(TrajectoryOpened(ScriptedReader(fixtureRows()))),
        usageFallback: (root) => [
          UsageSample(
            lane: 'adr-alignment',
            beadId: 'tg-bbb',
            fromFallback: true,
            costUsd: 2.5,
            durationMs: root.isEmpty ? null : 90000,
          ),
        ],
        telemetryRoot: '/tmp/telemetry',
        asJson: true,
        out: lines.add,
      );
      final report = jsonDecode(lines.join('\n')) as Map<String, Object?>;
      final adr = (report['lanes']! as List).firstWhere(
        (row) => (row as Map)['lane'] == 'adr-alignment',
      );
      expect((adr as Map)['runs_from_fallback'], 1);
    });

    test('a cut window prints TRUNCATED rather than a total', () async {
      final lines = <String>[];
      await runTrajCommitteeReport(
        gridHome: '/tmp',
        open: openerFor(
          TrajectoryOpened(
            ScriptedReader(fixtureRows(), truncateCompleteReadsAt: 3),
          ),
        ),
        usageFallback: (_) => const [],
        out: lines.add,
      );
      expect(lines.first, contains('TRUNCATED'));
    });
  });

  group('the .usage.json scan', () {
    test('parses cost and duration off a harness envelope', () {
      final sample = parseUsageEnvelope(
        beadId: 'tg-aaa',
        lane: 'coherence',
        content:
            '{"total_cost_usd": 3.25, "duration_ms": 42000, '
            '"usage": {"input_tokens": 10}}',
      );
      expect(sample!.costUsd, 3.25);
      expect(sample.durationMs, 42000);
      expect(sample.fromFallback, isTrue);
    });

    test('malformed or usage-free content yields NO sample, never a throw', () {
      expect(
        parseUsageEnvelope(beadId: 'a', lane: 'b', content: 'not json'),
        isNull,
      );
      expect(parseUsageEnvelope(beadId: 'a', lane: 'b', content: '{}'), isNull);
      expect(parseUsageEnvelope(beadId: 'a', lane: 'b', content: null), isNull);
    });

    test('an absent telemetry root scans to nothing', () {
      expect(scanUsageFallback('/tmp/no-such-telemetry-root-tg9x80'), isEmpty);
    });
  });
}
