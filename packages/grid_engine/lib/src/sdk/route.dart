/// Routing as a first-class engine primitive — ONE route verb, THREE verdicts,
/// and the TWO domain-bound targets (`docs/M5-THE-CIRCUIT-BUILD-ORDER.md` D-4a,
/// RATIFIED 2026-07-12).
///
/// A [RouteCapability] returns a [RouteVerdict] — a DISTINCT sealed type, NOT a
/// [StepOutcome] arm. An ordinary step SUCCEEDS or FAILS (`{Ok, Failed}`); a
/// build agent does not route. THEN a route decides what the circuit does next:
///
/// - [Advance]  — move the cursor forward. At the ROOT circuit's TERMINAL step
///   ([isDeliveryTerminal]) an advance ACTUATES the bound [DeliveryMethod];
///   delivery is the ACTUATION of a terminal advance, never a verdict of its own.
/// - [Rewind]   — re-run a sub-DAG of the routing node's OWN circuit (the A47
///   mechanics, re-homed here UNCHANGED: two incarnation axes, the sub-DAG
///   re-key, the `kMaxReworkRounds` belt).
/// - [Escalate] — the router declines; raise to the bound [EscalationHandler].
///
/// **The doctrine.** The engine owns the VERBS (advance / rewind / escalate +
/// actuate-the-terminal-delivery); the ASSET owns the TARGETS (the delivery
/// destination, the escalation authority), bound per-substation on the
/// [ServiceBundle] (ADR-0008 Decision 5: the engine knows a domain in CONCEPT,
/// never in DETAIL). [Rewind] is the only fully engine-internal verb.
///
/// The ROUTER is `CapabilityHost` — the ONE seam that effects a verdict, through
/// the ONE bd chokepoint, onto the_grid's OWN session bead (A37). A route never
/// writes (ADR-0009 Decision 3, invariant 2), exactly like every other capability.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'allocation.dart';
import 'capability.dart';
import 'circuit.dart';

/// What a [RouteCapability] decided — the ONE route primitive's output.
sealed class RouteVerdict {
  /// Const-constructible (a verdict is a value).
  const RouteVerdict();
}

/// Move the cursor FORWARD: this node completes and its dependents unblock.
///
/// At the ROOT circuit's terminal step ([isDeliveryTerminal]) an advance ALSO
/// actuates the substation's bound [DeliveryMethod] — the receipt is recorded
/// alongside the terminal `state=complete` in ONE chokepoint write. With NO
/// method bound the terminal advance simply completes: the commit-only posture.
class Advance extends RouteVerdict {
  /// Advances, optionally carrying a [payload] (e.g. the committee's grades),
  /// recorded under `grid.result.<nodePath>.*`.
  const Advance([this.payload]);

  /// An optional result payload (recorded on the session bead, never a pipeline
  /// signal).
  final Map<String, String>? payload;
}

/// Re-run a sub-DAG of the rewinding node's OWN circuit — routing's lossy arm,
/// re-homed off [StepOutcome] onto the verdict, UNCHANGED (A47).
///
/// The router flips the named SIBLING steps, every node transitively DOWNSTREAM
/// of them, and THIS node back to `state=pending` with a bumped per-node
/// `rewindCount`, in ONE write through the chokepoint. The bump RE-KEYS each
/// node, so keyed reconcile disposes (kills) the old incarnations and the sub-DAG
/// re-runs VIRGIN — with NO gate bead and NO session re-mint.
///
/// BOUNDED: the router REFUSES a rewind from a node whose own `rewindCount` has
/// reached `kMaxReworkRounds` and [Escalate]s to the bound handler instead (whose
/// default parks for a human), so a mis-specified route can never spin the loop.
/// [stepIds] must name steps of the rewinding node's OWN circuit; an empty or
/// dangling name is an authoring bug and routes to a supervised [Failed] — never
/// a silent no-op.
class Rewind extends RouteVerdict {
  /// Rewinds the sibling steps [stepIds] (plus their transitive dependents and
  /// this node), carrying a human-readable [reason] (flared + recorded as
  /// diagnostics; the engine NEVER parses it).
  const Rewind(this.stepIds, [this.reason = '']);

  /// The sibling step ids to re-run (in the rewinding node's own circuit).
  final Set<String> stepIds;

  /// Why the work rewound (diagnostics/telemetry only).
  final String reason;
}

/// The router DECLINES: raise to the substation's bound [EscalationHandler].
///
/// UNBOUND ⇒ [HumanGate], the M5 D-7 default (park `gated` + mint a real
/// `type=gate` bead in the OWN state store). The engine hardcodes NO authority —
/// the HANDLER BINDING is the seam a parent-router / governor-queue drops into
/// later with no engine change.
class Escalate extends RouteVerdict {
  /// Escalates with a human-readable [reason] (recorded on the park; never
  /// parsed).
  const Escalate([this.reason = '']);

  /// Why the route declined.
  final String reason;
}

/// A capability whose whole job is to ROUTE: it reads its siblings' terminal
/// states + results (the ambient [SiblingView] — M5 D-5's sibling-read
/// affordance) and emits exactly ONE [RouteVerdict].
///
/// It never spawns (that is a [ProcessCapability]), never writes, never
/// subscribes. The `CapabilityRegistry` resolves it exactly like any other
/// capability — dispatch is polymorphic through [createAllocation], so the
/// registry, the inflater and the frontier need NO change.
abstract class RouteCapability extends Capability {
  /// Const-constructible (capabilities are stateless description).
  const RouteCapability();

  /// Decides the verdict. Read ambient values from [context] at ENTRY (the
  /// effect verb — `getInheritedSeedOfExactType`); after every await, check
  /// [StepArgs.cancel] before touching the context again. A THROWING body routes
  /// to supervision as a [Failed] (the per-work fail-closed posture, ADR-0008
  /// Decision 10) — never an unhandled zone error.
  Future<RouteVerdict> route(TreeContext context, StepArgs args);

  /// Idempotent cleanup on unmount. Defaults to a no-op. Dispose-path: NO tree
  /// context (a lookup there would throw).
  Future<void> teardown(StepArgs args) async {}

  /// The default [Allocation] for a route (ADR-0009 Decision 4/6) —
  /// [RouteAllocation].
  @override
  Allocation createAllocation(AllocationContext ctx) =>
      RouteAllocation(this, ctx);
}

/// The **route family** (ADR-0009 Decision 6's graduated conveniences) — drives a
/// [RouteCapability]'s body once and reports its verdict. Not a process: it holds
/// no group to reap; `dispose` cancels the cooperative token and runs teardown.
class RouteAllocation extends Allocation {
  /// Creates the route allocation for [capability] under [context].
  RouteAllocation(this.capability, super.context);

  /// The pure route capability whose body this drives.
  final RouteCapability capability;

  @override
  Future<void> startOrAdopt() async {
    state = AllocationState.live;
    // A THROWING body routes to supervision as a failure — never an unhandled
    // zone error (ADR-0008 Decision 10, the per-work fail-closed posture).
    final RouteVerdict verdict;
    try {
      verdict = await capability.route(context.treeContext, context.args);
    } on Object catch (e) {
      state = AllocationState.gone;
      if (!context.args.cancel.isCancelled) {
        context.sink(AllocationFailed('route threw: $e'));
      }
      return;
    }
    if (context.args.cancel.isCancelled) {
      state = AllocationState.gone;
      return;
    }
    state = AllocationState.gone;
    context.sink(_reportFor(verdict));
  }

  /// Maps a verdict to the report the ROUTER (the Host) persists.
  AllocationReport _reportFor(RouteVerdict verdict) => switch (verdict) {
    Advance(:final payload) => AllocationAdvanced(payload),
    Rewind(:final stepIds, :final reason) => AllocationRewound(stepIds, reason),
    Escalate(:final reason) => AllocationEscalated(reason),
  };

  @override
  Future<void> dispose() async {
    state = AllocationState.dying;
    context.args.cancel.cancel();
    try {
      await capability.teardown(context.args);
    } on Object {
      // A throwing teardown must not break unmount (no one left to report to).
    }
    state = AllocationState.gone;
  }
}

/// Whether the step [stepId] of [circuit] (rooted at [circuitPath]) is the
/// TERMINAL step of the ROOT circuit for [beadId] — the ONE node whose [Advance]
/// ACTUATES delivery.
///
/// PURE. The root circuit's own path IS the work bead id (`SessionScope` mounts
/// `CircuitScope(nodePath: bead.id)`), so "root" is `circuitPath == beadId`. A
/// SUB-circuit's terminal advance never delivers: only the work bead's own
/// terminal route closes the work out of the station.
bool isDeliveryTerminal({
  required Circuit circuit,
  required String circuitPath,
  required String stepId,
  required String beadId,
}) => circuitPath == beadId && circuit.terminalStepId == stepId;

/// The DOMAIN half of a TERMINAL [Advance] (ADR-0008 Decision 5 — the engine
/// knows a domain in CONCEPT, never in DETAIL). The engine knows only "actuate
/// the terminal delivery"; WHAT delivery means is the substation's: open a PR /
/// merge-queue / direct-merge for code (bead tg-hlz builds those three), commit-
/// a-chapter or export for a book, hand the artifact back for an agent
/// supporting an agent.
///
/// Bound per-substation via [ServiceBundle.delivery] (DI — ADR-0008 D-H: config =
/// VALUES in the tree, impls = DI). UNBOUND ⇒ commit-only: the terminal advance
/// still completes, nothing is delivered, nothing fails. "Is landing armed?"
/// becomes "which delivery method did this substation bind?", and none is a valid
/// binding.
///
/// It never writes (invariant 2) and never touches the tree: the router reads
/// every ambient value it needs SYNCHRONOUSLY at entry and hands them over as
/// VALUES on the [DeliveryRequest] (ADR-0013 items 1/4), so a long push/PR
/// round-trip can never race an unmount into a thrown tree lookup.
abstract interface class DeliveryMethod {
  /// This method's id — recorded under `grid.result.<nodePath>.delivery` (the
  /// audit record of HOW the work left the station).
  String get id;

  /// Actuates delivery for [request]. [Ok] optionally carries the RECEIPT (a PR
  /// url, an export path), merged into the terminal `state=complete` write under
  /// `grid.result.<nodePath>.*`. [Failed] routes the terminal route node to
  /// SUPERVISION: a failed delivery NEVER silently advances. A THROWING method is
  /// treated exactly as [Failed] (the per-work fail-closed posture).
  Future<StepOutcome> deliver(DeliveryRequest request);
}

/// Everything a [DeliveryMethod] gets — plain VALUES the router read from the
/// tree at entry (never a `TreeContext`, never a writer).
class DeliveryRequest {
  /// Bundles the work [bead], the OWN [sessionId], the terminal route's
  /// [nodePath], the per-session [workspace], and the terminal [Advance]'s
  /// [payload].
  const DeliveryRequest({
    required this.bead,
    required this.sessionId,
    required this.nodePath,
    required this.workspace,
    this.payload = const {},
  });

  /// The work bead being delivered (the ambient [Bead], mounted by `WorkBead`) —
  /// a CODE delivery method infers its PR title from this; a book's would not.
  final Bead bead;

  /// the_grid's OWN session bead id driving this work (A37).
  final String sessionId;

  /// The terminal route node's full path (the result-key namespace).
  final String nodePath;

  /// The per-session workspace the work happened in (the [SourceControl] impl's
  /// layout — the engine's concept is "a workspace").
  final Workspace workspace;

  /// The terminal [Advance]'s payload (e.g. the committee's grades) — an input a
  /// delivery method MAY use (a PR body) but never must.
  final Map<String, String> payload;
}

/// The DOMAIN target of an [Escalate] verdict (ADR-0008 Decision 5). The engine
/// RAISES; the bound handler DECIDES. Bound per-substation via
/// [ServiceBundle.escalation] — UNBOUND ⇒ [HumanGate], the M5 D-7 default. The
/// engine hardcodes no authority: a parent-router / governor-queue handler drops
/// in HERE with no engine change.
///
/// A handler never writes (invariant 2) and never touches the tree — it receives
/// VALUES and returns a DECISION the ONE router effects through the chokepoint.
/// It MAY do out-of-band I/O (POST to a queue) before deciding.
abstract interface class EscalationHandler {
  /// This handler's id — recorded on the `step.escalated` flare (the audit record
  /// of WHO the work was raised to).
  String get id;

  /// Decides how [request] is absorbed. A THROWING handler routes the node to
  /// SUPERVISION (the per-work fail-closed posture, ADR-0008 Decision 10).
  Future<EscalationDecision> escalate(EscalationRequest request);
}

/// What the router RAISED — plain VALUES (ADR-0013 item 2: the distinguishing
/// identity — here the spent [rewindCount] — rides IN the value; a handler never
/// re-derives it from a side channel).
class EscalationRequest {
  /// Bundles the work [beadId], the OWN [sessionId], the escalating [nodePath],
  /// the route's [reason], and the node's spent [rewindCount].
  const EscalationRequest({
    required this.beadId,
    required this.sessionId,
    required this.nodePath,
    required this.reason,
    required this.rewindCount,
  });

  /// The work bead the escalation is about.
  final String beadId;

  /// the_grid's OWN session bead id (A37).
  final String sessionId;

  /// The escalating route node's full path.
  final String nodePath;

  /// Why the route declined — the route's OWN words. The engine never parses it.
  final String reason;

  /// How many rework rounds this node already spent (`kMaxReworkRounds` is the
  /// belt) — the input a policy handler needs to tell "the route declined" from
  /// "the loop hit its cap".
  final int rewindCount;
}

/// What the bound handler decided — the arms the ROUTER effects.
sealed class EscalationDecision {
  /// Const-constructible (a decision is a value).
  const EscalationDecision();
}

/// PARK the node at a gate: `state=gated` + a real `type=gate` bead minted in
/// the_grid's OWN state store through the chokepoint (never the foreign work bead
/// — A37). The node withholds its dependents and re-arms when that gate bead
/// CLOSES (`SessionScope`'s M5 D-7 re-arm, untouched). [HumanGate] returns this —
/// reproducing D-7 EXACTLY.
class ParkAtGate extends EscalationDecision {
  /// Parks with a human-readable [reason] (recorded on the minted gate bead —
  /// what the resolving authority reads).
  const ParkAtGate([this.reason = '']);

  /// Why the work parked.
  final String reason;
}

/// The handler could NOT absorb the escalation: route the node to SUPERVISION
/// (bumped `restartCount` + backoff, then the breaker → `SessionScope`'s
/// exhaustion escalation). The DECLINE arm — LOUD, never a silent park nobody
/// owns (ADR-0008 Decision 3: LOUD or GONE).
class FailToSupervision extends EscalationDecision {
  /// Declines with a human-readable [reason] (persisted as the failure
  /// diagnostic).
  const FailToSupervision([this.reason = '']);

  /// Why the handler declined.
  final String reason;
}

/// The DEFAULT escalation binding (M5 D-7): raise to a HUMAN by parking at a real
/// `type=gate` bead. Stateless + const — the engine's ONLY handler; every other
/// authority ships in an asset.
class HumanGate implements EscalationHandler {
  /// Const-constructible.
  const HumanGate();

  @override
  String get id => 'human-gate';

  @override
  Future<EscalationDecision> escalate(EscalationRequest request) async =>
      ParkAtGate(request.reason);
}
