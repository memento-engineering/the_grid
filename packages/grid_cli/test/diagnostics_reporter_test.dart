import 'dart:convert';

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart' show ExplorationTransport;
import 'package:test/test.dart';

void main() {
  test('flare writes one stable JSON line', () {
    final lines = <String>[];
    final reporter = StationDiagnosticsReporter(writeLine: lines.add);

    reporter.flare('station.wedged', <String, String>{'gated': '2'});

    expect(lines, hasLength(1));
    expect(jsonDecode(lines.single), <String, Object?>{
      'type': 'flare',
      'name': 'station.wedged',
      'data': <String, Object?>{'gated': '2'},
    });
  });

  test('throwing line writer is contained before a later transport', () {
    final transport = _RecordingTransport();
    final reporter = StationDiagnosticsReporter(
      writeLine: (_) => throw StateError('disk full'),
    )..addTransport(transport);

    expect(
      () => reporter.flare('work.held', const <String, String>{}),
      returnsNormally,
    );
    expect(transport.flares, hasLength(1));
    expect(transport.flares.single.name, 'work.held');
    expect(transport.flares.single.data, isEmpty);
  });

  test('rate limit accepts once before the whole fan-out', () {
    var now = DateTime.utc(2026, 9, 12);
    final order = <String>[];
    final first = _RecordingTransport(onFlare: (_) => order.add('first'));
    final second = _RecordingTransport(onFlare: (_) => order.add('second'));
    final reporter =
        StationDiagnosticsReporter(
            writeLine: (_) => order.add('line'),
            now: () => now,
          )
          ..addTransport(first)
          ..addTransport(second);

    reporter.flare('relay.escalated', {'beadId': 'tg-a'});
    reporter.flare('relay.escalated', {'beadId': 'tg-a'});

    expect(order, ['line', 'first', 'second']);
    expect(first.flares, hasLength(1));
    expect(second.flares, hasLength(1));

    now = now.add(const Duration(seconds: 30));
    reporter.flare('relay.escalated', {'beadId': 'tg-a'});
    expect(order, ['line', 'first', 'second', 'line', 'first', 'second']);
    expect(first.flares, hasLength(2));
    expect(second.flares, hasLength(2));
  });

  test('step failure flares use independent leading-edge rate limits', () {
    var now = DateTime.utc(2026, 8, 9);
    final lines = <String>[];
    final reporter = StationDiagnosticsReporter(
      writeLine: lines.add,
      now: () => now,
    );

    reporter.flare('step.persistFailed', {'bead': 'tg-6e4j'});
    expect(jsonDecode(lines.single), {
      'type': 'flare',
      'name': 'step.persistFailed',
      'data': {'bead': 'tg-6e4j'},
    });

    now = now.add(const Duration(seconds: 29));
    reporter.flare('step.persistFailed', {'bead': 'tg-6e4j'});
    expect(lines, hasLength(1));

    reporter.flare('step.persistFailed', {'bead': 'tg-sww5'});
    expect(lines, hasLength(2));
    expect(jsonDecode(lines.last), {
      'type': 'flare',
      'name': 'step.persistFailed',
      'data': {'bead': 'tg-sww5'},
    });

    reporter.flare('step.persistFailed', {
      'bead': 'tg-6e4j',
      'nodePath': 'tg-6e4j/review/route',
    });
    expect(lines, hasLength(3));

    reporter.flare('step.allocationFailed', {'bead': 'tg-6e4j'});
    expect(lines, hasLength(4));
    expect(jsonDecode(lines.last), {
      'type': 'flare',
      'name': 'step.allocationFailed',
      'data': {'bead': 'tg-6e4j'},
    });

    now = now.add(const Duration(seconds: 1));
    reporter.flare('step.persistFailed', {'bead': 'tg-6e4j'});
    expect(lines, hasLength(5));
    expect(
      (jsonDecode(lines.last) as Map<String, Object?>)['name'],
      'step.persistFailed',
    );

    reporter.flare('station.wedged', const <String, String>{});
    expect(lines, hasLength(6));
    reporter.flare('station.wedged', const <String, String>{});
    expect(lines, hasLength(6));
  });

  test('work-axis flare rate limits use the named subject', () {
    final now = DateTime.utc(2026, 9, 5);
    final lines = <String>[];
    final reporter = StationDiagnosticsReporter(
      writeLine: lines.add,
      now: () => now,
    );

    reporter.flare('work.mountEligibilityRefused', {
      'beadId': 'tg-a',
      'clause': 'approval: stale',
    });
    reporter.flare('work.mountEligibilityRefused', {
      'beadId': 'tg-a',
      'clause': 'attempt-cap: 3 mount attempts, cap 3',
    });
    reporter.flare('work.mountEligibilityRefused', {
      'beadId': 'tg-b',
      'clause': 'approval: stale',
    });
    reporter.flare('work.mountEligibilityRefused', {
      'nodePath': 'tg-a/review',
      'beadId': 'tg-a',
      'clause': 'approval: stale',
    });
    reporter.flare('gate.autoCloseFailed', {
      'sessionId': 's-a',
      'reason': 'first failure',
    });
    reporter.flare('gate.autoCloseFailed', {
      'sessionId': 's-a',
      'reason': 'second failure',
    });
    reporter.flare('gate.autoCloseFailed', {
      'sessionId': 's-b',
      'reason': 'first failure',
    });
    reporter.flare('session.mintRefused', {
      'workBeadId': 'w-a',
      'reason': 'first refusal',
    });
    reporter.flare('session.mintRefused', {
      'workBeadId': 'w-a',
      'reason': 'second refusal',
    });
    reporter.flare('session.mintRefused', {
      'workBeadId': 'w-b',
      'reason': 'first refusal',
    });

    expect(lines.map(jsonDecode).toList(), <Object?>[
      {
        'type': 'flare',
        'name': 'work.mountEligibilityRefused',
        'data': {'beadId': 'tg-a', 'clause': 'approval: stale'},
      },
      {
        'type': 'flare',
        'name': 'work.mountEligibilityRefused',
        'data': {'beadId': 'tg-b', 'clause': 'approval: stale'},
      },
      {
        'type': 'flare',
        'name': 'work.mountEligibilityRefused',
        'data': {
          'nodePath': 'tg-a/review',
          'beadId': 'tg-a',
          'clause': 'approval: stale',
        },
      },
      {
        'type': 'flare',
        'name': 'gate.autoCloseFailed',
        'data': {'sessionId': 's-a', 'reason': 'first failure'},
      },
      {
        'type': 'flare',
        'name': 'gate.autoCloseFailed',
        'data': {'sessionId': 's-b', 'reason': 'first failure'},
      },
      {
        'type': 'flare',
        'name': 'session.mintRefused',
        'data': {'workBeadId': 'w-a', 'reason': 'first refusal'},
      },
      {
        'type': 'flare',
        'name': 'session.mintRefused',
        'data': {'workBeadId': 'w-b', 'reason': 'first refusal'},
      },
    ]);
  });

  test('station.uncaughtError is never rate-suppressed', () {
    final lines = <String>[];
    final reporter = StationDiagnosticsReporter(writeLine: lines.add);
    final data = <String, String>{
      'error': 'Bad state: detached boom',
      'stackTrace': '#0 mountedTask',
      'attribution': 'unavailable',
    };

    reporter.flare('station.uncaughtError', data);
    reporter.flare('station.uncaughtError', data);

    expect(lines, hasLength(2));
    for (final line in lines) {
      expect(jsonDecode(line), <String, Object?>{
        'type': 'flare',
        'name': 'station.uncaughtError',
        'data': <String, Object?>{
          'error': 'Bad state: detached boom',
          'stackTrace': '#0 mountedTask',
          'attribution': 'unavailable',
        },
      });
    }
  });

  test('dispose closes the projector snapshots', () async {
    final reporter = StationDiagnosticsReporter(writeLine: (_) {});
    final done = expectLater(reporter.treeProjector.snapshots, emitsDone);

    reporter.dispose();

    await done;
  });
}

final class _RecordingTransport implements ExplorationTransport {
  _RecordingTransport({this.onFlare});

  final void Function(String name)? onFlare;
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map<String, String>.of(data)));
    onFlare?.call(name);
  }
}
