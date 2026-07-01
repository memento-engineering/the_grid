// Git-over-LAN code/asset SYNC (ADR-0011 D7, M6 Track E) — the federation-native
// distribution channel, DISTINCT from the lease bus.
//
// Pure-logic tests first (a FAKE GitCommandRunner records the argv + drives
// canned results, so the add-vs-set-url decision, the argv shape, the throw-on-
// failure, and the compose order run with zero IO). Then OFFLINE integration:
// real `git` against temp repos — a working repo pushes a branch to a LOCAL bare
// repo over a file-path remote (the offline stand-in for a peer's bare repo over
// SSH) and the ref is asserted to have landed. Fully offline; no network beyond
// none; temp dirs cleaned up.
import 'dart:io';

import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

/// A controllable, IO-free [GitCommandRunner]: records every argv + cwd and
/// returns whatever [responder] decides (Fakes, not mocks).
class _RecordingRunner {
  _RecordingRunner(this.responder);

  /// Maps an argv to its canned result.
  final GitCommandResult Function(List<String> args) responder;

  /// The argv of every call, in order.
  final List<List<String>> calls = [];

  /// The cwd of every call, in order.
  final List<String> dirs = [];

  Future<GitCommandResult> call(
    List<String> args, {
    required String workingDirectory,
  }) async {
    calls.add(args);
    dirs.add(workingDirectory);
    return responder(args);
  }
}

GitCommandResult _ok([String stdout = '']) =>
    GitCommandResult(exitCode: 0, stdout: stdout, stderr: '');

GitCommandResult _fail([String stderr = 'boom']) =>
    GitCommandResult(exitCode: 1, stdout: '', stderr: stderr);

/// Runs real `git` in [cwd] (offline — local repos only).
Future<ProcessResult> _git(List<String> args, String cwd) => Process.run(
  'git',
  args,
  workingDirectory: cwd,
  stdoutEncoding: const SystemEncoding(),
  stderrEncoding: const SystemEncoding(),
);

Future<String> _gitOut(List<String> args, String cwd) async =>
    ((await _git(args, cwd)).stdout as String).trim();

void main() {
  group('GitSyncService — pure logic (fake runner, no IO)', () {
    test('push builds `git push <remote> <refspec>`', () async {
      final runner = _RecordingRunner((_) => _ok());
      final svc = GitSyncService(runner: runner.call);

      final res = await svc.push(
        workingDirectory: '/work',
        remote: 'peer',
        refspec: 'main',
      );

      expect(res.ok, isTrue);
      expect(runner.calls.single, ['push', 'peer', 'main']);
      expect(runner.dirs.single, '/work');
    });

    test('push --force inserts the flag before the remote', () async {
      final runner = _RecordingRunner((_) => _ok());
      final svc = GitSyncService(runner: runner.call);

      await svc.push(
        workingDirectory: '/work',
        remote: 'peer',
        refspec: 'main',
        force: true,
      );

      expect(runner.calls.single, ['push', '--force', 'peer', 'main']);
    });

    test('push throws GitSyncException on a git failure', () async {
      final runner = _RecordingRunner((_) => _fail('rejected'));
      final svc = GitSyncService(runner: runner.call);

      await expectLater(
        svc.push(workingDirectory: '/work', remote: 'peer', refspec: 'main'),
        throwsA(
          isA<GitSyncException>()
              .having((e) => e.exitCode, 'exitCode', 1)
              .having((e) => e.output, 'output', contains('rejected'))
              .having((e) => e.command, 'command', ['push', 'peer', 'main']),
        ),
      );
    });

    test('ensureRemote ADDS the remote when it is absent', () async {
      // `git remote get-url` fails for an unknown remote → add.
      final runner = _RecordingRunner(
        (args) => args[1] == 'get-url' ? _fail('No such remote') : _ok(),
      );
      final svc = GitSyncService(runner: runner.call);

      await svc.ensureRemote(
        workingDirectory: '/work',
        name: 'peer',
        url: 'ssh://host/repo.git',
      );

      expect(runner.calls[0], ['remote', 'get-url', 'peer']);
      expect(runner.calls[1], [
        'remote',
        'add',
        'peer',
        'ssh://host/repo.git',
      ]);
    });

    test('ensureRemote UPDATES the url when the remote exists but differs',
        () async {
      final runner = _RecordingRunner(
        (args) =>
            args[1] == 'get-url' ? _ok('ssh://host/old.git') : _ok(),
      );
      final svc = GitSyncService(runner: runner.call);

      await svc.ensureRemote(
        workingDirectory: '/work',
        name: 'peer',
        url: 'ssh://host/new.git',
      );

      expect(runner.calls[1], [
        'remote',
        'set-url',
        'peer',
        'ssh://host/new.git',
      ]);
    });

    test('ensureRemote is a NO-OP when the url already matches', () async {
      final runner = _RecordingRunner((_) => _ok('ssh://host/repo.git'));
      final svc = GitSyncService(runner: runner.call);

      await svc.ensureRemote(
        workingDirectory: '/work',
        name: 'peer',
        url: 'ssh://host/repo.git',
      );

      // Only the get-url probe ran — no add/set-url mutation.
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single, ['remote', 'get-url', 'peer']);
    });

    test('distribute composes ensureRemote → push in order', () async {
      final runner = _RecordingRunner(
        (args) => args[1] == 'get-url' ? _fail() : _ok(),
      );
      final svc = GitSyncService(runner: runner.call);

      await svc.distribute(
        workingDirectory: '/work',
        remoteName: 'peer',
        remoteUrl: 'ssh://host/repo.git',
        refspec: 'main',
      );

      expect(runner.calls, [
        ['remote', 'get-url', 'peer'],
        ['remote', 'add', 'peer', 'ssh://host/repo.git'],
        ['push', 'peer', 'main'],
      ]);
    });

    test('onLog observes push + remote events (lib is print-free)', () async {
      final logs = <String>[];
      final runner = _RecordingRunner(
        (args) => args[1] == 'get-url' ? _fail() : _ok(),
      );
      final svc = GitSyncService(runner: runner.call, onLog: logs.add);

      await svc.distribute(
        workingDirectory: '/work',
        remoteName: 'peer',
        remoteUrl: 'ssh://host/repo.git',
        refspec: 'main',
      );

      expect(logs, contains(contains('added')));
      expect(logs, contains(contains('pushing main → peer')));
    });
  });

  group('GitSyncService — offline integration (real git, temp repos)', () {
    late Directory tmp;
    late String work;
    late String bare;
    late String branch;
    late String head;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('grid_sync_test_');
      work = '${tmp.path}/work';
      bare = '${tmp.path}/peer.git';
      Directory(work).createSync();
      Directory(bare).createSync();
      await _git(['init', '-q'], work);
      await _git(['init', '--bare', '-q'], bare);
      await _git(['config', 'user.email', 'grid@test.local'], work);
      await _git(['config', 'user.name', 'grid'], work);
      await _git(['config', 'commit.gpgsign', 'false'], work);
      File('$work/README.md').writeAsStringSync('hello federation\n');
      await _git(['add', '.'], work);
      await _git(['commit', '-q', '-m', 'init'], work);
      branch = await _gitOut(['branch', '--show-current'], work);
      head = await _gitOut(['rev-parse', 'HEAD'], work);
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('push lands the ref in the peer bare repo', () async {
      final svc = GitSyncService();

      final res = await svc.push(
        workingDirectory: work,
        remote: bare, // a file-path remote — the offline stand-in for SSH
        refspec: branch,
      );

      expect(res.ok, isTrue);
      // The branch now resolves in the bare repo to the same commit.
      expect(await _gitOut(['rev-parse', branch], bare), head);
    });

    test('distribute (ensureRemote + push) lands the ref via a named remote',
        () async {
      final logs = <String>[];
      final svc = GitSyncService(onLog: logs.add);

      await svc.distribute(
        workingDirectory: work,
        remoteName: 'dashboard',
        remoteUrl: bare,
        refspec: branch,
      );

      // The remote was created in the source repo...
      expect(await _gitOut(['remote', 'get-url', 'dashboard'], work), bare);
      // ...and the ref landed in the peer.
      expect(await _gitOut(['rev-parse', branch], bare), head);
    });

    test('ensureRemote add → set-url is idempotent and updates the url',
        () async {
      final other = '${tmp.path}/other.git';
      Directory(other).createSync();
      await _git(['init', '--bare', '-q'], other);
      final svc = GitSyncService();

      await svc.ensureRemote(workingDirectory: work, name: 'peer', url: bare);
      expect(await _gitOut(['remote', 'get-url', 'peer'], work), bare);

      // Re-running with a new url updates it (set-url path).
      await svc.ensureRemote(workingDirectory: work, name: 'peer', url: other);
      expect(await _gitOut(['remote', 'get-url', 'peer'], work), other);

      // Re-running with the same url is a no-op and leaves it stable.
      await svc.ensureRemote(workingDirectory: work, name: 'peer', url: other);
      expect(await _gitOut(['remote', 'get-url', 'peer'], work), other);
    });

    test('push to a non-existent remote throws GitSyncException', () async {
      final svc = GitSyncService();

      await expectLater(
        svc.push(
          workingDirectory: work,
          remote: '${tmp.path}/nope.git', // not a repo
          refspec: branch,
        ),
        throwsA(isA<GitSyncException>()),
      );
    });
  });
}
