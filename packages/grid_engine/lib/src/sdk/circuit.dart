/// The reentrant authoring surface (ADR-0008 D4 / M4-P1 Track A).
///
/// A [Circuit] is the value-typed step-graph the engine energizes (electrifies)
/// — inflates — into a reconciled subtree on `genesis_tree` — the depth-analogue
/// of the work lifecycle. The author composes value-types ([Circuit] / [CircuitStep]) +
/// opaque `Capability` leaves and **never a `Seed`**; that is what holds the
/// four derailment-invariants AT DEPTH by construction (ADR-0008 D2).
///
/// Two serializations of ONE shape (freezed + `json_serializable`): authored in
/// Dart today, or inflated from a TOML pack later (the `PackInflater` is
/// deferred — M4-P1 §11). The JSON round-trip is the offline proof of that one
/// shape.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'capability_facts.dart';

part 'circuit.freezed.dart';
part 'circuit.g.dart';

/// The lifetime of a leaf step (M4-P1 §3 / OQ-1).
///
/// A [job] runs to completion then retires (its `complete` satisfies a
/// `dependsOn`, then the keyed-reconcile prunes its host). A [daemon] stays
/// mounted after it signals `ready` (a harness, an mDNS advertiser) — its
/// `ready` satisfies a `dependsOn` while the process keeps running; its later
/// death writes a non-positive cursor (OQ-5) that re-closes the barrier.
///
/// Named `daemon` (not `service`) to avoid colliding with the pluggable
/// `Service` seam / `ServiceCapability`.
enum StepKind {
  /// Runs once to completion, then retires (pruned from the frontier).
  job,

  /// Stays mounted after signalling `ready` (a long-lived process).
  daemon,
}

/// The cursor state of one inflated node (M4-P1 §3).
///
/// `ready` AND `complete` are the two POSITIVE TERMINALS that satisfy a
/// `dependsOn`: a [StepKind.job] satisfies on [complete] then is pruned; a
/// [StepKind.daemon] satisfies on [ready] while staying mounted. [failed] routes
/// to supervision (re-key within budget, or escalation when exhausted).
enum StepState {
  /// Not yet started (no host mounted, or never spawned).
  pending,

  /// A host is mounted and the process is live (pre-terminal).
  running,

  /// A daemon signalled it is up — a positive terminal that satisfies a dep
  /// while the daemon stays mounted.
  ready,

  /// A job ran to completion — a positive terminal that satisfies a dep, then
  /// the job retires.
  complete,

  /// The step failed — routes to supervision (D-5).
  failed,

  /// Parked at a human gate — a NON-positive, non-failed terminal-ish state: it
  /// does not satisfy a `dependsOn`, is not retired, is not circuit-broken, and
  /// does not re-mount until the gate resolves — D-7.
  gated,
}

/// How a [Circuit] supervises a failed child (M4-P1 §3 / D-5).
///
/// Only [oneForOne] is exercised by the agent/verify/land `code` circuit; the
/// Burn uses [restForOne] (re-key the failed step ∪ its transitive dependents).
/// [oneForAll] is reserved.
enum SupervisionStrategy {
  /// Restart only the failed step.
  oneForOne,

  /// Restart the failed step and its transitive dependents.
  restForOne,

  /// Restart the whole circuit subtree.
  oneForAll,
}

/// The mandatory backoff schedule for a supervised restart (M4-P1 §3 / D-5).
///
/// Spawns cost minutes and tokens, so backoff is never optional. The cooldown
/// for restart attempt `n` (1-based) is `min * factor^(n-1)`, clamped to [max].
@freezed
abstract class Backoff with _$Backoff {
  /// Creates a backoff with a [min]/[max] window and growth [factor].
  const factory Backoff({
    /// The first cooldown (and the floor).
    required Duration min,

    /// The ceiling — the cooldown never exceeds this.
    required Duration max,

    /// The geometric growth factor between attempts (≥ 1).
    @Default(2.0) double factor,
  }) = _Backoff;

  const Backoff._();

  /// The default schedule — 1s → 60s, doubling.
  static const Backoff standard = Backoff(
    min: Duration(seconds: 1),
    max: Duration(seconds: 60),
  );

  factory Backoff.fromJson(Map<String, dynamic> json) => _$BackoffFromJson(json);

  /// The cooldown before restart attempt [attempt] (1-based), `min * factor^(n-1)`
  /// clamped to [max]. A non-positive [attempt] yields [min].
  Duration delayFor(int attempt) {
    if (attempt <= 1) return min;
    var ms = min.inMilliseconds.toDouble();
    for (var i = 1; i < attempt; i++) {
      ms *= factor;
      if (ms >= max.inMilliseconds) return max;
    }
    return Duration(milliseconds: ms.round());
  }
}

/// A declared, statically-inspectable resource peak (M4-P1 §3 / D-7).
///
/// Declaration-only in P1: the `DartEnvironment` governor + leaf-permit
/// acquisition are a separate, optional track the Burn does NOT block on (D-7).
/// Carried on [Circuit.peak] (the aggregate) and [CapabilityStep.resources] (the
/// per-leaf request) so a future governor can check both without a shape change.
@freezed
abstract class ResourceRequest with _$ResourceRequest {
  /// Creates a request for [builds] concurrent builds and [processes] live
  /// processes.
  const factory ResourceRequest({
    @Default(0) int builds,
    @Default(0) int processes,
  }) = _ResourceRequest;

  factory ResourceRequest.fromJson(Map<String, dynamic> json) =>
      _$ResourceRequestFromJson(json);
}

/// One step in a [Circuit] — a sealed union the inflater maps to a child Seed
/// (M4-P1 §3 / §4).
///
/// - [CapabilityStep] → a `CapabilityHost` (an opaque `Capability` leaf);
/// - [SubCircuitStep] → a nested `CircuitScope` (REENTRANCY: the SAME inflater
///   one level down).
///
/// `FanOutStep` (keyed dynamic-but-bounded) is deferred to dynamic planning
/// (OQ-2 / §11) — the 2-device Burn uses explicit [SubCircuitStep]s. Every step
/// carries [stepId], [params], and [dependsOn] (the barrier IS multiple deps);
/// a dep names a sibling step id, and is satisfied only by that step's POSITIVE
/// TERMINAL (a job `complete` or a daemon `ready`; a sub-circuit dep resolves to
/// its terminal-step descendant).
@Freezed(unionKey: 'type', unionValueCase: FreezedUnionCase.snake)
sealed class CircuitStep with _$CircuitStep {
  /// A leaf step resolved to an opaque `Capability` via the `CapabilityRegistry`.
  @FreezedUnionValue('capability')
  const factory CircuitStep.capability({
    /// The step's id (unique within its circuit).
    required String stepId,

    /// The capability id resolved via the `CapabilityRegistry`.
    required String capabilityId,

    /// Opaque parameters threaded to the capability leaf.
    @Default(<String, String>{}) Map<String, String> params,

    /// The sibling step ids whose positive terminals gate this step (the
    /// barrier).
    @Default(<String>{}) Set<String> dependsOn,

    /// Whether this leaf runs-to-completion ([StepKind.job]) or stays mounted
    /// ([StepKind.daemon]).
    @Default(StepKind.job) StepKind kind,

    /// The per-leaf resource request (declared-now, honored-later — D-7).
    ResourceRequest? resources,

    /// The per-leaf declared CAPABILITY REQUIREMENT (the honesty-pass D-A3/D-B5,
    /// 2026-07-03) — e.g. `{system-os: linux, radio: ble}` (the Burn's
    /// `Req macOS+BLE` / `Req Linux+BLE` split: ONE bead's fan-out is
    /// PER-REQUIREMENT, never per-bead). Null/empty (the overwhelming default)
    /// means "no declared requirement" — the step always resolves to its LOCAL
    /// capability, today's P1-only behavior, unchanged. A non-empty [requires]
    /// is checked by CONTAINMENT against the station's own [CapabilityFacts]
    /// at the `CapabilityRegistry` resolution seam: a match still resolves
    /// locally; a mismatch resolves to an asset-provided claim+lease capability
    /// instead of a local spawn (local-vs-remote is a resolver decision — the
    /// engine names no bus, D-B5).
    @CapabilityFactsConverter() CapabilityFacts? requires,
  }) = CapabilityStep;

  /// A reentrant step inflated by the SAME inflater one level down.
  @FreezedUnionValue('sub_circuit')
  const factory CircuitStep.subCircuit({
    /// The step's id (unique within its circuit).
    required String stepId,

    /// The id of the nested circuit (resolved via the `CapabilityRegistry`).
    required String circuitId,

    /// Opaque parameters threaded to the nested circuit.
    @Default(<String, String>{}) Map<String, String> params,

    /// The sibling step ids whose positive terminals gate this step.
    @Default(<String>{}) Set<String> dependsOn,
  }) = SubCircuitStep;

  const CircuitStep._();

  factory CircuitStep.fromJson(Map<String, dynamic> json) =>
      _$CircuitStepFromJson(json);

  // [stepId], [params], and [dependsOn] are declared in every union case, so
  // freezed exposes them on this sealed base directly — no hand-written getters.
}

/// A declared step-graph the engine inflates into a reconciled subtree
/// (M4-P1 §3 — the reentrant unit).
///
/// The agent/verify/land `code` circuit is the degenerate linear case whose
/// always-1-wide frontier reproduces P0 byte-for-byte (§6); the Burn is the
/// multi-step fan-out + barrier + long-lived-daemon stress case (§9).
@freezed
abstract class Circuit with _$Circuit {
  /// Creates a circuit [id]'d over [steps], with [terminalStepId] (its host's
  /// positive terminal closes the session — D-2), a [supervision] strategy, a
  /// mandatory [backoff], a restart budget [maxRestarts], and an optional
  /// declared resource [peak].
  const factory Circuit({
    /// The circuit id (resolved via the `CapabilityRegistry` for a sub-circuit).
    required String id,

    /// The step-graph.
    required List<CircuitStep> steps,

    /// The terminal step — its positive terminal drives the session close
    /// (D-2). A `dependsOn` on this circuit (as a sub-circuit) resolves here.
    required String terminalStepId,

    /// How a failed child is supervised (default [SupervisionStrategy.oneForOne]).
    @Default(SupervisionStrategy.oneForOne) SupervisionStrategy supervision,

    /// The mandatory restart backoff (default [Backoff.standard]).
    @Default(Backoff.standard) Backoff backoff,

    /// The supervised-restart budget per step — beyond it the breaker trips and
    /// the step is circuit-broken (escalation, D-5).
    @Default(3) int maxRestarts,

    /// The declared aggregate resource peak (declaration-only — D-7).
    ResourceRequest? peak,
  }) = _Circuit;

  const Circuit._();

  factory Circuit.fromJson(Map<String, dynamic> json) =>
      _$CircuitFromJson(json);

  /// The step with [stepId], or null when absent (a dangling `dependsOn` /
  /// `terminalStepId` resolves to null — the predicate treats that as
  /// unsatisfiable, fail-closed).
  CircuitStep? stepById(String stepId) {
    for (final step in steps) {
      if (step.stepId == stepId) return step;
    }
    return null;
  }
}
