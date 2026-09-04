/// The WORK-BEAD metadata keys the operator READ verbs project.
///
/// the_grid does NOT own these. The code asset writes them —
/// `grid_assets`' `lib/src/filing/approval_stamp.dart` (the three
/// `grid.approved_*` keys) and the `validation_plan` command its
/// `lib/src/code/mount_eligibility.dart` reads. `grid_assets` depends on
/// `grid_sdk`, so importing it here would invert the dependency arrow; the
/// NAMES are mirrored in ONE place instead, exactly as `ResultKeys`
/// (`grid_engine/lib/src/domain/session_bead.dart`) mirrors the committee's
/// result schema and `StepResultKeys` mirrors `ResultKeys` inside the
/// `grid_trajectory` leaf.
library;

import 'package:beads_dart/beads_dart.dart' show Bead;

/// The mirrored asset-owned work-bead metadata keys.
abstract final class WorkBeadKeys {
  /// The approve verb's `--actor`.
  static const approvedBy = 'grid.approved_by';

  /// The approve verb's UTC instant — the WITNESS: the verb writes all three
  /// keys in one update, so this one's presence IS approval.
  static const approvedAt = 'grid.approved_at';

  /// The store root's git HEAD sha at approval time.
  static const approvedRev = 'grid.approved_rev';

  /// The bead's own machine-gate command line.
  static const validationPlan = 'validation_plan';
}

/// [bead]'s metadata value at [key] when it is a non-blank String, else null.
///
/// bd metadata is an untyped JSON blob; a non-String or blank value is the
/// same absence to a projection and is never rendered as one.
String? beadMetadataText(Bead bead, String key) {
  final value = bead.metadata[key];
  return value is String && value.trim().isNotEmpty ? value : null;
}
