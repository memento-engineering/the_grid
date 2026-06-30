// Loopback proof of the federation bus: a lessor [StationServer] + a lessee
// [HttpStationClient] over localhost — presence, lease, dispatch, result,
// release, plus the fail-closed paths (no capacity, bad token, dead lease) AND
// the ADR-0011 hazard bake-ins ON THE WIRE: a stale fencing token is refused, a
// dispatch idempotency key dedups a re-run, and the FIFO wait-queue drains over
// the bus. The same flow runs cross-machine; only host/port change.
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

/// A deterministic compute executor — echoes the command back as a result, no
/// spawn.
Future<CommandResult> _fakeExec(DispatchCommand cmd) async => CommandResult(
  exitCode: 0,
  stdout: 'ran ${cmd.command} ${cmd.args.join(' ')}',
  stderr: '',
  durationMs: 7,
);

/// A controllable OWNER clock — injected into the lessor so heartbeat reaping is
/// driven by the test, not wall-time.
class _Clock {
  DateTime now = DateTime.utc(2026);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('federation loopback', () {
    test(
      'presence → lease → dispatch → result → release (the happy path)',
      () async {
        final server = await StationServer.start(
          station: 'the-dashboard',
          offered: 1,
          host: '127.0.0.1',
          handler: computeDispatchHandler(_fakeExec),
        );
        addTearDown(server.close);
        final client = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(client.close);

        final p = await client.presence();
        expect(p.station, 'the-dashboard');
        expect(p.offered, 1);
        expect(p.available, 1);

        final grant = await client.requestLease(
          const LeaseRequest(lessee: 'the-studio'),
        );
        expect(grant.station, 'the-dashboard');
        expect(grant.leaseId, isNotEmpty);
        expect(grant.fencingToken, greaterThan(0));
        // The slot is now held.
        expect((await client.presence()).available, 0);

        final result = CommandResult.fromJson(
          await client.dispatch(
            grant,
            const DispatchCommand(command: 'echo', args: ['hi']).toJson(),
          ),
        );
        expect(result.ok, isTrue);
        expect(result.stdout, contains('echo hi'));

        await client.release(grant);
        expect((await client.presence()).available, 1);
      },
    );

    test(
      'a real Process.run executes on the leased slot (default handler)',
      () async {
        final server = await StationServer.start(
          station: 'the-dashboard',
          offered: 1,
          host: '127.0.0.1',
        );
        addTearDown(server.close);
        final client = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(client.close);

        final grant = await client.requestLease(
          const LeaseRequest(lessee: 'x'),
        );
        final result = CommandResult.fromJson(
          await client.dispatch(
            grant,
            const DispatchCommand(
              command: 'echo',
              args: ['federation-works'],
            ).toJson(),
          ),
        );
        expect(result.exitCode, 0);
        expect(result.stdout.trim(), 'federation-works');
      },
    );

    test(
      'declare-and-check: a lease is DENIED when no capacity is free',
      () async {
        final server = await StationServer.start(
          station: 'b',
          offered: 1,
          host: '127.0.0.1',
          handler: computeDispatchHandler(_fakeExec),
        );
        addTearDown(server.close);
        final client = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(client.close);

        await client.requestLease(
          const LeaseRequest(lessee: 'a'),
        ); // takes the slot
        await expectLater(
          client.requestLease(const LeaseRequest(lessee: 'a2')),
          throwsA(isA<LeaseDeniedException>()),
        );
      },
    );

    test(
      'dispatch against a RELEASED lease throws LeaseInvalidException',
      () async {
        final server = await StationServer.start(
          station: 'b',
          offered: 1,
          host: '127.0.0.1',
          handler: computeDispatchHandler(_fakeExec),
        );
        addTearDown(server.close);
        final client = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(client.close);

        final grant = await client.requestLease(
          const LeaseRequest(lessee: 'a'),
        );
        await client.release(grant);
        await expectLater(
          client.dispatch(
            grant,
            const DispatchCommand(command: 'echo').toJson(),
          ),
          throwsA(isA<LeaseInvalidException>()),
        );
      },
    );

    test('token auth: a wrong/missing token is rejected (401)', () async {
      final server = await StationServer.start(
        station: 'b',
        offered: 1,
        host: '127.0.0.1',
        token: 'sekret',
        handler: computeDispatchHandler(_fakeExec),
      );
      addTearDown(server.close);

      final bad = HttpStationClient(
        host: '127.0.0.1',
        port: server.port,
        token: 'nope',
      );
      addTearDown(bad.close);
      await expectLater(bad.presence(), throwsA(isA<FederationException>()));

      final good = HttpStationClient(
        host: '127.0.0.1',
        port: server.port,
        token: 'sekret',
      );
      addTearDown(good.close);
      expect((await good.presence()).available, 1);
    });

    test(
      'fencing: a STALE token dispatch/release is refused on the wire',
      () async {
        final server = await StationServer.start(
          station: 'b',
          offered: 1,
          host: '127.0.0.1',
          handler: computeDispatchHandler(_fakeExec),
        );
        addTearDown(server.close);
        final client = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(client.close);

        final grant = await client.requestLease(
          const LeaseRequest(lessee: 'a'),
        );
        final forged = LeaseGrant(
          leaseId: grant.leaseId,
          station: grant.station,
          ttlSeconds: grant.ttlSeconds,
          fencingToken:
              grant.fencingToken + 99, // a token the owner never issued
        );
        await expectLater(
          client.dispatch(
            forged,
            const DispatchCommand(command: 'echo').toJson(),
          ),
          throwsA(isA<LeaseInvalidException>()),
        );
        await expectLater(
          client.release(forged),
          throwsA(isA<LeaseInvalidException>()),
        );
        // The real holder is untouched.
        final ok = CommandResult.fromJson(
          await client.dispatch(
            grant,
            const DispatchCommand(command: 'echo').toJson(),
          ),
        );
        expect(ok.ok, isTrue);
      },
    );

    test(
      'idempotency: a re-dispatched key runs ONCE and replays the result',
      () async {
        var runs = 0;
        Future<Map<String, dynamic>> countingHandler(
          Map<String, dynamic> payload,
        ) async {
          runs++;
          return {
            'exitCode': 0,
            'stdout': 'run #$runs',
            'stderr': '',
            'durationMs': 1,
          };
        }

        final server = await StationServer.start(
          station: 'b',
          offered: 1,
          host: '127.0.0.1',
          handler: countingHandler,
        );
        addTearDown(server.close);
        final client = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(client.close);

        final grant = await client.requestLease(
          const LeaseRequest(lessee: 'a'),
        );
        final payload = const DispatchCommand(command: 'echo').toJson();
        final r1 = CommandResult.fromJson(
          await client.dispatch(grant, payload, idempotencyKey: 'job-1'),
        );
        final r2 = CommandResult.fromJson(
          await client.dispatch(grant, payload, idempotencyKey: 'job-1'),
        );
        expect(runs, 1); // the owner deduped — a single run
        expect(r2.stdout, r1.stdout);
        expect(r1.stdout, 'run #1');
      },
    );

    test(
      'idempotency: a repeated lease key returns the SAME grant on the wire',
      () async {
        final server = await StationServer.start(
          station: 'b',
          offered: 2,
          host: '127.0.0.1',
          handler: computeDispatchHandler(_fakeExec),
        );
        addTearDown(server.close);
        final client = HttpStationClient(host: '127.0.0.1', port: server.port);
        addTearDown(client.close);

        final g1 = await client.requestLease(
          const LeaseRequest(lessee: 'a', idempotencyKey: 'lease-k'),
        );
        final g2 = await client.requestLease(
          const LeaseRequest(lessee: 'a', idempotencyKey: 'lease-k'),
        );
        expect(g2.leaseId, g1.leaseId);
        expect(g2.fencingToken, g1.fencingToken);
        expect(
          (await client.presence()).available,
          1,
        ); // only one slot consumed
      },
    );

    test('wait-queue: a full-capacity request WAITS over the bus, then is '
        'granted as the slot frees (instead of an immediate deny)', () async {
      final server = await StationServer.start(
        station: 'b',
        offered: 1,
        host: '127.0.0.1',
        leaseWait: const Duration(seconds: 60),
        handler: computeDispatchHandler(_fakeExec),
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final first = await client.requestLease(
        const LeaseRequest(lessee: 'first'),
      );
      // Capacity is full; this blocks server-side in the FIFO queue rather than
      // failing — fired WITHOUT awaiting so we can free the slot underneath it.
      final waiting = client.requestLease(const LeaseRequest(lessee: 'b'));

      await client.release(first); // frees the slot → the waiter is granted
      final granted = await waiting;
      expect(granted.leaseId, isNot(first.leaseId));
      expect(granted.fencingToken, greaterThan(first.fencingToken));

      await client.release(granted);
      expect((await client.presence()).available, 1);
    });
  });

  group('federation membership/presence/heartbeat (Track B)', () {
    test('presence carries the capability profile + ephemeral capacity', () async {
      final server = await StationServer.start(
        station: 'the-dashboard',
        offered: 2,
        host: '127.0.0.1',
        profile: const {
          'system-os': 'linux',
          'flutter-target': ['linux', 'android'],
        },
        handler: computeDispatchHandler(_fakeExec),
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final p = await client.presence();
      expect(p.station, 'the-dashboard');
      expect(p.offered, 2);
      expect(p.available, 2); // the EPHEMERAL half
      expect(p.profile['system-os'], 'linux'); // the DURABLE half
      expect(p.profile['flutter-target'], ['linux', 'android']);

      // After a lease only capacity churns; the durable profile is unchanged.
      await client.requestLease(const LeaseRequest(lessee: 'studio'));
      final p2 = await client.presence();
      expect(p2.available, 1);
      expect(p2.profile['system-os'], 'linux');
    });

    test('heartbeat over the wire keeps a lease alive; loss reaps it', () async {
      final clock = _Clock();
      final server = await StationServer.start(
        station: 'b',
        offered: 1,
        host: '127.0.0.1',
        heartbeat: const Duration(seconds: 10), // timeout = 10 × 3 = 30s
        handler: computeDispatchHandler(_fakeExec),
        clock: clock.call,
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final grant = await client.requestLease(const LeaseRequest(lessee: 'a'));
      expect(grant.heartbeatSeconds, 10); // the cadence is advertised
      expect((await client.presence()).available, 0); // held

      // A heartbeat before the 30s deadline pushes it out to 25 + 30 = 55s.
      clock.advance(const Duration(seconds: 25));
      await client.heartbeat(grant);
      clock.advance(const Duration(seconds: 25)); // total 50s < 55s
      expect((await client.presence()).available, 0); // still held — kept alive

      // Stop heartbeating: past the deadline the owner reaps on the next read.
      clock.advance(const Duration(seconds: 10)); // 60s > the 55s deadline
      expect((await client.presence()).available, 1); // reaped → slot returns
    });

    test('a missed heartbeat reaps the slot and a new lessee is granted over '
        'the bus (FIFO queue advances)', () async {
      final clock = _Clock();
      final server = await StationServer.start(
        station: 'b',
        offered: 1,
        host: '127.0.0.1',
        heartbeat: const Duration(seconds: 10), // timeout 30s
        leaseWait: const Duration(seconds: 600),
        handler: computeDispatchHandler(_fakeExec),
        clock: clock.call,
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final first = await client.requestLease(
        const LeaseRequest(lessee: 'first'),
      );
      // Capacity is full → this WAITS server-side in the FIFO queue.
      final waiting = client.requestLease(const LeaseRequest(lessee: 'next'));

      // 'first' never heartbeats; past the threshold the owner reaps it, and a
      // request that pumps the manager hands the freed slot to the waiter.
      clock.advance(const Duration(seconds: 31));
      await client.presence();

      final granted = await waiting;
      expect(granted.leaseId, isNot(first.leaseId));
      expect(granted.fencingToken, greaterThan(first.fencingToken));
      await client.release(granted);
    });
  });
}
