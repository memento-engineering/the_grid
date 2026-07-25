import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('command values expose typed request and result variants', () {
    const rework = GridCommandRequest.rework(beadId: 'tg-1', note: 'retry');
    const resolve = GridCommandRequest.resolveGate(
      gateId: 'tgdog-gate',
      grades: {'critic': 'A'},
      rationale: 'false negative',
    );

    expect(rework, isA<GridRework>());
    expect(resolve, isA<GridGateResolve>());
    expect(
      const GridCommandResult.completed(message: 'done'),
      isA<GridCommandCompleted>(),
    );
    expect(
      const GridCommandResult.refused(code: 'no', message: 'no'),
      isA<GridCommandRefused>(),
    );
  });

  test('command implementation has no lock, process, or cli dependency', () {
    final sources = [
      File('lib/src/command/command_operation.dart').readAsStringSync(),
      File('lib/src/command/resident_command_handler.dart').readAsStringSync(),
    ].join();

    for (final forbidden in [
      'grid_cli',
      'station_lock',
      'dart:io',
      'Process.start',
      'CommandRunner',
    ]) {
      expect(sources, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
