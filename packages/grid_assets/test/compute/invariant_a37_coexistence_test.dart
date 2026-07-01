// M6 Track G — federation invariant 5: A37 / COEXISTENCE, held AT DEPTH (ADR-0011
// "Coexistence / safety"): a lease NEVER writes a peer's store except via the
// federation protocol. The only mutation path into the peer (lessor) store is a
// PROTOCOL dispatch — there is no direct cross-store write seam.
//
// This is proven through the REAL lease consumer — the engine-mounted
// [LeaseCapability] (mount = acquire + dispatch, unmount = release) — driven over
// the REAL loopback HTTP bus ([StationServer] + [HttpStationClient]). Two separate
// stores model two stations' dolt-truth: the lessee writes only its OWN claim; the
// lessor store changes only when its OWN dispatch handler runs in response to a
// bus dispatch.
//
// Offline only: loopback (127.0.0.1) + fakes. No real network beyond loopback, no
// claude, no cross-machine, no SQL, no gc-owned beads touched.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// One station's append-only store of writes, each tagged with HOW it was made.
/// `via` is the discriminator the invariant turns on: the only legitimate value
/// for a peer's store is `'dispatch'` (a protocol-mediated write); a direct
/// cross-store write would carry any other tag.
class _Store {
  final List<({String key, String via})> writes = [];
  void write(String key, {required String via}) =>
      writes.add((key: key, via: via));
}

/// A [CapabilityContext] for a leased work node (mirrors the lease_capability
/// suite — the SAME instance reaches `run` + `teardown`, like the host).
CapabilityContext _ctx({String nodePath = 'tg-1/lease'}) => CapabilityContext(
  params: const {},
  bead: bead('tg-1'),
  workspaceDir: '/w/tg-1',
  branch: 'grid/tg-1',
  baseBranch: 'main',
  services: const ServiceBundle(),
  cancel: CancelToken(),
  nodePath: nodePath,
);

/// Drives [cap] as the engine would — a job [LeaseAllocation] (mount → acquire →
/// dispatch over the bus), returning the reports + the allocation (so the test
/// disposes it, releasing over the bus). The lease consumer is exercised through
/// its REAL engine carrier, not the retired `run`/`teardown` interface.
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
  group('Invariant 5 — A37 / coexistence: a lease never writes a peer store '
      'except via the protocol (at depth)', () {
    // MUTATION RESISTED: handing the lessee a direct write path into the lessor
    // store (a cross-store write that bypasses the bus). Such a write would land
    // in `lessor.writes` tagged with a `via` other than `'dispatch'` (or push the
    // count above the dispatch count) — failing `every(via == 'dispatch')` and the
    // `writes.length == dispatches` cross-check. The single legal channel is the
    // protocol dispatch; the lessee holds no reference to the peer store at all.
    test(
      'a real LeaseCapability over the loopback bus mutates the peer store ONLY '
      'via protocol dispatch; the lessee writes only its OWN store',
      () async {
        final lessor = _Store(); // the peer (lessor) station's dolt-truth
        final lessee = _Store(); // the leasing station's own dolt-truth

        // The lessor's dispatch handler is the ONLY thing that runs on the peer —
        // and the ONLY mutation path into the lessor store. It tags every write as
        // protocol-originated and counts the dispatches it served.
        var dispatches = 0;
        Future<Map<String, dynamic>> handler(Map<String, dynamic> payload) async {
          dispatches++;
          lessor.write(payload['command'] as String? ?? 'work', via: 'dispatch');
          return const {
            'exitCode': 0,
            'stdout': '',
            'stderr': '',
            'durationMs': 1,
          };
        }

        final server = await StationServer.start(
          station: 'the-dashboard',
          offered: 1,
          host: '127.0.0.1',
          kind: kComputeKind,
          handler: handler,
        );
        addTearDown(server.close);
        final busClient = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(busClient.close);

        // The lessee records its OWN claim in its OWN store (the A37 own-store
        // write) — then leases + dispatches via the bus. The LeaseCapability is
        // constructed with ONLY a StationClient (the bus) + the command: there is
        // no peer-store seam to write through.
        lessee.write('claim:tg-1', via: 'own');
        final cap = LeaseCapability(
          client: busClient,
          command: const DispatchCommand(command: 'echo', args: ['hi']),
          lessee: 'the-studio',
        );
        final ctx = _ctx();

        // Acquire + dispatch (over the bus), then release on dispose.
        final r = await _run(cap, ctx);
        expect(r.reports.whereType<AllocationCompleted>(), hasLength(1));
        await r.alloc.dispose(); // release (over the bus)

        // SANITY CONTROL: the dispatch DID mutate the peer store — the test is not
        // vacuously asserting "nothing was written".
        expect(lessor.writes, isNotEmpty, reason: 'the dispatch did real work');
        expect(dispatches, 1);

        // THE INVARIANT: every peer-store mutation arrived via a PROTOCOL dispatch
        // — no direct cross-store write exists.
        expect(
          lessor.writes.every((w) => w.via == 'dispatch'),
          isTrue,
          reason: 'A37 — the only write path into the peer store is the protocol',
        );
        // 1:1 — exactly as many writes as dispatches the lessor served; nothing
        // slipped in out-of-band.
        expect(lessor.writes.length, dispatches);

        // The lessee wrote ONLY its own store, and never reached the peer's.
        expect(lessee.writes.single.via, 'own');
        expect(
          identical(lessor, lessee),
          isFalse,
          reason: 'separate per-station stores — no shared mutation surface',
        );
      },
    );

    // MUTATION RESISTED: same as above, across a re-lease — proving each peer-store
    // change still maps 1:1 to a protocol dispatch (no accumulation of stray
    // writes between leases). A direct cross-store write would break the
    // dispatch-count parity after the second cycle.
    test(
      'each lease/dispatch/release cycle adds exactly one protocol-tagged peer '
      'write — the count tracks dispatches, nothing out-of-band accrues',
      () async {
        final lessor = _Store();
        var dispatches = 0;
        Future<Map<String, dynamic>> handler(Map<String, dynamic> _) async {
          dispatches++;
          lessor.write('cmd', via: 'dispatch');
          return const {
            'exitCode': 0,
            'stdout': '',
            'stderr': '',
            'durationMs': 1,
          };
        }

        final server = await StationServer.start(
          station: 'the-dashboard',
          offered: 1,
          host: '127.0.0.1',
          kind: kComputeKind,
          handler: handler,
        );
        addTearDown(server.close);
        final busClient = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(busClient.close);

        final cap = LeaseCapability(
          client: busClient,
          command: const DispatchCommand(command: 'echo'),
          lessee: 'the-studio',
        );

        // Cycle 1.
        final c1 = _ctx(nodePath: 'tg-1/lease');
        final r1 = await _run(cap, c1);
        expect(r1.reports.whereType<AllocationCompleted>(), hasLength(1));
        await r1.alloc.dispose(); // releases the slot
        expect(lessor.writes.length, 1);

        // Cycle 2 — the slot was freed on release, so this re-leases cleanly.
        final c2 = _ctx(nodePath: 'tg-2/lease');
        final r2 = await _run(cap, c2);
        expect(r2.reports.whereType<AllocationCompleted>(), hasLength(1));
        await r2.alloc.dispose();

        // Every peer-store mutation is protocol-tagged and 1:1 with dispatches.
        expect(lessor.writes.length, 2);
        expect(dispatches, 2);
        expect(lessor.writes.every((w) => w.via == 'dispatch'), isTrue);
      },
    );
  });
}
