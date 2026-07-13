// The `reload` verb: the dispatch and its exit codes, over the same fake VM
// session. Zero I/O.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

/// A fake VM session — the station answers a reload cleanly.
class _FakeSession implements StationVmSession {
  @override
  Future<SourceReload> reloadSources() async => const SourcesSwapped();

  @override
  Future<Map<String, Object?>> invokeReload(String mode) async =>
      <String, Object?>{
        'ok': true,
        'value': {'mode': mode, 'generation': 2, 'rebuiltBranches': 5},
      };

  @override
  Future<void> close() async {}
}

Future<int?> _run(Directory home, StationReload client, {bool restart = false}) {
  final runner = CommandRunner<int>('space', 'test runner')
    ..addCommand(ReloadCommand(client: client));
  return runner.run([
    'reload',
    '--grid-home',
    home.path,
    if (restart) '--restart',
  ]);
}

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('reload-command-'));
  tearDown(() => home.deleteSync(recursive: true));

  void writeLock({String? vmServiceUri}) {
    File(StationLockService.lockPath(home.path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(
          StationLockRecord(
            pid: 4242,
            pgid: 4242,
            startedAt: DateTime.utc(2026, 7, 12),
            vmServiceUri: vmServiceUri,
          ).toJson(),
        ),
      );
  }

  test('a successful reload exits 0', () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final code = await _run(
      home,
      StationReload(
        connect: (_) async => _FakeSession(),
        isPidAlive: (_) => true,
      ),
    );
    expect(code, 0);
  });

  test('--restart also exits 0 (the restart mode reaches the station)',
      () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final code = await _run(
      home,
      StationReload(
        connect: (_) async => _FakeSession(),
        isPidAlive: (_) => true,
      ),
      restart: true,
    );
    expect(code, 0);
  });

  test('a live station in NO dev mode exits 1 (never a silent success)',
      () async {
    writeLock(); // a live station advertising no VM service
    final code = await _run(
      home,
      StationReload(
        connect: (_) async => throw StateError('must not connect'),
        isPidAlive: (_) => true,
      ),
    );
    expect(code, 1);
  });

  test('no station at all exits 1', () async {
    final code = await _run(
      home,
      StationReload(
        connect: (_) async => throw StateError('must not connect'),
        isPidAlive: (_) => true,
      ),
    );
    expect(code, 1);
  });
}
