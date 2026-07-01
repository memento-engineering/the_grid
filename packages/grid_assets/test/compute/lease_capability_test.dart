// M6 Track D / U3 — lease-as-Capability, driven as a LeaseAllocation (ADR-0009
// D6). The compute LeaseCapability is a JOB lease: the engine mints a
// LeaseAllocation that ACQUIRES a slot + DISPATCHES the bounded compute use
// (reporting `complete`), and RELEASES on dispose. Driven by a fake StationClient
// (Fakes, not mocks) + a hand-built AllocationContext. Zero I/O.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// A recording fake bus (lessee view) — records every call in order; never
/// touches a socket. Settable to deny a lease, fail a dispatch, or throw on
/// release.
class FakeStationClient implements StationClient {
  FakeStationClient({this.station = 'peer'});

  final String station;

  /// Every operation, in call order (e.g. `lease:studio:compute:idem`).
  final List<String> calls = [];

  /// The payload of the most recent dispatch.
  Map<String, dynamic>? lastDispatch;

  /// When true, [requestLease] denies.
  bool denyLease = false;

  /// When true, [dispatch] throws [LeaseInvalidException] (lease gone).
  bool dispatchInvalid = false;

  /// When true, [release] throws [LeaseInvalidException] (already reaped).
  bool releaseThrows = false;

  /// The result [dispatch] returns (the opaque envelope).
  Map<String, dynamic> dispatchResult = const {
    'exitCode': 0,
    'stdout': '',
    'stderr': '',
    'durationMs': 0,
  };

  int _seq = 0;

  @override
  Future<Presence> presence() async => Presence(
    station: station,
    kinds: const [kComputeKind],
    offered: 1,
    available: 1,
  );

  @override
  Future<LeaseGrant> requestLease(LeaseRequest req) async {
    calls.add('lease:${req.lessee}:${req.kind}:${req.idempotencyKey}');
    if (denyLease) throw const LeaseDeniedException('no capacity');
    return LeaseGrant(
      leaseId: 'lease-${_seq++}',
      station: station,
      ttlSeconds: 300,
      fencingToken: 1,
      kind: req.kind,
    );
  }

  @override
  Future<Map<String, dynamic>> dispatch(
    LeaseGrant lease,
    Map<String, dynamic> payload, {
    String idempotencyKey = '',
  }) async {
    calls.add('dispatch:${lease.leaseId}:$idempotencyKey');
    lastDispatch = payload;
    if (dispatchInvalid) throw const LeaseInvalidException('lease gone');
    return dispatchResult;
  }

  @override
  Future<void> heartbeat(LeaseGrant lease) async =>
      calls.add('heartbeat:${lease.leaseId}');

  @override
  Future<void> release(LeaseGrant lease) async {
    calls.add('release:${lease.leaseId}');
    if (releaseThrows) throw const LeaseInvalidException('already reaped');
  }

  @override
  Future<void> close() async => calls.add('close');

  int countWith(String prefix) =>
      calls.where((c) => c.startsWith(prefix)).length;
  bool any(String prefix) => calls.any((c) => c.startsWith(prefix));
}

CapabilityContext _ctx({CancelToken? cancel, String nodePath = 'tg-1/lease'}) =>
    CapabilityContext(
      params: const {},
      bead: bead('tg-1'),
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
      baseBranch: 'main',
      services: const ServiceBundle(),
      cancel: cancel ?? CancelToken(),
      nodePath: nodePath,
    );

/// Drives [cap] as the engine would — a JOB LeaseAllocation (mount → acquire →
/// dispatch), returning the pushed reports + the allocation (so the test can
/// dispose it, releasing the lease). The compute use is a job (never adopts).
Future<({List<AllocationReport> reports, LeaseAllocation alloc})> _run(
  LeaseCapability cap,
  CapabilityContext ctx,
) async {
  final reports = <AllocationReport>[];
  final alloc = cap.createAllocation(
    AllocationContext(
      capContext: ctx,
      transport: FakeRuntimeProvider(),
      address: AllocationAddress('tgdog-s', ctx.nodePath),
      env: const {},
      sink: reports.add,
      kind: StepKind.job,
    ),
  ) as LeaseAllocation;
  await alloc.startOrAdopt();
  return (reports: reports, alloc: alloc);
}

void main() {
  group('LeaseCapability as a job LeaseAllocation', () {
    test('mount acquires + dispatches → complete; dispose releases', () async {
      final client = FakeStationClient()
        ..dispatchResult = const {
          'exitCode': 0,
          'stdout': 'done',
          'stderr': '',
          'durationMs': 5,
        };
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo', args: ['hi']),
        lessee: 'studio',
      );

      final r = await _run(cap, _ctx());
      final done = r.reports.whereType<AllocationCompleted>().single;
      expect(done.payload?['exitCode'], '0');
      expect(done.payload?['lease'], 'lease-0');
      expect(r.reports.whereType<AllocationReady>(), isEmpty,
          reason: 'a job lease completes, it does not stay ready');
      // Acquire then dispatch (with the per-node idempotency key) — not released.
      expect(client.calls, [
        'lease:studio:compute:studio/tg-1/lease',
        'dispatch:lease-0:studio/tg-1/lease',
      ]);
      expect(client.lastDispatch, {
        'command': 'echo',
        'args': ['hi'],
      });

      await r.alloc.dispose(); // unmount → release
      expect(client.calls.last, 'release:lease-0');
    });

    test('the lessee defaults to the work bead id when unset', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      await _run(cap, _ctx());
      expect(client.calls.first, 'lease:tg-1:compute:tg-1/tg-1/lease');
    });

    test('dispose releases ONCE (idempotent on a double dispose)', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final r = await _run(cap, _ctx());
      await r.alloc.dispose();
      await r.alloc.dispose();
      expect(client.countWith('release:'), 1);
    });

    test('a denied lease → Failed; no dispatch; dispose no-ops (nothing held)',
        () async {
      final client = FakeStationClient()..denyLease = true;
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final r = await _run(cap, _ctx());
      expect(r.reports.single, isA<AllocationFailed>());
      expect(client.any('dispatch:'), isFalse);
      await r.alloc.dispose();
      expect(client.any('release:'), isFalse);
    });

    test('a dispose during acquire RELEASES the grant + skips the dispatch '
        '(release even if cancelled)', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final r = await _run(cap, _ctx(cancel: CancelToken()..cancel()));
      expect(r.reports, isEmpty, reason: 'a cancelled start reports nothing');
      expect(client.any('dispatch:'), isFalse, reason: 'no dispatch after cancel');
      expect(client.any('release:'), isTrue, reason: 'released despite cancel');
      // dispose must NOT double-release (start released inline; no held grant).
      await r.alloc.dispose();
      expect(client.countWith('release:'), 1);
    });

    test('a non-zero compute result → Failed; the lease still releases on dispose',
        () async {
      final client = FakeStationClient()
        ..dispatchResult = const {
          'exitCode': 2,
          'stdout': '',
          'stderr': 'boom',
          'durationMs': 1,
        };
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final r = await _run(cap, _ctx());
      final failed = r.reports.whereType<AllocationFailed>().single;
      expect(failed.reason, contains('boom'));
      await r.alloc.dispose();
      expect(client.calls.last, 'release:lease-0');
    });

    test('a dispatch against a vanished lease → Failed; dispose still releases',
        () async {
      final client = FakeStationClient()..dispatchInvalid = true;
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final r = await _run(cap, _ctx());
      expect(r.reports.single, isA<AllocationFailed>());
      // The grant was acquired before the failed dispatch → dispose releases it.
      await r.alloc.dispose();
      expect(client.any('release:'), isTrue);
    });

    test('release on dispose swallows a federation error (idempotent)', () async {
      final client = FakeStationClient()..releaseThrows = true;
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final r = await _run(cap, _ctx());
      // Must not throw even though release errors.
      await r.alloc.dispose();
      expect(client.any('release:'), isTrue);
    });

    test('two concurrent mounts each hold + release their OWN lease (per-instance '
        'allocation state — no Expando, no clobber)', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final a = await _run(cap, _ctx(nodePath: 'a/lease')); // lease-0
      final b = await _run(cap, _ctx(nodePath: 'b/lease')); // lease-1
      expect(a.alloc.grant?.leaseId, 'lease-0');
      expect(b.alloc.grant?.leaseId, 'lease-1');
      await a.alloc.dispose();
      await b.alloc.dispose();
      final releases = client.calls.where((c) => c.startsWith('release:'));
      expect(releases, containsAll(['release:lease-0', 'release:lease-1']));
    });
  });
}
