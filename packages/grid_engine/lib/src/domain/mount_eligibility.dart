library;

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_runtime/grid_runtime.dart' show BeadOwnershipPredicate;

import 'driveable_work.dart';
import 'session_projection.dart';

part 'mount_eligibility.freezed.dart';

const _approvalCapturedAtKey = 'grid.approved_at';

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

/// Refuses a valid approval until the joined STATE read is at least as fresh.
///
/// Cross-store links live on the STATE axis while approval lives on the WORK
/// bead. A first eligible WORK pass can therefore observe the approval before
/// it observes a link authored immediately beforehand. [stateCapturedAt] is
/// the capture instant of the exact STATE snapshot used by the join; `null`
/// fails closed for a valid approval because no link-set read has been
/// observed. Absent, blank, non-string, and unparseable approval values remain
/// the vended approval policy's responsibility.
MountEligibilityPredicate freshCrossLinkReadClause(DateTime? stateCapturedAt) =>
    (bead) {
      final wireApproval = bead.metadata[_approvalCapturedAtKey];
      if (wireApproval is! String) {
        return const MountEligibilityDecision.eligible();
      }
      final approvalText = wireApproval.trim();
      if (approvalText.isEmpty) {
        return const MountEligibilityDecision.eligible();
      }
      final approval = DateTime.tryParse(approvalText);
      if (approval == null) {
        return const MountEligibilityDecision.eligible();
      }
      final stateCapture = stateCapturedAt?.toUtc();
      if (stateCapture == null || stateCapture.isBefore(approval.toUtc())) {
        return MountEligibilityDecision.refused(
          clause: 'fresh cross-link read pending: ${bead.id}',
        );
      }
      return const MountEligibilityDecision.eligible();
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
  if (_hasLivePublishedSession(bead.id, sessionsByWorkBead)) {
    return const MountEligibilityDecision.eligible();
  }
  return MountEligibilityDecision.refused(clause: clause);
};

/// Refuses a fresh bead blocked by an open dependency in its owning store.
///
/// [GraphSnapshot.readyIds] is the originating store's authoritative `bd ready`
/// result, so membership wins over locally projected dependency rows. When the
/// bead is absent from that set, blocking edges whose observed endpoints
/// resolve to the same non-null owner reproduce that store's blocked semantics.
/// A bead carrying a live published session remains eligible so adding an edge
/// never evicts work in flight.
MountEligibilityPredicate sameStoreDependencyExclusionClause(
  GraphSnapshot graph,
  BeadOwnershipPredicate ownership,
  Map<String, SessionProjection> sessionsByWorkBead,
) => (bead) {
  if (graph.readyIds.contains(bead.id)) {
    return const MountEligibilityDecision.eligible();
  }

  final sourceOwner = ownership.substationOf(bead);
  final blockerIds = <String>{};
  for (final dependency in graph.dependencies) {
    if (dependency.issueId != bead.id ||
        !dependency.type.isBlockingEdge ||
        sourceOwner == null) {
      continue;
    }
    final target = graph.beadsById[dependency.dependsOnId];
    if (target == null ||
        target.isClosed ||
        ownership.substationOf(target) != sourceOwner) {
      continue;
    }
    blockerIds.add(target.id);
  }
  if (blockerIds.isEmpty ||
      _hasLivePublishedSession(bead.id, sessionsByWorkBead)) {
    return const MountEligibilityDecision.eligible();
  }

  final blockers = blockerIds.toList()..sort();
  return MountEligibilityDecision.refused(
    clause:
        'frontier dependency: bead ${bead.id} is blocked by open dependency '
        '"${blockers.first}"',
  );
};

bool _hasLivePublishedSession(
  String beadId,
  Map<String, SessionProjection> sessionsByWorkBead,
) {
  final session = sessionsByWorkBead[beadId];
  return session != null && !session.isTerminal;
}
