// Pure-logic proof of the owner-authoritative [LeaseManager] — the four ADR-0011
// hazard bake-ins, tested with an injected clock + id generator, no IO:
//   1. fencing (monotonic token; stale token refused; reap+reissue bumps it)
//   2. max-lifetime + a FIFO wait-queue (starvation bound)
//   3. owner-clock reaping (no cross-machine time math)
//   4. request idempotency (a dup key → a single grant)
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

/// A controllable owner clock.
class _Clock {
  DateTime now = DateTime.utc(2026);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

LeaseManager _manager(
  _Clock clock, {
  int offered = 1,
  Duration ttl = const Duration(seconds: 300),
  Duration maxLifetime = const Duration(seconds: 3600),
  int maxQueueDepth = 64,
}) => LeaseManager(
  station: 'b',
  offered: offered,
  ttl: ttl,
  maxLifetime: maxLifetime,
  maxQueueDepth: maxQueueDepth,
  clock: clock.call,
);

void main() {
  group('fencing token (hazard #1)', () {
    test('every grant carries a monotonically increasing token', () {
      final m = _manager(_Clock(), offered: 3);
      final a = m.grant(const LeaseRequest(lessee: 'x'));
      final b = m.grant(const LeaseRequest(lessee: 'y'));
      final c = m.grant(const LeaseRequest(lessee: 'z'));
      expect([a.fencingToken, b.fencingToken, c.fencingToken], [1, 2, 3]);
    });

    test('touch/release with a STALE token is refused', () {
      final m = _manager(_Clock());
      final g = m.grant(const LeaseRequest(lessee: 'x')); // token 1
      expect(
        () => m.touch(g.leaseId, 999),
        throwsA(isA<LeaseInvalidException>()),
      );
      expect(
        () => m.release(g.leaseId, token: 999),
        throwsA(isA<LeaseInvalidException>()),
      );
      // The correct token still works.
      m.touch(g.leaseId, g.fencingToken);
      m.release(g.leaseId, token: g.fencingToken);
      expect(m.isValid(g.leaseId), isFalse);
    });

    test('reap+reissue bumps the token; the zombie old handle is refused', () {
      final clock = _Clock();
      final m = _manager(clock, ttl: const Duration(seconds: 10));
      final old = m.grant(const LeaseRequest(lessee: 'x')); // token 1
      clock.advance(const Duration(seconds: 11)); // TTL reaps the slot
      final fresh = m.grant(
        const LeaseRequest(lessee: 'y'),
      ); // token 2 on the reissue
      expect(fresh.fencingToken, greaterThan(old.fencingToken));
      // The zombie prior holder cannot act on its dead handle.
      expect(
        () => m.touch(old.leaseId, old.fencingToken),
        throwsA(isA<LeaseInvalidException>()),
      );
      // …and cannot free the NEW holder's slot with its stale token (fencing).
      expect(
        () => m.release(fresh.leaseId, token: old.fencingToken),
        throwsA(isA<LeaseInvalidException>()),
      );
      expect(m.isValid(fresh.leaseId), isTrue);
    });
  });

  group('FIFO wait-queue + max lifetime (hazard #2)', () {
    test(
      'full capacity → requests queue and are granted in ARRIVAL order',
      () async {
        final m = _manager(_Clock(), offered: 1);
        final held = m.grant(
          const LeaseRequest(lessee: 'first'),
        ); // takes the slot
        // Two more enqueue (do not await — they wait for capacity).
        final bFut = m.acquire(
          const LeaseRequest(lessee: 'b'),
          maxWait: const Duration(seconds: 60),
        );
        final cFut = m.acquire(
          const LeaseRequest(lessee: 'c'),
          maxWait: const Duration(seconds: 60),
        );
        expect(m.queued, 2);

        m.release(held.leaseId, token: held.fencingToken);
        final b = await bFut; // FIFO head granted first
        expect(m.queued, 1);
        m.release(b.leaseId, token: b.fencingToken);
        final c = await cFut;
        // Arrival order preserved by the monotonic id seq.
        expect(b.leaseId, 'b-lease-1');
        expect(c.leaseId, 'b-lease-2');
      },
    );

    test('a bounded queue DENIES when full', () {
      final m = _manager(_Clock(), offered: 1, maxQueueDepth: 1);
      m.grant(const LeaseRequest(lessee: 'held'));
      m.acquire(
        const LeaseRequest(lessee: 'q1'),
        maxWait: const Duration(seconds: 60),
      ); // fills the queue
      expect(
        m.acquire(
          const LeaseRequest(lessee: 'q2'),
          maxWait: const Duration(seconds: 60),
        ),
        throwsA(isA<LeaseDeniedException>()),
      );
    });

    test(
      'a waiter is DENIED once its wait expires by the owner clock',
      () async {
        final clock = _Clock();
        final m = _manager(clock, offered: 1);
        m.grant(const LeaseRequest(lessee: 'held'));
        final waiter = m.acquire(
          const LeaseRequest(lessee: 'late'),
          maxWait: const Duration(seconds: 10),
        );
        clock.advance(const Duration(seconds: 11));
        m.tick(); // owner-clock pump expires the overdue waiter
        await expectLater(waiter, throwsA(isA<LeaseDeniedException>()));
      },
    );

    test(
      'max lifetime CAPS renewal — touches cannot keep a lease alive forever',
      () {
        final clock = _Clock();
        // ttl is huge; lifetime is the real bound.
        final m = _manager(
          clock,
          ttl: const Duration(seconds: 1000),
          maxLifetime: const Duration(seconds: 100),
        );
        final g = m.grant(const LeaseRequest(lessee: 'greedy'));
        clock.advance(const Duration(seconds: 50));
        m.touch(g.leaseId, g.fencingToken); // renew — still inside the lifetime
        expect(m.isValid(g.leaseId), isTrue);
        clock.advance(
          const Duration(seconds: 51),
        ); // now past the 100s lifetime
        expect(m.isValid(g.leaseId), isFalse); // reaped despite a fresh touch
      },
    );
  });

  group('owner-clock reaping (hazard #3)', () {
    test('an idle lease is reaped strictly by the owner clock + TTL', () {
      final clock = _Clock();
      final m = _manager(clock, ttl: const Duration(seconds: 30));
      final g = m.grant(const LeaseRequest(lessee: 'x'));
      clock.advance(const Duration(seconds: 29));
      expect(m.isValid(g.leaseId), isTrue);
      clock.advance(const Duration(seconds: 2)); // 31s total → past TTL
      expect(m.isValid(g.leaseId), isFalse);
      expect(m.available, 1); // the slot frees
    });
  });

  group('onLeaseEnded (the lessor teardown hook)', () {
    test('fires on explicit release AND on every reap path; a throwing '
        'callback never corrupts accounting', () {
      final clock = _Clock();
      final ended = <String>[];
      final m = LeaseManager(
        station: 'b',
        offered: 2,
        ttl: const Duration(seconds: 30),
        clock: clock.call,
        onLeaseEnded: (id) {
          ended.add(id);
          throw StateError('hook explodes'); // exception-isolated
        },
      );

      // Explicit release fires the hook.
      final g1 = m.grant(const LeaseRequest(lessee: 'x'));
      m.release(g1.leaseId, token: g1.fencingToken);
      expect(ended, [g1.leaseId]);
      expect(m.available, 2, reason: 'a throwing hook never blocks the slot');

      // An idle-TTL reap fires the hook too (the follower app must die when
      // its lease does, however the lease ends).
      final g2 = m.grant(const LeaseRequest(lessee: 'x'));
      clock.advance(const Duration(seconds: 31));
      m.tick();
      expect(ended, [g1.leaseId, g2.leaseId]);
      expect(m.available, 2);
    });
  });

  group('idempotency (hazard #4)', () {
    test(
      'a retried request (same key) returns the SAME grant, never a second',
      () {
        final m = _manager(_Clock(), offered: 2);
        final a = m.grant(
          const LeaseRequest(lessee: 'x', idempotencyKey: 'k1'),
        );
        final b = m.grant(
          const LeaseRequest(lessee: 'x', idempotencyKey: 'k1'),
        );
        expect(b.leaseId, a.leaseId);
        expect(b.fencingToken, a.fencingToken);
        expect(m.available, 1); // only ONE slot consumed
      },
    );

    test('after release the key is freed — a re-request is a NEW grant', () {
      final m = _manager(_Clock());
      final a = m.grant(const LeaseRequest(lessee: 'x', idempotencyKey: 'k1'));
      m.release(a.leaseId, token: a.fencingToken);
      final b = m.grant(const LeaseRequest(lessee: 'x', idempotencyKey: 'k1'));
      expect(b.leaseId, isNot(a.leaseId));
      expect(b.fencingToken, greaterThan(a.fencingToken));
    });

    test(
      'a concurrent acquire retry attaches to the SAME queued waiter',
      () async {
        final m = _manager(_Clock(), offered: 1);
        final held = m.grant(const LeaseRequest(lessee: 'held'));
        final f1 = m.acquire(
          const LeaseRequest(lessee: 'x', idempotencyKey: 'dup'),
          maxWait: const Duration(seconds: 60),
        );
        final f2 = m.acquire(
          const LeaseRequest(lessee: 'x', idempotencyKey: 'dup'),
          maxWait: const Duration(seconds: 60),
        );
        expect(m.queued, 1); // one waiter, not two
        m.release(held.leaseId, token: held.fencingToken);
        final g1 = await f1;
        final g2 = await f2;
        expect(g2.leaseId, g1.leaseId); // one grant satisfies both
      },
    );
  });

  group('declare-and-check', () {
    test('grant DENIES immediately when no capacity (no queue)', () {
      final m = _manager(_Clock(), offered: 1);
      m.grant(const LeaseRequest(lessee: 'x'));
      expect(
        () => m.grant(const LeaseRequest(lessee: 'y')),
        throwsA(isA<LeaseDeniedException>()),
      );
    });

    test(
      'a kind that is not offered is a permanent deny (even with a wait)',
      () {
        final m = _manager(_Clock());
        expect(
          m.acquire(
            const LeaseRequest(lessee: 'x', kind: 'gpu'),
            maxWait: const Duration(seconds: 60),
          ),
          throwsA(isA<LeaseDeniedException>()),
        );
      },
    );
  });
}
