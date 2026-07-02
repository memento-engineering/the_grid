/// The opaque capability leaves + the pluggable Service seam (ADR-0008 D2/D5,
/// amended 2026-07-02 — the context rip-out).
///
/// The author implements a [Capability] (a [ProcessCapability] over a spawned
/// process, or a [ServiceCapability] over async collaborators) and NEVER a
/// `Seed`. A capability receives its host's stable `TreeContext` plus the
/// per-step [StepArgs] — **one lookup system, two verbs** (ADR-0008 Decision 3,
/// 2026-07-02):
///
/// - `dependOn*` is the TREE verb — branches always watch; only the engine's
///   carriers call it, during build.
/// - `getInheritedSeedOfExactType` is the EFFECT verb — a snapshot-at-read,
///   callable across the effect's async life, LOUD (`StateError`) on an
///   unmounted branch. A capability reads its ambient values with it: the work
///   [Bead] (mounted by `WorkBead`), the [Workspace] (mounted by
///   `SessionScope`), the [ServiceBundle] (per-substation), the [SiblingView]
///   (per-session), and any asset-owned value the asset mounted itself.
///
/// Discipline (the async-gap contract): read at ENTRY (synchronously, while
/// mounted — the kick guarantees it), then use the captured values; after every
/// await, check [StepArgs.cancel] (set on unmount) before touching the context
/// again. The invariants hold as mutation-verified gates, not a wall: a
/// capability never calls `dependOn*`, never `addListener`s anything it reads
/// from context, never subscribes to a pipeline, and never writes — the
/// engine-private `CapabilityHost` persists every report through the one
/// chokepoint.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'allocation.dart';
import 'cursor.dart';

/// A leaf the engine mounts. The engine ships three families — [ProcessCapability]
/// (a spawned process), [ServiceCapability] (an async body), and
/// [LeaseCapability] (a held lease) — and an asset may add its own (tmux, app, …).
///
/// NOT sealed: the carrier's dispatch is polymorphic through [createAllocation]
/// (the `createRenderObject` analogue, ADR-0009 D4), never an exhaustive `switch`
/// on the subtype — so a new family is an addition, not a core edit.
abstract class Capability {
  const Capability();

  /// Mints the [Allocation] that holds this capability's live effect — the
  /// `createRenderObject` analogue (ADR-0009 D4). Synchronous + cheap; the Host
  /// then drives it asynchronously (`startOrAdopt`/`update`/`dispose`/`detach`).
  /// [ProcessCapability]/[ServiceCapability] supply defaults, so an existing
  /// capability needs no change; an asset overrides only to customize adopt/
  /// detach/update for a bespoke effect.
  Allocation createAllocation(AllocationContext ctx);
}

/// The irreducibly per-step values a capability receives alongside the tree
/// context — NOT a context and NOT a grab-bag: everything ambient (bead,
/// workspace, services, siblings) is read from the tree with the effect verb;
/// only what is genuinely OF this step incarnation rides here.
class StepArgs {
  /// Bundles the step [params], this step's full [nodePath], the cooperative
  /// [cancel] token (set when the host unmounts), and the restoration [logFile]
  /// seam (deferred; null until restoration ships).
  const StepArgs({
    this.params = const {},
    required this.nodePath,
    required this.cancel,
    this.logFile,
  });

  /// The step's opaque params (from the `CapabilityStep`/`SubFormulaStep`).
  final Map<String, String> params;

  /// This step's FULL path within the formula tree (`'$parentNodePath/$stepId'`)
  /// — the cursor key; its root segment is the work bead id.
  final String nodePath;

  /// The work bead id — the root segment of [nodePath] (the root formula's
  /// nodePath IS the bead id).
  String get beadId =>
      nodePath.contains('/') ? nodePath.split('/').first : nodePath;

  /// The cooperative cancellation token — set when the host unmounts. Check it
  /// after EVERY async gap before touching the tree context again (an unmounted
  /// branch's context throws, loudly, by design).
  final CancelToken cancel;

  /// The durable log file for the deferred adopt-a-live-process seam
  /// (ADR-0008 D6 §restoration); null until restoration ships.
  final String? logFile;
}

/// The per-session workspace the work runs in — an ambient VALUE mounted by
/// `SessionScope` (computed once per session from the per-substation
/// [SourceControl]; ADR-0008 D5: the layout is the SourceControl impl's
/// opinion, the engine's concept is "a workspace"). A capability reads it with
/// the effect verb: `context.getInheritedSeedOfExactType<Workspace>()`.
class Workspace {
  /// Bundles the stable [workspaceDir] home, the work [branch], and the
  /// [baseBranch] a land opens its PR against.
  const Workspace({
    required this.workspaceDir,
    required this.branch,
    required this.baseBranch,
  });

  /// The stable home directory the work runs in (the cwd default; per-spawn
  /// overridable via `RuntimeConfig.workingDirectory`).
  final String workspaceDir;

  /// The branch the work is on (the git impl: `grid/<beadId>`).
  final String branch;

  /// The base branch a land opens its PR against.
  final String baseBranch;

  @override
  bool operator ==(Object other) =>
      other is Workspace &&
      other.workspaceDir == workspaceDir &&
      other.branch == branch &&
      other.baseBranch == baseBranch;

  @override
  int get hashCode => Object.hash(workspaceDir, branch, baseBranch);

  @override
  String toString() => 'Workspace($workspaceDir @ $branch → $baseBranch)';
}

/// A capability backed by a spawned, supervised process. The carrier owns
/// `provider.start/stop`; the capability is PURE description.
abstract class ProcessCapability extends Capability {
  /// Const-constructible (capabilities are stateless description).
  const ProcessCapability();

  /// Describes the process to spawn — PURE; the host owns the actual
  /// `provider.start` (and layers the per-incarnation env over the config).
  /// Called synchronously at kick (the branch is mounted): read ambient values
  /// from [context] here with the effect verb.
  RuntimeConfig spawn(TreeContext context, StepArgs args);

  /// Maps a runtime [event] to a [StepSignal] (a job's clean exit → `complete`;
  /// a daemon's up-signal → `ready`; a crash → `failed`; anything else →
  /// `none`). The host writes the resulting cursor state through the chokepoint.
  StepSignal interpretEvent(RuntimeEvent event);

  /// An optional result payload this process step contributes on a clean
  /// completion (e.g. a critic's grade). Called by the host on a `complete`
  /// signal; the returned map is recorded under `grid.result.<nodePath>.*`
  /// alongside the terminal `state=complete` write (one atomic chokepoint
  /// update). Defaults to null (no result). MUST be idempotent + side-effect-free
  /// beyond reading its inputs (e.g. a file the spawned process wrote); read
  /// [context] at entry and check [StepArgs.cancel] after any await.
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async =>
      null;

  /// Idempotent belt-and-braces cleanup on unmount (TEARDOWN-11/12) — e.g.
  /// `pkill` a detached side-process by token. Defaults to a no-op (the host's
  /// `provider.stop` kills the managed group). Runs on the dispose path, where
  /// the branch may already be unmounted — so it receives NO tree context (a
  /// lookup there would throw); it works from [args] + its own state.
  Future<void> teardown(StepArgs args) async {}

  /// Proves a prior incarnation at [fence] is STILL the live effect this
  /// capability manages — the daemon adopt-freshness half (ADR-0009 D4:
  /// "pgid alive ∧ token echoed over its endpoint"). The engine supplies the
  /// pgid-alive half (the injected liveness seam); this supplies the
  /// domain-specific half (a daemon probes its endpoint and checks the token
  /// echoes). **No-adopt-on-faith**: the default is `false`, so a job — or a
  /// daemon that cannot prove it — is respawned fresh, never adopted blind.
  /// MUST be side-effect-free beyond the read.
  Future<bool> proveFreshness(
    AdoptFence fence,
    TreeContext context,
    StepArgs args,
  ) async =>
      false;

  /// The default [Allocation] for a spawned process (ADR-0009 D6) — a
  /// [ProcessAllocation] driving [spawn]/[interpretEvent] over the transport.
  /// A one-shot (`StepKind.job`) is respawn-or-skip; a `StepKind.daemon` is
  /// adopt-or-respawn + detach-capable. Override only for a bespoke process
  /// effect.
  @override
  Allocation createAllocation(AllocationContext ctx) =>
      ProcessAllocation(this, ctx);
}

/// A capability backed by an async body driving [ServiceBundle] collaborators
/// (git/PR orchestration, the Burn coordinator). No process lifecycle; its
/// [run] resolves to a [StepOutcome].
abstract class ServiceCapability extends Capability {
  /// Const-constructible.
  const ServiceCapability();

  /// Runs the capability body, resolving to its outcome. The host maps the
  /// outcome to a cursor write through the chokepoint. Read ambient values from
  /// [context] at entry; after every await, check [StepArgs.cancel] before
  /// touching the context again.
  Future<StepOutcome> run(TreeContext context, StepArgs args);

  /// Idempotent cleanup on unmount. Defaults to a no-op. Dispose-path: NO tree
  /// context (see [ProcessCapability.teardown]).
  Future<void> teardown(StepArgs args) async {}

  /// The default [Allocation] for an async service body (ADR-0009 D6) — the
  /// [ServiceAllocation]/`JobAllocation` convenience: start-runs, no adopt/
  /// detach/update, respawn-or-skip.
  @override
  Allocation createAllocation(AllocationContext ctx) =>
      ServiceAllocation(this, ctx);
}

/// What a runtime event means to a [ProcessCapability]. `ready` and `complete`
/// are POSITIVE TERMINALS (satisfy a `dependsOn`); `none` is "no cursor change".
enum StepSignal { none, ready, complete, failed }

/// The outcome of a [ServiceCapability.run].
sealed class StepOutcome {
  const StepOutcome();
}

/// The capability succeeded, optionally carrying a [payload] (e.g. a PR url) the
/// engine may record. Maps to `StepState.complete`.
class Ok extends StepOutcome {
  /// Creates a success, optionally carrying [payload].
  const Ok([this.payload]);

  /// An optional result payload (recorded on the session bead, never used as a
  /// pipeline signal).
  final Map<String, String>? payload;
}

/// The capability failed (routes to supervision). Maps to `StepState.failed`.
class Failed extends StepOutcome {
  /// Creates a failure with an optional [reason] (diagnostics).
  const Failed([this.reason = '']);

  /// A human-readable failure reason.
  final String reason;
}

/// The capability decided the work must PARK at a human gate (a hard block, a
/// grade spread, a human-ultimatum). The host writes `state=gated` (parks the
/// node + withholds its dependents) and mints a real `type=gate` bead in the
/// OWN state store via the chokepoint — never a write to the foreign work bead
/// (A37). Resolving that gate bead re-arms the node. D-7.
class Gate extends StepOutcome {
  /// Creates a gate park with an optional human-readable [reason].
  const Gate([this.reason = '']);

  /// Why the work parked at the gate (recorded on the minted gate bead).
  final String reason;
}

/// A cooperative cancellation flag a [Capability] polls across async gaps — set
/// when the host unmounts. The engine never force-kills a `ServiceCapability`
/// body; the capability checks [isCancelled] and unwinds. It is ALSO the
/// mounted-probe by proxy: cancelled ⟺ the host disposed, so an uncancelled
/// token means the tree context is still safe to read.
class CancelToken {
  bool _cancelled = false;

  /// Whether the owning host has unmounted (the capability should unwind).
  bool get isCancelled => _cancelled;

  /// Marks cancelled (called by the host on dispose).
  void cancel() => _cancelled = true;
}

/// A read-only view of THIS session's per-node cursor + results — an ambient
/// VALUE mounted by `SessionScope` (never a subscription/re-query — A39/
/// invariant 1). A `ServiceCapability` (e.g. `route`) reads its sibling steps'
/// terminal states + result payloads by looking this up with the effect verb —
/// the ONLY sibling-read affordance (no writer, no notifier; the derailment
/// gates hold). D-5, plumbing moved ambient 2026-07-02.
class SiblingView {
  /// Wraps this session's [cursor] (per-node states) + [results] (per-node
  /// result payloads).
  const SiblingView({this.cursor = const {}, this.results = const {}});

  /// Every inflated node's [NodeCursor] in this session, keyed by `nodePath`.
  final FormulaCursor cursor;

  /// Every node's recorded result payload, keyed by `nodePath`.
  final Map<String, Map<String, String>> results;

  /// The [NodeCursor] at [nodePath] (a default `pending` cursor for an
  /// unknown/never-run node).
  NodeCursor cursorOf(String nodePath) => cursor[nodePath] ?? const NodeCursor();

  /// The result payload at [nodePath] (an empty map for a node that recorded
  /// none).
  Map<String, String> resultOf(String nodePath) =>
      results[nodePath] ?? const {};
}

/// The pluggable collaborators a [Capability] drives (ADR-0008 D5) — ONE
/// concrete bundle (genesis's exact-type inherited lookup can't resolve an
/// abstract `<SourceControl>`), provided per-`SubstationScope`. Impls ship in
/// assets.
class ServiceBundle {
  /// Creates a bundle of optional collaborators.
  const ServiceBundle({this.sourceControl, this.trust, this.transport});

  /// Source control (commit/push/PR) — the git impl ships in the asset.
  final SourceControl? sourceControl;

  /// Reserved (OQ-7) — local/reputation/ledger trust, distinct from
  /// `genesis_consent`. Designed-to-be-lifted; null in P1.
  final Trust? trust;

  /// Reserved — the outbound exploration sink (no inbound pipeline handle);
  /// null in P1.
  final ExplorationTransport? transport;
}

/// The first [Service] — provision-workspace + commit/push/open-PR, abstracted
/// so the engine knows it in CONCEPT, not detail (the git impl ships in the
/// asset pack). Clean + dependency-free so a future genesis-shared home is a
/// move, not a rewrite (designed-to-be-lifted).
abstract interface class SourceControl {
  /// The workspace directory the effect runs in for [beadId] — where the host
  /// spawns its process and the land step commits/pushes from. The LAYOUT is the
  /// SourceControl's detail, NOT the engine's (ADR-0008 D5 / ADR-0007 §1: the
  /// engine's concept is "a workspace"; "one git worktree per bead, built from
  /// source" is this impl's opinion). Deterministic + pure (no I/O);
  /// [provisionWorkspace] is what actually creates it.
  String workspaceFor(String beadId);

  /// The branch [beadId]'s work is on (the git impl: `grid/<beadId>`).
  String branchFor(String beadId);

  /// The base branch a land opens its PR against (the substation's default
  /// branch — the git impl reads its root checkout's default branch).
  String get baseBranch;

  /// Materializes the workspace for [beadId] at [workspaceDir] (the git impl
  /// cuts a worktree off the root — ADR-0008 D5: "the git worktree is the
  /// `SourceControl` impl's way of provisioning"). The host calls this BEFORE the
  /// first process spawns into the workspace. MUST be idempotent: a no-op when
  /// [workspaceDir] already exists (verify/land reuse the agent's workspace) or
  /// when provisioning isn't wired (an offline build).
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  });

  /// Whether land (commit/push/PR) is wired. When false, the land capability
  /// no-ops to `Ok` — the early-arm posture (commit-only working agreement; land
  /// is a deliberate human follow-up). Provisioning is independent of this.
  bool get canLand;

  /// Commits all changes in [workspaceDir] with [message].
  Future<void> commitAll({required String workspaceDir, required String message});

  /// Pushes [branch] to [remote] from [workspaceDir], setting upstream.
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  });

  /// Opens a PR for [branch] against [baseBranch]; returns the ref, or null on
  /// failure (an honest "did not complete" — never throws for a normal refusal).
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  });
}

/// A reference to an opened pull request.
class PrRef {
  /// Wraps the PR [url].
  const PrRef(this.url);

  /// The PR url.
  final String url;
}

/// Reserved trust abstraction (OQ-7) — local/reputation/ledger; designed to be
/// lifted to a genesis-shared home. No members in P1.
abstract interface class Trust {}

/// Reserved outbound exploration transport — an emit-only sink, never an inbound
/// pipeline handle (invariant 1). The live arm adapts it over the exploration
/// host event stream leonard reads (A39/A40).
abstract interface class ExplorationTransport {
  /// Emits a fire-and-forget observability flare [name] with [data] to the
  /// out-of-band sink (the exploration host event stream the live arm adapts).
  /// Emit-only — NEVER an inbound pipeline handle (invariant 1). Must not throw to
  /// the caller in a way that breaks the flush (the host swallows errors). D-8.
  void flare(String name, Map<String, String> data);
}
