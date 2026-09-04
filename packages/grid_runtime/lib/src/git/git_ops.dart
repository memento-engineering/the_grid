import 'git_runner.dart';

/// Classified state of one Layer-1 primary checkout.
enum PrimaryCheckoutState {
  fresh,
  unreadable,
  detached,
  remoteUnreadable,
  offDefaultBranch,
  behind,
}

/// Immutable result of inspecting one Layer-1 primary checkout.
class PrimaryCheckoutFreshness {
  /// Creates a checkout freshness result.
  const PrimaryCheckoutFreshness({
    required this.state,
    this.branch,
    this.defaultBranch,
    this.behindBy = 0,
  });

  final PrimaryCheckoutState state;
  final String? branch;
  final String? defaultBranch;
  final int behindBy;

  /// Whether every freshness probe succeeded and the checkout is current.
  bool get isFresh => state == PrimaryCheckoutState.fresh;

  /// Atomic operator-facing verdict for this checkout.
  String get verdict => switch (state) {
    PrimaryCheckoutState.fresh => 'fresh',
    PrimaryCheckoutState.unreadable => 'unreadable: not a git repository',
    PrimaryCheckoutState.detached => 'stale: detached HEAD',
    PrimaryCheckoutState.remoteUnreadable =>
      'unreadable: origin/HEAD or remote default history',
    PrimaryCheckoutState.offDefaultBranch =>
      'stale: branch $branch != $defaultBranch',
    PrimaryCheckoutState.behind =>
      'stale: $behindBy commit${behindBy == 1 ? '' : 's'} behind '
          'origin/$defaultBranch',
  };
}

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

/// The exit code a [GitOps] work-tree-root refusal carries. Negative, so it can
/// never collide with a real `git` status, and distinct from the runner's
/// non-launch sentinel (`-1`) so a refusal is legible as such in a log.
const int kGitRootGuardExitCode = -2;

/// The root probe's argv. `--show-prefix` is EMPTY exactly when the cwd IS the
/// work-tree root (a linked worktree root included); `--show-toplevel` names the
/// repository git resolved, so a refusal can report it. One `git` call answers
/// both.
const List<String> _rootProbeArgs = <String>[
  'rev-parse',
  '--show-toplevel',
  '--show-prefix',
];

/// Collapses [text] to one trimmed line so a refusal stays greppable.
String _oneLine(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Whether EVERY path a `git status --porcelain` [line] names lies under one of
/// the [excluded] directory prefixes — the completion fence's residue filter. A
/// line whose paths cannot be parsed is NEVER excluded (fail closed: unreadable
/// ⇒ it counts as work). A rename that moves a file OUT of an excluded dir
/// counts (only one of its two paths is excluded).
bool _fullyExcluded(String line, Set<String> excluded) {
  if (excluded.isEmpty) return false;
  final paths = _porcelainPaths(line);
  if (paths.isEmpty) return false;
  return paths.every(
    (path) => excluded.any((dir) => path == dir || path.startsWith('$dir/')),
  );
}

/// The paths a `git status --porcelain` [line] names: one, or TWO for a
/// rename/copy (`R  old -> new`). The format is `XY<space><path>`, so the path
/// starts at index 3. Unquotes git's C-style quoting (a path with
/// spaces/specials comes back `"quoted"`). Returns empty when the line is too
/// short to carry a path — the caller fails closed on that. Git COLLAPSES an
/// untracked directory to a single trailing-slash entry (`?? .grid/`), which the
/// `startsWith('$dir/')` test in [_fullyExcluded] matches.
List<String> _porcelainPaths(String line) {
  if (line.length < 4) return const <String>[];
  final rest = line.substring(3);
  // Only a rename/copy status carries the ` -> ` pair, so a literal ' -> ' inside
  // a plain path is never mis-split.
  final renamed = line[0] == 'R' || line[0] == 'C';
  final arrow = renamed ? rest.indexOf(' -> ') : -1;
  final parts = arrow < 0
      ? <String>[rest]
      : <String>[rest.substring(0, arrow), rest.substring(arrow + 4)];
  return parts
      .map(_unquotePath)
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
}

/// Strips git's C-style quoting from a porcelain [path] (`"a b.json"` →
/// `a b.json`).
String _unquotePath(String path) {
  final trimmed = path.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

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

  /// Refuses [args] unless [workDir] is ITSELF a git work-tree root — null when
  /// the run may proceed, or a failed [GitRunResult] naming both [workDir] and
  /// the repository git resolved.
  ///
  /// A `git` command run from a directory that is not a checkout does NOT fail:
  /// git walks UP and operates on the enclosing repository. A workspace dir left
  /// without a `.git` entry therefore lets `commit`/`push` act on the
  /// substation's PRIMARY checkout — the failure this guard exists for (a
  /// delivery step committed to the primary's `main` and pushed three branches
  /// from it; nothing downstream noticed, because the residue commit no-opped on
  /// a clean tree and the push succeeded). The primary is the base every later
  /// worktree is cut from, so one stray commit there poisons every later round.
  ///
  /// Asks git rather than stat-ing `.git`: a `.git` file can point at a gitdir
  /// that no longer exists, and `--show-prefix` needs no path canonicalisation,
  /// so a symlinked or differently-cased [workDir] cannot false-refuse.
  ///
  /// FAIL CLOSED, like the three reap gates: a probe that does not launch (a
  /// missing [workDir]), exits non-zero (not a repository, or a bare repo with
  /// no work tree), or answers unreadably is a REFUSAL, never a pass.
  Future<GitRunResult?> _guardRepoRoot(
    String workDir,
    List<String> args,
  ) async {
    final probe = await _run(workDir, _rootProbeArgs);
    if (!probe.ok) {
      return _rootRefusal(
        workDir: workDir,
        args: args,
        detail: 'git resolved no work tree here (${_oneLine(probe.output)})',
      );
    }
    // The runner puts stdout BEFORE stderr in `output`, so line 0 is the
    // toplevel and line 1 the prefix even when git also warned.
    final lines = probe.output.split('\n');
    final toplevel = lines.first.trim();
    final prefix = lines.length >= 2 ? lines[1].trim() : null;
    if (toplevel.isEmpty || prefix == null) {
      return _rootRefusal(
        workDir: workDir,
        args: args,
        detail:
            'the root probe answered unreadably '
            '(${_oneLine(probe.output)})',
      );
    }
    if (prefix.isNotEmpty) {
      return _rootRefusal(
        workDir: workDir,
        args: args,
        detail:
            'git resolved the enclosing repository "$toplevel" '
            '(this workDir is "$prefix" inside it)',
      );
    }
    return null;
  }

  /// The refusal value: LOUD (it names the refused command, the workDir, and
  /// what git found) and unmistakably failed (`ok == false`).
  GitRunResult _rootRefusal({
    required String workDir,
    required List<String> args,
    required String detail,
  }) {
    final message =
        'git-root-guard: refused `git ${args.join(' ')}` — workDir "$workDir" '
        'is not a git work-tree root: $detail';
    return GitRunResult(
      exitCode: kGitRootGuardExitCode,
      output: message,
      stderr: message,
      launched: false,
    );
  }

  /// [_run], but only when [workDir] is itself a work-tree root.
  Future<GitRunResult> _runAtRoot(String workDir, List<String> args) async {
    final refusal = await _guardRepoRoot(workDir, args);
    return refusal ?? await _run(workDir, args);
  }

  /// Whether [workDir] is inside a git repository. gc's `IsRepo`
  /// (`git.go:31-39`).
  Future<bool> isRepo(String workDir) async {
    final r = await _run(workDir, const <String>['rev-parse', '--git-dir']);
    return r.ok;
  }

  /// The current branch name, or 'HEAD' when detached. gc's `CurrentBranch`
  /// (`git.go:42-53`).
  Future<String?> currentBranch(String workDir) async {
    final r = await _run(workDir, const <String>[
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ]);
    if (!r.ok) return null;
    return r.output.trim();
  }

  /// Reads only the configured `origin/HEAD` remote default branch.
  Future<String?> probeRemoteDefaultBranch(String workDir) async {
    final result = await _run(workDir, const <String>[
      'symbolic-ref',
      'refs/remotes/origin/HEAD',
    ]);
    if (!result.ok) return null;
    const prefix = 'refs/remotes/origin/';
    final ref = result.output.trim();
    return ref.startsWith(prefix) && ref.length > prefix.length
        ? ref.substring(prefix.length)
        : null;
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
    final remoteDefault = await probeRemoteDefaultBranch(workDir);
    if (remoteDefault != null) return remoteDefault;
    final branch = await currentBranch(workDir);
    if (branch != null) {
      final trimmed = branch.trim();
      if (trimmed.isNotEmpty && trimmed != 'HEAD') return trimmed;
    }
    return '';
  }

  /// Counts commits reachable from the remote default but not from `HEAD`.
  Future<int?> commitsBehindRemoteDefault(
    String workDir,
    String defaultBranch,
  ) async {
    final result = await _run(workDir, <String>[
      'rev-list',
      '--count',
      'HEAD..refs/remotes/origin/$defaultBranch',
    ]);
    return result.ok ? int.tryParse(result.output.trim()) : null;
  }

  /// Inspects [workDir] in fail-closed probe order without mutating git state.
  Future<PrimaryCheckoutFreshness> inspectPrimaryCheckout(
    String workDir,
  ) async {
    if (!await isRepo(workDir)) {
      return const PrimaryCheckoutFreshness(
        state: PrimaryCheckoutState.unreadable,
      );
    }
    final branch = await currentBranch(workDir);
    if (branch == null) {
      return const PrimaryCheckoutFreshness(
        state: PrimaryCheckoutState.unreadable,
      );
    }
    if (branch == 'HEAD') {
      return const PrimaryCheckoutFreshness(
        state: PrimaryCheckoutState.detached,
      );
    }
    final defaultBranch = await probeRemoteDefaultBranch(workDir);
    if (defaultBranch == null) {
      return PrimaryCheckoutFreshness(
        state: PrimaryCheckoutState.remoteUnreadable,
        branch: branch,
      );
    }
    if (branch != defaultBranch) {
      return PrimaryCheckoutFreshness(
        state: PrimaryCheckoutState.offDefaultBranch,
        branch: branch,
        defaultBranch: defaultBranch,
      );
    }
    final behindBy = await commitsBehindRemoteDefault(workDir, defaultBranch);
    if (behindBy == null) {
      return PrimaryCheckoutFreshness(
        state: PrimaryCheckoutState.remoteUnreadable,
        branch: branch,
        defaultBranch: defaultBranch,
      );
    }
    return PrimaryCheckoutFreshness(
      state: behindBy == 0
          ? PrimaryCheckoutState.fresh
          : PrimaryCheckoutState.behind,
      branch: branch,
      defaultBranch: defaultBranch,
      behindBy: behindBy,
    );
  }

  /// **Gate 1.** Whether the working dir has uncommitted changes (staged,
  /// unstaged, or untracked). gc's `HasUncommittedWork` (`git.go:134-140`):
  /// fail-closed — a probe error is [GateOutcome.probeError] ("assume dirty").
  ///
  /// [excluding] names directory prefixes, RELATIVE to [workDir], whose entries
  /// do NOT count as work. It defaults to EMPTY, so ADR-0006 Decision 3's
  /// three-gate [StationGitService.reap] check is UNCHANGED: the reap gate
  /// protects work a removal would DESTROY, and residue in a worktree it is
  /// about to remove still blocks it.
  ///
  /// The COMPLETION FENCE is the one caller that excludes — it asks "did the
  /// coding agent leave its CODE uncommitted?", and the grid's OWN steps (the
  /// critics, `pin-diff`, `specify`) write `.grid/critique/`, `.grid/spec/`, and
  /// `.grid/telemetry/` by design, committing none of it. A substation that
  /// gitignores `.grid` never shows that residue; one that does NOT shows
  /// `?? .grid/`. Excluding it makes the work signal read the SAME on both,
  /// instead of reading a substation's `.gitignore` as an interrupted agent.
  ///
  /// Fail-closed on an unparsable status line: a line whose path cannot be read
  /// COUNTS as work — never silently excluded.
  ///
  /// Fail-closed, too, on a WARNING: `git status` can exit **0** while writing to
  /// stderr (`warning: could not open directory 'x/': Permission denied`), which
  /// means it could not fully scan the tree. [GitRunResult.output] is combined
  /// (gc fidelity), so a warning line would otherwise be parsed as a porcelain
  /// entry and fabricate a phantom change — inventing "uncommitted work" that
  /// does not exist. A degraded scan is [GateOutcome.probeError] ("couldn't
  /// tell"), never an invented answer: it still BLOCKS a reap exactly as before,
  /// and the completion fence reports it honestly as unreadable rather than as an
  /// interrupted agent.
  Future<GateOutcome> hasUncommittedWork(
    String workDir, {
    Set<String> excluding = const <String>{},
  }) async {
    final r = await _runAtRoot(workDir, const <String>[
      'status',
      '--porcelain',
    ]);
    if (!r.ok) return GateOutcome.probeError;
    if (r.stderr.trim().isNotEmpty) return GateOutcome.probeError;
    // stderr is empty, so `output` IS stdout: every line is porcelain.
    final work = r.output
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .where((line) => !_fullyExcluded(line, excluding));
    return work.isEmpty ? GateOutcome.clear : GateOutcome.present;
  }

  /// **Gate 2.** Whether HEAD has commits not reachable from any remote
  /// tracking branch — completed work that a removal would lose. gc's
  /// `HasUnpushedCommitsResult` (`git.go:156-162`): fail-closed on probe error.
  Future<GateOutcome> hasUnpushedCommits(String workDir) async {
    final r = await _runAtRoot(workDir, const <String>[
      'log',
      'HEAD',
      '--oneline',
      '--not',
      '--remotes',
    ]);
    if (!r.ok) return GateOutcome.probeError;
    return r.output.trim().isEmpty ? GateOutcome.clear : GateOutcome.present;
  }

  /// **Gate 3.** Whether the repository has stashed work. gc's
  /// `HasStashesResult` (`git.go:176-182`): fail-closed on probe error.
  Future<GateOutcome> hasStashes(String workDir) async {
    final r = await _runAtRoot(workDir, const <String>['stash', 'list']);
    if (!r.ok) return GateOutcome.probeError;
    return r.output.trim().isEmpty ? GateOutcome.clear : GateOutcome.present;
  }

  /// Lists worktrees in porcelain format. gc's `WorktreeList`
  /// (`git.go:123-129`). Returns null on probe error (caller fails closed).
  Future<List<GitWorktree>?> worktreeList(String rootRepo) async {
    final r = await _run(rootRepo, const <String>[
      'worktree',
      'list',
      '--porcelain',
    ]);
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
    return _runAtRoot(rootRepo, <String>[
      'worktree',
      'add',
      '-b',
      newBranch,
      path,
      baseBranch,
    ]);
  }

  /// Whether a LOCAL branch named [branch] exists in [rootRepo]. The
  /// [provisionWorktree]-self-heal check (tg-e0p): `-b` fails FOREVER once a
  /// `grid/<beadId>` branch outlives its worktree (a reaped worktree, or the
  /// losing side of a double-provision race) — this is how the caller decides
  /// whether to mint fresh or adopt what is already there. No gc analog (a
  /// single-root system, no adopt path).
  Future<bool> branchExists(String rootRepo, String branch) async {
    final r = await _run(rootRepo, <String>[
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$branch',
    ]);
    return r.ok;
  }

  /// Adds a worktree at [path] checked out on the EXISTING [branch] — no `-b`,
  /// so git itself refuses (informatively) if [branch] is already checked out
  /// elsewhere rather than silently duplicating it. The adopt half of the
  /// [provisionWorktree] self-heal.
  Future<GitRunResult> worktreeAddExisting({
    required String rootRepo,
    required String path,
    required String branch,
  }) {
    return _runAtRoot(rootRepo, <String>['worktree', 'add', path, branch]);
  }

  /// The resolved commit [workDir]'s HEAD points at — the BASE SHA the
  /// trajectory's `worktree.provisioned` record carries (stage1-wiring §2.2's
  /// `commit_sha` row; `ck_provision` promotes it to a required envelope
  /// column). Read from the freshly-added worktree, so it names the commit
  /// that worktree actually starts on whether its branch was minted off the
  /// root's mainline or adopted at its own tip. Null on any probe error —
  /// [GitRunner] never throws, and no caller fails a provision over telemetry.
  Future<String?> headSha(String workDir) async {
    final r = await _runAtRoot(workDir, const <String>['rev-parse', 'HEAD']);
    if (!r.ok) return null;
    final sha = r.output.trim();
    return sha.isEmpty ? null : sha;
  }

  /// Force-deletes a LOCAL branch, run from [rootRepo] once its worktree is
  /// gone. `-D` (not `-d`): the three-gate reap that calls this already proved
  /// the branch carries no commits unreachable from a remote, so a merge-check
  /// against whatever happens to be checked out in the root repo would only
  /// produce a false-negative refusal, never protect real work. Best-effort —
  /// [GitRunner] never throws, and the caller does not fail a clean reap over
  /// this.
  Future<GitRunResult> branchDelete({
    required String rootRepo,
    required String branch,
  }) {
    return _runAtRoot(rootRepo, <String>['branch', '-D', branch]);
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
    return _runAtRoot(rootRepo, <String>[
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
    final add = await _runAtRoot(workDir, const <String>['add', '-A']);
    if (!add.ok) return add;
    return _runAtRoot(workDir, <String>['commit', '-m', message]);
  }

  /// Pushes [branch] to [remote] with `-u` (sets upstream so
  /// [hasUnpushedCommits] reads clear afterward). Part of the land step.
  Future<GitRunResult> pushSetUpstream({
    required String workDir,
    required String remote,
    required String branch,
  }) {
    return _runAtRoot(workDir, <String>['push', '-u', remote, branch]);
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
