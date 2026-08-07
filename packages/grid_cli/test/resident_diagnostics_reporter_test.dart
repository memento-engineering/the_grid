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

  test('dispose closes the projector snapshots', () async {
    final reporter = StationDiagnosticsReporter(writeLine: (_) {});
    final done = expectLater(reporter.treeProjector.snapshots, emitsDone);

    reporter.dispose();

    await done;
  });
}
