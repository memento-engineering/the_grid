import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeAttach extends StationAttach {
  _FakeAttach(this.result);
  final AttachResult result;

  @override
  Future<AttachResult> status({
    required String stateWorkspaceDir,
    Duration timeout = const Duration(seconds: 3),
  }) async => result;
}

StationLockRecord record() => StationLockRecord(
  pid: 42,
  pgid: 42,
  startedAt: DateTime.utc(2026),
  controlUrl: 'http://127.0.0.1:42',
  token: 'secret',
);

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
    temp = Directory.systemTemp.createTempSync('resident-status-');
    seedState(temp.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<int?> run(AttachResult result, [List<String> extra = const []]) {
    final runner = CommandRunner<int>('lunar', 'test')
      ..addCommand(
        ResidentStatusCommand(
          stationName: 'lunar',
          attach: _FakeAttach(result),
        ),
      );
    return runner.run(['status', '--state-workspace', temp.path, ...extra]);
  }

  test('live payload renders successfully', () async {
    expect(
      await run(
        Up(
          record: record(),
          payload: const {
            'station': <String, Object?>{},
            'process': <String, Object?>{},
            'work': <String, Object?>{},
          },
        ),
      ),
      0,
    );
  });

  test('down without a discoverable work workspace succeeds', () async {
    expect(await run(const Down(), ['--workspace', '${temp.path}/absent']), 0);
  });

  test('stale and unauthorized refuse', () async {
    expect(await run(Stale(pid: 42, record: record())), 1);
    expect(await run(Unauthorized(record())), 1);
  });
}
