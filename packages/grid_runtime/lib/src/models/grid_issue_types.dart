import 'package:beads_dart/beads_dart.dart';

/// the_grid's registered custom issue-type vocabulary.
abstract final class GridIssueTypes {
  static const agent = IssueType('agent');
  static const convergence = IssueType('convergence');
  static const convoy = IssueType('convoy');
  static const event = IssueType('event');
  static const gate = IssueType('gate');

  /// A grid state store's metadata-carried cross-repository blocking edge.
  static const link = IssueType('link');
  static const mergeRequest = IssueType('merge-request');
  static const message = IssueType('message');
  static const molecule = IssueType('molecule');
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
