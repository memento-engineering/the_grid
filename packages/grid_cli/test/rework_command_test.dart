import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/src/rework_command.dart';
import 'package:grid_cli/src/station_command_client.dart';
import 'package:test/test.dart';

import 'support/recording_stdout.dart';

/// Offline proofs for the resident-door `grid rework` client.
///
/// Ported from the pre-door suite: request serialization, completed/refused/
/// unavailable outcomes, bead arity, absolute-root guards, and beyond-cap
/// actor/note syntax guards. Removed with the retired second-process path:
/// direct store export/write, prefix and note-root options, session cursor and
/// round projection; resident semantics live in station_command_handler_test.dart.
void main() {
  const fixture =
      "literal `cmd` and \$(cmd) and \$VAR and 'single'\n  trailing  ";
  CommandRunner<int> runner(FakeClient client) =>
      CommandRunner<int>('grid', 'test')
        ..addCommand(ReworkCommand(client: client));

  Future<({int? code, String stderr, String stdout})> runCaptured(
    FakeClient client,
  ) async {
    final stdoutBytes = ByteConsumer();
    final stdoutSink = RecordingStdout(stdoutBytes);
    final stderrBytes = ByteConsumer();
    final stderrSink = RecordingStdout(stderrBytes);
    final code = await IOOverrides.runZoned(
      () => runner(client).run(['rework', 'work-1', '--grid-root', '/grid']),
      stdout: () => stdoutSink,
      stderr: () => stderrSink,
    );
    await Future.wait([stdoutSink.flush(), stderrSink.flush()]);
    return (code: code, stderr: stderrBytes.text, stdout: stdoutBytes.text);
  }

  test('reports the closed session and gate receipts on stdout', () async {
    final result = await runCaptured(
      FakeClient(
        const StationCommandCompleted({
          'closedSession': {
            'sessionId': 'tgdog-session',
            'reason': 'reworked',
            'disposition': 'voided',
          },
          'closedGates': [
            {
              'gateId': 'tgdog-z-gate',
              'sessionId': 'tgdog-session',
              'cause': 'superseded-round',
            },
            {
              'gateId': 'tgdog-a-gate',
              'sessionId': 'tgdog-session',
              'cause': 'superseded-round',
            },
          ],
          'successorSession': {
            'sessionId': 'tgdog-successor',
            'workBeadId': 'work-1',
            'approvalRev': 'approved-rev',
          },
        }),
      ),
    );

    expect(result.code, 0);
    expect(
      result.stdout,
      'grid rework — voided session tgdog-session (reworked).\n'
      'grid rework — closed gate tgdog-a-gate (superseded-round).\n'
      'grid rework — closed gate tgdog-z-gate (superseded-round).\n'
      'grid rework — minted session tgdog-successor for work-1 at approval '
      'approved-rev.\n',
    );
    expect(result.stderr, isEmpty);
  });

  test('reports a pending successor from a complete retirement', () async {
    final result = await runCaptured(
      FakeClient(
        const StationCommandCompleted({
          'closedSession': {
            'sessionId': 'tgdog-session',
            'reason': 'reworked',
            'disposition': 'voided',
          },
          'closedGates': [],
          'successorSession': 'pending',
        }),
      ),
    );

    expect(result.code, 0);
    expect(
      result.stdout,
      'grid rework — voided session tgdog-session (reworked).\n'
      'grid rework — successor: pending.\n',
    );
    expect(result.stderr, isEmpty);
  });

  for (final fixture in <({String name, Map<String, Object?> value})>[
    (
      name: 'missing closed session',
      value: const {'closedGates': [], 'successorSession': 'pending'},
    ),
    (
      name: 'malformed gate receipt',
      value: const {
        'closedSession': {
          'sessionId': 'tgdog-session',
          'reason': 'reworked',
          'disposition': 'voided',
        },
        'closedGates': [
          {
            'gateId': 'tgdog-gate',
            'sessionId': 'tgdog-session',
            'cause': 'operator',
          },
        ],
        'successorSession': 'pending',
      },
    ),
  ]) {
    test('rejects ${fixture.name} without partial stdout', () async {
      final result = await runCaptured(
        FakeClient(StationCommandCompleted(fixture.value)),
      );

      expect(result.code, 64);
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        'grid rework: resident completed without a complete retirement receipt.\n',
      );
    });
  }

  test('reports a resident close refusal on stderr only', () async {
    final result = await runCaptured(
      FakeClient(
        const StationCommandRefused(
          'Could not close session "tgdog-session" for rework: writer failed',
        ),
      ),
    );

    expect(result.code, 64);
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      'grid rework: Could not close session "tgdog-session" for rework: '
      'writer failed\n',
    );
  });

  test('sends all authorization fields through resident door', () async {
    final client = FakeClient(_mintedCompleted());
    expect(
      await runner(client).run([
        'rework',
        'work-1',
        '--grid-root',
        '/grid',
        '--beyond-cap',
        '--actor',
        'Nico',
        '--note',
        'approved',
      ]),
      0,
    );
    expect(client.method, 'grid/rework');
    expect(client.params, {
      'beadId': 'work-1',
      'note': 'approved',
      'beyondCap': true,
      'actor': 'Nico',
    });
  });

  test('--note-file preserves shell-sensitive text exactly', () async {
    final temp = await Directory.systemTemp.createTemp('grid-rework-text-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/note.txt');
    await file.writeAsString(fixture, encoding: utf8, flush: true);
    final client = FakeClient(_mintedCompleted());

    expect(
      await runner(client).run([
        'rework',
        'work-1',
        '--grid-root',
        '/grid',
        '--note-file',
        file.path,
      ]),
      0,
    );
    expect(client.params!['note'], fixture);
  });

  test('--note and --note-file refuse before dispatch', () async {
    final client = FakeClient(_mintedCompleted());
    expect(
      await runner(client).run(const [
        'rework',
        'work-1',
        '--grid-root',
        '/grid',
        '--note',
        fixture,
        '--note-file',
        '-',
      ]),
      64,
    );
    expect(client.calls, 0);
  });

  for (final result in <StationCommandResult>[
    const StationCommandRefused('no session'),
    const StationCommandUnavailable('station.lock is absent'),
  ]) {
    test('resident refusal is exit 64 for ${result.runtimeType}', () async {
      final client = FakeClient(result);
      expect(
        await runner(client).run(['rework', 'work-1', '--grid-root', '/grid']),
        64,
      );
      expect(client.calls, 1);
    });
  }

  test('arity and root guards send nothing', () async {
    for (final args in <List<String>>[
      ['rework', '--grid-root', '/grid'],
      ['rework', 'work-1', 'work-2', '--grid-root', '/grid'],
      ['rework', 'work-1'],
      ['rework', 'work-1', '--grid-root', 'relative'],
    ]) {
      final client = FakeClient(_mintedCompleted());
      expect(await runner(client).run(args), 64);
      expect(client.calls, 0);
    }
  });

  test('beyond-cap actor and note guards send nothing', () async {
    for (final args in <List<String>>[
      ['rework', 'work-1', '--grid-root', '/grid', '--beyond-cap'],
      [
        'rework',
        'work-1',
        '--grid-root',
        '/grid',
        '--beyond-cap',
        '--actor',
        'Nico',
      ],
    ]) {
      final client = FakeClient(_mintedCompleted());
      expect(await runner(client).run(args), 64);
      expect(client.calls, 0);
    }
  });
}

StationCommandCompleted _mintedCompleted() => const StationCommandCompleted({
  'closedSession': {
    'sessionId': 'tgdog-session',
    'reason': 'reworked',
    'disposition': 'voided',
  },
  'closedGates': [],
  'successorSession': {
    'sessionId': 'tgdog-successor',
    'workBeadId': 'work-1',
    'approvalRev': 'approved-rev',
  },
});

final class FakeClient extends StationCommandClient {
  FakeClient(this.result);

  final StationCommandResult result;
  int calls = 0;
  String? method;
  Map<String, Object?>? params;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls++;
    this.method = method;
    this.params = params;
    return result;
  }
}
