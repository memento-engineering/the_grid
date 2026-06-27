import 'package:grid_runtime/grid_runtime.dart';

/// The injected bundle an [EffectSeed] resolves from the tree in ONE inherited
/// lookup (ADR-0007 / M4-P0-BUILD-ORDER Track C).
///
/// The kernel (Track E/F) provides exactly one of these via an
/// `InheritedSeed<EffectContext>` above the work tree, so every mounted effect
/// reaches its process transport ([provider]), its single bd write chokepoint
/// ([writer]), and the owned state rig ([stateSubstation]) through a single
/// `dependOnInheritedSeedOfExactType` — never three separate lookups, and never
/// a re-query of the store (A39).
///
/// Immutable and value-light: the bundle is a handle to long-lived
/// collaborators, not state. An effect captures it once in
/// `didChangeDependencies` and uses the captured reference across async gaps so
/// it never touches the `TreeContext` (which throws post-unmount) for I/O.
///
/// The first three collaborators are required (every effect needs the
/// transport, the chokepoint, and the owned rig). The land-orchestration ops
/// ([gitOps] / [prOpener]) and the worktree layout fields are OPTIONAL — a
/// process effect (`AgentEffectSeed` / `VerifyEffectSeed`) needs only the
/// worktree path, and an offline build that does not wire git/PR leaves
/// [gitOps] / [prOpener] null so the land effect no-ops rather than touches
/// real GitHub.
class EffectContext {
  /// Bundles the process transport [provider], the bd write [writer], and the
  /// owned [stateSubstation], plus the optional land-orchestration ops + worktree
  /// layout the capability Seeds resolve.
  const EffectContext({
    required this.provider,
    required this.writer,
    required this.stateSubstation,
    this.gitOps,
    this.prOpener,
    this.worktreeRoot,
    this.workSubstation = '',
    this.baseBranch = 'main',
  });

  /// The process transport — spawn (`start`), kill (`stop`), and the broadcast
  /// lifecycle [RuntimeProvider.events] stream the effect subscribes to.
  final RuntimeProvider provider;

  /// The single bd write chokepoint — the ONLY path session/lifecycle beads are
  /// written through (`createSession` / `update` / `close`), bd-only,
  /// `--actor grid-controller`, fail-closed on ownership (ADR-0006 Decision 2).
  final StationBeadWriter writer;

  /// The_grid's OWNED state rig (`tgdog`) — the partition session beads are
  /// minted into, kept separate from the read-only work source (A37).
  final String stateSubstation;

  /// The injectable git ops the land orchestration drives (commit → push).
  /// Null when land is not wired (an offline build that never touches real
  /// git); the land effect then no-ops.
  final GitOps? gitOps;

  /// The injectable PR opener the land orchestration drives. Null when land is
  /// not wired; the land effect then no-ops rather than touching real GitHub.
  final PrOpener? prOpener;

  /// The root checkout under which per-bead worktrees are allocated, or null to
  /// fall back to the bare `/grid/worktrees/$beadId` layout (the synthetic
  /// default for tests / a not-yet-registered root).
  final String? worktreeRoot;

  /// The work rig the worktrees partition under (`$root/.grid/worktrees/
  /// $workSubstation/$beadId`); empty by default.
  final String workSubstation;

  /// The base branch the land step opens PRs against (`main` by default).
  final String baseBranch;

  /// The per-bead worktree path for [beadId] — the working directory a process
  /// effect spawns into and the land effect commits/pushes from.
  ///
  /// Falls back to the bare `/grid/worktrees/$beadId` layout when no
  /// [worktreeRoot] is registered (the synthetic offline default); otherwise
  /// mirrors grid_runtime's `$root/.grid/worktrees/$workSubstation/$beadId` layout.
  String worktreeFor(String beadId) => worktreeRoot == null
      ? '/grid/worktrees/$beadId'
      : '$worktreeRoot/.grid/worktrees/$workSubstation/$beadId';

  /// The land branch for [beadId] (`grid/<beadId>`) — the branch the agent's
  /// worktree was cut on and the land step pushes + opens a PR for.
  String branchFor(String beadId) => 'grid/$beadId';
}
