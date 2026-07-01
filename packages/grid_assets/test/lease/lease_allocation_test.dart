// U2 / ADR-0009 Track E — the LeaseAllocation family (the deferred lease
// per-family default coming due in M6). PURE (no tree): drives LeaseAllocation
// directly with a fake bus (Fakes, not mocks) + a hand-built AllocationContext.
// Zero I/O; no live claude/git/bd/network. The daemon-reap bug the burn parked M6
// on is fixed HERE at the family level: a daemon lease reports `ready` (stays
// live), never `complete` (retires). Cross-restart lease adopt is proven as a
// DECISION (freshness proof) — the persisted-handle wiring is the live-arm gate.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// A recording fake bus (lessee view) — records every call in order; never
/// touches a socket. Settable to fail a dispatch, throw on heartbeat (a stale /
/// reaped grant — the adopt freshness-proof failure), or throw on release.
class FakeStationClient implements StationClient {
  FakeStationClient({this.station = 'peer'});

  final String station;

  /// Every operation, in call order.
  final List<String> calls = [];

  /// When true, [heartbeat] throws [LeaseInvalidException] (a stale/reaped grant
  /// — the freshness proof must then FAIL and the allocation acquire fresh).
  bool heartbeatInvalid = false;

  /// When true, [dispatch] throws [LeaseInvalidException] (lease gone).
  bool dispatchInvalid = false;

  /// When true, [release] throws [LeaseInvalidException] (already reaped).
  bool releaseThrows = false;

  /// Fires right after a heartbeat is recorded — used to simulate a dispose
  /// racing the adopt freshness proof (the await window inside `_proveFresh`).
  void Function()? onHeartbeat;

  int _seq = 0;

  /// Mints a grant as [requestLease] would (for seeding a prior/adopt grant).
  LeaseGrant mintGrant() => LeaseGrant(
    leaseId: 'lease-${_seq++}',
    station: station,
    ttlSeconds: 300,
    fencingToken: 1,
    kind: 'burn',
  );

  @override
  Future<Presence> presence() async =>
      Presence(station: station, kinds: const ['burn'], offered: 1, available: 1);

  @override
  Future<LeaseGrant> requestLease(LeaseRequest req) async {
    calls.add('lease:${req.lessee}:${req.kind}:${req.idempotencyKey}');
    return mintGrant();
  }

  @override
  Future<Map<String, dynamic>> dispatch(
    LeaseGrant lease,
    Map<String, dynamic> payload, {
    String idempotencyKey = '',
  }) async {
    calls.add('dispatch:${lease.leaseId}:$idempotencyKey');
    if (dispatchInvalid) throw const LeaseInvalidException('lease gone');
    return const {'ok': true};
  }

  @override
  Future<void> heartbeat(LeaseGrant lease) async {
    calls.add('heartbeat:${lease.leaseId}');
    onHeartbeat?.call();
    if (heartbeatInvalid) throw const LeaseInvalidException('stale / reaped');
  }

  @override
  Future<void> release(LeaseGrant lease) async {
    calls.add('release:${lease.leaseId}');
    if (releaseThrows) throw const LeaseInvalidException('already reaped');
  }

  @override
  Future<void> close() async => calls.add('close');

  int countWith(String prefix) => calls.where((c) => c.startsWith(prefix)).length;
  bool any(String prefix) => calls.any((c) => c.startsWith(prefix));
}

/// A programmable lease capability over the fake bus — the U2 subject. Extends
/// [ServiceCapability] with [LeasePlan] (the sealed-`Capability`-respecting shape
/// both real consumers use). [unavailable] forces a fail-closed acquire; [outcome]
/// is what the dispatch resolves to; [prior] is a grant to attempt adopting.
class _LeaseCap extends ServiceCapability with LeasePlan {
  _LeaseCap({
    required this.client,
    this.unavailable,
    this.outcome = const Ok({'endpoint': 'vm://follower', 'station': 'peer'}),
    this.prior,
    List<String>? log,
  }) : log = log ?? [];

  final StationClient client;
  final String? unavailable;
  final StepOutcome outcome;
  final LeaseBound? prior;
  final List<String> log;

  @override
  Future<LeaseResolution> acquire(CapabilityContext ctx) async {
    log.add('acquire');
    if (unavailable != null) return LeaseUnavailable(unavailable!);
    final grant = await client.requestLease(
      LeaseRequest(lessee: ctx.beadId, kind: 'burn', idempotencyKey: ctx.nodePath),
    );
    return LeaseBound(client, grant);
  }

  @override
  Future<StepOutcome> dispatchOn(
    StationClient c,
    LeaseGrant g,
    CapabilityContext ctx,
  ) async {
    log.add('dispatch');
    await c.dispatch(g, const {'launch': true}, idempotencyKey: ctx.nodePath);
    return outcome;
  }

  @override
  Future<LeaseBound?> adoptable(CapabilityContext ctx) async {
    log.add('adoptable');
    return prior;
  }
}

CapabilityContext _capCtx(CancelToken cancel, {String nodePath = 'tg-1/follower'}) =>
    CapabilityContext(
      params: const {},
      bead: bead('tg-1'),
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
      baseBranch: 'main',
      services: const ServiceBundle(),
      cancel: cancel,
      nodePath: nodePath,
    );

AllocationContext _allocCtx({
  required AllocationSink sink,
  required CancelToken cancel,
  StepKind kind = StepKind.daemon,
  String nodePath = 'tg-1/follower',
}) => AllocationContext(
  capContext: _capCtx(cancel, nodePath: nodePath),
  transport: FakeRuntimeProvider(),
  address: AllocationAddress('tgdog-s', nodePath),
  env: const {},
  sink: sink,
  kind: kind,
);

LeaseAllocation _alloc(
  _LeaseCap cap, {
  required AllocationSink sink,
  CancelToken? cancel,
  StepKind kind = StepKind.daemon,
}) => cap.createAllocation(
  _allocCtx(sink: sink, cancel: cancel ?? CancelToken(), kind: kind),
) as LeaseAllocation;

void main() {
  group('LeaseAllocation — kind drives adoptability/detachability (D6)', () {
    test('a daemon lease is adoptable + detachable; a job lease is neither', () {
      final client = FakeStationClient();
      final daemon = _alloc(_LeaseCap(client: client), sink: (_) {});
      final job = _alloc(
        _LeaseCap(client: client),
        sink: (_) {},
        kind: StepKind.job,
      );
      expect(daemon.isAdoptable, isTrue);
      expect(daemon.isDetachable, isTrue);
      expect(job.isAdoptable, isFalse);
      expect(job.isDetachable, isFalse);
    });
  });

  group('LeaseAllocation — daemon: acquire → dispatch → READY (the reap fix)', () {
    test('reports exactly one AllocationReady carrying the rendezvous payload — '
        'and NEVER AllocationCompleted (the daemon stays live, D6/OQ-5)', () async {
      final reports = <AllocationReport>[];
      final client = FakeStationClient();
      final cap = _LeaseCap(client: client);
      final alloc = _alloc(cap, sink: reports.add);

      await alloc.startOrAdopt();

      final readies = reports.whereType<AllocationReady>().toList();
      expect(readies, hasLength(1));
      expect(readies.single.payload, {'endpoint': 'vm://follower', 'station': 'peer'});
      expect(reports.whereType<AllocationCompleted>(), isEmpty,
          reason: 'the daemon-reap bug: a held daemon lease must NOT complete');
      expect(alloc.state, AllocationState.ready);
      // Acquired then dispatched (the per-node idempotency key), not released.
      expect(client.calls, [
        'lease:tg-1:burn:tg-1/follower',
        'dispatch:lease-0:tg-1/follower',
      ]);
    });

    test('dispose RELEASES the held grant (dispose == release, the floor)',
        () async {
      final client = FakeStationClient();
      final alloc = _alloc(_LeaseCap(client: client), sink: (_) {});
      await alloc.startOrAdopt();
      await alloc.dispose();
      expect(client.calls.last, 'release:lease-0');
      expect(alloc.state, AllocationState.gone);
    });
  });

  group('LeaseAllocation — job: acquire → dispatch → COMPLETE (latches)', () {
    test('a job lease reports AllocationCompleted (not ready) + dispose releases',
        () async {
      final reports = <AllocationReport>[];
      final client = FakeStationClient();
      final cap = _LeaseCap(client: client, outcome: const Ok({'exitCode': '0'}));
      final alloc = _alloc(cap, sink: reports.add, kind: StepKind.job);

      await alloc.startOrAdopt();
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
      expect(reports.whereType<AllocationReady>(), isEmpty);
      expect(alloc.state, AllocationState.gone);

      await alloc.dispose();
      expect(client.calls.last, 'release:lease-0');
    });

    test('a double dispose releases ONCE (idempotent)', () async {
      final client = FakeStationClient();
      final alloc = _alloc(
        _LeaseCap(client: client),
        sink: (_) {},
        kind: StepKind.job,
      );
      await alloc.startOrAdopt();
      await alloc.dispose();
      await alloc.dispose();
      expect(client.countWith('release:'), 1);
    });
  });

  group('LeaseAllocation — dispatch outcomes route to reports', () {
    test('a Failed dispatch → AllocationFailed (still releases on dispose)',
        () async {
      final reports = <AllocationReport>[];
      final client = FakeStationClient();
      final cap = _LeaseCap(client: client, outcome: const Failed('boom'));
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      expect(reports.single, isA<AllocationFailed>());
      expect((reports.single as AllocationFailed).reason, 'boom');
      await alloc.dispose();
      expect(client.any('release:'), isTrue);
    });

    test('a Gate dispatch → AllocationGated', () async {
      final reports = <AllocationReport>[];
      final client = FakeStationClient();
      final cap = _LeaseCap(client: client, outcome: const Gate('needs a human'));
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      expect(reports.single, isA<AllocationGated>());
      expect((reports.single as AllocationGated).reason, 'needs a human');
    });
  });

  group('LeaseAllocation — acquire fail-closed', () {
    test('a LeaseUnavailable acquire → AllocationFailed; nothing bound, dispose '
        'never releases (never acquired)', () async {
      final reports = <AllocationReport>[];
      final client = FakeStationClient();
      final cap = _LeaseCap(client: client, unavailable: 'no peer satisfies X');
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      expect(reports.single, isA<AllocationFailed>());
      expect((reports.single as AllocationFailed).reason, 'no peer satisfies X');
      expect(cap.log, isNot(contains('dispatch')));
      expect(alloc.grant, isNull);
      await alloc.dispose();
      expect(client.any('release:'), isFalse, reason: 'nothing to release');
    });
  });

  group('LeaseAllocation — a dispose racing the acquire releases the slot', () {
    test('cancel before startOrAdopt (job) → binds then RELEASES the grant + '
        'skips dispatch + no report (no leaked lease)', () async {
      final reports = <AllocationReport>[];
      final client = FakeStationClient();
      final cap = _LeaseCap(client: client);
      final alloc = _alloc(
        cap,
        sink: reports.add,
        cancel: CancelToken()..cancel(),
        kind: StepKind.job,
      );
      await alloc.startOrAdopt();
      expect(cap.log, isNot(contains('dispatch')), reason: 'no dispatch after cancel');
      expect(client.any('release:'), isTrue, reason: 'released the bound slot');
      expect(reports, isEmpty, reason: 'a cancelled start reports nothing');
      expect(alloc.state, AllocationState.gone);
    });
  });

  group('LeaseAllocation — daemon adopt-or-reacquire (no-adopt-on-faith, D4/D5)',
      () {
    test('a prior grant PROVEN fresh (heartbeat ok) is ADOPTED — reattached, '
        'ready, NO acquire/dispatch; dispose releases the adopted grant', () async {
      final reports = <AllocationReport>[];
      final client = FakeStationClient();
      final prior = LeaseBound(client, client.mintGrant()); // lease-0
      final cap = _LeaseCap(client: client, prior: prior);
      final alloc = _alloc(cap, sink: reports.add);

      await alloc.startOrAdopt();

      expect(alloc.adopted, isTrue);
      expect(cap.log, isNot(contains('acquire')), reason: 'adopt must NOT re-acquire');
      expect(cap.log, isNot(contains('dispatch')), reason: 'adopt must NOT re-dispatch');
      expect(client.any('lease:'), isFalse);
      expect(client.calls, contains('heartbeat:lease-0')); // the freshness proof
      expect(reports.whereType<AllocationReady>(), hasLength(1));
      expect(alloc.state, AllocationState.ready);
      expect(alloc.grant?.leaseId, 'lease-0');

      await alloc.dispose();
      expect(client.calls.last, 'release:lease-0');
    });

    test('a prior grant that FAILS the proof (heartbeat throws) → acquire FRESH '
        '(never adopt blind)', () async {
      final client = FakeStationClient()..heartbeatInvalid = true;
      final prior = LeaseBound(client, client.mintGrant()); // lease-0 (stale)
      final cap = _LeaseCap(client: client, prior: prior);
      final alloc = _alloc(cap, sink: (_) {});

      await alloc.startOrAdopt();

      expect(alloc.adopted, isFalse);
      expect(cap.log, contains('acquire'));
      expect(cap.log, contains('dispatch'));
      expect(client.any('lease:'), isTrue, reason: 'acquired a fresh grant');
      expect(alloc.grant?.leaseId, 'lease-1'); // the fresh one, not the stale prior
    });

    test('a dispose racing the adopt PROOF releases the (TTL-renewed) prior grant '
        '— never orphans it (invariant 4 at the adopt path)', () async {
      final client = FakeStationClient();
      final prior = LeaseBound(client, client.mintGrant()); // lease-0
      final cancel = CancelToken();
      // The heartbeat (the freshness proof) cancels the token mid-proof —
      // simulating a dispose landing inside `_proveFresh`'s await, BEFORE the
      // allocation binds `_grant` (so the racing dispose would release nothing).
      client.onHeartbeat = cancel.cancel;
      final cap = _LeaseCap(client: client, prior: prior);
      final alloc = _alloc(cap, sink: (_) {}, cancel: cancel);

      await alloc.startOrAdopt();

      expect(alloc.adopted, isFalse, reason: 'the cancel aborted the adopt');
      expect(client.calls, contains('heartbeat:lease-0'),
          reason: 'the proof ran (and renewed the prior grant TTL)');
      expect(client.any('release:'), isTrue,
          reason: 'the proven prior grant is RELEASED, not orphaned for its TTL');
      // A following dispose must not double-release (start released inline).
      await alloc.dispose();
      expect(client.countWith('release:'), 1);
    });

    test('a JOB never adopts even with a fresh prior grant available (respawn-'
        'or-skip is the job contract)', () async {
      final client = FakeStationClient();
      final prior = LeaseBound(client, client.mintGrant());
      final cap = _LeaseCap(client: client, prior: prior);
      final alloc = _alloc(cap, sink: (_) {}, kind: StepKind.job);

      await alloc.startOrAdopt();

      expect(alloc.adopted, isFalse);
      expect(cap.log, isNot(contains('adoptable')),
          reason: 'a job short-circuits the adopt block (isAdoptable=false)');
      expect(cap.log, contains('acquire'));
    });
  });

  group('LeaseAllocation — detach vs dispose (distinct verbs, D4)', () {
    test('detach LEAVES the daemon lease HELD (never releases); a later dispose '
        'still releases if adoption is abandoned', () async {
      final client = FakeStationClient();
      final alloc = _alloc(_LeaseCap(client: client), sink: (_) {});
      await alloc.startOrAdopt();

      await alloc.detach();
      expect(client.any('release:'), isFalse, reason: 'detach never releases');
      expect(alloc.state, AllocationState.gone);

      // Adoption abandoned → dispose still frees the slot (never leak).
      await alloc.dispose();
      expect(client.calls.last, 'release:lease-0');
    });

    test('detach on a JOB lease throws (a job must never leave a grant held)',
        () async {
      final client = FakeStationClient();
      final alloc = _alloc(
        _LeaseCap(client: client),
        sink: (_) {},
        kind: StepKind.job,
      );
      await alloc.startOrAdopt();
      await expectLater(alloc.detach(), throwsA(isA<UnsupportedError>()));
    });
  });

  group('LeaseAllocation — release stays idempotent for the holder', () {
    test('dispose swallows a federation error on release (already reaped)',
        () async {
      final client = FakeStationClient()..releaseThrows = true;
      final alloc = _alloc(_LeaseCap(client: client), sink: (_) {});
      await alloc.startOrAdopt();
      await alloc.dispose(); // must not throw
      expect(client.any('release:'), isTrue);
    });
  });

  group('LeaseAllocation — the plain-service run path is fenced off', () {
    test('run() throws (a lease capability is driven as a LeaseAllocation, never '
        'a ServiceAllocation)', () {
      final cap = _LeaseCap(client: FakeStationClient());
      expect(() => cap.run(_capCtx(CancelToken())), throwsA(isA<StateError>()));
    });
  });
}
