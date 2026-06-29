// Loopback proof of the federation bus: a lessor [StationServer] + a lessee
// [HttpStationClient] over localhost — presence, lease, dispatch, result,
// release, plus the fail-closed paths (no capacity, bad token, dead lease). The
// same flow runs cross-machine; only host/port change.
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

/// A deterministic executor — echoes the command back as a result, no spawn.
Future<CommandResult> _fakeExec(DispatchCommand cmd) async => CommandResult(
  exitCode: 0,
  stdout: 'ran ${cmd.command} ${cmd.args.join(' ')}',
  stderr: '',
  durationMs: 7,
);

void main() {
  group('federation loopback', () {
    test('presence → lease → dispatch → result → release (the happy path)',
        () async {
      final server = await StationServer.start(
        station: 'the-dashboard',
        offered: 1,
        host: '127.0.0.1',
        executor: _fakeExec,
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final p = await client.presence();
      expect(p.station, 'the-dashboard');
      expect(p.offered, 1);
      expect(p.available, 1);

      final grant = await client.requestLease(const LeaseRequest(lessee: 'the-studio'));
      expect(grant.station, 'the-dashboard');
      expect(grant.leaseId, isNotEmpty);
      // The slot is now held.
      expect((await client.presence()).available, 0);

      final result = await client.dispatch(
        grant.leaseId,
        const DispatchCommand(command: 'echo', args: ['hi']),
      );
      expect(result.ok, isTrue);
      expect(result.stdout, contains('echo hi'));

      await client.release(grant.leaseId);
      expect((await client.presence()).available, 1);
    });

    test('a real Process.run executes on the leased slot (default executor)',
        () async {
      final server = await StationServer.start(
        station: 'the-dashboard',
        offered: 1,
        host: '127.0.0.1',
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final grant = await client.requestLease(const LeaseRequest(lessee: 'x'));
      final result = await client.dispatch(
        grant.leaseId,
        const DispatchCommand(command: 'echo', args: ['federation-works']),
      );
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), 'federation-works');
    });

    test('declare-and-check: a lease is DENIED when no capacity is free',
        () async {
      final server = await StationServer.start(
        station: 'b',
        offered: 1,
        host: '127.0.0.1',
        executor: _fakeExec,
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      await client.requestLease(const LeaseRequest(lessee: 'a')); // takes the slot
      await expectLater(
        client.requestLease(const LeaseRequest(lessee: 'a2')),
        throwsA(isA<LeaseDeniedException>()),
      );
    });

    test('dispatch against a RELEASED lease throws LeaseInvalidException',
        () async {
      final server = await StationServer.start(
        station: 'b',
        offered: 1,
        host: '127.0.0.1',
        executor: _fakeExec,
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final grant = await client.requestLease(const LeaseRequest(lessee: 'a'));
      await client.release(grant.leaseId);
      await expectLater(
        client.dispatch(grant.leaseId, const DispatchCommand(command: 'echo')),
        throwsA(isA<LeaseInvalidException>()),
      );
    });

    test('token auth: a wrong/missing token is rejected (401)', () async {
      final server = await StationServer.start(
        station: 'b',
        offered: 1,
        host: '127.0.0.1',
        token: 'sekret',
        executor: _fakeExec,
      );
      addTearDown(server.close);

      final bad = HttpStationClient(host: '127.0.0.1', port: server.port, token: 'nope');
      addTearDown(bad.close);
      await expectLater(bad.presence(), throwsA(isA<FederationException>()));

      final good = HttpStationClient(host: '127.0.0.1', port: server.port, token: 'sekret');
      addTearDown(good.close);
      expect((await good.presence()).available, 1);
    });
  });
}
