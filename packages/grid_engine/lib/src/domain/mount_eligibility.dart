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

/// Refuses a bead whose issue type is not dispatchable by this substation.
///
/// Non-resident substations retain the core-work allow-list. Resident
/// substations narrow that list to the driveable work types because their
/// ready frontier is the station's autonomous drive set.
MountEligibilityPredicate dispatchableWorkClause({required bool resident}) =>
    (bead) {
      final type = bead.issueType;
      if (type.isCore && (!resident || type.isDriveable)) {
        return const MountEligibilityDecision.eligible();
      }
      return MountEligibilityDecision.refused(
        clause:
            'issue type ${type.wire} is not dispatchable for this substation',
      );
    };

/// Refuses a bead omitted from this substation's configured drive list.
///
/// An empty list means there is no per-bead restriction. The live-arm rule
/// requiring a non-empty list is enforced upstream; this clause only narrows
/// the already-owned candidates presented to the mount boundary.
MountEligibilityPredicate driveListClause(Set<String> driveList) => (bead) {
  if (driveList.isEmpty || driveList.contains(bead.id)) {
    return const MountEligibilityDecision.eligible();
  }
  return const MountEligibilityDecision.refused(
    clause: 'bead is not selected by the substation drive list',
  );
};

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
