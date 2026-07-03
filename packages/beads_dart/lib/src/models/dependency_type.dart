/// A dependency edge's type.
///
/// An **open set** modeled as an extension type over the wire string,
/// mirroring upstream `internal/types/types.go` constants. [affectsBlocking]
/// and [isBlockingEdge] reproduce the upstream `AffectsReadyWork` /
/// `IsBlockingEdge` predicates exactly.
extension type const DependencyType(String wire) {
  // ----- blocking edges (affect ready-work) -----
  static const blocks = DependencyType('blocks');
  static const parentChild = DependencyType('parent-child');
  static const conditionalBlocks = DependencyType('conditional-blocks');
  static const waitsFor = DependencyType('waits-for');

  // ----- knowledge-graph / relational edges -----
  static const related = DependencyType('related');
  static const discoveredFrom = DependencyType('discovered-from');
  static const repliesTo = DependencyType('replies-to');
  static const relatesTo = DependencyType('relates-to');
  static const duplicates = DependencyType('duplicates');
  static const supersedes = DependencyType('supersedes');
  static const authoredBy = DependencyType('authored-by');
  static const assignedTo = DependencyType('assigned-to');
  static const approvedBy = DependencyType('approved-by');
  static const attests = DependencyType('attests');
  static const tracks = DependencyType('tracks');
  static const until = DependencyType('until');
  static const causedBy = DependencyType('caused-by');
  static const validates = DependencyType('validates');
  static const delegatedFrom = DependencyType('delegated-from');

  /// True if this edge blocks the ready-work calculation (upstream
  /// `AffectsReadyWork`): blocks | parent-child | conditional-blocks |
  /// waits-for.
  bool get affectsBlocking =>
      this == blocks ||
      this == parentChild ||
      this == conditionalBlocks ||
      this == waitsFor;

  /// True if this edge is a hard blocker (upstream `IsBlockingEdge`):
  /// blocks | conditional-blocks | waits-for. Excludes parent-child, which is
  /// structural rather than blocking.
  bool get isBlockingEdge =>
      this == blocks || this == conditionalBlocks || this == waitsFor;
}
