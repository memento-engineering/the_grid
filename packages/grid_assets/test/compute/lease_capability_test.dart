// M6 Track D — lease-as-Capability (DoD-1's engine wrapper).
//
// The LeaseCapability mounts at the engine Capability seam: MOUNT (`run`)
// acquires a lease + dispatches the bounded compute use; UNMOUNT (`teardown`)
// releases. Driven by a fake StationClient (Fakes, not mocks) + a hand-built
// CapabilityContext (the SAME instance reaches run + teardown, like the host).
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

  Iterable<String> get _of => calls;
  int countWith(String prefix) =>
      _of.where((c) => c.startsWith(prefix)).length;
  bool any(String prefix) => _of.any((c) => c.startsWith(prefix));
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

void main() {
  group('LeaseCapability lifecycle', () {
    test('mount acquires + dispatches → Ok; dispose releases', () async {
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
      final ctx = _ctx();

      final outcome = await cap.run(ctx);
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload?['exitCode'], '0');
      expect((outcome).payload?['lease'], 'lease-0');
      // Acquire then dispatch (with the per-node idempotency key) — not released.
      expect(client.calls, [
        'lease:studio:compute:studio/tg-1/lease',
        'dispatch:lease-0:studio/tg-1/lease',
      ]);
      expect(client.lastDispatch, {
        'command': 'echo',
        'args': ['hi'],
      });

      await cap.teardown(ctx); // unmount → release
      expect(client.calls.last, 'release:lease-0');
    });

    test('the lessee defaults to the work bead id when unset', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      await cap.run(_ctx());
      expect(client.calls.first, 'lease:tg-1:compute:tg-1/tg-1/lease');
    });

    test('teardown releases ONCE (idempotent on a double dispose)', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final ctx = _ctx();
      await cap.run(ctx);
      await cap.teardown(ctx);
      await cap.teardown(ctx);
      expect(client.countWith('release:'), 1);
    });

    test('a denied lease → Failed; no dispatch; teardown no-ops', () async {
      final client = FakeStationClient()..denyLease = true;
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final ctx = _ctx();
      final outcome = await cap.run(ctx);
      expect(outcome, isA<Failed>());
      expect(client.any('dispatch:'), isFalse);
      await cap.teardown(ctx);
      expect(client.any('release:'), isFalse);
    });

    test('a dispose during acquire RELEASES the grant + skips the dispatch '
        '(release even if cancelled)', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final ctx = _ctx(cancel: CancelToken()..cancel());
      final outcome = await cap.run(ctx);
      expect(outcome, isA<Failed>());
      expect(client.any('dispatch:'), isFalse, reason: 'no dispatch after cancel');
      expect(client.any('release:'), isTrue, reason: 'released despite cancel');
      // teardown must NOT double-release (run released inline; no held grant).
      await cap.teardown(ctx);
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
      final ctx = _ctx();
      final outcome = await cap.run(ctx);
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).reason, contains('boom'));
      await cap.teardown(ctx);
      expect(client.calls.last, 'release:lease-0');
    });

    test('a dispatch against a vanished lease → Failed; teardown still releases',
        () async {
      final client = FakeStationClient()..dispatchInvalid = true;
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final ctx = _ctx();
      expect(await cap.run(ctx), isA<Failed>());
      // The grant was acquired before the failed dispatch → teardown releases it.
      await cap.teardown(ctx);
      expect(client.any('release:'), isTrue);
    });

    test('release on dispose swallows a federation error (idempotent)', () async {
      final client = FakeStationClient()..releaseThrows = true;
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final ctx = _ctx();
      await cap.run(ctx);
      // Must not throw even though release errors.
      await cap.teardown(ctx);
      expect(client.any('release:'), isTrue);
    });

    test('two concurrent mounts each hold + release their OWN lease (the '
        'per-mount Expando keying — no clobber)', () async {
      final client = FakeStationClient();
      final cap = LeaseCapability(
        client: client,
        command: const DispatchCommand(command: 'echo'),
      );
      final ctxA = _ctx(nodePath: 'a/lease');
      final ctxB = _ctx(nodePath: 'b/lease');
      await cap.run(ctxA); // lease-0
      await cap.run(ctxB); // lease-1
      await cap.teardown(ctxA);
      await cap.teardown(ctxB);
      final releases = client.calls.where((c) => c.startsWith('release:'));
      expect(releases, containsAll(['release:lease-0', 'release:lease-1']));
    });
  });
}
