/// The `legacy_attempt_count` JOIN (stage1-wiring §2.2, r2 major 8) as a §9
/// comparison lane.
///
/// `mount_attempt_id` is a recorder-minted ULID with no legacy counterpart, so
/// the mount axis would otherwise sit entirely in §9's unshadowable set and
/// leave the cut's evidence pack silent about remounts. The record therefore
/// carries the legacy bead's `grid.attempt.count` as `legacy_attempt_count`,
/// and §4 says why in as many words: it "exists precisely to keep the mint
/// ordinal in the shared set".
///
/// **The join is an INEQUALITY, not an equality, and that is the design.** The
/// legacy `type=mount-attempt` bead holds ONE count per work bead, merged in
/// place and only ever incremented (`mount_attempt.dart`: "merged in place,
/// never one bead per attempt"). Each record carries the value observed at its
/// own mount. So the ledger's count is `>=` the highest ordinal any record
/// carries, and a ledger running AHEAD is just a bead that mounted again
/// after the session under comparison. Only two shapes are divergence:
///
///   * the fold claims an ordinal the ledger has never reached — the fold
///     ahead of the incumbent, which §9 presumes wrong (unexplained);
///   * the ledger counts remounts and the fold carries no ordinal at all —
///     the missing-record direction, which is the non-atomic-crash class.
///
/// Deliberately NOT round-scoped: the mount ordinal is per WORK BEAD across
/// every round (a rework mints a fresh session against the same budget), so a
/// `--round` filter would hide exactly the remount history it measures.
library;

import '../cli/traj_shadow_diff_command.dart';
import '../cli/trajectory_reader.dart';
import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import 'legacy_mount_attempt_reader.dart';

/// The one field this lane compares.
const String mountOrdinalField = 'legacy_attempt_count';

/// The Family-1 mount-ordinal lane.
class MountOrdinalShadow implements ShadowCompare {
  MountOrdinalShadow(this._legacy);

  final LegacyMountAttemptReader _legacy;

  @override
  Set<String> get comparableFields => const {mountOrdinalField};

  @override
  String? get unavailableReason => null;

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async {
    if (records.truncatedAt case final int at) {
      return ShadowCompareResult.incomplete(
        'the reader could not hand over the whole record stream (cut at '
        '$at rows) — the highest observed mount ordinal would be the highest '
        'ordinal in a PREFIX, so the join was NOT made',
      );
    }
    // Highest observed ordinal per work bead. Highest, not last: the records
    // are point-in-time reads of a monotonically merged counter, and `seq`
    // order across a bounce is not a guarantee the counter itself makes.
    final observed = <String, int>{};
    // Work beads the session touched even without an ordinal on the record —
    // the fold-lags direction needs the bead id to ask the ledger about.
    final touched = <String>{};
    for (final envelope in records.records) {
      if (envelope.family != TrajectoryFamily.attempt) continue;
      final workBeadId = envelope.workBeadId;
      if (workBeadId == null || workBeadId.isEmpty) continue;
      final record = TrajectoryCodec.decode(envelope);
      final int? count;
      switch (record) {
        case AttemptSessionStarted(:final legacyAttemptCount):
          count = legacyAttemptCount;
        case AttemptMintOutcome(:final legacyAttemptCount):
          count = legacyAttemptCount;
        default:
          continue;
      }
      touched.add(workBeadId);
      if (count == null) continue;
      final held = observed[workBeadId];
      if (held == null || count > held) observed[workBeadId] = count;
    }
    if (touched.isEmpty) return const ShadowCompareResult([]);

    final mismatches = <ShadowMismatch>[];
    for (final workBeadId in touched) {
      final ledger = await _legacy.attemptCount(workBeadId);
      final fold = observed[workBeadId];
      if (fold == null) {
        // No ordinal on any record. A ledger that never counted a remount
        // (absent bead, or a first-try mount) agrees with that by saying
        // nothing; a ledger counting remounts does not.
        if (ledger == null || ledger <= 1) continue;
        mismatches.add(
          ShadowMismatch(
            sessionId: sessionId,
            field: mountOrdinalField,
            legacyValue: '$ledger',
            foldValue: null,
            seq: null,
            classification: ShadowMismatchClass.nonAtomicCrash,
          ),
        );
        continue;
      }
      // The inequality: the ledger must be at least as far along as anything
      // the fold observed. Ahead is history, behind is divergence.
      if (ledger != null && ledger >= fold) continue;
      mismatches.add(
        ShadowMismatch(
          sessionId: sessionId,
          field: mountOrdinalField,
          legacyValue: ledger == null ? null : '$ledger',
          foldValue: '$fold',
          seq: null,
        ),
      );
    }
    return ShadowCompareResult(mismatches);
  }
}
