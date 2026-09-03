import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/event_renderer.dart';
import 'package:grid_cli/src/watch_command.dart';
import 'package:grid_cli/src/watch_predicate.dart';
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 9, 3, 22, 45);

Bead _gate() => Bead(
  id: 'tg-gate-1',
  issueType: GridIssueTypes.gate,
  metadata: <String, dynamic>{'blocks': 'tgdog-1', 'node': 'tg-1/route'},
);

Bead _task(String id) => Bead(id: id, title: 'work');

void main() {
  test('gate-open exits 0 and the satisfying event is the LAST line', () async {
    final controller = StreamController<GraphEvent>();
    final renderer = EventRenderer(json: true);
    final lines = <String>[];
    final exit = awaitPredicate(
      events: controller.stream,
      evaluator: PredicateEvaluator(const UntilGateOpen()),
      timeout: const Duration(seconds: 60),
      render: (event) => lines.add(renderer.render(event, at: _at)),
    );

    controller.add(const SnapshotInitialized(beadCount: 3, readyCount: 1));
    controller.add(BeadCreated(_task('tg-9')));
    controller.add(BeadCreated(_gate()));
    controller.add(BeadCreated(_task('tg-10')));

    expect(await exit, kWatchUntilSatisfied);
    expect(lines, hasLength(3));
    final last = jsonDecode(lines.last) as Map<String, dynamic>;
    final event = last['event']! as Map<String, dynamic>;
    expect(event['type'], 'beadCreated');
    expect((event['bead']! as Map<String, dynamic>)['id'], 'tg-gate-1');
    expect((event['bead']! as Map<String, dynamic>)['issueType'], 'gate');
    await controller.close();
  });

  test('an unmet predicate exits 2 and writes no satisfying line', () async {
    final controller = StreamController<GraphEvent>();
    final renderer = EventRenderer(json: true);
    final lines = <String>[];
    final exit = awaitPredicate(
      events: controller.stream,
      evaluator: PredicateEvaluator(const UntilGateOpen()),
      timeout: const Duration(milliseconds: 40),
      render: (event) => lines.add(renderer.render(event, at: _at)),
    );

    controller.add(const SnapshotInitialized(beadCount: 1, readyCount: 1));
    controller.add(BeadCreated(_task('tg-9')));

    expect(await exit, kWatchUntilTimedOut);
    expect(lines, hasLength(2));
    expect(lines.every((l) => !l.contains('tg-gate-1')), isTrue);
    await controller.close();
  });

  test('a broken event stream completes with the LOUD StateError', () async {
    final controller = StreamController<GraphEvent>();
    final exit = awaitPredicate(
      events: controller.stream,
      evaluator: PredicateEvaluator(const UntilReadyCountZero()),
      timeout: const Duration(seconds: 5),
      render: (_) {},
    );
    controller.add(const ReadySetChanged(entered: {}, exited: {'tg-1'}));
    await expectLater(exit, throwsStateError);
    await controller.close();
  });

  test(
    'every illegal --until combination exits 64 before any store is opened',
    () async {
      for (final args in <List<String>>[
        ['watch', '/no-such-substation-root', '--until', 'gate-open'],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'gate-open',
          '--timeout',
          '60',
          '--for-seconds',
          '5',
        ],
        ['watch', '/no-such-substation-root', '--timeout', '60'],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'station-down',
          '--timeout',
          '60',
        ],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'gate-open',
          '--timeout',
          '0',
        ],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'gate-open',
          '--timeout',
          'abc',
        ],
      ]) {
        final runner = CommandRunner<int>('grid', 'test')
          ..addCommand(WatchCommand());
        expect(await runner.run(args), 64, reason: args.join(' '));
      }
    },
  );
}
