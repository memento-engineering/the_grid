import '../projections/convergence.dart';

/// The coexistence partition predicate (ADR-0003 Decision 6 / ADR-0000 A7): the
/// gate that decides which convergence loops the_grid's WRITING runtime may
/// actuate.
///
/// gc's convergence handler assumes a single writer per bead (ADR-0003
/// invariant 7); two reconcilers on one convergence corrupts state for both.
/// While gc and the_grid coexist, the_grid owns a bead/rig set **disjoint** from
/// gc's reconciler — partitioned by rig and/or an explicit ownership marker. The
/// live runtime actuates ONLY loops this predicate accepts; everything else it
/// observes read-only (shadow). The fs adoption ladder (M4-SCOPING) widens this
/// set: observe (M1) → shadow (M2) → drive one owned rig (M3) → cutover per rig
/// (M4f).
///
/// This is a structural safety boundary, not a hint: the writing runtime checks
/// it before every actuation, and shadow mode constructs no writer at all.
abstract interface class OwnershipPredicate {
  /// Whether the_grid owns [convergence] (may write to it).
  bool owns(Convergence convergence);
}

/// Owns nothing — the safe default (pure observation / shadow). Every loop is
/// gc's; the_grid actuates none.
class OwnsNothing implements OwnershipPredicate {
  const OwnsNothing();

  @override
  bool owns(Convergence convergence) => false;
}

/// Owns everything — for tests and hermetic environments where there is no gc.
/// NEVER use against the live `tg` server (the partition rule).
class OwnsEverything implements OwnershipPredicate {
  const OwnsEverything();

  @override
  bool owns(Convergence convergence) => true;
}

/// Owns loops whose `convergence.rig` is in an explicit allow-set — the M3
/// drive-one-owned-rig partition (the_grid's own rig). A loop with no rig is
/// NOT owned (it predates the partition / belongs to the city scope gc runs).
class OwnsRigs implements OwnershipPredicate {
  OwnsRigs(Iterable<String> rigs) : _rigs = rigs.toSet();

  final Set<String> _rigs;

  @override
  bool owns(Convergence convergence) {
    final rig = convergence.metadata.rig;
    if (rig == null || rig.isEmpty) return false;
    return _rigs.contains(rig);
  }
}

/// Owns loops carrying an explicit ownership-marker metadata key set to
/// `the_grid` (e.g. `convergence.owner` / a label) — an alternative partition
/// axis to rig, usable where a rig is not yet assigned. The marker key is
/// configurable; the default is `convergence.owner`.
class OwnsMarked implements OwnershipPredicate {
  const OwnsMarked({
    this.markerKey = 'convergence.owner',
    this.owner = 'the_grid',
  });

  final String markerKey;
  final String owner;

  @override
  bool owns(Convergence convergence) =>
      convergence.metadata.raw[markerKey] == owner;
}
