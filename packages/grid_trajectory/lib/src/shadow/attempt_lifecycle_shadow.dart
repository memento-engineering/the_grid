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

import '../cli/traj_shadow_diff_command.dart';
import '../codec/envelope.dart';
import '../fold/session_head_fold.dart';
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
class AttemptLifecycleShadow implements ShadowCompare {
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

  @override
  Future<List<ShadowMismatch>> compare({
    required String sessionId,
    required List<TrajectoryEnvelope> records,
    int? round,
  }) async {
    final fold = foldSessionHeads(records);
    final row = fold.rows[sessionId];
    final legacy = await _legacy.sessionView(sessionId);
    if (round != null && row?.round != round && legacy?.round != round) {
      // Operator-scoped run: this session never touched the named round.
      return const [];
    }

    final mismatches = <ShadowMismatch>[];
    void mismatch(String field, String? legacyValue, String? foldValue) {
      if (unshadowableMismatchFields.contains(field)) {
        // A comparator emitting an unshadowable field is a comparator bug —
        // §9's ratification gate must never be fed one.
        throw StateError(
          'shadow comparator produced a mismatch on unshadowable field '
          '"$field" — §9 excludes it from the window',
        );
      }
      mismatches.add(
        ShadowMismatch(
          sessionId: sessionId,
          field: field,
          legacyValue: legacyValue,
          foldValue: foldValue,
          seq: row?.lastSeq,
          classification: _classify(field, legacyValue, foldValue),
        ),
      );
    }

    if (row == null || legacy == null) {
      if (row == null && legacy == null) return const [];
      // One side is blind: presence is the only comparable fact.
      mismatch(
        'presence',
        legacy == null ? null : 'present',
        row == null ? null : 'present',
      );
      return mismatches;
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

    if (legacy.held != row.held) {
      mismatch('held', '${legacy.held}', '${row.held}');
    }

    return mismatches;
  }
}
