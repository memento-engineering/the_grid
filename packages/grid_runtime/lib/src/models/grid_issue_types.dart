import 'package:beads_dart/beads_dart.dart';

/// the_grid's registered custom issue-type vocabulary.
abstract final class GridIssueTypes {
  static const agent = IssueType('agent');
  static const convergence = IssueType('convergence');
  static const convoy = IssueType('convoy');
  static const event = IssueType('event');
  static const gate = IssueType('gate');

  /// The RETIRED state-store link bead (tg-6t0h). Nothing authors or enforces
  /// one any more — a cross-store blocker is a bd
  /// `external:<project>:<capability>` dependency row on the consumer's own
  /// work bead. The type survives only so a store still holding the inert
  /// receipts can be READ (the one-pass `grid link migrate`), and it is absent
  /// from [customTypes] so no fresh store seeds it.
  static const link = IssueType('link');
  static const mergeRequest = IssueType('merge-request');
  static const message = IssueType('message');
  static const molecule = IssueType('molecule');

  /// A station's DURABLE remount-attempt budget for ONE work bead (tg-zlfu) —
  /// state that PREVENTS a mount, never a mechanism that starts one.
  ///
  /// A bead that IS a record rather than work. One record per work bead, its
  /// count merged in place; never one bead per attempt, which would make the
  /// bound into the storage amplifier it exists to stop.
  static const mountAttempt = IssueType('mount-attempt');
  static const rig = IssueType('rig');
  static const role = IssueType('role');
  static const session = IssueType('session');
  static const spec = IssueType('spec');
  static const step = IssueType('step');

  static const customTypes = <IssueType>[
    agent,
    convergence,
    convoy,
    event,
    gate,
    mergeRequest,
    message,
    molecule,
    mountAttempt,
    rig,
    role,
    session,
    spec,
    step,
  ];

  static const infrastructureTypes = <IssueType>[agent, rig, role];

  static const all = <IssueType>{...customTypes, link};
}

/// the_grid-only classifications over beads' open [IssueType].
extension GridIssueTypeClassification on IssueType {
  /// Whether `bd list` hides this the_grid infrastructure type regardless of
  /// `--all` (ADR-0001 Decision 4, promoted from ADR-0000 A5).
  bool get isGridInfrastructure =>
      GridIssueTypes.infrastructureTypes.contains(this);
}
