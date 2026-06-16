import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// A fake [SubprocessSpawner] (Fakes, not mocks): it records the env/argv/cwd it
/// was handed, hands back synthesizable stdout/stderr, and resolves a
/// caller-controlled exit code — so the env-allowlist, output-streaming, and
/// exit-event behaviour run with no real OS process.
class FakeSpawner implements SubprocessSpawner {
  Map<String, String>? lastEnv;
  List<String>? lastArgs;
  String? lastExecutable;
  String? lastWorkDir;

  final StreamController<List<int>> stdoutCtl =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> stderrCtl =
      StreamController<List<int>>.broadcast();
  final Completer<int> exit = Completer<int>();

  int nextPid = 4242;

  @override
  Future<SpawnedProcess> spawn({
    required String executable,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    lastExecutable = executable;
    lastArgs = args;
    lastWorkDir = workingDirectory;
    lastEnv = environment;
    return _FakeSpawned(
      pid: nextPid,
      stdout: stdoutCtl.stream,
      stderr: stderrCtl.stream,
      exitCode: exit.future,
    );
  }

  void emitStdout(String line) => stdoutCtl.add(utf8.encode('$line\n'));
  void emitStderr(String line) => stderrCtl.add(utf8.encode('$line\n'));
  void finish(int code) {
    stdoutCtl.close();
    stderrCtl.close();
    if (!exit.isCompleted) exit.complete(code);
  }
}

class _FakeSpawned implements SpawnedProcess {
  _FakeSpawned({
    required this.pid,
    required this.stdout,
    required this.stderr,
    required Future<int> exitCode,
  }) : _exit = exitCode;

  @override
  final int pid;
  @override
  final Stream<List<int>> stdout;
  @override
  final Stream<List<int>> stderr;
  final Future<int> _exit;

  @override
  Future<int>? get exitCode => _exit;
}

/// A fake process-group seam that reports the spawned pid as always-alive until
/// told otherwise — keeps the liveness poll from racing the exit-code path in
/// the fake-spawner tests.
class AliveGroupController implements ProcessGroupController {
  bool alive = true;
  final List<(int, ProcessSignal)> signals = [];

  @override
  Future<int?> resolvePgid(int pid) async => pid;
  @override
  bool processAlive(int pid) => alive;
  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    return true;
  }

  @override
  int currentGroupId() => 99999;
}

void main() {
  group('SubprocessProvider — env policy (fake spawner)', () {
    test(
        'child env contains the token allowlist and NOT GC_DOLT_PASSWORD; '
        'injects GRID_* incarnation env', () async {
      final spawner = FakeSpawner();
      final provider = SubprocessProvider(
        spawner: spawner,
        groupController: AliveGroupController(),
        // A fake parent env: a real OAuth token + a real Dolt password we prove
        // is filtered out.
        parentEnvironment: const {
          'CLAUDE_CODE_OAUTH_TOKEN': 'fake-token-xyz',
          'GC_DOLT_PASSWORD': 'must-not-leak',
          'HOME': '/Users/tgdog',
          'PATH': '/usr/bin',
        },
      );

      await provider.start(
        'tgdog-sess-1',
        const RuntimeConfig(
          workDir: '/tmp/worktree',
          command: 'claude',
          args: ['-p', '--dangerously-skip-permissions'],
          env: {'GRID_BEAD_ID': 'tgdog-work-7'},
        ),
      );

      final env = spawner.lastEnv!;
      // (a) token allowlist forwarded:
      expect(env['CLAUDE_CODE_OAUTH_TOKEN'], 'fake-token-xyz');
      expect(env['HOME'], '/Users/tgdog');
      expect(env['PATH'], '/usr/bin');
      // (a) host secret filtered:
      expect(env.containsKey('GC_DOLT_PASSWORD'), isFalse);
      // GRID_* incarnation env injected:
      expect(env['GRID_SESSION_ID'], 'tgdog-sess-1');
      expect(env['GRID_BEAD_ID'], 'tgdog-work-7');
      expect(env['GRID_RUNTIME_EPOCH'], '1');
      expect(env['GRID_INSTANCE_TOKEN'], matches(RegExp(r'^[0-9a-f]{32}$')));
      // argv carries no secret:
      expect(spawner.lastArgs, ['-p', '--dangerously-skip-permissions']);
      expect(spawner.lastArgs!.join(' '), isNot(contains('fake-token-xyz')));

      await provider.dispose();
    });

    test('(c) output streams the transcript line by line', () async {
      final spawner = FakeSpawner();
      final provider = SubprocessProvider(
        spawner: spawner,
        groupController: AliveGroupController(),
        parentEnvironment: const {'PATH': '/usr/bin'},
      );

      await provider.start(
        'sess',
        const RuntimeConfig(workDir: '/tmp', command: 'claude'),
      );

      final lines = <String>[];
      final sub = provider.output('sess').listen(lines.add);

      spawner.emitStdout('hello from agent');
      spawner.emitStderr('a warning');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(lines, containsAll(['hello from agent', 'a warning']));
      expect(provider.peek('sess', 0), contains('hello from agent'));

      await sub.cancel();
      await provider.dispose();
    });

    test('(d) RuntimeEvent.exited fires with the exit code on process exit',
        () async {
      final spawner = FakeSpawner();
      final group = AliveGroupController();
      final provider = SubprocessProvider(
        spawner: spawner,
        groupController: group,
        parentEnvironment: const {'PATH': '/usr/bin'},
      );

      final events = <RuntimeEvent>[];
      final sub = provider.events.listen(events.add);

      await provider.start(
        'sess',
        const RuntimeConfig(workDir: '/tmp', command: 'claude'),
      );

      // Process exits with code 7 (the fake resolves the exit future).
      spawner.finish(7);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(events.whereType<SessionStarted>(), hasLength(1));
      final exited = events.whereType<Exited>().toList();
      expect(exited, hasLength(1));
      expect(exited.single.exitCode, 7);
      expect(exited.single.name, 'sess');
      // The session is no longer running after exit.
      expect(provider.isRunning('sess'), isFalse);

      await sub.cancel();
      await provider.dispose();
    });

    test('duplicate start rejects with SessionAlreadyExists', () async {
      final spawner = FakeSpawner();
      final provider = SubprocessProvider(
        spawner: spawner,
        groupController: AliveGroupController(),
        parentEnvironment: const {'PATH': '/usr/bin'},
      );

      await provider.start(
        'dup',
        const RuntimeConfig(workDir: '/tmp', command: 'claude'),
      );
      expect(
        () => provider.start(
          'dup',
          const RuntimeConfig(workDir: '/tmp', command: 'claude'),
        ),
        throwsA(isA<SessionAlreadyExists>()),
      );

      await provider.dispose();
    });

    test('SessionStarted carries the resolved pgid and bead id', () async {
      final spawner = FakeSpawner()..nextPid = 31337;
      final provider = SubprocessProvider(
        spawner: spawner,
        groupController: AliveGroupController(),
        parentEnvironment: const {'PATH': '/usr/bin'},
      );

      final events = <RuntimeEvent>[];
      final sub = provider.events.listen(events.add);

      await provider.start(
        'sess',
        const RuntimeConfig(
          workDir: '/tmp',
          command: 'claude',
          env: {'GRID_BEAD_ID': 'tgdog-9'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final started = events.whereType<SessionStarted>().single;
      expect(started.pid, 31337);
      expect(started.pgid, 31337); // identity resolvePgid in the fake
      expect(started.beadId, 'tgdog-9');

      await sub.cancel();
      await provider.dispose();
    });
  });

  group('SubprocessProvider — whole-tree kill (REAL stub, never claude)', () {
    test(
        '(b) stop() SIGKILLs the whole process group — a child that spawns a '
        'grandchild: BOTH die', () async {
      // A stub that records its grandchild pid to a marker file, then both the
      // child and the grandchild sleep "forever". NEVER the real claude binary.
      final tmp = await Directory.systemTemp.createTemp('grid_runtime_pg_');
      addTearDown(() => tmp.delete(recursive: true));
      final marker = File('${tmp.path}/grandchild.pid');
      final stub = File('${tmp.path}/stub.sh')
        ..writeAsStringSync('''
#!/bin/sh
# grandchild: a long sleep in the same process group
( sleep 120 ) &
echo \$! > "${marker.path}"
echo "stub-up pid=\$\$"
sleep 120
''');
      await Process.run('chmod', ['+x', stub.path]);

      final provider = SubprocessProvider(
        // Real spawn (detached, new group) + real group controller — this test
        // proves the actual OS group kill.
        parentEnvironment: const {'PATH': '/usr/bin:/bin'},
        stopGrace: const Duration(milliseconds: 300),
      );

      await provider.start(
        'kill-tree',
        RuntimeConfig(workDir: tmp.path, command: '/bin/sh', args: [stub.path]),
      );

      // Wait for the stub to write the grandchild pid.
      var grandchildPid = 0;
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (marker.existsSync()) {
          final s = marker.readAsStringSync().trim();
          if (s.isNotEmpty) {
            grandchildPid = int.tryParse(s) ?? 0;
            if (grandchildPid > 0) break;
          }
        }
      }
      expect(grandchildPid, greaterThan(0),
          reason: 'stub should have recorded its grandchild pid');
      expect(_pidAlive(grandchildPid), isTrue,
          reason: 'grandchild sleep should be alive before stop()');

      await provider.stop('kill-tree');
      // Give the OS a moment to reap.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(_pidAlive(grandchildPid), isFalse,
          reason: 'stop() must SIGKILL the WHOLE group — grandchild dies too');

      await provider.dispose();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('(c)+(d real) a real stub streams output and death is observed',
        () async {
      final tmp = await Directory.systemTemp.createTemp('grid_runtime_out_');
      addTearDown(() => tmp.delete(recursive: true));
      final stub = File('${tmp.path}/stub.sh')
        ..writeAsStringSync('''
#!/bin/sh
echo "line-one"
echo "line-two"
exit 0
''');
      await Process.run('chmod', ['+x', stub.path]);

      final provider = SubprocessProvider(
        parentEnvironment: const {'PATH': '/usr/bin:/bin'},
        livenessPollPeriod: const Duration(milliseconds: 25),
      );

      final lines = <String>[];
      final events = <RuntimeEvent>[];
      final evSub = provider.events.listen(events.add);

      await provider.start(
        'streamer',
        RuntimeConfig(workDir: tmp.path, command: '/bin/sh', args: [stub.path]),
      );
      final outSub = provider.output('streamer').listen(lines.add);

      // Wait for death to be observed (detached path → Died, no readable code).
      for (var i = 0; i < 80; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (events.whereType<Died>().isNotEmpty ||
            events.whereType<Exited>().isNotEmpty) {
          break;
        }
      }

      expect(lines, containsAll(['line-one', 'line-two']));
      // Real detached process: death observed as Died (no readable exit code).
      expect(
        events.any((e) => e is Died || e is Exited),
        isTrue,
        reason: 'death of a real stub must surface as a RuntimeEvent',
      );

      await outSub.cancel();
      await evSub.cancel();
      await provider.dispose();
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}

/// True when [pid] still names a live process (SIGWINCH is a harmless probe).
bool _pidAlive(int pid) => Process.killPid(pid, ProcessSignal.sigwinch);
