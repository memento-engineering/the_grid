// M6 Track D — the COMPUTE domain's BOUNDED "use" (ADR-0011 D3 + the Hazards
// RCE-bounds note).
//
// The bound runs a CONSTRAINED command (allow-list + explicit argv + timeout) —
// NOT raw shell-as-a-service. Fakes (an injected executor), no real process; a
// loopback case proves the lessor-side glue + the bound end-to-end over the bus.
import 'dart:async';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

void main() {
  group('ComputeBounds', () {
    test('allows only allow-listed executables', () {
      const bounds = ComputeBounds(allowedCommands: {'echo', 'uname'});
      expect(bounds.allows('echo'), isTrue);
      expect(bounds.allows('uname'), isTrue);
      expect(bounds.allows('rm'), isFalse);
    });
  });

  group('BoundedCommandExecutor — the bounded "use"', () {
    test('runs an in-bounds command through the injected executor', () async {
      final ran = <DispatchCommand>[];
      final bounded = BoundedCommandExecutor(
        bounds: const ComputeBounds(allowedCommands: {'echo'}),
        executor: (cmd) async {
          ran.add(cmd);
          return CommandResult(
            exitCode: 0,
            stdout: 'ran ${cmd.command}',
            stderr: '',
            durationMs: 1,
          );
        },
      );
      final r = await bounded.run(
        const DispatchCommand(command: 'echo', args: ['hi']),
      );
      expect(r.ok, isTrue);
      expect(r.stdout, 'ran echo');
      expect(ran.single.command, 'echo');
    });

    test('REJECTS an out-of-bounds command (not on the allow-list)', () async {
      var ran = false;
      final bounded = BoundedCommandExecutor(
        bounds: const ComputeBounds(allowedCommands: {'echo'}),
        executor: (cmd) async {
          ran = true;
          return const CommandResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            durationMs: 0,
          );
        },
      );
      await expectLater(
        bounded.run(const DispatchCommand(command: 'rm', args: ['-rf', '/'])),
        throwsA(isA<ComputeBoundsException>()),
      );
      expect(
        ran,
        isFalse,
        reason: 'the executor must NOT run an out-of-bounds command',
      );
    });

    test('REJECTS an empty command', () async {
      final bounded = BoundedCommandExecutor(
        bounds: const ComputeBounds(allowedCommands: {'echo'}),
      );
      await expectLater(
        bounded.run(const DispatchCommand(command: '')),
        throwsA(isA<ComputeBoundsException>()),
      );
    });

    test('a hung command is bounded by the timeout (non-zero result)', () async {
      final bounded = BoundedCommandExecutor(
        bounds: const ComputeBounds(
          allowedCommands: {'sleep'},
          timeout: Duration(milliseconds: 20),
        ),
        // Never completes — the timeout must fire.
        executor: (cmd) => Completer<CommandResult>().future,
      );
      final r = await bounded.run(const DispatchCommand(command: 'sleep'));
      expect(r.ok, isFalse);
      expect(r.exitCode, 124);
      expect(r.stderr, contains('timed out'));
    });
  });

  group('computeDispatchHandler — the lessor-side bus glue', () {
    test('decodes → runs a bounded use → encodes the result', () async {
      final handler = computeDispatchHandler(
        bounds: const ComputeBounds(allowedCommands: {'echo'}),
        executor: (cmd) async => CommandResult(
          exitCode: 0,
          stdout: cmd.args.join(' '),
          stderr: '',
          durationMs: 2,
        ),
      );
      final out = await handler(
        const DispatchCommand(command: 'echo', args: ['federation']).toJson(),
      );
      final r = CommandResult.fromJson(out);
      expect(r.ok, isTrue);
      expect(r.stdout, 'federation');
    });

    test('an out-of-bounds command surfaces as exit 126 (refused, never run)',
        () async {
      var ran = false;
      final handler = computeDispatchHandler(
        bounds: const ComputeBounds(allowedCommands: {'echo'}),
        executor: (cmd) async {
          ran = true;
          return const CommandResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            durationMs: 0,
          );
        },
      );
      final r = CommandResult.fromJson(
        await handler(const DispatchCommand(command: 'curl').toJson()),
      );
      expect(r.exitCode, 126);
      expect(r.stderr, contains('allow-list'));
      expect(ran, isFalse);
    });
  });

  group('computeDispatchHandler over the federation bus (loopback)', () {
    test('a lessor BOUNDS dispatched commands end-to-end over the wire',
        () async {
      final server = await StationServer.start(
        station: 'lessor',
        offered: 1,
        host: '127.0.0.1',
        kind: kComputeKind,
        handler: computeDispatchHandler(
          bounds: const ComputeBounds(allowedCommands: {'echo'}),
          executor: (cmd) async => CommandResult(
            exitCode: 0,
            stdout: 'echoed:${cmd.args.join(',')}',
            stderr: '',
            durationMs: 1,
          ),
        ),
      );
      addTearDown(server.close);
      final client = HttpStationClient(host: '127.0.0.1', port: server.port);
      addTearDown(client.close);

      final grant = await client.requestLease(
        const LeaseRequest(lessee: 'studio', kind: kComputeKind),
      );
      // In-bounds → runs on the lessor.
      final ok = CommandResult.fromJson(
        await client.dispatch(
          grant,
          const DispatchCommand(command: 'echo', args: ['hi']).toJson(),
        ),
      );
      expect(ok.ok, isTrue);
      expect(ok.stdout, 'echoed:hi');
      // Out-of-bounds → refused (126); the lessor never runs it.
      final refused = CommandResult.fromJson(
        await client.dispatch(
          grant,
          const DispatchCommand(command: 'rm', args: ['-rf']).toJson(),
        ),
      );
      expect(refused.exitCode, 126);

      await client.release(grant);
    });
  });
}
