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
  String? controlUrl = 'http://127.0.0.1:42',
  String? token = 'secret',
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
    StationAttach attach, [
    List<String> extra = const [],
  ]) async {
    final stdoutBytes = ByteConsumer();
    final stdoutSink = RecordingStdout(stdoutBytes);
    final stderrBytes = ByteConsumer();
    final stderrSink = RecordingStdout(stderrBytes);
    final code = await IOOverrides.runZoned(
      () => runWithAttach(attach, extra),
      stdout: () => stdoutSink,
      stderr: () => stderrSink,
    );
    await Future.wait([stdoutSink.flush(), stderrSink.flush()]);
    return (code: code, stderr: stderrBytes.text, stdout: stdoutBytes.text);
  }

  Future<({int? code, String stderr, String stdout})> runCaptured(
    AttachResult result, [
    List<String> extra = const [],
  ]) => runCapturedWithAttach(_FakeAttach(result), extra);

  test('live payload retains the exact station UP first line', () async {
    final result = await runCaptured(
      Up(record: record(), payload: statusPayload),
    );

    expect(result.code, 0);
    expect(const LineSplitter().convert(result.stdout).first, 'station: UP');
    expect(result.stderr, isEmpty);
  });

  test('admission renders a budget and remains raw in JSON mode', () async {
    final payload = <String, Object?>{
      ...statusPayload,
      'admission': <String, Object?>{
        'maxAgents': 4,
        'reservations': <Object?>[
          <String, Object?>{
            'bead': 'tg-null-session',
            'sessionId': null,
            'since': '2026-09-07T10:00:00.000Z',
          },
        ],
        'refusals': <Object?>[
          <String, Object?>{
            'bead': 'tg-refused',
            'clause': 'approval: not approved - run the approve verb',
            'since': '2026-09-07T11:00:00.000Z',
          },
        ],
        'zeroAdmissionWaiters': <Object?>[
          <String, Object?>{
            'bead': 'tg-wait-z',
            'substation': 'zeta',
            'since': '2026-09-07T12:00:00.000Z',
          },
          <String, Object?>{
            'bead': 'tg-wait-a',
            'substation': 'alpha',
            'since': '2026-09-07T13:00:00.000Z',
          },
        ],
      },
    };

    final human = await runCaptured(Up(record: record(), payload: payload));
    expect(human.code, 0);
    expect(human.stdout, contains('  budget: 1/4\n'));
    expect(
      const LineSplitter()
          .convert(human.stdout)
          .where((line) => line.contains('admission: BLOCKED')),
      [
        '  admission: BLOCKED — 0 admitted with pending work: '
            'tg-wait-a, tg-wait-z',
      ],
    );
    expect(human.stderr, isEmpty);

    final json = await runCaptured(Up(record: record(), payload: payload), [
      '--json',
    ]);
    expect(json.code, 0);
    expect(const LineSplitter().convert(json.stdout), hasLength(1));
    expect(json.stdout, '${jsonEncode(payload)}\n');
    final decoded = jsonDecode(json.stdout) as Map<String, Object?>;
    expect(decoded, payload);
    final admission = decoded['admission'] as Map<String, Object?>;
    final reservations = admission['reservations'] as List<Object?>;
    final reservation = reservations.single as Map<String, Object?>;
    expect(reservation['sessionId'], isNull);
    final refusals = admission['refusals'] as List<Object?>;
    expect(
      refusals.single,
      containsPair('clause', 'approval: not approved - run the approve verb'),
    );
    expect(json.stderr, isEmpty);

    final emptyPayload = <String, Object?>{
      ...payload,
      'admission': <String, Object?>{
        ...(payload['admission']! as Map<String, Object?>),
        'zeroAdmissionWaiters': <Object?>[],
      },
    };
    final empty = await runCaptured(
      Up(record: record(), payload: emptyPayload),
    );
    expect(empty.stdout, isNot(contains('admission: BLOCKED')));
  });

  test('a payload without admission preserves the legacy UP output', () async {
    final result = await runCaptured(
      Up(record: record(), payload: statusPayload),
    );

    expect(result.code, 0);
    expect(
      result.stdout,
      'station: UP\n'
      '  substation: lunar\n'
      '  state store: /tmp/state\n'
      '  work root: /tmp/work\n'
      '  mode: LIVE\n'
      '  pid: 42  ·  uptime: 10s  ·  version: test-vm\n'
      '  ready: 1  ·  mounted: 1  ·  live sessions: 1  ·  last sync: null\n',
    );
    expect(result.stderr, isEmpty);
    expect(result.stdout, isNot(contains('admission: BLOCKED')));
  });

  test('AC-5 slow-up unchanged in human and JSON output', () async {
    final slow = SlowUp(
      record: record(),
      payload: statusPayload,
      elapsed: const Duration(milliseconds: 3200),
    );

    final human = await runCaptured(slow);
    expect(human.code, 0);
    expect(
      const LineSplitter().convert(human.stdout).first,
      'station: UP — alive but slow (3.2 s)',
    );
    expect(human.stdout, isNot(contains('(station: down)')));
    expect(human.stderr, isEmpty);

    final json = await runCaptured(slow, ['--json']);
    expect(json.code, 0);
    expect(const LineSplitter().convert(json.stdout), hasLength(1));
    expect(jsonDecode(json.stdout), statusPayload);
    expect(json.stderr, isEmpty);
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

  test('AC-1 live PID refused door renders alive connection failure', () async {
    final unreachable = Unreachable(
      pid: 42,
      record: record(),
      failure: DoorFailure.connectionFailed,
      hardBound: const Duration(seconds: 15),
    );

    final human = await runCaptured(unreachable);
    expect(human.code, 1);
    expect(human.stdout, isEmpty);
    expect(human.stderr, contains('process pid 42 is alive'));
    expect(
      human.stderr,
      contains('control door at http://127.0.0.1:42/status'),
    );
    expect(
      human.stderr,
      contains('failed to connect before the 15.0 s hard bound'),
    );
    expect(
      human.stderr,
      contains('(station: alive; control door: connection failed)'),
    );
    expect(
      human.stderr.trimRight(),
      endsWith('check the door, not the process'),
    );
    expect(human.stderr, isNot(contains('dead')));
    expect(human.stderr, isNot(contains('(station: down)')));

    final json = await runCaptured(unreachable, ['--json']);
    expect(json.code, 1);
    expect(json.stderr, isEmpty);
    expect(const LineSplitter().convert(json.stdout), hasLength(1));
    expect(jsonDecode(json.stdout), <String, Object?>{
      'classification': 'control_door_unavailable',
      'process': <String, Object?>{'pid': 42, 'alive': true},
      'controlDoor': <String, Object?>{
        'url': 'http://127.0.0.1:42/status',
        'failure': 'connection_failed',
        'hardBoundMilliseconds': 15000,
      },
    });
  });

  test('AC-2 live PID timed-out door renders its 0.2 s bound', () async {
    final unreachable = Unreachable(
      pid: 42,
      record: record(),
      failure: DoorFailure.timedOut,
      hardBound: const Duration(milliseconds: 200),
    );

    final human = await runCaptured(unreachable);
    expect(human.code, 1);
    expect(human.stdout, isEmpty);
    expect(human.stderr, contains('process pid 42 is alive'));
    expect(
      human.stderr,
      contains('control door at http://127.0.0.1:42/status'),
    );
    expect(
      human.stderr,
      contains('did not answer within the 0.2 s hard bound'),
    );
    expect(human.stderr, contains('(station: alive; control door: timed out)'));
    expect(human.stderr, isNot(contains('dead')));
    expect(human.stderr, isNot(contains('(station: down)')));

    final json = await runCaptured(unreachable, ['--json']);
    expect(json.code, 1);
    expect(json.stderr, isEmpty);
    final payload = jsonDecode(json.stdout) as Map<String, Object?>;
    expect(payload['classification'], 'control_door_unavailable');
    expect(payload['process'], <String, Object?>{'pid': 42, 'alive': true});
    expect(payload['controlDoor'], <String, Object?>{
      'url': 'http://127.0.0.1:42/status',
      'failure': 'timed_out',
      'hardBoundMilliseconds': 200,
    });
  });

  test('AC-3 dead PID renders the distinct down result', () async {
    final dead = DeadPid(pid: 42, record: record());

    final human = await runCaptured(dead);
    expect(human.code, 1);
    expect(human.stdout, isEmpty);
    expect(human.stderr, contains('station.lock'));
    expect(human.stderr, contains('names pid 42'));
    expect(human.stderr, contains('the pid probe found no live process'));
    expect(human.stderr, contains('(station: down)'));

    final json = await runCaptured(dead, ['--json']);
    expect(json.code, 1);
    expect(json.stderr, isEmpty);
    expect(const LineSplitter().convert(json.stdout), hasLength(1));
    expect(jsonDecode(json.stdout), <String, Object?>{
      'classification': 'pid_dead',
      'process': <String, Object?>{'pid': 42, 'alive': false},
    });
  });

  test(
    'AC-4 live PID malformed door response renders invalid response',
    () async {
      final unreachable = Unreachable(
        pid: 42,
        record: record(),
        failure: DoorFailure.invalidResponse,
        hardBound: const Duration(seconds: 15),
      );

      final human = await runCaptured(unreachable);
      expect(human.code, 1);
      expect(human.stdout, isEmpty);
      expect(human.stderr, contains('process pid 42 is alive'));
      expect(
        human.stderr,
        contains(
          'control door at http://127.0.0.1:42/status did not return a valid '
          'status response within the 15.0 s hard bound',
        ),
      );
      expect(
        human.stderr,
        contains('(station: alive; control door: invalid response)'),
      );
      expect(human.stderr, isNot(contains('dead')));
      expect(human.stderr, isNot(contains('(station: down)')));

      final json = await runCaptured(unreachable, ['--json']);
      expect(json.code, 1);
      expect(json.stderr, isEmpty);
      final payload = jsonDecode(json.stdout) as Map<String, Object?>;
      expect(payload['classification'], 'control_door_unavailable');
      expect(payload['process'], <String, Object?>{'pid': 42, 'alive': true});
      expect(payload['controlDoor'], <String, Object?>{
        'url': 'http://127.0.0.1:42/status',
        'failure': 'invalid_response',
        'hardBoundMilliseconds': 15000,
      });
    },
  );

  test('releasing and unadvertised live doors remain explicit', () async {
    final releasing = await runCaptured(
      Unreachable(
        pid: 42,
        record: record(phase: StationLifecyclePhase.releasing),
        failure: DoorFailure.releasing,
        hardBound: const Duration(seconds: 15),
      ),
    );
    expect(releasing.code, 1);
    expect(releasing.stderr, contains('process pid 42 is alive and releasing'));
    expect(releasing.stderr, contains('control door at'));
    expect(releasing.stderr, contains('was not probed'));
    expect(releasing.stderr, isNot(contains('dead')));
    expect(releasing.stderr, isNot(contains('(station: down)')));

    final notAdvertised = await runCaptured(
      Unreachable(
        pid: 42,
        record: record(controlUrl: null, token: null),
        failure: DoorFailure.notAdvertised,
        hardBound: const Duration(seconds: 15),
      ),
      ['--json'],
    );
    expect(notAdvertised.code, 1);
    expect(notAdvertised.stderr, isEmpty);
    final payload = jsonDecode(notAdvertised.stdout) as Map<String, Object?>;
    expect(payload['controlDoor'], <String, Object?>{
      'url': null,
      'failure': 'not_advertised',
      'hardBoundMilliseconds': 15000,
    });
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
