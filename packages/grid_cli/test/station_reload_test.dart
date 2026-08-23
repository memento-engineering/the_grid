// The reload client: the ORDER (sources first), the refusals, the
// classifications. Zero I/O: a fake VM session, a temp lock, a fake pid probe.
import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// A fake VM session (Fakes, not mocks): records the calls, in order.
class _FakeSession implements StationVmSession {
  _FakeSession({
    this.capability = const ReloadSupported(),
    this.swap = const SourcesSwapped(),
  });
  final ReloadCapability capability;
  final SourceReload swap;
  final List<String> calls = <String>[];

  @override
  Future<ReloadCapability> probeReloadCapability() async {
    calls.add('probeReloadCapability');
    return capability;
  }

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

class _FakeVmService extends VmService {
  _FakeVmService({required this.vm, required this.isolates})
    : super(const Stream<dynamic>.empty(), (_) {});

  final VM vm;
  final Map<String, Isolate> isolates;
  final List<String> requestedIsolateIds = <String>[];

  @override
  Future<VM> getVM() async => vm;

  @override
  Future<Isolate> getIsolate(String isolateId) async {
    requestedIsolateIds.add(isolateId);
    return isolates[isolateId]!;
  }
}

Future<({StationVmSession session, _FakeVmService service})> connectPayload({
  required List<IsolateRef> isolateRefs,
  required Map<String, Isolate> isolates,
}) async {
  final service = _FakeVmService(
    vm: VM(isolates: isolateRefs),
    isolates: isolates,
  );
  final session = await VmServiceSession.connect(
    Uri.parse('http://127.0.0.1:1234/token=/'),
    connectService: (_) async => service,
  );
  return (session: session, service: service);
}

Isolate isolatePayload(String id, {String? rootUri}) => Isolate(
  id: id,
  name: 'lunar',
  rootLib: rootUri == null ? null : LibraryRef(id: 'libraries/1', uri: rootUri),
);

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

  test('probe refuses a snapshot root reported by the live VM', () async {
    final payload = await connectPayload(
      isolateRefs: <IsolateRef>[IsolateRef(id: 'isolates/user')],
      isolates: <String, Isolate>{
        'isolates/user': isolatePayload(
          'isolates/user',
          rootUri: 'file:///tmp/lunar.dart.snapshot',
        ),
      },
    );
    addTearDown(payload.session.close);

    final capability = await payload.session.probeReloadCapability();

    expect(capability, isA<ReloadUnsupported>());
    expect(
      (capability as ReloadUnsupported).reason,
      contains('has no incremental compiler'),
    );
  });

  test(
    'probe supports a source root reported by a snapshot-launched resident',
    () async {
      final payload = await connectPayload(
        isolateRefs: <IsolateRef>[IsolateRef(id: 'isolates/user')],
        isolates: <String, Isolate>{
          'isolates/user': isolatePayload(
            'isolates/user',
            rootUri: 'package:lunar/lunar.dart',
          ),
        },
      );
      addTearDown(payload.session.close);

      expect(
        await payload.session.probeReloadCapability(),
        isA<ReloadSupported>(),
      );
    },
  );

  for (final rootUri in <String?>[null, '']) {
    test('probe fails closed for root URI ${rootUri ?? 'null'}', () async {
      final payload = await connectPayload(
        isolateRefs: <IsolateRef>[IsolateRef(id: 'isolates/user')],
        isolates: <String, Isolate>{
          'isolates/user': isolatePayload('isolates/user', rootUri: rootUri),
        },
      );
      addTearDown(payload.session.close);

      final capability = await payload.session.probeReloadCapability();

      expect(capability, isA<ReloadUnsupported>());
      expect(
        (capability as ReloadUnsupported).reason,
        contains('reload capability cannot be established'),
      );
    });
  }

  test('connect skips leading system and id-less isolates', () async {
    final payload = await connectPayload(
      isolateRefs: <IsolateRef>[
        IsolateRef(id: 'isolates/system', isSystemIsolate: true),
        IsolateRef(name: 'id-less'),
        IsolateRef(id: 'isolates/user', isSystemIsolate: false),
      ],
      isolates: <String, Isolate>{
        'isolates/user': isolatePayload(
          'isolates/user',
          rootUri: 'package:lunar/lunar.dart',
        ),
      },
    );
    addTearDown(payload.session.close);

    expect(
      await payload.session.probeReloadCapability(),
      isA<ReloadSupported>(),
    );
    expect(payload.service.requestedIsolateIds, <String>['isolates/user']);
  });

  test('reload swaps sources FIRST, then re-composes', () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    final session = _FakeSession();
    final result = await StationReload(
      connect: (_) async => session,
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path);

    expect(session.calls, [
      'probeReloadCapability',
      'reloadSources',
      'invokeReload:reload',
      'close',
    ]);
    expect(result, isA<Reloaded>());
    expect((result as Reloaded).generation, 1);
    expect(result.rebuiltBranches, 3);
  });

  test('snapshot launch is refused before any reload request', () async {
    writeLock(vmServiceUri: 'http://127.0.0.1:1234/tok=/');
    const probeReason =
        'root library is lunar.dart.snapshot; a pub App-JIT snapshot has no '
        'incremental compiler';
    final session = _FakeSession(
      capability: const ReloadUnsupported(probeReason),
    );

    final result = await StationReload(
      connect: (_) async => session,
      isPidAlive: (_) => true,
    ).reload(gridHome: home.path);

    expect(result, isA<ReloadUnsupportedLaunchShape>());
    expect((result as ReloadUnsupportedLaunchShape).reason, probeReason);
    expect(session.calls, ['probeReloadCapability', 'close']);
    expect(session.calls, isNot(contains('reloadSources')));
    expect(
      session.calls.where((call) => call.startsWith('invokeReload:')),
      isEmpty,
    );
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
    expect(session.calls, ['probeReloadCapability', 'reloadSources', 'close']);
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
    final result =
        await StationReload(
          connect: (_) async => session,
          isPidAlive: (_) => true,
        ).reload(
          gridHome: home.path,
          vmServiceUri: Uri.parse('http://127.0.0.1:9999/tok=/'),
        );

    expect(result, isA<Reloaded>());
    expect(session.calls, contains('invokeReload:reload'));
  });

  test(
    'a station with no reload tool REFUSES loudly (the invoke throws)',
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
    },
  );
}

/// A station that never composed a `ReassembleTool`: the extension is not
/// registered, so the invoke throws — and the connection is still CLOSED.
class _ThrowingSession implements StationVmSession {
  bool closed = false;

  @override
  Future<ReloadCapability> probeReloadCapability() async =>
      const ReloadSupported();

  @override
  Future<SourceReload> reloadSources() async => const SourcesSwapped();

  @override
  Future<Map<String, Object?>> invokeReload(String mode) async =>
      throw StateError('method not found: ext.leonard.grid.reload');

  @override
  Future<void> close() async => closed = true;
}
