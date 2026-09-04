import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/recording_stdout.dart';

class _FakeAttach extends StationAttach {
  _FakeAttach(this.result);
  final AttachResult result;

  @override
  Future<AttachResult> status({
    required String stateWorkspaceDir,
    Duration timeout = const Duration(seconds: 3),
  }) async => result;
}

StationLockRecord record({
  StationLifecyclePhase phase = StationLifecyclePhase.live,
}) => StationLockRecord(
  pid: 42,
  pgid: 42,
  startedAt: DateTime.utc(2026),
  phase: phase,
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
        StatusCommand(stationName: 'lunar', attach: _FakeAttach(result)),
      );
    return runner.run(['status', '--state-workspace', temp.path, ...extra]);
  }

  Future<({int? code, String stderr})> runCaptured(AttachResult result) async {
    final stderrBytes = ByteConsumer();
    final stderrSink = RecordingStdout(stderrBytes);
    final code = await IOOverrides.runZoned(
      () => run(result),
      stderr: () => stderrSink,
    );
    await stderrSink.flush();
    return (code: code, stderr: stderrBytes.text);
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

  test(
    'starting reports BOOTING without crash-investigation language',
    () async {
      final result = await runCaptured(
        Starting(
          pid: 42,
          record: record(phase: StationLifecyclePhase.acquired),
        ),
      );

      expect(result.code, 1);
      expect(result.stderr, allOf(contains('BOOTING'), contains('pid 42')));
      expect(result.stderr, isNot(contains('investigate')));
      expect(result.stderr, isNot(contains('dead')));
    },
  );

  test('unreachable and unauthorized refuse', () async {
    expect(await run(Unreachable(pid: 42, record: record())), 1);
    expect(await run(Unauthorized(record())), 1);
  });

  test('grid_cli barrel exports the lifecycle phase', () {
    expect(StationLifecyclePhase.values, [
      StationLifecyclePhase.acquired,
      StationLifecyclePhase.live,
      StationLifecyclePhase.releasing,
    ]);
  });
}
