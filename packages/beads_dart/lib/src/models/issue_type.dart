/// A bead's issue type.
///
/// An **open set** modeled as an extension type over the wire string: beads
/// ships 9 core types and any workspace may register custom types (the_grid's
/// `tg` registers 13: agent, convergence, convoy, event, gate, merge-request,
/// message, molecule, rig, role, session, spec, step; a grid STATE store adds
/// `link`). Named constants cover the types the_grid projects; unknown strings
/// pass through unharmed.
extension type const IssueType(String wire) {
  // ----- core types (upstream built-ins) -----
  static const task = IssueType('task');
  static const bug = IssueType('bug');
  static const feature = IssueType('feature');
  static const chore = IssueType('chore');
  static const epic = IssueType('epic');
  static const decision = IssueType('decision');
  static const spike = IssueType('spike');
  static const story = IssueType('story');
  static const milestone = IssueType('milestone');

  // ----- the_grid custom types (tg `types.custom`) -----
  static const agent = IssueType('agent');
  static const convergence = IssueType('convergence');
  static const convoy = IssueType('convoy');
  static const event = IssueType('event');
  static const gate = IssueType('gate');

  /// A grid state store's own CROSS-REPO blocking edge, carried entirely in the
  /// bead's metadata (`grid.link.*`) rather than a dependency row — see
  /// `grid_engine`'s `domain/cross_link.dart`. Registered only where the grid
  /// writes its state, never in a work store.
  static const link = IssueType('link');
  static const mergeRequest = IssueType('merge-request');
  static const message = IssueType('message');
  static const molecule = IssueType('molecule');
  static const rig = IssueType('rig');
  static const role = IssueType('role');
  static const session = IssueType('session');
  static const spec = IssueType('spec');
  static const step = IssueType('step');

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

  /// Infrastructure types that `bd list` does **not** surface regardless of
  /// `--all` (ADR-0001 Decision 4, promoted from ADR-0000 A5): sampling these
  /// requires an infra-inclusive export — the snapshot read uses
  /// `bd export --all`, which subsumes `--include-infra` (cmd/bd/export.go).
  static const infraTypes = <IssueType>[agent, rig, role];

  bool get isCore => coreTypes.contains(this);

  /// True for types `bd list` hides; see [infraTypes].
  bool get isInfra => infraTypes.contains(this);
}
