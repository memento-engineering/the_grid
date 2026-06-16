import 'dart:io';

import 'package:path/path.dart' as p;

import 'git_ops.dart';
import 'git_runner.dart';
import 'pr_opener.dart';
import 'stale_ancestor_guard.dart';

/// The Layer-1 root checkout registration — a the_grid-OWNED real clone of the
/// target repo (lenny), registered ONCE, with `origin` set and the default
/// branch probed from `origin/HEAD` (ADR-0006 Decision 3; gc's rig model). This
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
    required this.rig,
    this.remote = 'origin',
  });

  /// The absolute path of the registered root checkout (e.g.
  /// `/Users/nico/development/engineering.memento/lenny-tgdog`).
  final String path;

  /// The mainline branch probed from `origin/HEAD` at registration
  /// ([GitOps.probeDefaultBranch]). Per-bead worktrees branch off this — never
  /// a hardcoded `main`.
  final String defaultBranch;

  /// The owned dogfood rig (e.g. `tgdog`) — the dir segment under
  /// `<root>/.grid/worktrees/<rig>/` (ADR-0006 Decision 1).
  final String rig;

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

  /// `<root>/.grid/worktrees/<rig>/<beadId>`.
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

/// Pure helpers for the `<root>/.grid/worktrees/<rig>/<beadId>` layout +
/// `grid/<beadId>` branch naming — mirrors gc's `.gc/worktrees/<rig>/<name>`
/// (`internal/workdir/workdir.go:76-86`). Separated out so the path/branch
/// derivation and the bead-id round-trip are unit-tested with no IO.
class WorktreeLayout {
  const WorktreeLayout._();

  /// The worktrees root under the registered root checkout:
  /// `<root>/.grid/worktrees`.
  static String worktreesRoot(String rootPath) =>
      p.join(rootPath, '.grid', 'worktrees');

  /// The rig dir: `<root>/.grid/worktrees/<rig>`.
  static String rigDir(String rootPath, String rig) =>
      p.join(worktreesRoot(rootPath), rig);

  /// The per-bead worktree path: `<root>/.grid/worktrees/<rig>/<beadId>`.
  static String worktreePath(String rootPath, String rig, String beadId) =>
      p.join(rigDir(rootPath, rig), beadId);

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
class GridGitService {
  GridGitService({
    required GitRunner runner,
    required PrOpener prOpener,
  }) : _ops = GitOps(runner),
       _prOpener = prOpener;

  final GitOps _ops;
  final PrOpener _prOpener;

  /// **Layer 1 — register the root checkout.** Records [path] (an
  /// already-present clone) + the probed default branch from `origin/HEAD`
  /// (gc's `ProbeDefaultBranch`). Does NOT create the clone (the `lenny-tgdog`
  /// clone is Nico's one-time out-of-band step; ADR-0006). Verifies [path] is a
  /// git repo and probes the mainline; throws [StateError] if [path] is not a
  /// repo (fail closed at registration rather than minting worktrees off a
  /// non-repo).
  Future<RootCheckout> registerRootCheckout({
    required String path,
    required String rig,
    String remote = 'origin',
  }) async {
    final normalized = p.normalize(path);
    if (!await _ops.isRepo(normalized)) {
      throw StateError(
        'registerRootCheckout: "$normalized" is not a git repository '
        '(register an existing clone; the_grid never auto-provisions it)',
      );
    }
    final defaultBranch = await _ops.probeDefaultBranch(normalized);
    if (defaultBranch.isEmpty) {
      throw StateError(
        'registerRootCheckout: could not probe a default branch for '
        '"$normalized" (origin/HEAD unset and no usable current branch)',
      );
    }
    return RootCheckout(
      path: normalized,
      defaultBranch: defaultBranch,
      rig: rig,
      remote: remote,
    );
  }

  /// **Layer 2 — provision a per-bead worktree.** Runs the stale-ancestor guard
  /// (fail closed), then runs, from the root repo,
  /// `git worktree add -b grid/<beadId> <root>/.grid/worktrees/<rig>/<beadId> <base>`.
  /// Idempotency / single-worktree-per-bead is the caller's job (Track 5's
  /// per-bead queue); this throws if the worktree path already exists.
  Future<BeadWorktree> provisionWorktree({
    required RootCheckout root,
    required String beadId,
  }) async {
    final branch = WorktreeLayout.branchFor(beadId);
    final path = WorktreeLayout.worktreePath(root.path, root.rig, beadId);

    // Stale-ancestor guard BEFORE any `git worktree add` (gascity#1556).
    final rejection = validateAncestorWorktreesNotStale(path);
    if (rejection != null) {
      throw StateError(rejection);
    }

    // Ensure the rig dir exists so `git worktree add` lands the target under
    // it. (git creates the leaf; the parent dirs must exist.)
    final rigDir = Directory(WorktreeLayout.rigDir(root.path, root.rig));
    if (!rigDir.existsSync()) {
      rigDir.createSync(recursive: true);
    }

    final result = await _ops.worktreeAdd(
      rootRepo: root.path,
      path: path,
      newBranch: branch,
      baseBranch: root.defaultBranch,
    );
    if (!result.ok) {
      throw StateError(
        'provisionWorktree: git worktree add failed for $beadId: '
        '${result.output.trim()}',
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
    return ReapOutcome.removed();
  }
}
