/// A bead's issue type.
///
/// An open set modeled over the wire string. Beads ships the nine named
/// built-ins below; a workspace registers custom values by constructing
/// `const IssueType('its-type')`.
extension type const IssueType(String wire) {
  static const task = IssueType('task');
  static const bug = IssueType('bug');
  static const feature = IssueType('feature');
  static const chore = IssueType('chore');
  static const epic = IssueType('epic');
  static const decision = IssueType('decision');
  static const spike = IssueType('spike');
  static const story = IssueType('story');
  static const milestone = IssueType('milestone');

  static const coreTypes = <IssueType>[
    task,
    bug,
    feature,
    chore,
    epic,
    decision,
    spike,
    story,
    milestone,
  ];

  /// Whether this is one of beads' nine built-in issue types.
  bool get isCore => coreTypes.contains(this);
}
