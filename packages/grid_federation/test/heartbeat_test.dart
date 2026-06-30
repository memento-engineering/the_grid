// Pure-logic proof of owner-side HEARTBEAT reaping (ADR-0011 D5/D7), tested with
// an injected owner clock — no IO:
//   * a beat renews the lease's liveness deadline (heartbeat KEEPS it alive);
//   * missing heartbeats past the threshold → the OWNER reaps it by its own
//     clock (the disconnect handler), freeing the slot + advancing the FIFO queue;
//   * the heartbeat deadline is fenced (a stale token cannot beat) and capped by
//     the max lifetime.
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

/// A controllable owner clock.
class _Clock {
  DateTime now = DateTime.utc(2026);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

LeaseManager _hbManager(
  _Clock clock, {
  int offered = 1,
  Duration heartbeat = const Duration(seconds: 10),
  int threshold = 3,
  // A long idle TTL so heartbeat is the relevant liveness bound under test.
  Duration ttl = const Duration(seconds: 3600),
  Duration maxLifetime = const Duration(seconds: 7200),
}) => LeaseManager(
  station: 'b',
  offered: offered,
  ttl: ttl,
  maxLifetime: maxLifetime,
  heartbeat: heartbeat,
  missedHeartbeatThreshold: threshold,
  clock: clock.call,
);

void main() {
  group('heartbeat liveness', () {
    test('the grant advertises the heartbeat cadence; off by default', () {
      final off = LeaseManager(station: 'b', offered: 1);
      expect(off.grant(const LeaseRequest(lessee: 'x')).heartbeatSeconds, 0);
      expect(off.heartbeatTimeout, isNull);

      final on = _hbManager(_Clock());
      expect(on.grant(const LeaseRequest(lessee: 'x')).heartbeatSeconds, 10);
      expect(on.heartbeatTimeout, const Duration(seconds: 30)); // 10 × 3
    });

    test('a beat KEEPS the lease alive past the original deadline', () {
      final clock = _Clock();
      final m = _hbManager(clock); // timeout = 30s
      final g = m.grant(const LeaseRequest(lessee: 'x'));

      clock.advance(const Duration(seconds: 25)); // before the 30s deadline
      m.beat(g.leaseId, g.fencingToken); // → deadline now 25+30 = 55s
      clock.advance(const Duration(seconds: 25)); // total 50s < 55s
      expect(m.isValid(g.leaseId), isTrue); // still alive thanks to the beat
    });

    test(
      'missing heartbeats past the threshold → the OWNER reaps the lease',
      () {
        final clock = _Clock();
        final m = _hbManager(clock); // timeout = 30s
        final g = m.grant(const LeaseRequest(lessee: 'x'));
        expect(m.available, 0);

        clock.advance(const Duration(seconds: 29));
        expect(m.isValid(g.leaseId), isTrue); // inside the grace window

        clock.advance(const Duration(seconds: 2)); // 31s, no beat → past 30s
        m.tick(); // owner-clock reap
        expect(m.isValid(g.leaseId), isFalse);
        expect(m.available, 1); // the slot returns
      },
    );

    test(
      'heartbeat loss frees the slot and the FIFO waiter is granted',
      () async {
        final clock = _Clock();
        final m = _hbManager(clock); // offered 1, timeout 30s
        final held = m.grant(const LeaseRequest(lessee: 'first'));
        final waiterFut = m.acquire(
          const LeaseRequest(lessee: 'next'),
          maxWait: const Duration(seconds: 600),
        );
        expect(m.queued, 1);

        clock.advance(const Duration(seconds: 31)); // 'first' misses its beat
        m.tick(); // reap the disconnected holder → hand the slot to the waiter

        final granted = await waiterFut;
        expect(granted.leaseId, isNot(held.leaseId));
        expect(granted.fencingToken, greaterThan(held.fencingToken));
        expect(m.queued, 0);
      },
    );

    test('a beat with a STALE fencing token is refused', () {
      final m = _hbManager(_Clock());
      final g = m.grant(const LeaseRequest(lessee: 'x')); // token 1
      expect(
        () => m.beat(g.leaseId, 999),
        throwsA(isA<LeaseInvalidException>()),
      );
      // The rightful token works.
      m.beat(g.leaseId, g.fencingToken);
      expect(m.isValid(g.leaseId), isTrue);
    });

    test('a beat cannot push liveness past the max lifetime', () {
      final clock = _Clock();
      final m = _hbManager(
        clock,
        heartbeat: const Duration(seconds: 10),
        threshold: 3, // timeout 30s
        maxLifetime: const Duration(seconds: 40),
      );
      final g = m.grant(const LeaseRequest(lessee: 'greedy'));
      clock.advance(const Duration(seconds: 25)); // still inside the 30s window
      m.beat(g.leaseId, g.fencingToken); // would be 25+30=55s, capped at 40s
      clock.advance(const Duration(seconds: 16)); // 41s > the 40s lifetime
      expect(m.isValid(g.leaseId), isFalse); // reaped despite the fresh beat
    });
  });
}
