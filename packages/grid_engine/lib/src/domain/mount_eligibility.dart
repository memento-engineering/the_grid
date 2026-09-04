library;

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'driveable_work.dart';
import 'session_projection.dart';

part 'mount_eligibility.freezed.dart';

/// Decides whether [bead] is fit to mount at this reconciliation.
///
/// [IssueTypeDriveability] asks whether this KIND of bead may ever mount;
/// MountEligibility asks whether THIS bead is fit to mount right now.
typedef MountEligibilityPredicate =
    MountEligibilityDecision Function(Bead bead);

/// The content-gate decision returned by [MountEligibilityPredicate].
@freezed
sealed class MountEligibilityDecision with _$MountEligibilityDecision {
  /// The candidate may cross the content gate.
  const factory MountEligibilityDecision.eligible() = MountEligible;

  /// The candidate is excluded by the named [clause].
  const factory MountEligibilityDecision.refused({required String clause}) =
      MountRefused;
}

/// Refuses a fresh bead held out by the join's active cross-link projection.
///
/// Both inputs are immutable snapshot projections. A bead carrying a live
/// session remains eligible so authoring a link never evicts work in flight.
MountEligibilityPredicate crossLinkExclusionClause(
  Map<String, String> frontierExclusionsByBeadId,
  Map<String, SessionProjection> sessionsByWorkBead,
) => (bead) {
  final clause = frontierExclusionsByBeadId[bead.id];
  if (clause == null) {
    return const MountEligibilityDecision.eligible();
  }
  final session = sessionsByWorkBead[bead.id];
  if (session != null && !session.isTerminal) {
    return const MountEligibilityDecision.eligible();
  }
  return MountEligibilityDecision.refused(clause: clause);
};
