/// Several §9 comparison LANES behind one [ShadowCompare].
///
/// Stage 1 shadows two record families over two different legacy oracles: the
/// attempt lifecycle against the session bead (`AttemptLifecycleShadow`), the
/// step transitions against the step beads (`StepTransitionShadow`), plus the
/// mount-ordinal join (`MountOrdinalShadow`). They fold different projections
/// and read different beads, so they are separate strategies rather than one
/// widening comparator — and the verb takes exactly one strategy, so they
/// compose here.
///
/// Composition rules, all of them consequences of §9's "a run counts only if
/// it actually compared":
///
///   * `comparableFields` is the UNION, and a lane contributing nothing
///     contributes nothing to it — so the verb's "compares: …" line names
///     what was really compared;
///   * a lane that cannot compare at all (its ledger is absent) is carried as
///     an [unavailableReason] fragment, never dropped silently;
///   * a lane reporting itself incomplete disqualifies the SESSION while the
///     lanes that did compare keep their mismatches
///     ([ShadowCompareResult.partial]) — hiding an earned divergence behind
///     another lane's short read would be the same lie in the other
///     direction.
library;

import '../cli/traj_shadow_diff_command.dart';
import '../cli/trajectory_reader.dart';
import 'shadow_corroboration.dart';

/// Optional G2 lane routed into the station's incumbent comparator core.
///
/// The leaf package supplies only the invocation shape. The SDK/CLI adapter
/// owns engine types and calls `DualReadStepObserver.observeG2Round`, so this
/// callback never becomes a second [ShadowCompare] implementation.
typedef G2ShadowRoundCompare =
    Future<ShadowCompareResult> Function({
      required String sessionId,
      required SubjectRecords records,
      int? round,
      required ShadowCorroboration corroboration,
    });

/// The lane composition. Order is preserved into the report so a mismatch
/// list reads family by family.
class CompositeShadow implements ShadowCompare, ShadowDefaultScope {
  CompositeShadow(this.lanes, {G2ShadowRoundCompare? g2Compare})
    : _g2Compare = g2Compare;

  final List<ShadowCompare> lanes;
  final G2ShadowRoundCompare? _g2Compare;

  @override
  Set<String> get comparableFields => {
    for (final lane in lanes) ...lane.comparableFields,
    if (_g2Compare != null) ...const {
      'molecule_graph',
      'graph_apply_plan',
      'successor_relationship',
      'successor_depth',
    },
  };

  /// Null once ANY lane can compare something: the run is a real comparison
  /// of what that lane covers. The reasons of the lanes that cannot are still
  /// printed, so a half-armed window never reads as a whole one.
  @override
  String? get unavailableReason {
    final reasons = [
      for (final lane in lanes)
        if (lane.unavailableReason case final String reason)
          '${lane.runtimeType}: $reason',
    ];
    if (reasons.isEmpty) return null;
    if (comparableFields.isEmpty) return reasons.join('; ');
    return 'some lanes are dark — ${reasons.join('; ')}';
  }

  /// Combines the optional implicit-scope decisions supplied by the lanes.
  @override
  Future<ShadowDefaultSessionDisposition> defaultDispositionFor(
    String sessionId,
  ) async {
    for (final lane in lanes) {
      if (lane is! ShadowDefaultScope) continue;
      final defaultScope = lane as ShadowDefaultScope;
      final selected = switch (await defaultScope.defaultDispositionFor(
        sessionId,
      )) {
        ShadowDefaultSessionDisposition.compare => null,
        ShadowDefaultSessionDisposition.inFlight =>
          ShadowDefaultSessionDisposition.inFlight,
        ShadowDefaultSessionDisposition.voided =>
          ShadowDefaultSessionDisposition.voided,
      };
      if (selected != null) return selected;
    }
    return ShadowDefaultSessionDisposition.compare;
  }

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
    ShadowCorroboration corroboration = const ShadowCorroboration.none(),
  }) async {
    final mismatches = <ShadowMismatch>[];
    final incomplete = <String>[];
    for (final lane in lanes) {
      final result = await lane.compare(
        sessionId: sessionId,
        records: records,
        round: round,
        corroboration: corroboration,
      );
      mismatches.addAll(result.mismatches);
      if (result.incompleteReason case final String reason) {
        incomplete.add('${lane.runtimeType} — $reason');
      }
    }
    if (_g2Compare case final compare?) {
      final result = await compare(
        sessionId: sessionId,
        records: records,
        round: round,
        corroboration: corroboration,
      );
      mismatches.addAll(result.mismatches);
      if (result.incompleteReason case final String reason) {
        incomplete.add('G2 — $reason');
      }
    }
    if (incomplete.isEmpty) return ShadowCompareResult(mismatches);
    return ShadowCompareResult.partial(mismatches, incomplete.join('; '));
  }
}
