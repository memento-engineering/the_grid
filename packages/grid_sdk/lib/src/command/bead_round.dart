/// The ROUND-CONTEXT projection — the bead-side half of `bead round`.
///
/// Pure and I/O-free: the resident handler supplies the work bead plus the
/// state store's beads, and this file joins them into the current round's
/// identity. The VERDICTS are NOT here — verification bindings live in the
/// trajectory log (`the_grid#trajectory-ledger-split`) and are folded by
/// `grid_trajectory`'s `foldBeadRound`.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_engine/grid_engine.dart'
    show GridIssueTypes, SessionBeadKeys, maxReworkRound;

import 'work_bead_keys.dart';

part 'bead_round.freezed.dart';
part 'bead_round.g.dart';

/// One bead's current-round identity, or the typed statement that it has none.
@Freezed(unionKey: 'kind', unionValueCase: FreezedUnionCase.snake)
sealed class RoundContext with _$RoundContext {
  /// The bead has exactly one live session: round [round] under [sessionId].
  @FreezedUnionValue('round')
  const factory RoundContext.round({
    @JsonKey(name: 'bead_id') required String beadId,
    required String title,
    required String status,
    @JsonKey(name: 'session_id') required String sessionId,
    required int round,
    @JsonKey(name: 'validation_plan') String? validationPlan,
  }) = BeadRoundFound;

  /// The bead has no single live session. [reason] says which case it is —
  /// a bead between rounds is an ordinary state of the world, never a refusal.
  @FreezedUnionValue('no_round')
  const factory RoundContext.noRound({
    @JsonKey(name: 'bead_id') required String beadId,
    required String title,
    required String status,
    required String reason,
    @JsonKey(name: 'validation_plan') String? validationPlan,
  }) = BeadRoundAbsent;

  /// Decodes the context off the resident door's `context` object.
  factory RoundContext.fromJson(Map<String, dynamic> json) =>
      _$RoundContextFromJson(json);
}

/// Joins [workBead] to its live session among [stateBeads].
///
/// The live session is the one whose `work_bead` is EXACTLY the bead id.
/// Retired rounds carry `<id>#r<N>` and voided ones `<id>#void-<session>`
/// (`grid_engine`'s `src/domain/rework.dart`), so both drop out of this join
/// by construction — the same predicate `StationCommandHandler._rework` uses.
/// The round number is `maxReworkRound(...) + 1`, rework.dart's own stated
/// rule ("The next round is `maxReworkRound(...) + 1`"), not a second
/// definition of it.
RoundContext projectRoundContext({
  required Bead workBead,
  required Iterable<Bead> stateBeads,
}) {
  final validationPlan = beadMetadataText(
    workBead,
    WorkBeadKeys.validationPlan,
  );
  final sessions = stateBeads
      .where((bead) => bead.issueType == GridIssueTypes.session)
      .toList(growable: false);
  final keys = <String>[
    for (final session in sessions)
      if (beadMetadataText(session, SessionBeadKeys.workBead)
          case final String key)
        key,
  ];
  final live = sessions
      .where(
        (session) =>
            beadMetadataText(session, SessionBeadKeys.workBead) == workBead.id,
      )
      .toList(growable: false);
  if (live.length != 1) {
    return RoundContext.noRound(
      beadId: workBead.id,
      title: workBead.title,
      status: workBead.status.wire,
      validationPlan: validationPlan,
      reason: live.isEmpty
          ? 'No session is linked to "${workBead.id}".'
          : '${live.length} sessions are linked to "${workBead.id}".',
    );
  }
  return RoundContext.round(
    beadId: workBead.id,
    title: workBead.title,
    status: workBead.status.wire,
    validationPlan: validationPlan,
    sessionId: live.single.id,
    round: maxReworkRound(workBead.id, keys) + 1,
  );
}
