import 'dart:convert';
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
    Duration slowThreshold = const Duration(seconds: 3),
    Duration timeout = const Duration(seconds: 15),
  }) async => result;
}

StationLockRecord record({
  StationLifecyclePhase phase = StationLifecyclePhase.live,
  String controlUrl = 'http://127.0.0.1:42',
  String token = 'secret',
}) => StationLockRecord(
  pid: 42,
  pgid: 42,
  startedAt: DateTime.utc(2026),
  phase: phase,
  controlUrl: controlUrl,
  token: token,
);

const statusPayload = <String, Object?>{
  'station': <String, Object?>{
    'substation': 'lunar',
    'stateStore': '/tmp/state',
    'workRoot': '/tmp/work',
    'dryRun': false,
  },
  'process': <String, Object?>{
    'pid': 42,
    'uptimeSeconds': 10,
    'version': 'test-vm',
  },
  'work': <String, Object?>{
    'ready': 1,
    'mounted': 1,
    'liveSessions': 1,
    'lastSyncAt': null,
  },
};

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

  Future<int?> runWithAttach(
    StationAttach attach, [
    List<String> extra = const [],
  ]) {
    final runner = CommandRunner<int>('lunar', 'test')
      ..addCommand(StatusCommand(stationName: 'lunar', attach: attach));
    return runner.run(['status', '--state-workspace', temp.path, ...extra]);
  }

  Future<int?> run(AttachResult result, [List<String> extra = const []]) =>
      runWithAttach(_FakeAttach(result), extra);

  Future<({int? code, String stderr, String stdout})> runCapturedWithAttach(
    StationAttach attach,
  ) async {
    final stdoutBytes = ByteConsumer();
    final stdoutSink = RecordingStdout(stdoutBytes);
    final stderrBytes = ByteConsumer();
    final stderrSink = RecordingStdout(stderrBytes);
    final code = await IOOverrides.runZoned(
      () => runWithAttach(attach),
      stdout: () => stdoutSink,
      stderr: () => stderrSink,
    );
    await Future.wait([stdoutSink.flush(), stderrSink.flush()]);
    return (code: code, stderr: stderrBytes.text, stdout: stdoutBytes.text);
  }

  Future<({int? code, String stderr, String stdout})> runCaptured(
    AttachResult result,
  ) => runCapturedWithAttach(_FakeAttach(result));

  test('live payload retains the exact station UP first line', () async {
    final result = await runCaptured(
      Up(record: record(), payload: statusPayload),
    );

    expect(result.code, 0);
    expect(const LineSplitter().convert(result.stdout).first, 'station: UP');
    expect(result.stderr, isEmpty);
  });

  test(
    'a live authenticated door delayed past three seconds renders slow UP',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer secret',
        );
        await Future<void>.delayed(const Duration(milliseconds: 3200));
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(statusPayload));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final liveRecord = record(controlUrl: 'http://127.0.0.1:${server.port}');
      File(
        StationLockService.lockPath(temp.path),
      ).writeAsStringSync(jsonEncode(liveRecord.toJson()));

      final result = await runCapturedWithAttach(
        StationAttach(isPidAlive: (_) => true),
      );

      expect(result.code, 0);
      final firstLine = const LineSplitter().convert(result.stdout).first;
      final match = RegExp(
        r'^station: UP — alive but slow \(([0-9]+\.[0-9]) s\)$',
      ).firstMatch(firstLine);
      expect(match, isNotNull);
      expect(double.parse(match!.group(1)!), greaterThanOrEqualTo(3.2));
      final allOutput = '${result.stdout}${result.stderr}';
      expect(allOutput, isNot(contains('unreachable')));
      expect(allOutput, isNot(contains('(station: down)')));
      expect(result.stderr, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

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

  test('unreachable remains the down refusal', () async {
    final result = await runCaptured(Unreachable(pid: 42, record: record()));

    expect(result.code, 1);
    expect(result.stderr, contains('pid 42 but it is unreachable'));
    expect(result.stderr, contains('(station: down)'));
    expect(result.stderr, isNot(contains('stale or foreign')));
  });

  test(
    '401 remains the stale-or-foreign refusal, never station down',
    () async {
      final result = await runCaptured(Unauthorized(record()));

      expect(result.code, 1);
      expect(
        result.stderr,
        contains('rejected this client\'s bearer token (401)'),
      );
      expect(result.stderr, contains('stale or foreign'));
      expect(result.stderr, isNot(contains('(station: down)')));
    },
  );

  test('grid_cli barrel exports the lifecycle phase', () {
    expect(StationLifecyclePhase.values, [
      StationLifecyclePhase.acquired,
      StationLifecyclePhase.live,
      StationLifecyclePhase.releasing,
    ]);
  });
}
