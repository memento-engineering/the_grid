@Tags(<String>['git'])
library;

import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Hermetic real-`git` tests for [StationGitService] (Track 3). They drive the
/// REAL `git` binary against TEMP repos only — `git init` a working repo + a
/// LOCAL bare `file://` origin, clone, worktree-add off the probed default,
/// push to the LOCAL bare origin, and open a PR through a FAKE [PrOpener]. They
/// NEVER touch real lenny / real GitHub / `lenny-tgdog`, never run `gh`, never
/// spawn `claude`.
///
/// The reaper-refusal proofs are the heart of the suite: a worktree with (a)
/// uncommitted work, (b) unpushed commits, (c) a stash is each provably NOT
/// removed (fail-closed), and a probe ERROR (a non-repo worktree dir) is ALSO
/// fail-closed.
void main() {
  late Directory tmp;
  // A pinned-clean git env: an isolated HOME + committer identity so the suite
  // does not read the developer's ~/.gitconfig and stays reproducible.
  late Map<String, String> gitEnv;
  late GitRunner runner;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grid_git_');
    final fakeHome = Directory(p.join(tmp.path, 'home'))..createSync();
    gitEnv = <String, String>{
      'PATH': Platform.environment['PATH'] ?? '',
      'HOME': fakeHome.path,
      'GIT_AUTHOR_NAME': 'grid-test',
      'GIT_AUTHOR_EMAIL': 'grid-test@example.com',
      'GIT_COMMITTER_NAME': 'grid-test',
      'GIT_COMMITTER_EMAIL': 'grid-test@example.com',
      // Deterministic default-branch name for `git init`.
      'GIT_CONFIG_GLOBAL': p.join(fakeHome.path, '.gitconfig'),
    };
    runner = SystemGitRunner(parentEnvironment: gitEnv);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs a raw git command in [dir] using the same clean env the service uses;
  /// throws on failure so test setup is loud.
  Future<void> git(String dir, List<String> args) async {
    final r = await runner.run(workingDirectory: dir, args: args);
    if (!r.ok) {
      throw StateError('git ${args.join(' ')} failed: ${r.output}');
    }
  }

  /// Builds a bare origin with a `main` mainline + an `origin/HEAD` symref, then
  /// clones it into a root checkout. Returns (barePath, rootPath).
  Future<({String bare, String root})> seedOriginAndClone() async {
    final bare = p.join(tmp.path, 'origin.git');
    await git(tmp.path, <String>['init', '--bare', '--initial-branch=main', bare]);

    // A seed working repo to push an initial commit + main into the bare origin.
    final seed = Directory(p.join(tmp.path, 'seed'))..createSync();
    await git(seed.path, <String>['init', '--initial-branch=main']);
    File(p.join(seed.path, 'README.md')).writeAsStringSync('seed\n');
    await git(seed.path, <String>['add', '-A']);
    await git(seed.path, <String>['commit', '-m', 'initial']);
    await git(seed.path, <String>['remote', 'add', 'origin', bare]);
    await git(seed.path, <String>['push', '-u', 'origin', 'main']);
    // Wire origin/HEAD on the bare repo so ProbeDefaultBranch reads the symref.
    await git(bare, <String>['symbolic-ref', 'HEAD', 'refs/heads/main']);

    // The root checkout: a real clone with origin set.
    final root = p.join(tmp.path, 'lenny-clone');
    await git(tmp.path, <String>['clone', bare, root]);
    return (bare: bare, root: root);
  }

  StationGitService serviceWith(PrOpener opener) =>
      StationGitService(runner: runner, prOpener: opener);

  test('Layer 1: register probes the default branch from origin/HEAD', () async {
    final seeded = await seedOriginAndClone();
    final svc = serviceWith(_FakePrOpener());

    final root = await svc.registerRootCheckout(
      path: seeded.root,
      substation: 'tgdog',
    );
    expect(root.defaultBranch, 'main');
    expect(root.substation, 'tgdog');
    expect(p.normalize(root.path), p.normalize(seeded.root));
  });

  test('an assigned head OVERRIDES the origin/HEAD probe; worktrees cut off the '
      'assigned branch, not main (the_grid-as-substation)', () async {
    final seeded = await seedOriginAndClone();
    // A feature branch carrying a commit `main` does NOT have.
    await git(seeded.root, <String>['checkout', '-b', 'feature']);
    File(p.join(seeded.root, 'feature.txt')).writeAsStringSync('on feature\n');
    await git(seeded.root, <String>['add', '-A']);
    await git(seeded.root, <String>['commit', '-m', 'feature-only change']);
    // Back to main so the clone's CURRENT branch is NOT the assigned head — this
    // proves the worktree base is the ASSIGNED branch, not whatever is checked out.
    await git(seeded.root, <String>['checkout', 'main']);

    final svc = serviceWith(_FakePrOpener());
    final root = await svc.registerRootCheckout(
      path: seeded.root,
      substation: 'tgdog',
      head: 'feature',
    );
    // The assigned head won — no origin/HEAD probe (which would yield `main`).
    expect(root.defaultBranch, 'feature');

    // The worktree is branched off the assigned head: it carries the
    // feature-only file (which `main` lacks).
    final wt = await svc.provisionWorktree(root: root, beadId: 'tg-1');
    expect(
      File(p.join(wt.path, 'feature.txt')).existsSync(),
      isTrue,
      reason: 'the worktree was branched off the ASSIGNED head (feature), not main',
    );
  });

  test('an empty/whitespace head falls back to the origin/HEAD probe', () async {
    final seeded = await seedOriginAndClone();
    final svc = serviceWith(_FakePrOpener());
    final root = await svc.registerRootCheckout(
      path: seeded.root,
      substation: 'tgdog',
      head: '   ',
    );
    expect(root.defaultBranch, 'main', reason: 'blank head → probe, not ""');
  });

  test('register refuses a non-repo path (fail closed)', () async {
    final notARepo = Directory(p.join(tmp.path, 'plain'))..createSync();
    final svc = serviceWith(_FakePrOpener());
    expect(
      () => svc.registerRootCheckout(path: notARepo.path, substation: 'tgdog'),
      throwsA(isA<StateError>()),
    );
  });

  test('Layer 2: provision adds a worktree on grid/<beadId> off the default',
      () async {
    final seeded = await seedOriginAndClone();
    final svc = serviceWith(_FakePrOpener());
    final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');

    final wt = await svc.provisionWorktree(root: root, beadId: 'lenny-1');
    expect(
      p.normalize(wt.path),
      p.normalize(WorktreeLayout.worktreePath(root.path, 'tgdog', 'lenny-1')),
    );
    expect(wt.branch, 'grid/lenny-1');
    expect(Directory(wt.path).existsSync(), isTrue);

    // The worktree is on the right branch off main.
    final branch = await runner.run(
      workingDirectory: wt.path,
      args: const <String>['rev-parse', '--abbrev-ref', 'HEAD'],
    );
    expect(branch.output.trim(), 'grid/lenny-1');

    // listBeadWorktrees re-binds the dir name → bead id (restart reconcile).
    final list = await svc.listBeadWorktrees(root);
    expect(list, isNotNull);
    expect(
      list!.map((w) => w.beadId),
      contains('lenny-1'),
    );
  });

  test('land: commit -> push -> open PR via the fake opener, then reap is clean',
      () async {
    final seeded = await seedOriginAndClone();
    final fakePr = _FakePrOpener();
    final svc = serviceWith(fakePr);
    final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');
    final wt = await svc.provisionWorktree(root: root, beadId: 'lenny-2');

    // The agent "did work".
    File(p.join(wt.path, 'agent_output.txt')).writeAsStringSync('done\n');

    final landed = await svc.land(
      root: root,
      worktree: wt,
      commitMessage: 'grid: lenny-2 work',
      prTitle: 'grid/lenny-2',
      prBody: 'body',
    );
    expect(landed.isLanded, isTrue, reason: landed.failureReason ?? '');
    expect(landed.pr!.url, contains('lenny-2'));

    // The FAKE PR-opener was called with the right branch + base.
    expect(fakePr.lastBranch, 'grid/lenny-2');
    expect(fakePr.lastBaseBranch, 'main');
    expect(fakePr.calls, 1);

    // After push, the branch really exists on the bare origin.
    final lsRemote = await runner.run(
      workingDirectory: wt.path,
      args: const <String>['ls-remote', '--heads', 'origin', 'grid/lenny-2'],
    );
    expect(lsRemote.output.trim(), isNotEmpty);

    // And now the three-gate reaper finds it clean → removes it.
    final reap = await svc.reap(root: root, worktree: wt);
    expect(reap.removed, isTrue, reason: reap.refusedReason ?? '');
    expect(Directory(wt.path).existsSync(), isFalse);
  });

  group('the three-gate reaper REFUSES unsafe worktrees (fail closed)', () {
    test('(a) uncommitted work blocks removal', () async {
      final seeded = await seedOriginAndClone();
      final svc = serviceWith(_FakePrOpener());
      final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');
      final wt = await svc.provisionWorktree(root: root, beadId: 'lenny-u');

      // Uncommitted (untracked) work present.
      File(p.join(wt.path, 'dirty.txt')).writeAsStringSync('wip\n');

      final reap = await svc.reap(root: root, worktree: wt);
      expect(reap.refused, isTrue);
      expect(reap.uncommitted, GateOutcome.present);
      expect(reap.refusedReason, contains('uncommitted=present'));
      // The worktree is STILL on disk — no data loss.
      expect(Directory(wt.path).existsSync(), isTrue);
    });

    test('(b) unpushed commits block removal', () async {
      final seeded = await seedOriginAndClone();
      final svc = serviceWith(_FakePrOpener());
      final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');
      final wt = await svc.provisionWorktree(root: root, beadId: 'lenny-p');

      // A committed-but-unpushed change (clean tree, but commits not on remote).
      File(p.join(wt.path, 'work.txt')).writeAsStringSync('committed\n');
      await git(wt.path, const <String>['add', '-A']);
      await git(wt.path, const <String>['commit', '-m', 'local only']);

      final reap = await svc.reap(root: root, worktree: wt);
      expect(reap.refused, isTrue);
      expect(reap.uncommitted, GateOutcome.clear);
      expect(reap.unpushed, GateOutcome.present);
      expect(reap.refusedReason, contains('unpushed=present'));
      expect(Directory(wt.path).existsSync(), isTrue);
    });

    test('(c) a stash blocks removal', () async {
      final seeded = await seedOriginAndClone();
      final svc = serviceWith(_FakePrOpener());
      final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');
      final wt = await svc.provisionWorktree(root: root, beadId: 'lenny-s');

      // Create a tracked file, commit, then stash a modification so the tree is
      // clean but a stash exists. Stashes are repo-wide; the worktree shares the
      // common stash store with the root, so isolate via a fresh modification.
      File(p.join(wt.path, 'tracked.txt')).writeAsStringSync('v1\n');
      await git(wt.path, const <String>['add', '-A']);
      await git(wt.path, const <String>['commit', '-m', 'add tracked']);
      // Push so the unpushed gate is CLEAR — isolating the stash gate.
      await git(wt.path, <String>['push', '-u', 'origin', wt.branch]);
      File(p.join(wt.path, 'tracked.txt')).writeAsStringSync('v2 wip\n');
      await git(wt.path, const <String>['stash', 'push', '-u', '-m', 'wip']);

      final reap = await svc.reap(root: root, worktree: wt);
      expect(reap.refused, isTrue);
      expect(reap.uncommitted, GateOutcome.clear);
      expect(reap.unpushed, GateOutcome.clear);
      expect(reap.stashed, GateOutcome.present);
      expect(reap.refusedReason, contains('stashes=present'));
      expect(Directory(wt.path).existsSync(), isTrue);
    });

    test('scope gate: a path outside the worktrees root is refused', () async {
      final seeded = await seedOriginAndClone();
      final svc = serviceWith(_FakePrOpener());
      final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');

      final outside = BeadWorktree(
        beadId: 'evil',
        path: p.join(tmp.path, 'totally-elsewhere'),
        branch: 'grid/evil',
      );
      final reap = await svc.reap(root: root, worktree: outside);
      expect(reap.refused, isTrue);
      expect(reap.refusedReason, contains('not strictly under'));
    });
  });

  test(
    'reap deletes the branch too (tg-e0p): symmetric cleanup so a done bead '
    'never wedges a future re-mint',
    () async {
      final seeded = await seedOriginAndClone();
      final svc = serviceWith(_FakePrOpener());
      final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');
      final wt = await svc.provisionWorktree(root: root, beadId: 'lenny-sym');

      // Push so the unpushed gate is clear, then reap.
      await git(wt.path, const <String>['push', '-u', 'origin', 'grid/lenny-sym']);
      final reap = await svc.reap(root: root, worktree: wt);
      expect(reap.removed, isTrue, reason: reap.refusedReason ?? '');

      final branchGone = await runner.run(
        workingDirectory: seeded.root,
        args: <String>['show-ref', '--verify', '--quiet', 'refs/heads/${wt.branch}'],
      );
      expect(
        branchGone.ok,
        isFalse,
        reason: 'the local branch must be deleted alongside the worktree',
      );
    },
  );

  test(
    'provisionWorktree ADOPTS a branch that outlived its worktree — '
    'self-heals the wedge (tg-e0p, tg-rm5/tg-457)',
    () async {
      final seeded = await seedOriginAndClone();
      final svc = serviceWith(_FakePrOpener());
      final root = await svc.registerRootCheckout(path: seeded.root, substation: 'tgdog');

      // First mint: succeeds, creates the branch + worktree.
      final wt = await svc.provisionWorktree(root: root, beadId: 'tg-wedge');
      expect(Directory(wt.path).existsSync(), isTrue);

      // Simulate the wedge exactly as observed: the worktree vanishes WITHOUT
      // the branch being deleted (an out-of-band removal, or any cleanup path
      // that predates the symmetric reap fix above) — the branch survives
      // with no worktree checked out against it.
      await git(seeded.root, <String>['worktree', 'remove', wt.path]);
      final stillThere = await runner.run(
        workingDirectory: seeded.root,
        args: <String>['show-ref', '--verify', '--quiet', 'refs/heads/${wt.branch}'],
      );
      expect(
        stillThere.ok,
        isTrue,
        reason: 'the branch must survive the raw removal (the wedge setup)',
      );

      // Re-provisioning the SAME bead must ADOPT the surviving branch rather
      // than fail forever on "already exists" — the exact operator-observed
      // failure: every re-mint hit branch-exists with no self-healing path,
      // costing 3 re-keys + 2 manual git bridges on one bead.
      final wt2 = await svc.provisionWorktree(root: root, beadId: 'tg-wedge');
      expect(wt2.branch, wt.branch);
      expect(Directory(wt2.path).existsSync(), isTrue);
      final onBranch = await runner.run(
        workingDirectory: wt2.path,
        args: const <String>['rev-parse', '--abbrev-ref', 'HEAD'],
      );
      expect(onBranch.output.trim(), wt.branch);
    },
  );

  test('land records a failure (does not throw) when push has no remote',
      () async {
    // A standalone repo with NO origin — push fails; land returns a recorded
    // failure rather than throwing, and the worktree is left for retry.
    final standalone = Directory(p.join(tmp.path, 'noremote'))..createSync();
    await git(standalone.path, const <String>['init', '--initial-branch=main']);
    File(p.join(standalone.path, 'f')).writeAsStringSync('x');
    await git(standalone.path, const <String>['add', '-A']);
    await git(standalone.path, const <String>['commit', '-m', 'c']);

    final svc = serviceWith(_FakePrOpener());
    final wt = BeadWorktree(
      beadId: 'lenny-nr',
      path: standalone.path,
      branch: 'main',
    );
    final root = RootCheckout(
      path: standalone.path,
      defaultBranch: 'main',
      substation: 'tgdog',
    );
    File(p.join(standalone.path, 'more')).writeAsStringSync('y');

    final res = await svc.land(
      root: root,
      worktree: wt,
      commitMessage: 'm',
      prTitle: 't',
    );
    expect(res.isLanded, isFalse);
    expect(res.committed, isTrue);
    expect(res.pushed, isFalse);
    expect(res.failureReason, contains('push failed'));
  });
}

/// A FAKE [PrOpener] (Fakes, not mocks): records the branch/base it was asked to
/// open and returns a synthetic [PullRequestRef]. NEVER touches GitHub or `gh`.
class _FakePrOpener implements PrOpener {
  int calls = 0;
  String? lastBranch;
  String? lastBaseBranch;
  String? lastTitle;

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    calls++;
    lastBranch = branch;
    lastBaseBranch = baseBranch;
    lastTitle = title;
    return PullRequestResult.opened(
      PullRequestRef(
        url: 'https://example.test/org/lenny/pull/1?b=$branch',
        number: 1,
      ),
    );
  }
}
