// The reload client: the ORDER (sources first), the refusals, the
// classifications. Zero I/O: a fake VM session, a temp lock, a fake pid probe.
import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

/// A fake VM session (Fakes, not mocks): records the calls, in order.
class _FakeSession implements StationVmSession {
  _FakeSession({this.swap = const SourcesSwapped()});
  final SourceReload swap;
  final List<String> calls = <String>[];

  @override
  Future<SourceReload> reloadSources() async {
    calls.add('reloadSources');
    return swap;
  }

  @override
  Future<Map<String, Object?>> invokeReload(String mode) async {
    calls.add('invokeReload:$mode');
    return <String, Object?>{
      'ok': true,
      'value': {'mode': mode, 'generation': 1, 'rebuiltBranches': 3},
    };
  }

  @override
  Future<void> close() async => calls.add('close');
}

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('station-reload-'));
  tearDown(() => home.deleteSync(recursive: true));

  void writeLock({String? vmServiceUri}) {
    final file = File(StationLockService.lockPath(home.path))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(
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

  test('reload swaps sources FIRST, then re-composes', () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final session = _FakeSession();
    final result = await StationReload(
      connect: (_) async => session,
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path);

    expect(session.calls, ['reloadSources', 'invokeReload:reload', 'close']);
    expect(result, isA<Reloaded>());
    expect((result as Reloaded).generation, 1);
    expect(result.rebuiltBranches, 3);
  });

  test('--restart invokes the restart mode', () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final session = _FakeSession();
    await StationReload(
      connect: (_) async => session,
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path, restart: true);

    expect(session.calls, contains('invokeReload:restart'));
  });

  test('a REJECTED source swap refuses and NEVER invokes the tool', () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final session = _FakeSession(
      swap: const SourcesRejected('lib/x.dart:3:1: Error: expected ;'),
    );
    final result = await StationReload(
      connect: (_) async => session,
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path);

    expect(result, isA<ReloadRefused>());
    expect((result as ReloadRefused).reason, contains('expected ;'));
    // The tree was NEVER re-composed on un-compilable code.
    expect(session.calls, ['reloadSources', 'close']);
  });

  test('no lock → StationDown; a dead pid → StationDown', () async {
    final down = await StationReload(
      connect: (_) async => throw StateError('must not connect'),
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path);
    expect(down, isA<ReloadStationDown>());

    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final dead = await StationReload(
      connect: (_) async => throw StateError('must not connect'),
      isPidAlive: (_) => false,
    ).reload(gridHome: home.path);
    expect(dead, isA<ReloadStationDown>());
  });

  test('a live station with no advertised VM service → NotDevMode', () async {
    writeLock();
    final result = await StationReload(
      connect: (_) async => throw StateError('must not connect'),
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path);

    expect(result, isA<ReloadNotDevMode>());
    expect((result as ReloadNotDevMode).pid, 4242);
  });

  test('--vm-service-uri overrides a lock that advertises none', () async {
    writeLock();
    final session = _FakeSession();
    final result = await StationReload(
      connect: (_) async => session,
      isPidAlive: (_) => true,
    ).reload(
      gridHome: home.path,
      vmServiceUri: Uri.parse('http://127.0.0.1:9999/tok=/'),
    );

    expect(result, isA<Reloaded>());
    expect(session.calls, contains('invokeReload:reload'));
  });

  test('a station with no reload tool REFUSES loudly (the invoke throws)',
      () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final result = await StationReload(
      connect: (_) async => _ThrowingSession(),
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path);

    expect(result, isA<ReloadRefused>());
    expect(
      (result as ReloadRefused).reason,
      contains('method not found'),
      reason: "the VM's own message reaches the operator",
    );
  });
}

/// A station that never composed a `ReassembleTool`: the extension is not
/// registered, so the invoke throws — and the connection is still CLOSED.
class _ThrowingSession implements StationVmSession {
  bool closed = false;

  @override
  Future<SourceReload> reloadSources() async => const SourcesSwapped();

  @override
  Future<Map<String, Object?>> invokeReload(String mode) async =>
      throw StateError('method not found: ext.exploration.grid.reload');

  @override
  Future<void> close() async => closed = true;
}
