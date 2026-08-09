import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeAttach extends StationAttach {
  _FakeAttach(this.result);
  final StopResult result;
  String? home;

  @override
  Future<StopResult> stop({
    required String stateWorkspaceDir,
    Duration grace = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    home = stateWorkspaceDir;
    return result;
  }
}

void seedState(String home) {
  final beads = Directory(p.join(home, '.grid', '.beads'))
    ..createSync(recursive: true);
  File(
    p.join(beads.path, 'metadata.json'),
  ).writeAsStringSync('{"dolt_mode":"embedded"}');
}

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('resident-down-');
    seedState(temp.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<int?> run(StopResult result) {
    final runner = CommandRunner<int>('lunar', 'test')
      ..addCommand(
        DownCommand(stationName: 'lunar', attach: _FakeAttach(result)),
      );
    return runner.run(['down', '--state-workspace', temp.path]);
  }

  test('already down and stopped are successful', () async {
    expect(await run(const AlreadyDown()), 0);
    expect(await run(const Stopped(42)), 0);
  });

  test('timeout refuses without escalation', () async {
    expect(await run(const TimedOut(42)), 1);
  });

  test('missing root is a usage refusal', () async {
    final runner = CommandRunner<int>('lunar', 'test')
      ..addCommand(DownCommand(stationName: 'lunar'));
    expect(await runner.run(['down']), 64);
  });
}
