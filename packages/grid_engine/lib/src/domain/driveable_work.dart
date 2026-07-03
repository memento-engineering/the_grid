import 'package:grid_controller/grid_controller.dart';

/// The plain coding-work core types — the DRIVEABLE-WORK boundary a resident
/// station's all-ready arming narrows to (RS-3/D-R4): every other core type
/// (`epic`/`decision`/`spike`/`story`/`milestone`) is organizational, not
/// something an agent drives.
const driveableTypes = <IssueType>[
  IssueType.task,
  IssueType.bug,
  IssueType.feature,
  IssueType.chore,
];

/// The_grid's resident-station driveability narrowing (RS-3/D-R4) — a grid
/// opinion layered on beads' generic [IssueType], not a beads fact.
extension IssueTypeDriveability on IssueType {
  /// True for the four driveable core types; see [driveableTypes].
  bool get isDriveable => driveableTypes.contains(this);
}
