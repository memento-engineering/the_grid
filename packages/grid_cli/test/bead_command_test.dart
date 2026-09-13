import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

void main() {
  const fixture =
      "literal `cmd` and \$(cmd) and \$VAR and 'single'\n  trailing  ";

  test('bead set reads stdin exactly and has no inline text flag', () async {
    final client = _FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(
        BeadCommand(client: client, input: Stream.value(utf8.encode(fixture))),
      );
    expect(
      await runner.run(const [
        'bead',
        'set',
        '--bead',
        'tg-a',
        '--field',
        'notes',
        '--file',
        '-',
        '--grid-root',
        '/grid',
      ]),
      0,
    );
    expect(client.params!['content'], fixture);
    expect(client.params!['allowNotesReplacement'], isFalse);
    expect(
      () => runner.run(const [
        'bead',
        'set',
        '--bead',
        'tg-a',
        '--field',
        'notes',
        '--text',
        'bad',
        '--file',
        '-',
        '--grid-root',
        '/grid',
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test('append is restricted before reading or dispatch', () async {
    final client = _FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(BeadCommand(client: client));
    expect(
      await runner.run(const [
        'bead',
        'set',
        '--bead',
        'tg-a',
        '--field',
        'design',
        '--append',
        '--file',
        '/missing',
        '--grid-root',
        '/grid',
      ]),
      64,
    );
    expect(client.calls, 0);
  });

  test('notes replacement opt-in reaches the resident payload', () async {
    final client = _FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(
        BeadCommand(client: client, input: Stream.value(utf8.encode(fixture))),
      );

    expect(
      await runner.run(const [
        'bead',
        'set',
        '--bead',
        'tg-a',
        '--field',
        'notes',
        '--allow-notes-replacement',
        '--file',
        '-',
        '--grid-root',
        '/grid',
      ]),
      0,
    );
    expect(client.params!['allowNotesReplacement'], isTrue);
    expect(client.params!['append'], isFalse);
  });

  test(
    'notes replacement opt-in invalid combinations read and dispatch nothing',
    () async {
      for (final args in const <List<String>>[
        [
          'bead',
          'set',
          '--bead',
          'tg-a',
          '--field',
          'design',
          '--allow-notes-replacement',
          '--file',
          '/missing',
          '--grid-root',
          '/grid',
        ],
        [
          'bead',
          'set',
          '--bead',
          'tg-a',
          '--field',
          'notes',
          '--append',
          '--allow-notes-replacement',
          '--file',
          '/missing',
          '--grid-root',
          '/grid',
        ],
      ]) {
        final client = _FakeClient(const StationCommandCompleted({}));
        final runner = CommandRunner<int>('grid', 'test')
          ..addCommand(BeadCommand(client: client));
        expect(await runner.run(args), 64);
        expect(client.calls, 0);
      }
    },
  );

  test('bead rearm sends the attributed resident request', () async {
    final client = _FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(BeadCommand(client: client));

    expect(
      await runner.run(const [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        '  operator@example.test  ',
        '--reason',
        fixture,
      ]),
      0,
    );
    expect(client.gridRoot, '/grid');
    expect(client.method, 'grid/mount-attempt/rearm');
    expect(client.params, {
      'beadId': 'tg-a',
      'actor': 'operator@example.test',
      'reason': fixture,
    });
  });

  test('bead rearm preserves a reason read from a UTF-8 file', () async {
    final directory = await Directory.systemTemp.createTemp('grid-rearm-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/reason.txt');
    await file.writeAsString(fixture);
    final client = _FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(BeadCommand(client: client));

    expect(
      await runner.run([
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
        '--reason-file',
        file.path,
      ]),
      0,
    );
    expect(client.params!['reason'], fixture);
  });

  test('bead rearm preserves resident refusal exit posture', () async {
    final refused = _FakeClient(const StationCommandRefused('not exhausted'));
    final unavailable = _FakeClient(
      const StationCommandUnavailable('resident is down.'),
    );
    for (final entry in <(_FakeClient, int)>[(refused, 1), (unavailable, 69)]) {
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(BeadCommand(client: entry.$1));
      expect(
        await runner.run(const [
          'bead',
          'rearm',
          'tg-a',
          '--grid-root',
          '/grid',
          '--actor',
          'Nico',
          '--reason',
          'operator approved retry',
        ]),
        entry.$2,
      );
    }
  });

  test('bead rearm guards invalid input before resident dispatch', () async {
    final directory = await Directory.systemTemp.createTemp('grid-rearm-');
    addTearDown(() => directory.delete(recursive: true));
    final invalidUtf8 = File('${directory.path}/invalid.txt');
    await invalidUtf8.writeAsBytes(const [0xff]);
    final cases = <List<String>>[
      const [
        'bead',
        'rearm',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
        '--reason',
        'retry',
      ],
      const [
        'bead',
        'rearm',
        'tg-a',
        'tg-b',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
        '--reason',
        'retry',
      ],
      const [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        'relative',
        '--actor',
        'Nico',
        '--reason',
        'retry',
      ],
      const [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        '  ',
        '--reason',
        'retry',
      ],
      const [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
      ],
      const [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
        '--reason',
        'retry',
        '--reason-file',
        '/missing',
      ],
      const [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
        '--reason',
        '   ',
      ],
      const [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
        '--reason-file',
        '/missing',
      ],
      [
        'bead',
        'rearm',
        'tg-a',
        '--grid-root',
        '/grid',
        '--actor',
        'Nico',
        '--reason-file',
        invalidUtf8.path,
      ],
    ];

    for (final args in cases) {
      final client = _FakeClient(const StationCommandCompleted({}));
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(BeadCommand(client: client));
      expect(await runner.run(args), 64, reason: args.join(' '));
      expect(client.calls, 0, reason: args.join(' '));
    }
  });
}

final class _FakeClient extends StationCommandClient {
  _FakeClient(this.result);
  final StationCommandResult result;
  int calls = 0;
  String? gridRoot;
  String? method;
  Map<String, Object?>? params;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls++;
    this.gridRoot = gridRoot;
    this.method = method;
    this.params = params;
    return result;
  }
}
