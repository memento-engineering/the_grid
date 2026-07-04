/// The STATION-WIDE unclaimed-frontier hook (D-B5 hook #1, the honesty-pass,
/// 2026-07-03) — the engine-private wiring over the pure [unclaimedSteps]
/// predicate (`sdk/claim.dart`).
///
/// D-A3's claim flow: whatever is still unclaimed **at the end of a
/// reconciliation phase** is broadcast for pickup by a peer station. This file
/// is the "end of a reconciliation phase" half: [stationUnclaimedFrontier]
/// aggregates every LIVE session's unclaimed steps from the SAME
/// [JoinedSnapshot] the kernel already holds after a flush — no extra
/// subscription, no re-query (A39) — and [StationKernel] calls it once per
/// flush cycle (mirroring its existing cooldown scan) so a composed asset's
/// `onUnclaimedFrontier` callback sees a fresh snapshot each time. Still no
/// transport, no bus: what the callback does with the list is the asset's
/// affair entirely.
library;

import '../domain/joined_snapshot.dart';
import '../sdk/capability_facts.dart';
import '../sdk/claim.dart';
import 'capability_registry.dart';
import 'circuit_resolver.dart';

/// One session's unclaimed requirement — [step] (the pure per-circuit record)
/// plus which session/work bead it belongs to, so a claim capability can
/// correlate a broadcast reply back to the right node.
class UnclaimedRequirement {
  /// Creates a station-level unclaimed-requirement record.
  const UnclaimedRequirement({
    required this.sessionId,
    required this.workBeadId,
    required this.step,
  });

  /// The_grid's OWN session bead id this requirement's cursor lives on (the
  /// target a claim capability's eventual result write targets).
  final String sessionId;

  /// The work bead this session drives (the JOIN key `SessionProjection`
  /// carries).
  final String workBeadId;

  /// The unclaimed step itself (nodePath/stepId/capabilityId/requires).
  final UnclaimedStep step;

  @override
  bool operator ==(Object other) =>
      other is UnclaimedRequirement &&
      other.sessionId == sessionId &&
      other.workBeadId == workBeadId &&
      other.step == step;

  @override
  int get hashCode => Object.hash(sessionId, workBeadId, step);

  @override
  String toString() =>
      'UnclaimedRequirement(session: $sessionId, workBead: $workBeadId, $step)';
}

/// Aggregates [unclaimedSteps] across every LIVE (non-terminal) session in
/// [snapshot] — the unit [StationKernel] computes once per reconciliation
/// phase and hands to its `onUnclaimedFrontier` hook (D-B5 hook #1).
///
/// Resolves each session's ROOT circuit via [rootCircuitFor] — the SAME
/// bead→circuit policy [CircuitResolver] roots the live tree with — and its
/// nested circuits via [registry.circuit]; [registry.now] gates the same
/// backoff-cooldown clock the frontier predicate reads elsewhere, so a step
/// mid-cooldown is consistently excluded from both the mount frontier AND the
/// unclaimed set. A session whose work bead is momentarily absent from the
/// joined graph contributes nothing (fail-closed, mirroring the frontier's own
/// dangling-dep posture) rather than throwing mid-scan.
List<UnclaimedRequirement> stationUnclaimedFrontier(
  JoinedSnapshot snapshot, {
  required RootCircuitFor rootCircuitFor,
  required CapabilityRegistry registry,
  required CapabilityFacts stationFacts,
}) {
  final now = registry.now();
  final unclaimed = <UnclaimedRequirement>[];
  for (final session in snapshot.sessionsByWorkBead.values) {
    if (session.isTerminal) continue;
    final bead = snapshot.graph.beadsById[session.workBeadId];
    if (bead == null) continue;
    final root = rootCircuitFor(bead);
    final steps = unclaimedSteps(
      root,
      session.cursor,
      session.workBeadId,
      stationFacts: stationFacts,
      circuitById: registry.circuit,
      now: now,
    );
    for (final step in steps) {
      unclaimed.add(
        UnclaimedRequirement(
          sessionId: session.sessionId ?? '',
          workBeadId: session.workBeadId,
          step: step,
        ),
      );
    }
  }
  return unclaimed;
}
