import 'dart:io';

import 'package:path/path.dart' as p;

import 'git_ops.dart';
import 'git_runner.dart';
import 'pr_opener.dart';
import 'stale_ancestor_guard.dart';

/// The Layer-1 root checkout registration — a the_grid-OWNED real clone of the
/// target repo (lenny), registered ONCE, with `origin` set and the default
/// branch probed from `origin/HEAD` (ADR-0006 Decision 3; gc's substation model). This
/// is NOT a worktree; it is the_grid's "rig" in gc's sense.
///
/// This service NEVER creates the clone — registration RECORDS an
/// already-present checkout (the `lenny-tgdog` clone is created out of band by
/// Nico's one-time procedure; auto-provision is the gascity#1556 stale-ancestor
/// hazard, ADR-0006 alternatives). Plain value type (predictable-flutter).
class RootCheckout {
  const RootCheckout({
    required this.path,
    required this.defaultBranch,
    required this.substation,
    this.remote = 'origin',
  });

  /// The absolute path of the registered root checkout (e.g.
  /// `/Users/nico/development/engineering.memento/lenny-tgdog`).
  final String path;

  /// The mainline branch probed from `origin/HEAD` at registration
  /// ([GitOps.probeDefaultBranch]). Per-bead worktrees branch off this — never
  /// a hardcoded `main`.
  final String defaultBranch;

  /// The owned dogfood substation (e.g. `tgdog`) — the dir segment under
  /// `<root>/.grid/worktrees/<substation>/` (ADR-0006 Decision 1).
  final String substation;

  /// The push remote (default `origin`).
  final String remote;
}

/// A provisioned per-bead worktree — Layer 2 (ADR-0006 Decision 3). Plain value
/// type. The dir name encodes the bead id so an orphaned worktree can be
/// re-bound to its lifecycle bead on restart without external state
/// ([WorktreeLayout.beadIdFromName]).
class BeadWorktree {
  const BeadWorktree({
    required this.beadId,
    required this.path,
    required this.branch,
  });

  final String beadId;

  /// `<root>/.grid/worktrees/<substation>/<beadId>`.
  final String path;

  /// `grid/<beadId>`.
  final String branch;
}

/// The outcome of a reap attempt — distinguishes a clean removal from a
/// fail-closed REFUSAL, so the dispatcher (and a test) can assert WHY a
/// worktree was kept. Mirrors gc's reaper skip-vs-remove split
/// (`cmd/gc/bead_worktree_reaper.go:101-141`).
class ReapOutcome {
  const ReapOutcome._({
    required this.removed,
    required this.refusedReason,
    required this.uncommitted,
    required this.unpushed,
    required this.stashed,
  });

  /// Removed cleanly (all three gates clear).
  factory ReapOutcome.removed() => const ReapOutcome._(
    removed: true,
    refusedReason: null,
    uncommitted: GateOutcome.clear,
    unpushed: GateOutcome.clear,
    stashed: GateOutcome.clear,
  );

  /// Refused: at least one gate blocked (present OR probe error). Carries the
  /// per-gate outcomes so the refusal reason is precise and a fail-closed
  /// probe error is visible as such.
  factory ReapOutcome.refused({
    required GateOutcome uncommitted,
    required GateOutcome unpushed,
    required GateOutcome stashed,
    required String reason,
  }) => ReapOutcome._(
    removed: false,
    refusedReason: reason,
    uncommitted: uncommitted,
    unpushed: unpushed,
    stashed: stashed,
  );

  final bool removed;
  final String? refusedReason;
  final GateOutcome uncommitted;
  final GateOutcome unpushed;
  final GateOutcome stashed;

  bool get refused => !removed;
}

/// The result of the land step (DIVERGES from gc; ADR-0006 Decision 3): commit
/// → push → open PR. Carries either the [PullRequestRef] or a failure reason so
/// the caller records the outcome on the lifecycle bead.
class LandResult {
  const LandResult._({
    required this.committed,
    required this.pushed,
    required this.pr,
    required this.failureReason,
  });

  factory LandResult.landed({required PullRequestRef pr}) => LandResult._(
    committed: true,
    pushed: true,
    pr: pr,
    failureReason: null,
  );

  factory LandResult.failed({
    required bool committed,
    required bool pushed,
    required String reason,
  }) => LandResult._(
    committed: committed,
    pushed: pushed,
    pr: null,
    failureReason: reason,
  );

  final bool committed;
  final bool pushed;
  final PullRequestRef? pr;
  final String? failureReason;

  bool get isLanded => pr != null;
}

/// Pure helpers for the `<root>/.grid/worktrees/<substation>/<beadId>` layout +
/// `grid/<beadId>` branch naming — mirrors gc's `.gc/worktrees/<substation>/<name>`
/// (`internal/workdir/workdir.go:76-86`). Separated out so the path/branch
/// derivation and the bead-id round-trip are unit-tested with no IO.
class WorktreeLayout {
  const WorktreeLayout._();

  /// The worktrees root under the registered root checkout:
  /// `<root>/.grid/worktrees`.
  static String worktreesRoot(String rootPath) =>
      p.join(rootPath, '.grid', 'worktrees');

  /// The substation dir: `<root>/.grid/worktrees/<substation>`.
  static String substationDir(String rootPath, String substation) =>
      p.join(worktreesRoot(rootPath), substation);

  /// The per-bead worktree path: `<root>/.grid/worktrees/<substation>/<beadId>`.
  static String worktreePath(String rootPath, String substation, String beadId) =>
      p.join(substationDir(rootPath, substation), beadId);

  /// The per-bead branch: `grid/<beadId>`.
  static String branchFor(String beadId) => 'grid/$beadId';

  /// Recovers the bead id from a worktree DIR NAME on restart. The dir name IS
  /// the bead id (we encode it directly, unlike gc's `builder-ga-…-pr…`
  /// composite), so this is the identity — but we still guard against an empty
  /// name. gc's restart-rebind seam
  /// (`cmd/gc/bead_worktree_reaper.go:157-173`).
  static String? beadIdFromName(String dirName) {
    final trimmed = dirName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Whether [path] is strictly contained within [dir] — the scope gate that
/// guarantees the reaper can only ever delete inside the_grid's own worktrees
/// root. gc's `isStrictlyUnderDir`
/// (`cmd/gc/bead_worktree_reaper.go:191-198`).
///
/// Both sides are symlink-canonicalized first (gc's `canonicalWorktreePath`,
/// `git.go:362-367`): `git worktree list` reports resolved paths (e.g. macOS
/// `/private/var` for a `/var` tmp dir), so a raw prefix check against an
/// unresolved root would spuriously reject a legitimate child.
bool isStrictlyUnderDir(String dir, String path) {
  final rel = p.relative(_canonical(path), from: _canonical(dir));
  return rel != '.' && !rel.startsWith('..');
}

/// Resolves symlinks where the path exists; otherwise normalizes. gc's
/// `canonicalWorktreePath` (`git.go:362-367`).
String _canonical(String path) {
  try {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      return Directory(path).resolveSymbolicLinksSync();
    }
  } on FileSystemException {
    // fall through to normalize.
  }
  return p.normalize(path);
}

/// The Service that gives the_grid git-worktree-per-bead isolation (M3 Track 3;
/// ADR-0006 Decision 3). Stateless IO over the injectable [GitRunner] +
/// [PrOpener] seams (predictable-flutter: a Service owns one source — here the
/// `git` binary + the PR-open boundary — and is constructed with its
/// dependencies). **Futures for acts** (register/provision/land/reap);
/// point-in-time `list` is a Future too (a read act, not an observation
/// stream).
///
/// **The load-bearing safety, ported verbatim from gc:**
///  - the **three-gate** pre-removal check ([reap]) — refuse if uncommitted OR
///    unpushed OR stashed, ALL fail-closed on probe error
///    ([GitOps.hasUncommittedWork]/[GitOps.hasUnpushedCommits]/
///    [GitOps.hasStashes], `git.go:134-213`); `git worktree remove` is run from
///    the ROOT repo, never inside the worktree;
///  - the **GIT_* env blacklist** — stripped on every git exec by the
///    [GitRunner] seam ([gitEnvBlacklist], `git.go:285-301`);
///  - the **stale-ancestor guard** ([validateAncestorWorktreesNotStale],
///    `workdir.go:303-359`) — run before EVERY `git worktree add`;
///  - the **scope gate** ([isStrictlyUnderDir]) — reap only acts on paths
///    strictly under the worktrees root.
///
/// **The land step DIVERGES from gc** (no gc prior art): commit → push -u →
/// open PR via the injectable [PrOpener] → return the [PullRequestRef] for the
/// caller to record on the lifecycle bead. NEVER auto-merges.
class StationGitService {
  StationGitService({
    required GitRunner runner,
    required PrOpener prOpener,
  }) : _ops = GitOps(runner),
       _prOpener = prOpener;

  final GitOps _ops;
  final PrOpener _prOpener;

  /// **Layer 1 — register the root checkout.** Records [path] (an
  /// already-present clone) + the default branch per-bead worktrees branch off.
  ///
  /// By default the mainline is PROBED from `origin/HEAD` (gc's
  /// `ProbeDefaultBranch`). Pass [head] to ASSIGN it explicitly instead — the
  /// "assign-head" affordance for the_grid-as-substation: when THIS checkout is
  /// the root and its work lives on a feature branch (e.g.
  /// `m4-p1-reentrant-engine`), worktrees must cut off THAT branch, not `main`.
  /// An assigned [head] skips the probe; it is NOT verified to exist here (no
  /// cheap ref-probe seam), so a bad branch fails loudly at the first
  /// [provisionWorktree] `git worktree add` rather than silently cutting off the
  /// wrong base.
  ///
  /// Does NOT create the clone (the root checkout is registered, never
  /// auto-provisioned; ADR-0006). Verifies [path] is a git repo; throws
  /// [StateError] if [path] is not a repo (fail closed at registration rather
  /// than minting worktrees off a non-repo).
  Future<RootCheckout> registerRootCheckout({
    required String path,
    required String substation,
    String remote = 'origin',
    String? head,
  }) async {
    final normalized = p.normalize(path);
    if (!await _ops.isRepo(normalized)) {
      throw StateError(
        'registerRootCheckout: "$normalized" is not a git repository '
        '(register an existing clone; the_grid never auto-provisions it)',
      );
    }
    final String defaultBranch;
    if (head != null && head.trim().isNotEmpty) {
      // Assigned head: trust the operator; verified at `git worktree add` time.
      defaultBranch = head.trim();
    } else {
      defaultBranch = await _ops.probeDefaultBranch(normalized);
      if (defaultBranch.isEmpty) {
        throw StateError(
          'registerRootCheckout: could not probe a default branch for '
          '"$normalized" (origin/HEAD unset and no usable current branch). '
          'Pass an explicit head to assign one.',
        );
      }
    }
    return RootCheckout(
      path: normalized,
      defaultBranch: defaultBranch,
      substation: substation,
      remote: remote,
    );
  }

  /// **Layer 2 — provision a per-bead worktree.** Runs the stale-ancestor guard
  /// (fail closed), then runs, from the root repo,
  /// `git worktree add -b grid/<beadId> <root>/.grid/worktrees/<substation>/<beadId> <base>`.
  /// Idempotency / single-worktree-per-bead is the caller's job (Track 5's
  /// per-bead queue); this throws if the worktree path already exists.
  ///
  /// **Self-heals a WEDGED branch (tg-e0p).** `grid/<beadId>` can outlive its
  /// worktree — a reaped worktree never used to delete the branch it was cut
  /// from ([reap] now does, but an out-of-band `git worktree remove`, or the
  /// losing side of a double-provision race, still leaves one behind). Left
  /// alone, `-b` fails on "already exists" FOREVER — every subsequent mint
  /// attempt hits the same wedge with no self-healing path (the exact
  /// operator-observed failure: 3 re-mints, 2 manual git bridges, one bead).
  /// So: when [branch] already exists locally, ADOPT it (`git worktree add`
  /// with no `-b`) instead of minting fresh; only mint a new branch when it
  /// genuinely is not there yet.
  Future<BeadWorktree> provisionWorktree({
    required RootCheckout root,
    required String beadId,
  }) async {
    final branch = WorktreeLayout.branchFor(beadId);
    final path = WorktreeLayout.worktreePath(root.path, root.substation, beadId);

    // Stale-ancestor guard BEFORE any `git worktree add` (gascity#1556).
    final rejection = validateAncestorWorktreesNotStale(path);
    if (rejection != null) {
      throw StateError(rejection);
    }

    // Ensure the substation dir exists so `git worktree add` lands the target under
    // it. (git creates the leaf; the parent dirs must exist.)
    final substationDir = Directory(WorktreeLayout.substationDir(root.path, root.substation));
    if (!substationDir.existsSync()) {
      substationDir.createSync(recursive: true);
    }

    final preexisting = await _ops.branchExists(root.path, branch);
    final result = preexisting
        ? await _ops.worktreeAddExisting(
            rootRepo: root.path,
            path: path,
            branch: branch,
          )
        : await _ops.worktreeAdd(
            rootRepo: root.path,
            path: path,
            newBranch: branch,
            baseBranch: root.defaultBranch,
          );
    if (!result.ok) {
      // LOUD + precise (tg-e0p): name exactly what was found so a human never
      // has to re-derive it from a raw git stderr blob mid-incident.
      throw StateError(
        'provisionWorktree: git worktree add failed for $beadId — branch '
        '"$branch" ${preexisting ? 'already existed (adopt attempted, no -b)' : 'did not exist yet (minted fresh)'}, '
        'target path "$path": ${result.output.trim()}',
      );
    }
    return BeadWorktree(beadId: beadId, path: path, branch: branch);
  }

  /// Lists the_grid's per-bead worktrees under [root], each re-bound to its bead
  /// id via [WorktreeLayout.beadIdFromName] (the dir name encodes the id) — the
  /// restart-reconciliation seam. Only worktrees strictly under the worktrees
  /// root on a `grid/<beadId>` branch are returned. Returns `null` on a probe
  /// error (the caller fails closed; does not assume "no worktrees").
  Future<List<BeadWorktree>?> listBeadWorktrees(RootCheckout root) async {
    final all = await _ops.worktreeList(root.path);
    if (all == null) return null;
    final wtRoot = WorktreeLayout.worktreesRoot(root.path);
    final out = <BeadWorktree>[];
    for (final wt in all) {
      if (!isStrictlyUnderDir(wtRoot, wt.path)) continue;
      final beadId = WorktreeLayout.beadIdFromName(p.basename(wt.path));
      if (beadId == null) continue;
      out.add(
        BeadWorktree(
          beadId: beadId,
          path: wt.path,
          branch: wt.branch.isNotEmpty
              ? wt.branch
              : WorktreeLayout.branchFor(beadId),
        ),
      );
    }
    return out;
  }

  /// **The land step (DIVERGES from gc; ADR-0006 Decision 3).** On session
  /// success: commit all changes on `grid/<beadId>`, then
  /// `git push -u origin grid/<beadId>`, then open a PR via the injectable
  /// [PrOpener], then return
  /// the [PullRequestRef] (for the caller to record on the lifecycle bead).
  /// **NEVER auto-merges.** After the push, [GitOps.hasUnpushedCommits] reads
  /// clear, so the three-gate [reap] then considers the worktree removable —
  /// push and cleanup compose cleanly.
  ///
  /// Each failure short-circuits and is recorded (never thrown) so the caller
  /// can mark the lifecycle bead and leave the worktree in place for retry.
  Future<LandResult> land({
    required RootCheckout root,
    required BeadWorktree worktree,
    required String commitMessage,
    required String prTitle,
    String prBody = '',
  }) async {
    final commit = await _ops.commitAll(
      workDir: worktree.path,
      message: commitMessage,
    );
    if (!commit.ok) {
      return LandResult.failed(
        committed: false,
        pushed: false,
        reason: 'commit failed: ${commit.output.trim()}',
      );
    }

    final push = await _ops.pushSetUpstream(
      workDir: worktree.path,
      remote: root.remote,
      branch: worktree.branch,
    );
    if (!push.ok) {
      return LandResult.failed(
        committed: true,
        pushed: false,
        reason: 'push failed: ${push.output.trim()}',
      );
    }

    final pr = await _prOpener.open(
      workDir: worktree.path,
      branch: worktree.branch,
      baseBranch: root.defaultBranch,
      title: prTitle,
      body: prBody,
    );
    if (!pr.isOpened) {
      return LandResult.failed(
        committed: true,
        pushed: true,
        reason: pr.failure?.reason ?? 'pr open failed',
      );
    }
    return LandResult.landed(pr: pr.ref!);
  }

  /// The **work signal** of the engine's completion fence: whether
  /// [workspaceDir] still holds UNCOMMITTED work (staged, unstaged, or
  /// untracked).
  ///
  /// A CODING AGENT's working agreement is "COMMIT your work in the worktree",
  /// so a CLEAN tree is the observable trace of a FINISHED turn and a DIRTY one
  /// is the trace of a turn CUT SHORT. The engine fences an INFERRED exit
  /// (`Exited.inferred` — a detached agent's vanish, which a murder and a
  /// completion produce identically) on this signal before it advances the
  /// circuit. Only a capability that DECLARES that agreement
  /// (`CompletionContract.committedWorkspace`) is fenced — a critic writes an
  /// uncommitted verdict and vanishes by design.
  ///
  /// [excluding] names dir prefixes that do not count as work — the composer
  /// passes the grid's own runtime dir (`.grid`), whose critique/spec/telemetry
  /// artifacts no step commits. Default EMPTY ⇒ **ADR-0006 Decision 3's Gate 1
  /// verbatim**, which is what [reap] still calls: the same
  /// [GitOps.hasUncommittedWork], the same ratified fail-closed posture (a failed
  /// `git status` is [GateOutcome.probeError], never a silent
  /// [GateOutcome.clear]). This adds NO new reap gate and changes NO reap
  /// behavior. Mutates nothing.
  Future<GateOutcome> hasUncommittedWork(
    String workspaceDir, {
    Set<String> excluding = const <String>{},
  }) => _ops.hasUncommittedWork(workspaceDir, excluding: excluding);

  /// **The three-gate reaper (ported VERBATIM from gc, `git.go:134-213` +
  /// `bead_worktree_reaper.go:100-141`).** Refuses to remove [worktree] if it
  /// has uncommitted work OR unpushed commits OR a stash — ALL fail-closed on
  /// probe error (a gate probe that errors blocks removal exactly like a
  /// present condition). The gates run FROM the worktree dir (so `git status` /
  /// `git stash list` apply to its branch); `git worktree remove` runs from the
  /// ROOT repo, never inside the worktree.
  ///
  /// The caller is responsible for the higher-level removal TRIGGER (lifecycle
  /// bead closed AND branch pushed) — this method is the fail-closed mechanism
  /// that executes once the trigger fires. Registry removal ≠ disk deletion is
  /// the caller's concern (mirror gc); this only removes the on-disk worktree
  /// when safe.
  Future<ReapOutcome> reap({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
    // Scope gate: only ever act on a path strictly under the worktrees root.
    final wtRoot = WorktreeLayout.worktreesRoot(root.path);
    if (!isStrictlyUnderDir(wtRoot, worktree.path)) {
      return ReapOutcome.refused(
        uncommitted: GateOutcome.probeError,
        unpushed: GateOutcome.probeError,
        stashed: GateOutcome.probeError,
        reason:
            'refused: ${worktree.path} is not strictly under the worktrees '
            'root $wtRoot',
      );
    }

    // The three gates, run from the worktree dir. ALL fail-closed on probe
    // error (GateOutcome.probeError blocks, same as present).
    final uncommitted = await _ops.hasUncommittedWork(worktree.path);
    final unpushed = await _ops.hasUnpushedCommits(worktree.path);
    final stashed = await _ops.hasStashes(worktree.path);

    if (gateBlocks(uncommitted) ||
        gateBlocks(unpushed) ||
        gateBlocks(stashed)) {
      final reason =
          'uncommitted=${uncommitted.name} '
          'unpushed=${unpushed.name} '
          'stashes=${stashed.name}';
      return ReapOutcome.refused(
        uncommitted: uncommitted,
        unpushed: unpushed,
        stashed: stashed,
        reason: reason,
      );
    }

    // All gates clear — remove from the ROOT repo (never from inside the
    // worktree). No --force: the gates ARE the safety, not a force flag.
    final result = await _ops.worktreeRemove(
      rootRepo: root.path,
      path: worktree.path,
    );
    if (!result.ok) {
      return ReapOutcome.refused(
        uncommitted: uncommitted,
        unpushed: unpushed,
        stashed: stashed,
        reason: 'git worktree remove failed: ${result.output.trim()}',
      );
    }
    // Symmetric cleanup (tg-e0p): the worktree is gone — also delete the
    // branch it was cut from. Left behind, `grid/<beadId>` would wedge every
    // future re-mint's `git worktree add -b` FOREVER ([provisionWorktree]'s
    // own adopt fallback now self-heals that case too, but a reaped bead
    // should never need to). Best-effort: [GitOps.branchDelete] never throws,
    // and a delete failure must not flip an already-successful worktree
    // removal into a refusal.
    await _ops.branchDelete(rootRepo: root.path, branch: worktree.branch);
    return ReapOutcome.removed();
  }
}
