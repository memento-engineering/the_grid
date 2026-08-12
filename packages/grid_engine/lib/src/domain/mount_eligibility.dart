library;

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'driveable_work.dart';

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
