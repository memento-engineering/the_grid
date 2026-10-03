import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/recording_stdout.dart';

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

  Future<({int? code, String out, String err})> run(StopResult result) async {
    final outConsumer = ByteConsumer();
    final errConsumer = ByteConsumer();
    final outSink = RecordingStdout(outConsumer);
    final errSink = RecordingStdout(errConsumer);
    final runner = CommandRunner<int>('lunar', 'test')
      ..addCommand(
        DownCommand(stationName: 'lunar', attach: _FakeAttach(result)),
      );
    final code = await IOOverrides.runZoned(
      () => runner.run(['down', '--state-workspace', temp.path]),
      stdout: () => outSink,
      stderr: () => errSink,
    );
    await outSink.flush();
    await errSink.flush();
    return (code: code, out: outConsumer.text, err: errConsumer.text);
  }

  test('already down and stopped are successful', () async {
    expect((await run(const AlreadyDown())).code, 0);
    expect((await run(const Stopped(42))).code, 0);
  });

  test(
    'timeout prints the current refusal exactly for a legacy lock',
    () async {
      _writeLock(
        temp.path,
        StationLockRecord(
          pid: 42,
          pgid: 42,
          startedAt: DateTime.utc(2026, 9, 17),
        ),
      );

      final outcome = await run(const TimedOut(42));

      expect(outcome.code, 1);
      expect(
        outcome.err,
        'lunar down: SIGTERM sent to pid 42 but it did not exit and release '
        'its lock within the grace window — this client never escalates to '
        'SIGKILL. Investigate pid 42 directly.\n',
      );
    },
  );

  for (final lockState in ['absent', 'unreadable']) {
    test('timeout adds no diagnostics when the lock is $lockState', () async {
      if (lockState == 'unreadable') {
        File(
          StationLockService.lockPath(temp.path),
        ).writeAsStringSync('{not json');
      }

      final outcome = await run(const TimedOut(42));

      expect(outcome.code, 1);
      expect(
        outcome.err,
        'lunar down: SIGTERM sent to pid 42 but it did not exit and release '
        'its lock within the grace window — this client never escalates to '
        'SIGKILL. Investigate pid 42 directly.\n',
      );
    });
  }

  test(
    'timeout prints lock-backed unwind diagnostics in stored order',
    () async {
      _writeLock(
        temp.path,
        StationLockRecord(
          pid: 42,
          pgid: 42,
          startedAt: DateTime.utc(2026, 9, 17),
          unwind: StationUnwindRecord(
            step: 'store connections close',
            startedAt: DateTime.utc(2026, 9, 17, 7, 31),
            outstanding: const [
              'runtime provider dispose',
              '"state" (127.0.0.1:49967/lunar) — close pending',
            ],
          ),
        ),
      );

      final outcome = await run(const TimedOut(42));

      expect(outcome.code, 1);
      expect(
        outcome.err.split('\n'),
        containsAllInOrder([
          startsWith('lunar down: SIGTERM sent to pid 42'),
          'lunar down: resident unwind step: store connections close '
              '(started at 2026-09-17T07:31:00.000Z).',
          'lunar down: resident unwind outstanding: runtime provider dispose.',
          'lunar down: resident unwind outstanding: "state" '
              '(127.0.0.1:49967/lunar) — close pending.',
        ]),
      );
    },
  );

  test('missing root is a usage refusal', () async {
    final runner = CommandRunner<int>('lunar', 'test')
      ..addCommand(DownCommand(stationName: 'lunar'));
    expect(await runner.run(['down']), 64);
  });
}

void _writeLock(String home, StationLockRecord record) {
  File(
    StationLockService.lockPath(home),
  ).writeAsStringSync(jsonEncode(record.toJson()));
}
