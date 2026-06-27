import 'git_runner.dart';

/// One git worktree entry, parsed from `git worktree list --porcelain`. Plain
/// value type (predictable-flutter). gc's `git.Worktree`
/// (`internal/git/git.go:13-18`).
class GitWorktree {
  const GitWorktree({required this.path, this.head = '', this.branch = ''});

  final String path;
  final String head;

  /// The branch name with `refs/heads/` stripped, or '' when detached.
  final String branch;
}

/// The outcome of one of the three pre-removal safety gates. Distinguishes a
/// clean "no" from a fail-closed "couldn't tell, assume unsafe" so callers (and
/// tests) can assert WHICH rung tripped and that a probe ERROR is treated as
/// unsafe — not silently as safe. gc collapses this into a `bool` that returns
/// `true` on probe error (`git.go:146-152,166-172`); we keep the distinction
/// explicit because fail-closed-on-probe-error is the load-bearing invariant.
enum GateOutcome {
  /// The condition is absent (clean): no uncommitted work / no unpushed commits
  /// / no stashes. Safe with respect to THIS gate.
  clear,

  /// The condition is present: there IS uncommitted work / unpushed commits /
  /// a stash. Removal must refuse.
  present,

  /// The probe itself failed (git error / non-launch). FAIL CLOSED — treated as
  /// unsafe exactly like [present]. gc's "assume dirty on error (safe default)".
  probeError,
}

/// Whether [GateOutcome] blocks removal — both [GateOutcome.present] and
/// [GateOutcome.probeError] block; only [GateOutcome.clear] permits.
bool gateBlocks(GateOutcome outcome) => outcome != GateOutcome.clear;

/// Low-level git operations scoped to a working directory — the Dart port of
/// gc's `Git` (`gascity/internal/git/git.go`), over the injectable [GitRunner]
/// seam. This is a stateless Service in predictable-flutter terms (owns one
/// source: the `git` binary); [StationGitService] composes it.
///
/// Every method runs `git` with the [gitEnvBlacklist] stripped (via the
/// runner) so a parent `GIT_DIR` from a melos/hook context can never redirect
/// the command — gc's clean-env build (`git.go:314-320`).
class GitOps {
  const GitOps(this._runner);

  final GitRunner _runner;

  Future<GitRunResult> _run(String workDir, List<String> args) =>
      _runner.run(workingDirectory: workDir, args: args);

  /// Whether [workDir] is inside a git repository. gc's `IsRepo`
  /// (`git.go:31-39`).
  Future<bool> isRepo(String workDir) async {
    final r = await _run(workDir, const <String>['rev-parse', '--git-dir']);
    return r.ok;
  }

  /// The current branch name, or 'HEAD' when detached. gc's `CurrentBranch`
  /// (`git.go:42-53`).
  Future<String?> currentBranch(String workDir) async {
    final r = await _run(
      workDir,
      const <String>['rev-parse', '--abbrev-ref', 'HEAD'],
    );
    if (!r.ok) return null;
    return r.output.trim();
  }

  /// Probes the repo's mainline branch at registration time — the VERBATIM
  /// port of gc's `ProbeDefaultBranch` (`git.go:92-106`):
  ///
  ///  1. `refs/remotes/origin/HEAD` symref (the configured default),
  ///  2. the currently checked-out branch (when origin/HEAD is unset),
  ///  3. '' (caller decides).
  ///
  /// Used at Layer-1 root-checkout registration to record the repo's actual
  /// mainline rather than a hardcoded `main` (ADR-0006 Decision 3).
  Future<String> probeDefaultBranch(String workDir) async {
    final symref = await _run(
      workDir,
      const <String>['symbolic-ref', 'refs/remotes/origin/HEAD'],
    );
    if (symref.ok) {
      final ref = symref.output.trim();
      const prefix = 'refs/remotes/origin/';
      if (ref.startsWith(prefix)) {
        final branch = ref.substring(prefix.length);
        if (branch.isNotEmpty) return branch;
      }
    }
    final branch = await currentBranch(workDir);
    if (branch != null) {
      final trimmed = branch.trim();
      if (trimmed.isNotEmpty && trimmed != 'HEAD') return trimmed;
    }
    return '';
  }

  /// **Gate 1.** Whether the working dir has uncommitted changes (staged,
  /// unstaged, or untracked). gc's `HasUncommittedWork` (`git.go:134-140`):
  /// fail-closed — a probe error is [GateOutcome.probeError] ("assume dirty").
  Future<GateOutcome> hasUncommittedWork(String workDir) async {
    final r = await _run(workDir, const <String>['status', '--porcelain']);
    if (!r.ok) return GateOutcome.probeError;
    return r.output.trim().isEmpty ? GateOutcome.clear : GateOutcome.present;
  }

  /// **Gate 2.** Whether HEAD has commits not reachable from any remote
  /// tracking branch — completed work that a removal would lose. gc's
  /// `HasUnpushedCommitsResult` (`git.go:156-162`): fail-closed on probe error.
  Future<GateOutcome> hasUnpushedCommits(String workDir) async {
    final r = await _run(
      workDir,
      const <String>['log', 'HEAD', '--oneline', '--not', '--remotes'],
    );
    if (!r.ok) return GateOutcome.probeError;
    return r.output.trim().isEmpty ? GateOutcome.clear : GateOutcome.present;
  }

  /// **Gate 3.** Whether the repository has stashed work. gc's
  /// `HasStashesResult` (`git.go:176-182`): fail-closed on probe error.
  Future<GateOutcome> hasStashes(String workDir) async {
    final r = await _run(workDir, const <String>['stash', 'list']);
    if (!r.ok) return GateOutcome.probeError;
    return r.output.trim().isEmpty ? GateOutcome.clear : GateOutcome.present;
  }

  /// Lists worktrees in porcelain format. gc's `WorktreeList`
  /// (`git.go:123-129`). Returns null on probe error (caller fails closed).
  Future<List<GitWorktree>?> worktreeList(String rootRepo) async {
    final r = await _run(
      rootRepo,
      const <String>['worktree', 'list', '--porcelain'],
    );
    if (!r.ok) return null;
    return parseWorktreeList(r.output);
  }

  /// Adds a worktree at [path] on a new branch [newBranch] off [baseBranch].
  /// Must be run from the [rootRepo]. Mirrors gc's worktree-add RPC param shape
  /// (cwd=rootRepo, newBranch, path, base). Returns the raw result so the
  /// caller can surface git's error text.
  Future<GitRunResult> worktreeAdd({
    required String rootRepo,
    required String path,
    required String newBranch,
    required String baseBranch,
  }) {
    return _run(rootRepo, <String>[
      'worktree',
      'add',
      '-b',
      newBranch,
      path,
      baseBranch,
    ]);
  }

  /// Removes a worktree. MUST be run from the [rootRepo], never from inside the
  /// worktree being removed (gc `cmd/gc/bead_worktree_reaper.go:128-130`). gc's
  /// `WorktreeRemove` (`git.go:110-120`). [force] removes even with
  /// uncommitted changes — the three-gate check is the caller's job, NOT a
  /// `force` here.
  Future<GitRunResult> worktreeRemove({
    required String rootRepo,
    required String path,
    bool force = false,
  }) {
    return _run(rootRepo, <String>[
      'worktree',
      'remove',
      path,
      if (force) '--force',
    ]);
  }

  /// Commits all changes in [workDir] with [message] (`git add -A` then
  /// `git commit`). Part of the land step (no gc prior art). Returns the
  /// commit result; an empty tree yields a non-ok result the caller inspects.
  Future<GitRunResult> commitAll({
    required String workDir,
    required String message,
  }) async {
    final add = await _run(workDir, const <String>['add', '-A']);
    if (!add.ok) return add;
    return _run(workDir, <String>['commit', '-m', message]);
  }

  /// Pushes [branch] to [remote] with `-u` (sets upstream so
  /// [hasUnpushedCommits] reads clear afterward). Part of the land step.
  Future<GitRunResult> pushSetUpstream({
    required String workDir,
    required String remote,
    required String branch,
  }) {
    return _run(workDir, <String>['push', '-u', remote, branch]);
  }
}

/// Parses `git worktree list --porcelain` output. Each block is separated by a
/// blank line: `worktree <path>`, `HEAD <sha>`, `branch refs/heads/<name>`. gc's
/// `parseWorktreeList` (`git.go:331-360`).
List<GitWorktree> parseWorktreeList(String output) {
  final worktrees = <GitWorktree>[];
  var path = '';
  var head = '';
  var branch = '';

  void flush() {
    if (path.isNotEmpty) {
      worktrees.add(GitWorktree(path: path, head: head, branch: branch));
    }
    path = '';
    head = '';
    branch = '';
  }

  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('worktree ')) {
      path = line.substring('worktree '.length);
    } else if (line.startsWith('HEAD ')) {
      head = line.substring('HEAD '.length);
    } else if (line.startsWith('branch ')) {
      final ref = line.substring('branch '.length);
      const prefix = 'refs/heads/';
      branch = ref.startsWith(prefix) ? ref.substring(prefix.length) : ref;
    }
  }
  flush();
  return worktrees;
}
