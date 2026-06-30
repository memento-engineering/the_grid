// M6 Track G — the FEDERATION INVARIANTS, mutation-resistant + non-vacuous, held
// AT DEPTH (ADR-0011 Hazards / build-order G). These are NOT a restatement of the
// `LeaseManager` unit suite: each invariant is exercised end-to-end across the
// composed stack — the REAL loopback HTTP bus ([StationServer] +
// [HttpStationClient]), the owner-authoritative arbiter, the wire fencing
// headers, the queue draining across genuine request/response cycles — with:
//   * a SANITY CONTROL (a positive case that passes) so the test cannot be
//     vacuously green; and
//   * a documented MUTATION the assertion FAILS under.
//
// The fifth invariant (A37 / coexistence — a lease never writes a peer's store
// except via the protocol) lives where the behavior does: over the REAL
// `LeaseCapability` consumer in `grid_assets/test/compute/`.
//
// Offline only: loopback (127.0.0.1) + an injected owner clock + fake handlers.
// No real network beyond loopback, no claude, no cross-machine.
import 'dart:async';

import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

/// A controllable OWNER clock — injected into the lessor so reaping/lifetime math
/// is driven by the test, never wall-time (ADR-0011 D5: owner-clock reaping).
class _Clock {
  DateTime now = DateTime.utc(2026);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// A kind-agnostic echo handler — the bus only ever sees opaque maps.
Future<Map<String, dynamic>> _echo(Map<String, dynamic> payload) async => {
  'echo': payload,
};

void main() {
  /// Starts a loopback lessor and tears it down with the test.
  Future<StationServer> serve({
    int offered = 1,
    Duration leaseWait = Duration.zero,
    Duration ttl = const Duration(seconds: 300),
    Duration maxLifetime = const Duration(seconds: 3600),
    DateTime Function()? clock,
    DispatchHandler? handler,
  }) async {
    final s = await StationServer.start(
      station: 'peer',
      offered: offered,
      host: '127.0.0.1',
      leaseWait: leaseWait,
      ttl: ttl,
      maxLifetime: maxLifetime,
      clock: clock,
      handler: handler ?? _echo,
    );
    addTearDown(s.close);
    return s;
  }

  /// A lessee client against [s], torn down with the test.
  HttpStationClient client(StationServer s) {
    final c = HttpStationClient(host: '127.0.0.1', port: s.port);
    addTearDown(c.close);
    return c;
  }

  /// Spins the event loop until [cond] holds (or fails after [maxTurns] turns),
  /// letting the loopback server process in-flight requests deterministically.
  Future<void> until(bool Function() cond, {int maxTurns = 2000}) async {
    for (var i = 0; i < maxTurns && !cond(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    if (!cond()) {
      throw StateError('condition not met within $maxTurns event-loop turns');
    }
  }

  // ===========================================================================
  group('Invariant 1 — owner-authoritative ⇒ NO DOUBLE-GRANT (at depth)', () {
    // MUTATION RESISTED: weakening/removing the capacity guard in
    // `LeaseManager._tryGrantNow` — `if (_held.length >= offered) return null;`.
    // If `>=` were `>` (off-by-one) you would get `offered + 1` grants; if removed
    // entirely, ALL concurrent requests would grant. The exact-count + distinct-
    // slot assertions catch both: a single asset slot is never granted twice.
    test(
      'N CONCURRENT lease requests over the bus grant EXACTLY the offered slots — '
      'each a distinct slot (id + fencing token); the rest are denied',
      () async {
        const offered = 3;
        const fired = 10;
        final s = await serve(offered: offered); // leaseWait 0 ⇒ deny when full
        // Independent clients ⇒ independent connections ⇒ genuine concurrency.
        final clients = [for (var i = 0; i < fired; i++) client(s)];

        Future<LeaseGrant?> tryLease(HttpStationClient c, int i) async {
          try {
            return await c.requestLease(LeaseRequest(lessee: 'r$i'));
          } on LeaseDeniedException {
            return null; // the owner refused — capacity was already taken
          }
        }

        final results = await Future.wait([
          for (var i = 0; i < fired; i++) tryLease(clients[i], i),
        ]);
        final grants = results.whereType<LeaseGrant>().toList();

        // SANITY CONTROL: it DID grant up to capacity (not vacuously all-denied).
        expect(grants, hasLength(offered), reason: 'exactly the offered slots');
        // THE INVARIANT: every granted slot is distinct — no slot granted twice.
        expect(
          grants.map((g) => g.leaseId).toSet(),
          hasLength(offered),
          reason: 'distinct lease ids — no double-grant of one slot',
        );
        expect(
          grants.map((g) => g.fencingToken).toSet(),
          hasLength(offered),
          reason: 'distinct fencing tokens — distinct slots',
        );
        // The over-capacity requests were refused, not silently double-served.
        expect(results.where((g) => g == null), hasLength(fired - offered));
        expect((await client(s).presence()).available, 0, reason: 'all consumed');
      },
    );
  });

  // ===========================================================================
  group('Invariant 2 — fencing ⇒ NO ZOMBIE DOUBLE-USE (reap + reissue)', () {
    // MUTATION RESISTED: removing the fencing check `h.fencingToken != token` in
    // `LeaseManager._validate` (dispatch/touch) and in `release`. Without it, the
    // zombie's forged dispatch would RUN the handler a third time (double-use of
    // the reissued slot) and its forged release would free the new holder's slot.
    // The `runs == 2` (never the zombie) assertion fails under that mutation.
    test(
      'after reap + reissue, the stale prior holder cannot dispatch/release; the '
      'dispatched handler runs ONCE per live holder, NEVER for the zombie',
      () async {
        var runs = 0;
        Future<Map<String, dynamic>> counting(Map<String, dynamic> _) async {
          runs++;
          return {'run': runs};
        }

        final clock = _Clock();
        final s = await serve(
          offered: 1,
          ttl: const Duration(seconds: 30),
          clock: clock.call,
          handler: counting,
        );
        final c = client(s);

        final g1 = await c.requestLease(const LeaseRequest(lessee: 'a'));
        await c.dispatch(g1, const {}); // run #1 — the rightful holder
        expect(runs, 1);

        // REAP g1 by the owner clock, then REISSUE the slot to a new holder.
        clock.advance(const Duration(seconds: 31));
        await c.presence(); // pump the owner clock → g1 reaped, slot freed
        final g2 = await c.requestLease(const LeaseRequest(lessee: 'b'));
        expect(
          g2.fencingToken,
          greaterThan(g1.fencingToken),
          reason: 'the reissue carries a strictly greater fencing token',
        );

        // ZOMBIE (still holds g1): its dead handle is refused.
        await expectLater(
          c.dispatch(g1, const {}),
          throwsA(isA<LeaseInvalidException>()),
        );
        // ...and a FORGED dispatch/release at g2's id with g1's STALE token is
        // refused by fencing — it cannot ride on the reissued slot.
        final forged = LeaseGrant(
          leaseId: g2.leaseId,
          station: g2.station,
          ttlSeconds: g2.ttlSeconds,
          fencingToken: g1.fencingToken, // the stale token
        );
        await expectLater(
          c.dispatch(forged, const {}),
          throwsA(isA<LeaseInvalidException>()),
        );
        await expectLater(
          c.release(forged),
          throwsA(isA<LeaseInvalidException>()),
        );

        // SANITY CONTROL: the rightful holder g2 still dispatches fine — the
        // refusal above is STALENESS, not a dead server / dead slot.
        await c.dispatch(g2, const {}); // run #2
        expect(
          runs,
          2,
          reason: 'the handler ran for g1 + g2 ONLY — never for the zombie',
        );
      },
    );
  });

  // ===========================================================================
  group('Invariant 3 — STARVATION BOUNDED (max-lifetime cap + FIFO fairness)', () {
    // MUTATION RESISTED: removing the max-lifetime reap in `LeaseManager._reap`
    // (`!h.hardDeadline.isAfter(now)`). This is the SOLE reaper of the greedy in
    // this scenario and is NOT masked by the idle-TTL reap: ttl (1000s) ≫
    // maxLifetime (100s), and a `touch` pushes the idle expiry FORWARD (renewal no
    // longer clamps it to the hard deadline — the `_cap` masking was removed), so
    // at +101s the idle clause (expiry ≈ +1050s) is NOT due and only the
    // hard-deadline clause frees the slot. Without it, the greedy renews its idle
    // TTL FOREVER and the waiter starves — `await until(() => waiterGrant != null)`
    // then never completes (timeout = failure). Verified: dropping that clause
    // alone now reds this test (the masking the spike shipped is gone).
    test(
      'a greedy incumbent that keeps dispatching is STILL reaped at max-lifetime, '
      'freeing the slot for the waiter (no indefinite monopoly)',
      () async {
        final clock = _Clock();
        final s = await serve(
          offered: 1,
          ttl: const Duration(seconds: 1000), // huge idle TTL — renew "forever"
          maxLifetime: const Duration(seconds: 100), // the real bound
          leaseWait: const Duration(seconds: 600),
          clock: clock.call,
        );
        final greedyC = client(s);
        final waiterC = client(s);

        final greedy = await greedyC.requestLease(
          const LeaseRequest(lessee: 'greedy'),
        );
        // The waiter queues (capacity full) — fired, not awaited.
        LeaseGrant? waiterGrant;
        final waiting = waiterC.requestLease(const LeaseRequest(lessee: 'late'));
        unawaited(waiting.then((g) => waiterGrant = g));
        await until(() => s.leases.queued == 1);

        // The incumbent renews mid-life — a touch CANNOT push past the cap.
        clock.advance(const Duration(seconds: 50));
        await greedyC.dispatch(greedy, const {}); // touch → expiry capped @ +100
        // SANITY CONTROL: while the incumbent legitimately holds, the waiter is
        // NOT yet served — so the eventual grant proves it came FROM the cap.
        expect(waiterGrant, isNull, reason: 'still held inside the lifetime');

        // Past the max lifetime: a pump reaps the greedy despite its renewals.
        clock.advance(const Duration(seconds: 51)); // total 101s > 100s lifetime
        await greedyC.presence(); // pump the owner clock → reap + drain the queue

        await until(() => waiterGrant != null); // the waiter IS served
        expect(
          waiterGrant!.fencingToken,
          greaterThan(greedy.fencingToken),
          reason: 'a fresh grant on the freed slot — starvation is bounded',
        );
      },
    );

    // MUTATION RESISTED: changing the FIFO dequeue in `LeaseManager._pump`
    // (`_queue.removeAt(0)` → `removeLast()`, i.e. LIFO). Arrival order is fixed
    // deterministically over the wire by waiting for each request to ENQUEUE
    // before firing the next; under LIFO the first release would serve the
    // last-arrived waiter, failing `expect(order[0], 'A')`.
    test(
      'queued waiters are served in ARRIVAL order across real request/response '
      'cycles — first-come first-served (FIFO fairness)',
      () async {
        final s = await serve(
          offered: 1,
          leaseWait: const Duration(seconds: 600),
        );
        final holderC = client(s);
        final wA = client(s);
        final wB = client(s);
        final wC = client(s);

        final held = await holderC.requestLease(
          const LeaseRequest(lessee: 'holder'),
        );

        // Fire waiters, fixing ARRIVAL ORDER over the real wire: poll the owner's
        // queue depth so each request has enqueued before the next is fired.
        final order = <String>[];
        final grants = <String, LeaseGrant>{};
        void record(String who, Future<LeaseGrant> f) =>
            unawaited(f.then((g) {
              grants[who] = g;
              order.add(who);
            }));

        record('A', wA.requestLease(const LeaseRequest(lessee: 'A')));
        await until(() => s.leases.queued == 1);
        record('B', wB.requestLease(const LeaseRequest(lessee: 'B')));
        await until(() => s.leases.queued == 2);
        record('C', wC.requestLease(const LeaseRequest(lessee: 'C')));
        await until(() => s.leases.queued == 3);

        // SANITY CONTROL: all three really are waiting (not a vacuous empty queue).
        expect(s.leases.queued, 3);

        // Drain one slot at a time; each release frees the slot for the FIFO head.
        await holderC.release(held);
        await until(() => order.length == 1);
        expect(order[0], 'A', reason: 'first-arrived served first');

        await wA.release(grants['A']!);
        await until(() => order.length == 2);
        expect(order[1], 'B');

        await wB.release(grants['B']!);
        await until(() => order.length == 3);
        expect(order[2], 'C');
        await wC.release(grants['C']!);

        // Tokens monotonically increase in service order — no waiter starved.
        expect(grants['A']!.fencingToken, lessThan(grants['B']!.fencingToken));
        expect(grants['B']!.fencingToken, lessThan(grants['C']!.fencingToken));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });

  // ===========================================================================
  group('Invariant 4 — IDEMPOTENCY (dup messages don\'t double-grant/run)', () {
    // MUTATION RESISTED: removing the `_grantsByKey` dedup in
    // `LeaseManager._tryGrantNow`. Without it, the same-key retry consumes a
    // SECOND slot (available would drop to 0 after g2) — failing the first
    // assertion. The sanity control (a DIFFERENT key DOES consume a slot) rules
    // out the opposite over-correction (always returning the first grant).
    test(
      'a retried lease (same idempotency key) returns the SAME grant — one slot; '
      'a DIFFERENT key consumes a new slot',
      () async {
        final s = await serve(offered: 2);
        final c = client(s);

        final g1 = await c.requestLease(
          const LeaseRequest(lessee: 'a', idempotencyKey: 'k'),
        );
        final g2 = await c.requestLease(
          const LeaseRequest(lessee: 'a', idempotencyKey: 'k'),
        );
        expect(g2.leaseId, g1.leaseId, reason: 'deduped to the live grant');
        expect(g2.fencingToken, g1.fencingToken);
        expect((await c.presence()).available, 1, reason: 'only ONE slot consumed');

        // SANITY CONTROL: dedup is KEY-scoped, not "always the first grant".
        final g3 = await c.requestLease(
          const LeaseRequest(lessee: 'a', idempotencyKey: 'k2'),
        );
        expect(g3.leaseId, isNot(g1.leaseId));
        expect((await c.presence()).available, 0, reason: 'a 2nd slot consumed');
      },
    );

    // MUTATION RESISTED: removing the `_dispatchByKey` memoization in
    // `StationServer._runDispatch`. Without it, the same-key re-dispatch RE-RUNS
    // the handler (`runs` would reach 2 after r2) — failing the first assertion.
    // The sanity control (a different dispatch key re-runs) rules out a constant /
    // key-ignoring memo that would wrongly replay everything.
    test(
      'a re-dispatched idempotency key runs the handler ONCE and replays the '
      'result; a DIFFERENT key runs again',
      () async {
        var runs = 0;
        Future<Map<String, dynamic>> counting(Map<String, dynamic> _) async {
          runs++;
          return {'run': runs};
        }

        final s = await serve(offered: 1, handler: counting);
        final c = client(s);
        final g = await c.requestLease(const LeaseRequest(lessee: 'a'));

        final r1 = await c.dispatch(g, const {}, idempotencyKey: 'd1');
        final r2 = await c.dispatch(g, const {}, idempotencyKey: 'd1');
        expect(runs, 1, reason: 'the owner deduped — a single run');
        expect(r2['run'], r1['run']);

        // SANITY CONTROL: a fresh dispatch key DOES run the handler again.
        await c.dispatch(g, const {}, idempotencyKey: 'd2');
        expect(runs, 2, reason: 'dedup is key-scoped, not blanket-replay');
      },
    );
  });
}
