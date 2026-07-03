/// Lifecycle category for a status (beads `BuiltInStatusCategory`).
enum StatusCategory { active, wip, done, frozen, unspecified }

/// A bead's workflow status.
///
/// Modeled as an extension type over the wire string rather than a closed
/// 7-value enum: beads supports custom statuses (`Status.IsValidWithCustom`
/// in upstream `internal/types/types.go`), so a strict enum would throw on a
/// custom value during decode. The seven built-ins are exposed as named
/// constants; [category] maps the built-ins and returns
/// [StatusCategory.unspecified] for anything else. At runtime a [BeadStatus]
/// *is* its wire `String`, so `==`/`hashCode` are value-based for free.
///
/// (Refines the plan/ADR-0001 "enum, closed set of 7" call — recorded as
/// ADR-0000 amendment A9.)
extension type const BeadStatus(String wire) {
  static const open = BeadStatus('open');
  static const inProgress = BeadStatus('in_progress');
  static const blocked = BeadStatus('blocked');
  static const deferred = BeadStatus('deferred');
  static const closed = BeadStatus('closed');
  static const pinned = BeadStatus('pinned');
  static const hooked = BeadStatus('hooked');

  /// The seven built-in statuses, in upstream declaration order.
  static const builtIns = <BeadStatus>[
    open,
    inProgress,
    blocked,
    deferred,
    closed,
    pinned,
    hooked,
  ];

  StatusCategory get category => switch (wire) {
    'open' => StatusCategory.active,
    'in_progress' || 'blocked' || 'hooked' => StatusCategory.wip,
    'closed' => StatusCategory.done,
    'deferred' || 'pinned' => StatusCategory.frozen,
    _ => StatusCategory.unspecified,
  };

  /// True only for the terminal `closed` status.
  bool get isClosed => wire == 'closed';

  /// True when this is one of the seven built-in statuses.
  bool get isBuiltIn => builtIns.contains(this);
}
