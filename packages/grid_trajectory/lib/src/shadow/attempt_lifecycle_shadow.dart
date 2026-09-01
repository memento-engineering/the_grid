/// The REAL §9 shadow comparator for the attempt-lifecycle family: fold the
/// session's trajectory records through the P1 fold, read the legacy bead
/// view through the injected [LegacySessionReader], and report typed
/// mismatches keyed `(session, field, legacy_value, fold_value, seq)`.
///
/// The legacy path is the incumbent oracle during its own replacement (§9):
/// an unexplained mismatch presumes the FOLD wrong, blocks the stage cut, and
/// is rendered by `traj shadow-diff`. The one named allow-list class —
/// `non_atomic_crash`, a crash between the legacy write and the trajectory
/// append — is classified by the injectable [ShadowMismatchClassifier] seam
/// and adjudicated once by the operator, never silently dropped.
library;

import 'package:meta/meta.dart';

import '../cli/traj_shadow_diff_command.dart';
import '../cli/trajectory_reader.dart';
import '../codec/envelope.dart';
import '../fold/session_head_fold.dart';
import '../fold/session_head_row.dart';
import 'legacy_session_reader.dart';

/// §9's unshadowable facts as mismatch-field names: these MUST NEVER appear
/// in a mismatch report — they have no legacy counterpart, and a comparator
/// emitting one is broken (asserted at emit, pinned by test).
const Set<String> unshadowableMismatchFields = {
  'attempt_id',
  'commit_sha',
  'effect_id',
  'effect_ordering',
  'provenance',
  'provenance_basis',
  'incarnation',
};

/// Classifies one mismatch against the §9 allow-list.
typedef ShadowMismatchClassifier =
    ShadowMismatchClass Function(
      String field,
      String? legacyValue,
      String? foldValue,
    );

/// The default classifier: the `non_atomic_crash` shape is the FOLD side
/// missing a fact the legacy side already holds — exactly what a crash
/// between the legacy write and the trajectory append leaves behind. The
/// reverse direction (the fold ahead of the ledger) is never that crash and
/// stays unexplained.
///
/// The `held` arm is narrow ON PURPOSE. It classifies a fold that genuinely
/// LOST a hold record, and nothing else: the escalated class no longer
/// reaches it at all, because escalation is folded into the comparator's
/// comparable-held projection ([AttemptLifecycleShadow._comparableHeld])
/// rather than being waved through here as a crash it never was.
ShadowMismatchClass nonAtomicCrashClassifier(
  String field,
  String? legacyValue,
  String? foldValue,
) {
  final foldLags = switch (field) {
    'presence' => foldValue == null,
    'status' => legacyValue == 'closed' && foldValue == 'open',
    'outcome' => legacyValue != null && foldValue == null,
    'held' => legacyValue == 'true' && foldValue == 'false',
    _ => false,
  };
  return foldLags
      ? ShadowMismatchClass.nonAtomicCrash
      : ShadowMismatchClass.unexplained;
}

/// The Family-1 [ShadowCompare] strategy — the seam `traj shadow-diff` runs
/// when a station composes a real [LegacySessionReader] (grid_cli does).
class AttemptLifecycleShadow implements ShadowCompare, ShadowDefaultScope {
  AttemptLifecycleShadow(
    this._legacy, {
    ShadowMismatchClassifier classifier = nonAtomicCrashClassifier,
  }) : _classify = classifier;

  final LegacySessionReader _legacy;
  final ShadowMismatchClassifier _classify;

  /// `presence` is the row-existence axis; the rest are the shared §7 head
  /// facts. Disjoint from [unshadowableMismatchFields] by construction
  /// (pinned by test).
  @override
  Set<String> get comparableFields => const {
    'presence',
    'work_bead_id',
    'status',
    'outcome',
    'round',
    'held',
  };

  @override
  String? get unavailableReason => null;

  /// Builds one mismatch, refusing §9's unshadowable fields AT EMIT: a
  /// comparator producing one is broken, and §9's ratification gate must
  /// never be fed one.
  ///
  /// A method rather than a closure inside [compare] so the refusal is
  /// EXERCISABLE — a subclass (or a future comparator sharing this base) can
  /// be driven into it, and a guard that cannot be reached is a guard nobody
  /// has checked.
  @protected
  @visibleForTesting
  ShadowMismatch buildMismatch({
    required String sessionId,
    required String field,
    required String? legacyValue,
    required String? foldValue,
    required int? seq,
  }) {
    if (unshadowableMismatchFields.contains(field)) {
      throw StateError(
        'shadow comparator produced a mismatch on unshadowable field '
        '"$field" — §9 excludes it from the window',
      );
    }
    return ShadowMismatch(
      sessionId: sessionId,
      field: field,
      legacyValue: legacyValue,
      foldValue: foldValue,
      seq: seq,
      classification: _classify(field, legacyValue, foldValue),
    );
  }

  /// The fold side's HELD, projected onto the legacy model's single axis.
  ///
  /// §6 row 4 keeps `outcome` and `held` separate on P1, and P1 must stay
  /// that way — `held` there is `attempt.rework_declined` and nothing else.
  /// The LEGACY model does not have two axes: `humanHeld` is escalation OR
  /// rework-declined (grid_engine `session_projection.dart`, the `humanHeld`
  /// field). So the disjunction is re-derived HERE, on the comparator's
  /// fold-side projection, where it is a statement about the oracle's shape
  /// and not a widening of the projection under test.
  static bool _comparableHeld(SessionHeadRow row) =>
      row.held || row.outcome == TerminalOutcome.escalated;

  /// Projects the legacy ledger's liveness into the implicit CLI scope.
  @override
  Future<ShadowDefaultSessionDisposition> defaultDispositionFor(
    String sessionId,
  ) async {
    final legacy = await _legacy.sessionView(sessionId);
    return switch (legacy) {
      LegacySessionView(voided: true) => ShadowDefaultSessionDisposition.voided,
      LegacySessionView(closed: false) =>
        ShadowDefaultSessionDisposition.inFlight,
      _ => ShadowDefaultSessionDisposition.compare,
    };
  }

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async {
    if (records.truncatedAt case final int at) {
      // A fold over a cut stream is not a comparison: the head it produces is
      // the head of a PREFIX, so both its agreement and its divergence are
      // unearned. Say so instead of reporting zero mismatches (§9: a run
      // counts only if it actually compared).
      return ShadowCompareResult.incomplete(
        'the reader could not hand over the whole record stream (cut at '
        '$at rows) — the fold would be a fold of a prefix, so this session '
        'was NOT compared',
      );
    }
    final fold = foldSessionHeads(records.records);
    final row = fold.rows[sessionId];
    final legacy = await _legacy.sessionView(sessionId);

    final mismatches = <ShadowMismatch>[];
    void mismatch(String field, String? legacyValue, String? foldValue) =>
        mismatches.add(
          buildMismatch(
            sessionId: sessionId,
            field: field,
            legacyValue: legacyValue,
            foldValue: foldValue,
            seq: row?.lastSeq,
          ),
        );

    // PRESENCE FIRST, and outside the round scope. A session one side has
    // never seen carries no round on that side, so a `--round` filter would
    // silently hide exactly the divergence the operator most needs to see —
    // the round guard governs the field-by-field compare below, never this.
    if (row == null || legacy == null) {
      if (row == null && legacy == null) return const ShadowCompareResult([]);
      // One side is blind: presence is the only comparable fact.
      mismatch(
        'presence',
        legacy == null ? null : 'present',
        row == null ? null : 'present',
      );
      return ShadowCompareResult(mismatches);
    }

    if (round != null && row.round != round && legacy.round != round) {
      // Operator-scoped run: this session never touched the named round.
      return const ShadowCompareResult([]);
    }

    // work_bead: the legacy key is compared BASE-stripped (the fold's key is
    // immutable, §1); an empty legacy key has nothing to say.
    if (legacy.workBeadId.isNotEmpty && legacy.workBeadId != row.workBeadId) {
      mismatch('work_bead_id', legacy.workBeadId, row.workBeadId);
    }

    final legacyStatus = legacy.closed ? 'closed' : 'open';
    if (legacyStatus != row.status.wire) {
      mismatch('status', legacyStatus, row.status.wire);
    }

    // outcome — the legacy side is OUTCOME-ISH (markers, not an enum):
    //   open              → determinately no outcome;
    //   closed+completed  → succeeded;
    //   closed+voided     → lost (the dead-key class, §2 F1);
    //   closed otherwise  → INDETERMINATE (held rides its own axis — §6
    //                       row 4 — and a bare close carries no marker), so
    //                       nothing is compared rather than a guess.
    final (determinate, legacyOutcome) = switch ((
      legacy.closed,
      legacy.completed,
      legacy.voided,
    )) {
      (false, _, _) => (true, null),
      (true, true, _) => (true, 'succeeded'),
      (true, false, true) => (true, 'lost'),
      (true, false, false) => (false, null),
    };
    if (determinate && legacyOutcome != row.outcome?.wire) {
      mismatch('outcome', legacyOutcome, row.outcome?.wire);
    }

    // round: only a retired `#rN` key carries one on the legacy side.
    if (legacy.round != null && legacy.round != row.round) {
      mismatch('round', '${legacy.round}', '${row.round}');
    }

    // held — compared against the fold's COMPARABLE-held (see
    // [_comparableHeld]), never P1's raw `held`: an escalated session is
    // human-held on the legacy side by construction, and comparing the raw
    // axis would manufacture a mismatch for every escalation.
    final foldHeld = _comparableHeld(row);
    if (legacy.held != foldHeld) {
      mismatch('held', '${legacy.held}', '$foldHeld');
    }

    return ShadowCompareResult(mismatches);
  }
}
