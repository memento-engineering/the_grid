import 'dart:convert';

import 'package:grid_cli/grid_cli.dart';
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

  test('throwing line writer propagates', () {
    final reporter = StationDiagnosticsReporter(
      writeLine: (_) => throw StateError('disk full'),
    );

    expect(
      () => reporter.flare('work.held', const <String, String>{}),
      throwsStateError,
    );
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

    reporter.flare(
      'step.persistFailed',
      {'bead': 'tg-6e4j', 'nodePath': 'tg-6e4j/review/route'},
    );
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

  test('dispose closes the projector snapshots', () async {
    final reporter = StationDiagnosticsReporter(writeLine: (_) {});
    final done = expectLater(reporter.treeProjector.snapshots, emitsDone);

    reporter.dispose();

    await done;
  });
}
