/// The opaque capability leaves + the pluggable Service seam (ADR-0008 D2/D5 /
/// M4-P1 §3, Track E).
///
/// The author implements a [Capability] (a [ProcessCapability] over a spawned
/// process, or a [ServiceCapability] over async collaborators) and NEVER a
/// `Seed`. A capability sees only the sandboxed [CapabilityContext] — no
/// `TreeContext`, no writer, no notifier, no `markNeedsRebuild` — so the four
/// derailment-invariants hold AT DEPTH by construction. The engine-private
/// `CapabilityHost` carrier owns the tree lifecycle (mount=spawn, dispose=kill);
/// the capability just describes what to run and how to read its events.
library;

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'allocation.dart';
import 'cursor.dart';

/// A leaf the engine mounts — either a [ProcessCapability] or a
/// [ServiceCapability]. Sealed so the carrier's dispatch is exhaustive; the two
/// flavors are open for an asset to implement.
sealed class Capability {
  const Capability();

  /// Mints the [Allocation] that holds this capability's live effect — the
  /// `createRenderObject` analogue (ADR-0009 D4). Synchronous + cheap; the Host
  /// then drives it asynchronously (`startOrAdopt`/`update`/`dispose`/`detach`).
  /// [ProcessCapability]/[ServiceCapability] supply defaults, so an existing
  /// capability needs no change; an asset overrides only to customize adopt/
  /// detach/update for a bespoke effect.
  Allocation createAllocation(AllocationContext ctx);
}

/// A capability backed by a spawned, supervised process (generalizes P0's
/// `AgentEffectSeed`/`VerifyEffectSeed`). The carrier owns `provider.start/stop`;
/// the capability is PURE description.
abstract class ProcessCapability extends Capability {
  /// Const-constructible (capabilities are stateless description).
  const ProcessCapability();

  /// Describes the process to spawn for [ctx] — PURE; the host owns the actual
  /// `provider.start` (and layers the per-incarnation env over the config).
  RuntimeConfig spawn(CapabilityContext ctx);

  /// Maps a runtime [event] to a [StepSignal] (a job's clean exit → `complete`;
  /// a daemon's up-signal → `ready`; a crash → `failed`; anything else →
  /// `none`). The host writes the resulting cursor state through the chokepoint.
  StepSignal interpretEvent(RuntimeEvent event);

  /// An optional result payload this process step contributes on a clean
  /// completion (e.g. a critic's grade). Called by the host on a `complete`
  /// signal; the returned map is recorded under `grid.result.<nodePath>.*`
  /// alongside the terminal `state=complete` write (one atomic chokepoint
  /// update). Defaults to null (no result). MUST be idempotent + side-effect-free
  /// beyond reading [ctx] (e.g. reading a file the spawned process wrote).
  Future<Map<String, String>?> result(CapabilityContext ctx) async => null;

  /// Idempotent belt-and-braces cleanup on unmount (TEARDOWN-11/12) — e.g.
  /// `pkill` a detached side-process by token. Defaults to a no-op (the host's
  /// `provider.stop` kills the managed group).
  Future<void> teardown(CapabilityContext ctx) async {}

  /// Proves a prior incarnation at [fence] is STILL the live effect this
  /// capability manages — the daemon adopt-freshness half (ADR-0009 D4:
  /// "pgid alive ∧ token echoed over its endpoint"). The engine supplies the
  /// pgid-alive half (the injected liveness seam); this supplies the
  /// domain-specific half (a daemon probes its endpoint and checks the token
  /// echoes). **No-adopt-on-faith**: the default is `false`, so a job — or a
  /// daemon that cannot prove it — is respawned fresh, never adopted blind. A
  /// daemon capability (the M6 burn-follower) overrides this. MUST be
  /// side-effect-free beyond the read.
  Future<bool> proveFreshness(AdoptFence fence, CapabilityContext ctx) async =>
      false;

  /// The default [Allocation] for a spawned process (ADR-0009 D6) — a
  /// [ProcessAllocation] driving [spawn]/[interpretEvent] over the transport.
  /// A one-shot (`StepKind.job`) is respawn-or-skip; a `StepKind.daemon` is
  /// adopt-or-respawn + detach-capable (Track C). Override only for a bespoke
  /// process effect.
  @override
  Allocation createAllocation(AllocationContext ctx) =>
      ProcessAllocation(this, ctx);
}

/// A capability backed by an async body driving [ServiceBundle] collaborators
/// (generalizes P0's `LandEffectSeed`: git/PR orchestration, the Burn
/// coordinator). No process lifecycle; its [run] resolves to a [StepOutcome].
abstract class ServiceCapability extends Capability {
  /// Const-constructible.
  const ServiceCapability();

  /// Runs the capability body for [ctx], resolving to its outcome. The host maps
  /// the outcome to a cursor write through the chokepoint.
  Future<StepOutcome> run(CapabilityContext ctx);

  /// Idempotent cleanup on unmount. Defaults to a no-op.
  Future<void> teardown(CapabilityContext ctx) async {}

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
/// body; the capability checks [isCancelled] and unwinds.
class CancelToken {
  bool _cancelled = false;

  /// Whether the owning host has unmounted (the capability should unwind).
  bool get isCancelled => _cancelled;

  /// Marks cancelled (called by the host on dispose).
  void cancel() => _cancelled = true;
}

/// A read-only view of THIS session's per-node cursor + results, threaded down
/// (config, never a subscription/re-query — A39/invariant 1). A `ServiceCapability`
/// (e.g. `route`) reads its sibling steps' terminal states + result payloads
/// through this — the ONLY sibling-read affordance (no TreeContext/writer/notifier;
/// invariants 1/2 hold by construction). D-5.
class SiblingView {
  /// Wraps the threaded-down [cursor] (per-node states) + [results] (per-node
  /// result payloads) of this session.
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

/// The narrow, sandboxed projection a [Capability] leaf gets (M4-P1 §3): NO
/// `TreeContext`, NO writer, NO notifier, NO `markNeedsRebuild` — a read-only
/// slice. This is what holds invariants 1/2 at depth by construction.
class CapabilityContext {
  /// Bundles the step [params], the full work [bead] (so a capability — e.g. the
  /// agent — can author the rich, full-bead prompt), the [workspaceDir] the
  /// capability runs in (OQ-6: the stable home — was "worktree"), the [branch] /
  /// [baseBranch], the pluggable [services], the [cancel] token, this step's full
  /// [nodePath] (so a `route` can compute its sibling paths), the read-only
  /// [siblings] view (D-5), and the restoration [logFile] seam (deferred).
  const CapabilityContext({
    required this.params,
    required this.bead,
    required this.workspaceDir,
    required this.branch,
    required this.baseBranch,
    required this.services,
    required this.cancel,
    required this.nodePath,
    this.siblings = const SiblingView(),
    this.logFile,
  });

  /// The step's opaque params (from the `CapabilityStep`/`SubFormulaStep`).
  final Map<String, String> params;

  /// The full work bead this capability serves (title/description/design/
  /// acceptance/notes/metadata) — a read-only value, the load-bearing input to
  /// the agent's prompt. Threaded down from `WorkBead` via the inflater (never a
  /// re-query — A39).
  final Bead bead;

  /// The work bead id (`bead.id`) — the cursor key + provider-name root segment.
  String get beadId => bead.id;

  /// The stable home directory the capability runs in (the cwd default;
  /// per-spawn overridable via `RuntimeConfig.workingDirectory`). OQ-6: the
  /// engine concept is `workspace`; "git worktree" is the git `SourceControl`
  /// impl's way of provisioning it.
  final String workspaceDir;

  /// The branch the work is on (`grid/<beadId>`).
  final String branch;

  /// The base branch a land opens its PR against.
  final String baseBranch;

  /// The pluggable collaborators (source control, trust, transport).
  final ServiceBundle services;

  /// The cooperative cancellation token (set when the host unmounts).
  final CancelToken cancel;

  /// This step's FULL path within the formula tree (`'$parentNodePath/$stepId'`)
  /// — a `route` step computes its sibling critic paths off this.
  final String nodePath;

  /// The read-only view of THIS session's sibling cursors + results, threaded
  /// down pull-free (D-5) — the only way a `ServiceCapability` reads its
  /// siblings' grades without a subscription/re-query (invariants 1/2).
  final SiblingView siblings;

  /// The durable log file for the deferred adopt-a-live-process seam (§11);
  /// null until restoration ships.
  final String? logFile;
}

/// The pluggable collaborators a [Capability] drives (ADR-0008 D5) — ONE
/// concrete bundle (genesis's exact-type inherited lookup can't resolve an
/// abstract `<SourceControl>`), provided stably above `Station`. Impls ship in
/// assets (Track H wires the git `SourceControl`).
class ServiceBundle {
  /// Creates a bundle of optional collaborators.
  const ServiceBundle({this.sourceControl, this.trust, this.transport});

  /// Source control (commit/push/PR) — today's git ops migrate IN (Track H).
  final SourceControl? sourceControl;

  /// Reserved (OQ-7) — local/reputation/ledger trust, distinct from
  /// `genesis_consent`. Designed-to-be-lifted; null in P1.
  final Trust? trust;

  /// Reserved — the outbound exploration sink (no inbound pipeline handle);
  /// null in P1.
  final ExplorationTransport? transport;
}

/// The first [Service] — provision-workspace + commit/push/open-PR, abstracted
/// so the engine knows it in CONCEPT, not detail (the git impl ships in
/// `station_grid_assets`, Track H). Clean + dependency-free so a future
/// genesis-shared home is a move, not a rewrite (designed-to-be-lifted).
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
