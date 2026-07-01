// M6 Track D — the COMPUTE domain's BOUNDED "use" (ADR-0011 D3 + the Hazards
// RCE-bounds note).
//
// The bound runs a CONSTRAINED command (allow-list + explicit argv + timeout) —
// NOT raw shell-as-a-service. Fakes (an injected executor), no real process; a
// loopback case proves the lessor-side glue + the bound end-to-end over the bus.
import 'dart:async';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_federation/grid_federation.dart';
import 'package:grid_runtime/grid_runtime.dart' show ProcessGroupController;
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

    test('a hung command is REAPED on timeout (the M4 group reaper fires, not '
        'just an abandoned wait)', () async {
      final groups = _FakeGroups(); // resolvePgid = identity; dies on SIGTERM
      final hung = _HungComputeProcess(pid: 4242);
      final bounded = BoundedCommandExecutor(
        bounds: const ComputeBounds(
          allowedCommands: {'sleep'},
          timeout: Duration(milliseconds: 20),
        ),
        spawn: (cmd) async => hung,
        groups: groups,
      );
      final r = await bounded.run(const DispatchCommand(command: 'sleep'));
      expect(r.exitCode, 124);
      expect(r.stderr, contains('reaped'));
      // The reaper SIGNALLED the spawned group — the leak fix, not the old
      // abandon-the-wait behaviour (this assertion fails if _reap is removed).
      expect(
        groups.signals.map((s) => s.$2),
        contains(ProcessSignal.sigterm),
        reason: 'the timeout must reap the spawned group',
      );
      expect(groups.signals.first.$1, 4242, reason: 'reaped the spawned pgid');
      expect(
        hung.killed,
        isFalse,
        reason: 'the group reaper handled it — no direct-kill fallback needed',
      );
    });

    test('an unresolvable pgid falls back to a direct kill (never leaks)',
        () async {
      final groups = _FakeGroups(resolvesToNull: true);
      final hung = _HungComputeProcess(pid: 4242);
      final bounded = BoundedCommandExecutor(
        bounds: const ComputeBounds(
          allowedCommands: {'sleep'},
          timeout: Duration(milliseconds: 20),
        ),
        spawn: (cmd) async => hung,
        groups: groups,
      );
      final r = await bounded.run(const DispatchCommand(command: 'sleep'));
      expect(r.exitCode, 124);
      expect(groups.signals, isEmpty, reason: 'no pgid → no group signal');
      expect(hung.killed, isTrue, reason: 'fell back to a direct kill');
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

/// A fake [ProcessGroupController] for the reap path: [resolvePgid] is identity
/// (or null when [resolvesToNull]); the group "dies" after the first SIGTERM so
/// [terminateGroup] returns within one poll. Records every signal sent.
class _FakeGroups implements ProcessGroupController {
  _FakeGroups({this.resolvesToNull = false});

  final bool resolvesToNull;
  final List<(int pgid, ProcessSignal signal)> signals = [];
  int _termCount = 0;
  bool _killed = false;

  @override
  Future<int?> resolvePgid(int pid) async => resolvesToNull ? null : pid;

  @override
  bool processAlive(int pid) => !_killed && _termCount == 0;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    if (signal == ProcessSignal.sigterm) _termCount++;
    if (signal == ProcessSignal.sigkill) _killed = true;
    return true;
  }

  @override
  int currentGroupId() => 99999; // never equals a test pgid → guard passes
}

/// A [ComputeProcess] whose [exitCode] never completes — a hung command, so the
/// bound's timeout (and the reap) is the only way out.
class _HungComputeProcess implements ComputeProcess {
  _HungComputeProcess({required this.pid});

  @override
  final int pid;

  bool killed = false;

  @override
  Future<int> get exitCode => Completer<int>().future; // never completes

  @override
  Future<String> stdoutText() async => '';

  @override
  Future<String> stderrText() async => '';

  @override
  void kill() => killed = true;
}
