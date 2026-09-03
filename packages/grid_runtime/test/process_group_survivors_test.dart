import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fake [SubprocessSpawner] (Fakes, not mocks): synthesizable stdio and NO
/// readable exit code — the real detached path, so supervision is driven only by
/// the group seam and the reaper's status file.
class _FakeSpawner implements SubprocessSpawner {
  final StreamController<List<int>> stdoutCtl =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> stderrCtl =
      StreamController<List<int>>.broadcast();
  Map<String, String>? lastEnv;
  int nextPid = 4242;

  @override
  Future<SpawnedProcess> spawn({
    required String executable,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    lastEnv = environment;
    return _FakeSpawned(
      pid: nextPid,
      stdout: stdoutCtl.stream,
      stderr: stderrCtl.stream,
    );
  }
}

class _FakeSpawned implements SpawnedProcess {
  _FakeSpawned({required this.pid, required this.stdout, required this.stderr});

  @override
  final int pid;
  @override
  final Stream<List<int>> stdout;
  @override
  final Stream<List<int>> stderr;
  @override
  Future<int>? get exitCode => null; // detached: no readable code
  @override
  Future<void> write(List<int> bytes) async {}
  @override
  Future<void> closeInput() async {}
}

/// A group seam whose LEADER and MEMBERS die independently — exactly what the
/// real seam sees when a harness backgrounds a descendant and exits.
class _SurvivorGroups implements ProcessGroupController {
  bool leaderAlive = true;
  List<int> members = <int>[];
  final List<(int, ProcessSignal)> signals = <(int, ProcessSignal)>[];

  @override
  Future<int?> resolvePgid(int pid) async => pid;

  @override
  bool processAlive(int pid) => leaderAlive;

  @override
  Future<List<int>> groupMembers(int pgid) async => members;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    members = <int>[]; // the group obeys the first signal
    return true;
  }

  @override
  int currentGroupId() => 99999;
}

Future<void> _pumpUntil(bool Function() done, {int ticks = 400}) async {
  for (var i = 0; i < ticks && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('a leader that leaves survivors behind', () {
    test(
      'is NOT terminal while the group is live; after the grace the OWNED pgid '
      'is signalled and the terminal says so',
      () async {
        final spawner = _FakeSpawner();
        final groups = _SurvivorGroups();
        final provider = SubprocessProvider(
          spawner: spawner,
          groupController: groups,
          livenessPollPeriod: const Duration(milliseconds: 5),
          orphanGrace: const Duration(milliseconds: 120),
          stopGrace: const Duration(milliseconds: 20),
          parentEnvironment: const <String, String>{},
          agentDeadline: null,
        );
        addTearDown(provider.dispose);
        final events = <RuntimeEvent>[];
        final sub = provider.events.listen(events.add);
        addTearDown(sub.cancel);

        await provider.start(
          'sess/agent',
          const RuntimeConfig(
            workDir: '/tmp',
            command: 'claude',
            lifecycle: Lifecycle.oneTurn,
          ),
        );

        // The leader finishes; a backgrounded descendant is still running.
        groups.members = <int>[9001];
        groups.leaderAlive = false;

        await _pumpUntil(() => events.whereType<SessionOrphaned>().isNotEmpty);
        final orphaned = events.whereType<SessionOrphaned>().toList();
        expect(orphaned, hasLength(1), reason: 'the orphan is reported ONCE');
        expect(orphaned.single.pgid, 4242);
        expect(orphaned.single.memberCount, 1);
        expect(
          events.whereType<Exited>(),
          isEmpty,
          reason: 'a live group can NEVER produce an inferred success',
        );
        expect(events.whereType<Died>(), isEmpty);

        await _pumpUntil(() => events.whereType<Died>().isNotEmpty);
        expect(
          groups.signals.map((s) => s.$1),
          contains(4242),
          reason: 'the grace elapsed — the OWNED pgid is signalled',
        );
        final died = events.whereType<Died>().single;
        expect(died.reason, contains('orphaned descendants killed'));
        expect(
          events.whereType<Exited>(),
          isEmpty,
          reason: 'a session we shot for its survivors is never a clean exit',
        );
        expect(provider.terminalOf('sess/agent'), isA<Died>());
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      'stop() signals the OWNED pgid when the leader is already gone',
      () async {
        final spawner = _FakeSpawner();
        final groups = _SurvivorGroups();
        final provider = SubprocessProvider(
          spawner: spawner,
          groupController: groups,
          livenessPollPeriod: const Duration(milliseconds: 5),
          orphanGrace: const Duration(seconds: 10), // only stop() may signal
          stopGrace: const Duration(milliseconds: 20),
          parentEnvironment: const <String, String>{},
          agentDeadline: null,
        );
        addTearDown(provider.dispose);

        await provider.start(
          'sess/agent',
          const RuntimeConfig(workDir: '/tmp', command: 'claude'),
        );
        groups.members = <int>[9001];
        groups.leaderAlive = false;

        await provider.stop('sess/agent');

        expect(
          groups.signals.map((s) => s.$1),
          contains(4242),
          reason: 'a dead leader must not make teardown refuse the group',
        );
      },
    );

    test(
      'the transcript stays attached after the leader exits and is cancelled '
      'at teardown',
      () async {
        final spawner = _FakeSpawner();
        final groups = _SurvivorGroups();
        final provider = SubprocessProvider(
          spawner: spawner,
          groupController: groups,
          livenessPollPeriod: const Duration(milliseconds: 5),
          orphanGrace: const Duration(seconds: 10),
          stopGrace: const Duration(milliseconds: 20),
          parentEnvironment: const <String, String>{},
          agentDeadline: null,
        );
        addTearDown(provider.dispose);
        final events = <RuntimeEvent>[];
        final evSub = provider.events.listen(events.add);
        addTearDown(evSub.cancel);

        await provider.start(
          'sess/agent',
          const RuntimeConfig(
            workDir: '/tmp',
            command: 'claude',
            lifecycle: Lifecycle.oneTurn,
          ),
        );
        final lines = <String>[];
        final outSub = provider.output('sess/agent').listen(lines.add);

        groups.members = <int>[9001];
        groups.leaderAlive = false;
        await _pumpUntil(() => events.whereType<SessionOrphaned>().isNotEmpty);

        expect(
          spawner.stdoutCtl.hasListener,
          isTrue,
          reason: 'the transcript follows the GROUP, not the leader',
        );
        spawner.stdoutCtl.add(utf8.encode('survivor-line\n'));
        await _pumpUntil(() => lines.contains('survivor-line'));
        expect(lines, contains('survivor-line'));

        await outSub.cancel();
        await provider.stop('sess/agent');
        await _pumpUntil(() => !spawner.stdoutCtl.hasListener);
        expect(
          spawner.stdoutCtl.hasListener,
          isFalse,
          reason: 'teardown cancels the transcript subscriptions',
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });

  group('the reaper parent preserves the real exit status', () {
    test('a status file of "3" is exited(3), NOT inferred', () async {
      final spawner = _FakeSpawner();
      final groups = _SurvivorGroups();
      final statusDir = await Directory.systemTemp.createTemp('grid_status_b_');
      addTearDown(() => statusDir.delete(recursive: true));
      final provider = SubprocessProvider(
        spawner: spawner,
        groupController: groups,
        livenessPollPeriod: const Duration(milliseconds: 5),
        exitStatusDirectory: statusDir,
        parentEnvironment: const <String, String>{},
        agentDeadline: null,
      );
      addTearDown(provider.dispose);
      final events = <RuntimeEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);

      await provider.start(
        'sess/agent',
        const RuntimeConfig(
          workDir: '/tmp',
          command: 'claude',
          lifecycle: Lifecycle.oneTurn,
        ),
      );

      // The provider hands the reaper its path; stand in for the wrapper.
      final statusPath = spawner.lastEnv![kExitStatusFileEnv]!;
      expect(p.isWithin(statusDir.path, statusPath), isTrue);
      File(statusPath).writeAsStringSync('3\n');
      groups.leaderAlive = false;

      await _pumpUntil(() => events.whereType<Exited>().isNotEmpty);
      final exited = events.whereType<Exited>().single;
      expect(exited.exitCode, 3);
      expect(exited.inferred, isFalse, reason: 'a code we READ is proof');
    });

    test('NO status file leaves the inferred oneTurn path untouched', () async {
      final spawner = _FakeSpawner();
      final groups = _SurvivorGroups();
      final statusDir = await Directory.systemTemp.createTemp('grid_status_c_');
      addTearDown(() => statusDir.delete(recursive: true));
      final provider = SubprocessProvider(
        spawner: spawner,
        groupController: groups,
        livenessPollPeriod: const Duration(milliseconds: 5),
        exitStatusDirectory: statusDir,
        parentEnvironment: const <String, String>{},
        agentDeadline: null,
      );
      addTearDown(provider.dispose);
      final events = <RuntimeEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);

      await provider.start(
        'sess/agent',
        const RuntimeConfig(
          workDir: '/tmp',
          command: 'claude',
          lifecycle: Lifecycle.oneTurn,
        ),
      );
      groups.leaderAlive = false; // vanish, nothing written

      await _pumpUntil(() => events.whereType<Exited>().isNotEmpty);
      final exited = events.whereType<Exited>().single;
      expect(exited.exitCode, 0);
      expect(exited.inferred, isTrue);
    });

    test(
      'REAL reaper: a stub that exits 7 surfaces exited(7), NOT inferred',
      () async {
        final tmp = await Directory.systemTemp.createTemp('grid_reaper_');
        addTearDown(() => tmp.delete(recursive: true));
        final stub = File(p.join(tmp.path, 'stub.sh'))
          ..writeAsStringSync('#!/bin/sh\necho "working"\nexit 7\n');
        await Process.run('chmod', <String>['+x', stub.path]);

        final provider = SubprocessProvider(
          parentEnvironment: const <String, String>{'PATH': '/usr/bin:/bin'},
          livenessPollPeriod: const Duration(milliseconds: 25),
          // Generous on purpose: if a transient `pgrep` read catches the group
          // mid-reap the session is reported ORPHANED, but the NEXT poll finds
          // the group empty and takes the ordinary terminal path — the grace
          // must never elapse first and convert that into an orphan kill.
          orphanGrace: const Duration(seconds: 30),
          agentDeadline: null,
        );
        addTearDown(provider.dispose);
        final events = <RuntimeEvent>[];
        final sub = provider.events.listen(events.add);
        addTearDown(sub.cancel);

        await provider.start(
          'reaped',
          RuntimeConfig(
            workDir: tmp.path,
            command: '/bin/sh',
            args: <String>[stub.path],
            lifecycle: Lifecycle.oneTurn,
          ),
        );

        await _pumpUntil(
          () =>
              events.whereType<Exited>().isNotEmpty ||
              events.whereType<Died>().isNotEmpty,
          ticks: 600,
        );

        final exited = events.whereType<Exited>().single;
        expect(
          exited.exitCode,
          7,
          reason: 'the reaper parent preserved the REAL leader exit status',
        );
        expect(exited.inferred, isFalse);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
