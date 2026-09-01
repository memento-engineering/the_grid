/// The §9 shadow comparator for the STEP family: fold the session's
/// `step.transition` records through P2 (`proj_step_cursor`), read the legacy
/// step beads through the injected [LegacyStepReader], and report typed
/// mismatches on the facts both sides genuinely hold.
///
/// **The reap asymmetry, stated once because everything below depends on it.**
/// Stage 1 does not retire `reapMolecule` (stage1-wiring §5 / schema §9 Stage
/// 2), so step beads are DELETED when a molecule is reaped while the
/// trajectory log keeps its rows forever. A fold row with no step bead behind
/// it is therefore the ordinary end state of every finished session, not
/// divergence — and this lane does not emit it. The other direction, a step
/// bead the fold never recorded, is exactly the missing-record class the
/// window exists to count, and it does emit.
///
/// That asymmetry is §9's incumbent rule applied honestly rather than
/// mechanically: the legacy path is the oracle, so what the oracle no longer
/// holds is not evidence against the fold.
///
/// **Which step_round.** P2 keys on `(session_id, round, step_path,
/// step_round)`; the legacy step bead is ONE bead per node path, mutated in
/// place. The comparable fold row is therefore the LATEST `(round,
/// step_round)` per path — the one the bead's current state corresponds to.
library;

import 'package:meta/meta.dart';

import '../cli/traj_shadow_diff_command.dart';
import '../cli/trajectory_reader.dart';
import '../fold/step_cursor_fold.dart';
import '../fold/step_cursor_row.dart';
// The unshadowable-field set and the classifier signature are ONE rule for
// every lane, and they were declared with the first lane. Imported rather
// than re-declared — two copies of §9's exclusion list is how the exclusion
// list drifts.
import 'attempt_lifecycle_shadow.dart'
    show ShadowMismatchClassifier, unshadowableMismatchFields;
import 'legacy_step_reader.dart';

/// The states this lane can order. `pending` precedes `running`, which
/// precedes every terminal-ish state — enough to answer "is the fold BEHIND
/// the ledger", which is the only ordering question the classifier asks.
/// A state outside the vocabulary orders as unknown and is never called a lag.
const Map<String, int> stepStateProgress = {
  'pending': 0,
  'running': 1,
  'gated': 2,
  'ready': 3,
  'complete': 3,
  'failed': 3,
};

/// A step that reached this state (or beyond) had a process incarnation
/// behind it, which is what makes a missing `attempt_id` on the fold row a
/// gap rather than a step that simply had not started yet.
const int _ranProgress = 1;

/// The step lane's classifier. Two named gaps live here:
///
///   * a fold that LAGS the ledger on presence or state is the
///     non-atomic-crash class (the append after a successful legacy write was
///     lost — §2.3's "at Stage 1 the recorder appends only on legacy
///     success");
///   * a step the ledger says RAN with no `attempt_id` on the fold row is
///     stop-races-spawn (§2.3, r2 minor 16): the provider killed the process
///     before emitting `sessionStarted`, so the process family produced zero
///     records while the step-bead write went through.
///
/// Everything else stays unexplained, and unexplained blocks the cut.
ShadowMismatchClass stepGapClassifier(
  String field,
  String? legacyValue,
  String? foldValue,
) {
  switch (field) {
    case 'step_presence':
      return foldValue == null
          ? ShadowMismatchClass.nonAtomicCrash
          : ShadowMismatchClass.unexplained;
    case 'step_attempt':
      return foldValue == null
          ? ShadowMismatchClass.stopRacesSpawn
          : ShadowMismatchClass.unexplained;
    case 'step_state':
      final legacy = stepStateProgress[legacyValue];
      final fold = stepStateProgress[foldValue];
      // A state outside the vocabulary orders as unknown, and an unknown
      // order is never called a lag.
      if (legacy == null || fold == null) {
        return ShadowMismatchClass.unexplained;
      }
      return legacy > fold
          ? ShadowMismatchClass.nonAtomicCrash
          : ShadowMismatchClass.unexplained;
    default:
      return ShadowMismatchClass.unexplained;
  }
}

/// The Family-5 [ShadowCompare] lane.
class StepTransitionShadow implements ShadowCompare {
  StepTransitionShadow(
    this._legacy, {
    ShadowMismatchClassifier classifier = stepGapClassifier,
  }) : _classify = classifier;

  final LegacyStepReader _legacy;
  final ShadowMismatchClassifier _classify;

  /// `step_presence` is the row-existence axis; `step_attempt` is the
  /// process-facts axis; the other two are the shared step-bead facts.
  /// Disjoint from [unshadowableMismatchFields] by construction — see
  /// `legacy_step_reader.dart` for the three step facts deliberately left
  /// out and why.
  @override
  Set<String> get comparableFields => const {
    'step_presence',
    'step_state',
    'step_attempt',
    'cooldown_until',
  };

  @override
  String? get unavailableReason => null;

  /// Same refusal-at-emit guard as the Family-1 lane: §9's unshadowable
  /// fields must never reach a report, and the guard is a method so it stays
  /// exercisable.
  @protected
  @visibleForTesting
  ShadowMismatch buildMismatch({
    required String sessionId,
    required String stepPath,
    required String field,
    required String? legacyValue,
    required String? foldValue,
    required int? seq,
    ShadowMismatchClass? classification,
  }) {
    if (unshadowableMismatchFields.contains(field)) {
      throw StateError(
        'step shadow lane produced a mismatch on unshadowable field '
        '"$field" — §9 excludes it from the window',
      );
    }
    return ShadowMismatch(
      sessionId: sessionId,
      stepPath: stepPath,
      field: field,
      legacyValue: legacyValue,
      foldValue: foldValue,
      seq: seq,
      classification:
          classification ?? _classify(field, legacyValue, foldValue),
    );
  }

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async {
    if (records.truncatedAt case final int at) {
      return ShadowCompareResult.incomplete(
        'the reader could not hand over the whole record stream (cut at '
        '$at rows) — the P2 fold would be a fold of a prefix, so this '
        "session's steps were NOT compared",
      );
    }
    final fold = foldStepCursors(records.records);
    final byPath = _latestPerPath(fold.rows.values, sessionId, round);
    final legacy = await _legacy.stepViews(sessionId);
    if (legacy.isEmpty) {
      // The molecule was reaped (or never poured): the oracle holds nothing,
      // so there is nothing to compare — never a fold-side accusation.
      return const ShadowCompareResult([]);
    }

    final mismatches = <ShadowMismatch>[];
    for (final view in legacy) {
      final row = byPath[view.stepPath];
      final resumeGap = row != null && _isUninstrumentedResume(fold, row);
      void mismatch(String field, String? legacyValue, String? foldValue) =>
          mismatches.add(
            buildMismatch(
              sessionId: sessionId,
              stepPath: view.stepPath,
              field: field,
              legacyValue: legacyValue,
              foldValue: foldValue,
              seq: row?.lastSeq,
              classification:
                  resumeGap &&
                      (field == 'step_state' || field == 'step_attempt')
                  ? ShadowMismatchClass.uninstrumentedResume
                  : null,
            ),
          );

      if (row == null) {
        mismatch('step_presence', 'present', null);
        continue;
      }
      // A freshly poured step carries no fine state — honest "nothing has
      // run" (MoleculeStepKeys.state's own words), not a value to compare.
      if (view.state != null && view.state != row.state) {
        mismatch('step_state', view.state, row.state);
      }
      // The process facts: the ledger says this step ran, the fold row has no
      // attempt behind it. That is the stop-races-spawn signature and the
      // lost-`attempt.process.started` class both — named, counted, and
      // adjudicated once rather than left to read as agreement.
      final ran = (stepStateProgress[view.state] ?? -1) >= _ranProgress;
      if (ran && row.attemptId == null) {
        mismatch('step_attempt', 'ran', null);
      }
      // Compared at whole-second granularity: the legacy key is an ISO-8601
      // string and the record a DATETIME(6), so sub-second disagreement is a
      // formatting artifact of the carrier, never a divergence of the fact.
      final legacyCooldown = _second(view.cooldownUntil);
      final foldCooldown = _second(row.cooldownUntil);
      if (legacyCooldown != foldCooldown) {
        mismatch('cooldown_until', legacyCooldown, foldCooldown);
      }
    }
    return ShadowCompareResult(mismatches);
  }

  static bool _isUninstrumentedResume(
    StepCursorFoldResult fold,
    StepCursorRow latest,
  ) {
    if (latest.stepRound == 0 ||
        latest.state != 'pending' ||
        latest.attemptId != null) {
      return false;
    }
    final predecessor =
        fold.rows[(
          sessionId: latest.sessionId,
          round: latest.round,
          stepPath: latest.stepPath,
          stepRound: latest.stepRound - 1,
        )];
    if (predecessor == null) return false;
    return predecessor.supersededByStepRound == latest.stepRound &&
        predecessor.lastSeq > latest.lastSeq &&
        (stepStateProgress[predecessor.state] ?? -1) >= _ranProgress;
  }

  /// The comparable row per step path: the greatest `(round, step_round)`,
  /// scoped to [round] when the operator named one.
  static Map<String, StepCursorRow> _latestPerPath(
    Iterable<StepCursorRow> rows,
    String sessionId,
    int? round,
  ) {
    final latest = <String, StepCursorRow>{};
    for (final row in rows) {
      if (row.sessionId != sessionId) continue;
      if (round != null && row.round != round) continue;
      final held = latest[row.stepPath];
      if (held == null ||
          row.round > held.round ||
          (row.round == held.round && row.stepRound >= held.stepRound)) {
        latest[row.stepPath] = row;
      }
    }
    return latest;
  }

  static String? _second(DateTime? value) {
    if (value == null) return null;
    final utc = value.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    ).toIso8601String();
  }
}
