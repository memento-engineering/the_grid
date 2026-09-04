@Tags(<String>['git'])
library;

import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The GitOps WORK-TREE ROOT GUARD (tg-amwa). A `git` command run from a
/// directory that is not a checkout does not fail — git walks UP and acts on the
/// enclosing repository, which is how a delivery step committed to a
/// substation's primary `main` and pushed branches from it. These tests pin that
/// every mutating op and every reap gate refuses instead, that a real root
/// (including a linked worktree root) still passes, and that a missing workDir
/// refuses rather than throwing.
void main() {
  late Directory tmp;
  late GitRunner runner;
  late GitOps ops;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grid_root_guard_');
    final fakeHome = Directory(p.join(tmp.path, 'home'))..createSync();
    runner = SystemGitRunner(
      parentEnvironment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': fakeHome.path,
        'GIT_AUTHOR_NAME': 'grid-test',
        'GIT_AUTHOR_EMAIL': 'grid-test@example.com',
        'GIT_COMMITTER_NAME': 'grid-test',
        'GIT_COMMITTER_EMAIL': 'grid-test@example.com',
        'GIT_CONFIG_GLOBAL': p.join(fakeHome.path, '.gitconfig'),
      },
    );
    ops = GitOps(runner);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> git(String dir, List<String> args) async {
    final r = await runner.run(workingDirectory: dir, args: args);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.output}');
  }

  /// A bare origin plus a clone holding one commit on `main` — the stand-in for
  /// a substation's PRIMARY checkout.
  Future<({String bare, String root})> seedPrimary() async {
    final bare = p.join(tmp.path, 'origin.git');
    await git(tmp.path, <String>[
      'init',
      '--bare',
      '--initial-branch=main',
      bare,
    ]);
    final seed = Directory(p.join(tmp.path, 'seed'))..createSync();
    await git(seed.path, <String>['init', '--initial-branch=main']);
    File(p.join(seed.path, 'README.md')).writeAsStringSync('seed\n');
    await git(seed.path, <String>['add', '-A']);
    await git(seed.path, <String>['commit', '-m', 'initial']);
    await git(seed.path, <String>['remote', 'add', 'origin', bare]);
    await git(seed.path, <String>['push', '-u', 'origin', 'main']);
    final root = p.join(tmp.path, 'primary');
    await git(tmp.path, <String>['clone', bare, root]);
    return (bare: bare, root: root);
  }

  /// The incident's shape: the engine's `.grid` scaffold and nothing else — a
  /// workspace dir INSIDE the primary checkout with no `.git` entry of its own.
  String sourcelessWorkspaceIn(String root) {
    final dir = p.join(root, '.grid', 'worktrees', 'the_grid', 'tg-83k1');
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, 'residue.txt')).writeAsStringSync('residue\n');
    return dir;
  }

  /// git reports the PHYSICAL path (`/private/var/...` on macOS), so a refusal
  /// names the resolved toplevel, not the `/var/...` alias the test holds.
  String resolved(String path) => Directory(path).resolveSymbolicLinksSync();

  group('a workspace dir that is NOT a checkout is refused', () {
    test(
      'commitAll refuses naming both paths; HEAD and the index survive',
      () async {
        final seeded = await seedPrimary();
        final workspace = sourcelessWorkspaceIn(seeded.root);
        final headBefore = await ops.headSha(seeded.root);
        expect(headBefore, isNotNull);

        final result = await ops.commitAll(
          workDir: workspace,
          message: 'chore: commit residual review changes',
        );

        expect(result.ok, isFalse);
        expect(result.exitCode, kGitRootGuardExitCode);
        expect(result.output, contains(workspace));
        expect(result.output, contains(resolved(seeded.root)));
        expect(await ops.headSha(seeded.root), headBefore);
        final staged = await runner.run(
          workingDirectory: seeded.root,
          args: const <String>['diff', '--cached', '--name-only'],
        );
        expect(staged.output.trim(), isEmpty);
        final status = await runner.run(
          workingDirectory: seeded.root,
          args: const <String>['status', '--porcelain'],
        );
        expect(status.output, contains('.grid/'));
      },
    );

    test('pushSetUpstream refuses and the origin gains no ref', () async {
      final seeded = await seedPrimary();
      final workspace = sourcelessWorkspaceIn(seeded.root);
      // A local branch the origin does NOT have: without the guard, pushing it
      // from the workspace dir would create it on the origin from the PRIMARY.
      await git(seeded.root, <String>['branch', 'grid/tg-83k1', 'main']);

      final result = await ops.pushSetUpstream(
        workDir: workspace,
        remote: 'origin',
        branch: 'grid/tg-83k1',
      );

      expect(result.ok, isFalse);
      expect(result.exitCode, kGitRootGuardExitCode);
      expect(result.output, contains(workspace));
      final refs = await runner.run(
        workingDirectory: seeded.bare,
        args: const <String>[
          'for-each-ref',
          '--format=%(refname)',
          'refs/heads',
        ],
      );
      expect(refs.output.trim(), 'refs/heads/main');
    });

    test('the worktree and branch ops refuse; the branch survives', () async {
      final seeded = await seedPrimary();
      final workspace = sourcelessWorkspaceIn(seeded.root);
      await git(seeded.root, <String>['branch', 'grid/tg-83k1', 'main']);
      final target = p.join(tmp.path, 'wt-never');

      final added = await ops.worktreeAdd(
        rootRepo: workspace,
        path: target,
        newBranch: 'grid/tg-u5xt',
        baseBranch: 'main',
      );
      final adopted = await ops.worktreeAddExisting(
        rootRepo: workspace,
        path: target,
        branch: 'grid/tg-83k1',
      );
      final removed = await ops.worktreeRemove(
        rootRepo: workspace,
        path: target,
      );
      final deleted = await ops.branchDelete(
        rootRepo: workspace,
        branch: 'grid/tg-83k1',
      );

      for (final result in <GitRunResult>[added, adopted, removed, deleted]) {
        expect(result.ok, isFalse);
        expect(result.exitCode, kGitRootGuardExitCode);
        expect(result.output, contains(workspace));
      }
      expect(Directory(target).existsSync(), isFalse);
      expect(await ops.branchExists(seeded.root, 'grid/tg-83k1'), isTrue);
    });

    test('the reap gates and headSha fail CLOSED', () async {
      final seeded = await seedPrimary();
      final workspace = sourcelessWorkspaceIn(seeded.root);

      expect(await ops.hasUncommittedWork(workspace), GateOutcome.probeError);
      expect(await ops.hasUnpushedCommits(workspace), GateOutcome.probeError);
      expect(await ops.hasStashes(workspace), GateOutcome.probeError);
      expect(await ops.headSha(workspace), isNull);
    });
  });

  group('a real work-tree root PASSES the guard', () {
    test('the primary checkout commits, pushes, and reads clear', () async {
      final seeded = await seedPrimary();
      File(p.join(seeded.root, 'work.txt')).writeAsStringSync('real work\n');

      final commit = await ops.commitAll(
        workDir: seeded.root,
        message: 'feat: real work',
      );
      final push = await ops.pushSetUpstream(
        workDir: seeded.root,
        remote: 'origin',
        branch: 'main',
      );

      expect(commit.ok, isTrue, reason: commit.output);
      expect(push.ok, isTrue, reason: push.output);
      expect(await ops.hasUncommittedWork(seeded.root), GateOutcome.clear);
    });

    test('a linked worktree root passes; a subdir of it does not', () async {
      final seeded = await seedPrimary();
      final wt = p.join(tmp.path, 'wt-tg-1');
      await git(seeded.root, <String>[
        'worktree',
        'add',
        '-b',
        'grid/tg-1',
        wt,
        'main',
      ]);
      File(p.join(wt, 'agent.txt')).writeAsStringSync('agent output\n');

      final commit = await ops.commitAll(
        workDir: wt,
        message: 'feat: agent output',
      );

      expect(commit.ok, isTrue, reason: commit.output);
      expect(await ops.headSha(wt), isNotNull);
      expect(await ops.hasUncommittedWork(wt), GateOutcome.clear);

      // The discriminating control: one level down is NOT a root.
      final sub = Directory(p.join(wt, 'sub'))..createSync();
      final refused = await ops.commitAll(
        workDir: sub.path,
        message: 'chore: from a subdir',
      );
      expect(refused.ok, isFalse);
      expect(refused.exitCode, kGitRootGuardExitCode);
      expect(refused.output, contains(resolved(wt)));
    });
  });

  group('a workDir that does not exist', () {
    test(
      'refuses with the guard shape instead of throwing from the spawn',
      () async {
        final missing = p.join(tmp.path, 'gone');

        final commit = await ops.commitAll(workDir: missing, message: 'x');
        final push = await ops.pushSetUpstream(
          workDir: missing,
          remote: 'origin',
          branch: 'main',
        );

        for (final result in <GitRunResult>[commit, push]) {
          expect(result.ok, isFalse);
          expect(result.launched, isFalse);
          expect(result.exitCode, kGitRootGuardExitCode);
          expect(result.output, contains(missing));
          expect(result.output, startsWith('git-root-guard:'));
        }
        expect(await ops.hasUncommittedWork(missing), GateOutcome.probeError);
      },
    );
  });
}
