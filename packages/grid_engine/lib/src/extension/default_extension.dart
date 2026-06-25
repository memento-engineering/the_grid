/// The compiled `DefaultExtension` — the_grid's built-in capability Seeds and
/// the resolver that maps a [WorkPhase] to one (ADR-0007 §1: the *opinions*
/// live HERE, in an extension, never in the kernel/effect core).
///
/// This is the minimal compiled extension: three phase capabilities
/// (`implement` → spawn a coding agent, `verify` → run the check, `land` → the
/// git/PR orchestration) wired by [DefaultEffectResolver]. The TOML
/// `PackInflater` / full dynamic `GridExtension` (a capability set loaded from a
/// `city.toml`-style manifest) is P1 / ADR-0008 — not built here.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../domain/session_projection.dart';
import '../domain/work_phase.dart';
import '../effect/effect_context.dart';
import '../effect/effect_seed.dart';
import '../kernel/effect_resolver.dart';
import '../kernel/idle.dart';

/// The IMPLEMENT capability: spawn the coding agent in the bead's worktree
/// (ADR-0007 — `implement` = supervise the `claude` subprocess).
///
/// A process effect over the shared transport ([EffectContext.provider]): the
/// engine's [EffectSeed] lifecycle mints/reuses the session bead, spawns this
/// config, persists the started identity, and on a clean completion advances
/// the cursor to [advanceTo] (`verify`).
///
/// The exact `claude` argv is a live-arm concern (model / effort / prompt
/// threading); kept minimal and honest here (`claude -p`, non-interactive print
/// mode) — the fake provider records the config in the offline build.
class AgentEffectSeed extends EffectSeed {
  /// Creates the implement-phase agent effect for [bead] with its [session].
  const AgentEffectSeed({
    required super.bead,
    required super.phase,
    super.session,
    super.key,
  });

  @override
  RuntimeConfig buildConfig(EffectContext ctx) => RuntimeConfig(
    workDir: ctx.worktreeFor(bead.id),
    command: 'claude',
    args: const ['-p'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  WorkPhase? get advanceTo => WorkPhase.verify;
}

/// The VERIFY capability: run the verification check in the bead's worktree
/// (ADR-0007 — `verify`, deliberately NOT the M2 convergence gate).
///
/// A process effect via the SAME transport as the agent — `sh -c 'melos test'`
/// one-turn — so a green check advances the cursor to [advanceTo] (`land`) and
/// a non-zero exit (a `Died`/non-clean terminal) does NOT.
class VerifyEffectSeed extends EffectSeed {
  /// Creates the verify-phase effect for [bead] with its [session].
  const VerifyEffectSeed({
    required super.bead,
    required super.phase,
    super.session,
    super.key,
  });

  @override
  RuntimeConfig buildConfig(EffectContext ctx) => RuntimeConfig(
    workDir: ctx.worktreeFor(bead.id),
    command: 'sh',
    args: const ['-c', 'melos test'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  WorkPhase? get advanceTo => WorkPhase.land;
}

/// The LAND capability: commit → push → open the PR, then record the PR url on
/// the session bead and close it (ADR-0007 — the positive terminal).
///
/// A SEPARATE guard-bearing Seed — land is git/PR ORCHESTRATION, not a
/// supervised process, so it does NOT extend [EffectSeed] (there is no provider
/// spawn, no process lifecycle to mount/kill). It mirrors the [EffectSeed]
/// guard discipline: capture [EffectContext] in `didChangeDependencies`, run
/// the async orchestration off `initState` with the `_cancelled` /
/// `context.mounted` / `_done` guards so a dispose mid-land writes nothing
/// after, and resolve everything off the CAPTURED context (never `context`,
/// which throws post-unmount).
///
/// Offline-safe: when [EffectContext.gitOps] / [EffectContext.prOpener] are
/// null (land not wired), it no-ops — it never touches real git/GitHub. A
/// [PullRequestResult] failure records no `pr_url` and does NOT close the
/// session (an honest "land did not complete").
class LandEffectSeed extends StatefulSeed {
  /// Creates the land effect for [bead] with its linked [session] (whose
  /// [SessionProjection.sessionId] is the bead the PR url is recorded on +
  /// closed).
  const LandEffectSeed({
    required this.bead,
    this.session,
    super.key,
  });

  /// The work bead being landed (its id derives the worktree + branch).
  final Bead bead;

  /// The bead's linked session projection — its [SessionProjection.sessionId]
  /// is the session bead the result is recorded on, then closed.
  final SessionProjection? session;

  @override
  State<LandEffectSeed> createState() => _LandEffectSeedState();
}

class _LandEffectSeedState extends State<LandEffectSeed> {
  EffectContext? _ctx;
  bool _cancelled = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    // Resolve + CAPTURE the context once, into a field, so the async land never
    // re-resolves via `context` across a gap (which throws post-unmount).
    _ctx ??= context.dependOnInheritedSeedOfExactType<EffectContext>();
    assert(
      _ctx != null,
      'LandEffectSeed mounted without an InheritedSeed<EffectContext>',
    );
  }

  @override
  void initState() {
    unawaited(_land());
  }

  Future<void> _land() async {
    // Yield once so `didChangeDependencies` (which captures `_ctx`) has run —
    // genesis drives `initState` then `didChangeDependencies` within one
    // performRebuild, and this body must not touch `_ctx` before capture. A
    // disposal in this window is caught by the guards below.
    await null;
    if (_cancelled || !context.mounted) return;
    final ctx = _ctx!;
    final sessionId = seed.session?.sessionId;
    // No session to record against — nothing to land onto (verify/land reuse an
    // existing session; a land effect without one is a no-op).
    if (sessionId == null) return;
    // Land not wired (an offline build with no git/PR ops) — no-op rather than
    // touch real git/GitHub.
    final gitOps = ctx.gitOps;
    final prOpener = ctx.prOpener;
    if (gitOps == null || prOpener == null) return;

    final workDir = ctx.worktreeFor(seed.bead.id);
    final branch = ctx.branchFor(seed.bead.id);

    await gitOps.commitAll(
      workDir: workDir,
      message: 'grid: land ${seed.bead.id}',
    );
    if (_cancelled || !context.mounted) return;

    await gitOps.pushSetUpstream(
      workDir: workDir,
      remote: 'origin',
      branch: branch,
    );
    if (_cancelled || !context.mounted) return;

    final pr = await prOpener.open(
      workDir: workDir,
      branch: branch,
      baseBranch: ctx.baseBranch,
      title: 'grid: ${seed.bead.id}',
    );
    if (_cancelled || !context.mounted || _done) return;
    // The PR open did not produce a ref — record nothing, do not close (an
    // honest "land did not complete"; the cursor stays so a retry is possible).
    if (!pr.isOpened) return;
    // Latch BEFORE the terminal writes so a re-entrant call cannot double-close.
    _done = true;

    await ctx.writer.update(
      sessionId,
      metadata: {'pr_url': pr.ref!.url},
    );
    if (_cancelled) return;
    await ctx.writer.close(sessionId, reason: 'landed');
  }

  @override
  void dispose() {
    _cancelled = true;
  }

  @override
  Seed build(TreeContext context) => const Idle();
}

/// The compiled `DefaultExtension`'s resolver — the [EffectResolver] the kernel
/// resolves a [WorkPhase] through (ADR-0007 Decision 5).
///
/// Every effect is keyed `'<beadId>.<capId>'` so a phase advance SWAPS the
/// effect child (unmount the old capability → its `dispose` kills; mount the
/// new → its `initState` spawns) while the owning work node keeps its branch
/// identity. The kernel/effect core never references these capabilities — only
/// this extension does (the opinion-free-kernel invariant, ADR-0007 §1).
class DefaultEffectResolver implements EffectResolver {
  /// Creates the resolver (stateless; the compiled built-in capability set).
  const DefaultEffectResolver();

  @override
  Seed effectFor({
    required Bead bead,
    required WorkPhase phase,
    SessionProjection? session,
  }) {
    final key = ValueKey('${bead.id}.${phase.capId}');
    return switch (phase) {
      WorkPhase.implement => AgentEffectSeed(
        bead: bead,
        phase: phase,
        session: session,
        key: key,
      ),
      WorkPhase.verify => VerifyEffectSeed(
        bead: bead,
        phase: phase,
        session: session,
        key: key,
      ),
      WorkPhase.land => LandEffectSeed(
        bead: bead,
        session: session,
        key: key,
      ),
    };
  }
}
