/// The pure per-circuit claim predicate (the honesty-pass D-A3/D-B5,
/// `docs/SCRATCH-grid-alignment.md`, 2026-07-03).
///
/// D-A3's claim flow: a station tries to claim new work LOCALLY first;
/// whatever is still unclaimed at the end of a reconciliation phase is what an
/// asset claim capability broadcasts for pickup by a peer that fulfills the
/// requirement. Claims are **per-requirement** (capability slots), never
/// per-bead — one bead can fan out (the Burn: `Req macOS+BLE` claimed locally,
/// `Req Linux+BLE` unclaimed).
///
/// [unclaimedSteps] is the depth-analogue of [eligibleSteps] (`frontier.dart`):
/// the SAME eligible frontier, narrowed to the [CapabilityStep]s whose
/// declared [CapabilityStep.requires] the station's own [CapabilityFacts] do
/// NOT satisfy by containment (ADR-0011 D6). Zero I/O, deterministic, and
/// engine-observable only — NO transport, NO bus (D-B5): what an asset does
/// with an [UnclaimedStep] (broadcast it, log it, ignore it) is entirely its
/// own affair.
library;

import 'capability_facts.dart';
import 'circuit.dart';
import 'cursor.dart';
import 'frontier.dart';

/// One eligible step whose declared requirement the station cannot fulfill
/// locally (D-A3/D-B5) — the unit an asset claim capability broadcasts.
class UnclaimedStep {
  /// Creates an unclaimed-requirement record for the step at [nodePath].
  const UnclaimedStep({
    required this.nodePath,
    required this.stepId,
    required this.capabilityId,
    required this.requires,
  });

  /// The step's full path within its circuit tree (the cursor key).
  final String nodePath;

  /// The step's id within its circuit (unique among siblings, not globally).
  final String stepId;

  /// The capability id the step would resolve to LOCALLY were the requirement
  /// met — carried through so a claim capability can advertise what kind of
  /// work is on offer.
  final String capabilityId;

  /// The declared requirement the station's own profile does not satisfy —
  /// always non-empty (an empty/null requirement never appears here; see
  /// [unclaimedSteps]).
  final CapabilityFacts requires;

  @override
  bool operator ==(Object other) =>
      other is UnclaimedStep &&
      other.nodePath == nodePath &&
      other.stepId == stepId &&
      other.capabilityId == capabilityId &&
      other.requires == requires;

  @override
  int get hashCode => Object.hash(nodePath, stepId, capabilityId, requires);

  @override
  String toString() =>
      'UnclaimedStep($nodePath capabilityId: $capabilityId, requires: $requires)';
}

/// The UNCLAIMED subset of [circuit]'s eligible frontier under [cursor] at
/// [nodePath] (D-A3/D-B5 hook #1) — every [CapabilityStep] [eligibleSteps]
/// would mount whose declared [CapabilityStep.requires] the [stationFacts]
/// do NOT satisfy by containment ([CapabilityFacts.matches], ADR-0011 D6). A
/// step with no declared requirement (`requires` null or empty) is NEVER
/// unclaimed — it always resolves locally (today's P1-only behavior,
/// unchanged).
///
/// DESCENDS into an eligible [SubCircuitStep] exactly as `CircuitScope`'s
/// inflater does (the SAME reentrant walk, one level down, over the SAME flat
/// [cursor]): a [SubCircuitStep] carries no requirement of its own, but once
/// it is itself eligible (mounted) its nested circuit's OWN frontier is "in
/// play," so this recurses into it at the nested `nodePath`. An ineligible
/// step — including a [SubCircuitStep] withheld by the barrier — never
/// surfaces its nested leaves, mirroring the tree: nothing is mounted there
/// yet. An unresolvable sub-circuit id is skipped (fail-closed, matching
/// `CircuitScope`'s own skip).
///
/// Pure — mirrors [eligibleSteps]'s signature exactly, so a caller already
/// computing the frontier for mount purposes can compute this from the SAME
/// inputs.
List<UnclaimedStep> unclaimedSteps(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath, {
  required CapabilityFacts stationFacts,
  required Circuit? Function(String circuitId) circuitById,
  required DateTime now,
}) {
  final unclaimed = <UnclaimedStep>[];
  for (final step in eligibleSteps(
    circuit,
    cursor,
    nodePath,
    circuitById: circuitById,
    now: now,
  )) {
    switch (step) {
      case CapabilityStep(:final requires):
        if (requires != null &&
            !requires.isEmpty &&
            !CapabilityFacts.matches(stationFacts, requires)) {
          unclaimed.add(
            UnclaimedStep(
              nodePath: stepPath(nodePath, step.stepId),
              stepId: step.stepId,
              capabilityId: step.capabilityId,
              requires: requires,
            ),
          );
        }
      case SubCircuitStep(:final circuitId):
        final sub = circuitById(circuitId);
        if (sub == null) continue; // unresolvable — nothing to descend into.
        unclaimed.addAll(
          unclaimedSteps(
            sub,
            cursor,
            stepPath(nodePath, step.stepId),
            stationFacts: stationFacts,
            circuitById: circuitById,
            now: now,
          ),
        );
    }
  }
  return unclaimed;
}
