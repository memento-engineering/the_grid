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

import '../domain/mount_eligibility.dart';
import 'allocation.dart';
import 'cursor.dart';
import 'process_session.dart';
import 'route.dart';
import 'step_signal.dart';

export 'process_session.dart';
export 'step_signal.dart';

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

  /// The step's opaque params (from the `CapabilityStep`/`SubCircuitStep`).
  final Map<String, String> params;

  /// This step's FULL path within the circuit tree (`'$parentNodePath/$stepId'`)
  /// — the cursor key; its root segment is the work bead id.
  final String nodePath;

  /// The work bead id — the root segment of [nodePath] (the root circuit's
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

/// What a capability's FINISHED turn leaves behind — the capability's own
/// declared working agreement, and the thing that lets the engine PROVE a
/// completion (**no-complete-on-faith**, the dual of ADR-0009 D4/D5's
/// no-adopt-on-faith).
///
/// A detached one-shot exposes no readable exit code, so its vanish is reported
/// as an INFERRED clean exit (`Exited.inferred`) — and a MURDERED effect vanishes
/// exactly like a finished one. The engine can only tell them apart for a
/// capability that PROMISES an observable trace of a finished turn. A coding
/// agent promises a committed workspace after an inferred exit. An
/// artifact-writing critic promises its declared artifact after every exit;
/// workspace dirtiness cannot prove that promise because leaving an uncommitted
/// artifact IS its job.
///
/// So the contract is DECLARED, per capability, and defaults to [none]. The
/// engine holds the CONCEPT ("what does a finished turn leave behind?"); the
/// capability holds its own working agreement (ADR-0008 D5 / D2 — compose, never
/// subclass).
enum CompletionContract {
  /// **The default.** This capability promises NOTHING observable when it
  /// finishes, so its completion is taken at face value.
  none,

  /// This capability finishes by writing a declared artifact. Every completion
  /// is withheld until [ProcessCapability.probeCompletionArtifact] proves that
  /// artifact durable; an absent or unreadable artifact routes to supervision.
  artifactDurability,

  /// This capability's working agreement is **commit your work in the workspace**
  /// (the coding agent). A workspace left holding UNCOMMITTED work is therefore
  /// the observable trace of a turn CUT SHORT: an inferred completion over one is
  /// an INTERRUPTED turn, not a completion, and the step respawns.
  committedWorkspace,
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

  /// Creates a protocol session for this incarnation, or null for one-turn I/O.
  ProcessSession? createSession({
    required RuntimeProvider runtime,
    required String name,
    required String attemptId,
    required String instanceFence,
    required TreeContext context,
    required StepArgs args,
  }) => null;

  /// An optional result payload this process step contributes on a clean
  /// completion (e.g. a critic's grade). Called by the host on a `complete`
  /// signal; the returned map is recorded under `grid.result.<nodePath>.*`
  /// alongside the terminal `state=complete` write (one atomic chokepoint
  /// update). Defaults to null (no result). MUST be idempotent + side-effect-free
  /// beyond reading its inputs (e.g. a file the spawned process wrote); read
  /// [context] at entry and check [StepArgs.cancel] after any await.
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async => null;

  /// Proves the artifact promised by [CompletionContract.artifactDurability] is
  /// durably readable. Returns [GateOutcome.clear] only when durable,
  /// [GateOutcome.present] when absent, and [GateOutcome.probeError] when the read
  /// cannot decide. Must be idempotent and side-effect-free beyond reading the
  /// declared artifact.
  Future<GateOutcome> probeCompletionArtifact(
    TreeContext context,
    StepArgs args,
  ) async => GateOutcome.probeError;

  /// This capability's declared [CompletionContract] — what a FINISHED turn of it
  /// leaves behind, and so whether the engine may PROVE an INFERRED completion (a
  /// detached vanish) before advancing the circuit.
  ///
  /// Defaults to [CompletionContract.none]: NOT fenced and taken at face value.
  /// An artifact-writing critic overrides this with
  /// [CompletionContract.artifactDurability] and implements
  /// [probeCompletionArtifact]. A CODING AGENT — whose working agreement IS
  /// "commit your work in the worktree" — overrides this with
  /// [CompletionContract.committedWorkspace], and its inferred completions are
  /// then proven against the workspace's work signal before the circuit advances.
  CompletionContract get completionContract => CompletionContract.none;

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
  ) async => false;

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

/// The outcome of an ordinary capability body — `{Ok, Failed}` and nothing else.
///
/// A build agent does not ROUTE: it succeeds or it fails; THEN the committee's
/// [RouteCapability] decides (a distinct [RouteVerdict] — M5 D-4a). The `Gate`
/// and `Rewind` arms this union used to carry are now the [Escalate] and
/// [Rewind] VERDICTS, effected by the ONE router.
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
  const Failed([this.reason = '']) : nonResult = false;

  /// Creates a failure for a step that produced nothing to grade.
  const Failed.nonResult([this.reason = '']) : nonResult = true;

  /// A human-readable failure reason.
  final String reason;

  /// Whether the step produced no result rather than a bad result.
  final bool nonResult;
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
  final CircuitCursor cursor;

  /// Every node's recorded result payload, keyed by `nodePath`.
  final Map<String, Map<String, String>> results;

  /// The [NodeCursor] at [nodePath] (a default `pending` cursor for an
  /// unknown/never-run node).
  NodeCursor cursorOf(String nodePath) =>
      cursor[nodePath] ?? const NodeCursor();

  /// The result payload at [nodePath] (an empty map for a node that recorded
  /// none).
  Map<String, String> resultOf(String nodePath) =>
      results[nodePath] ?? const {};
}

/// The pluggable collaborators a [Capability] drives (ADR-0008 D5) — ONE
/// concrete bundle (genesis's exact-type inherited lookup can't resolve an
/// abstract `<SourceControl>`), provided per-`SubstationScope`. Impls ship in
/// assets.
///
/// [sourceControl] is the substation's source control (its ONE root — v3:
/// a substation names ONE root, so there is no per-bead root SELECTOR; a
/// bead's root is its substation's root, resolved bead → substation → root,
/// never a `metadata.grid.root` stamp).
class ServiceBundle {
  /// Creates a bundle of optional collaborators.
  const ServiceBundle({
    this.sourceControl,
    this.delivery,
    this.escalation,
    this.trust,
    this.trustFloor = const TrustFloor(TrustLevel.trusted),
    this.transport,
    this.mountEligibility,
  });

  const ServiceBundle._derived({
    required this.sourceControl,
    required this.delivery,
    required this.escalation,
    required this.trust,
    required this.trustFloor,
    required this.transport,
    required this.mountEligibility,
  });

  /// Derives a bundle from [base], replacing only non-null collaborators.
  ///
  /// Every field is forwarded through the all-required private constructor so
  /// adding a field produces a compile error until this single derivation site
  /// handles it.
  factory ServiceBundle.derive(
    ServiceBundle base, {
    SourceControl? sourceControl,
    DeliveryMethod? delivery,
    EscalationHandler? escalation,
    Trust? trust,
    TrustFloor? trustFloor,
    ExplorationTransport? transport,
    MountEligibilityPredicate? mountEligibility,
  }) => ServiceBundle._derived(
    sourceControl: sourceControl ?? base.sourceControl,
    delivery: delivery ?? base.delivery,
    escalation: escalation ?? base.escalation,
    trust: trust ?? base.trust,
    trustFloor: trustFloor ?? base.trustFloor,
    transport: transport ?? base.transport,
    mountEligibility: mountEligibility ?? base.mountEligibility,
  );

  /// Workspace provisioning for this substation's ONE root — the git impl ships
  /// in the asset.
  final SourceControl? sourceControl;

  /// This substation's bound DELIVERY METHOD — what a TERMINAL [Advance]
  /// ACTUATES (M5 D-4a). NULL ⇒ commit-only: the terminal advance completes and
  /// nothing is delivered (the posture the retired `--land` flag expressed as
  /// "unarmed"). The impl ships in the asset.
  final DeliveryMethod? delivery;

  /// This substation's bound ESCALATION HANDLER — where an [Escalate] verdict is
  /// raised. NULL ⇒ [HumanGate] (the M5 D-7 default: park + mint a `type=gate`
  /// bead). The engine hardcodes no authority.
  final EscalationHandler? escalation;

  /// This substation's trust resolver. It is used at intake, never by the mount
  /// guard; null makes an origin-stamped bead fail closed when guarded.
  final Trust? trust;

  /// This substation's minimum admitted origin trust.
  final TrustFloor trustFloor;

  /// Reserved — the outbound exploration sink (no inbound pipeline handle);
  /// null in P1.
  final ExplorationTransport? transport;

  /// This substation's optional per-bead content gate; null preserves the
  /// engine's existing permissive mount behavior. Implementations ship in assets.
  final MountEligibilityPredicate? mountEligibility;
}

/// The first [Service] — WORKSPACE PROVISIONING, abstracted so the engine knows
/// it in CONCEPT, not detail (the git impl ships in the asset pack). Clean +
/// dependency-free so a future genesis-shared home is a move, not a rewrite
/// (designed-to-be-lifted).
///
/// It NO LONGER commits/pushes/opens a PR (M5 D-4a): that is DELIVERY detail,
/// and it lives behind the substation's bound [DeliveryMethod]. The engine knows
/// only "actuate the terminal delivery" — it names no VCS verb beyond "give this
/// work a workspace to happen in".
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
}

/// An actor identity whose scheme and identifier are opaque to the engine.
class ActorIdentity {
  /// Creates an identity in [scheme] with opaque [id].
  const ActorIdentity({required this.scheme, required this.id});

  /// The producer-owned origin scheme; the engine never parses it.
  final String scheme;

  /// The producer-owned actor identifier; the engine never parses it.
  final String id;
}

/// Origin trust on the single admission axis, ordered least to most trusted.
enum TrustLevel { external, trusted, self }

/// The minimum origin trust a substation admits at its mount boundary.
class TrustFloor {
  /// Creates a floor at [level].
  const TrustFloor(this.level);

  /// The least [TrustLevel] that may mount.
  final TrustLevel level;
}

/// Resolves producer-owned actor identities for intake admission.
///
/// Ordinary bead metadata is forgeable by any holder of bead-write authority.
/// Signed origin stamps and their verification are outside this abstraction.
abstract interface class Trust {
  /// Resolves [actor] off the mount path; implementations may perform I/O.
  Future<TrustLevel> levelOf(ActorIdentity actor);
}

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
