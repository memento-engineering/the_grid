import '../work/work_assembly.dart' show SubstationWorkSpec;

/// One runtime-attached substation seat in the appended roster layer.
class RosterSeat {
  /// Creates a seat for [spec]. A non-empty [drainIds] marks it draining.
  const RosterSeat(this.spec, {this.drainIds = const <String>{}});

  /// The substation's assembly identity.
  final SubstationWorkSpec spec;

  /// While draining, the only work-bead ids this seat may still mount.
  final Set<String> drainIds;

  /// Whether this seat is draining toward detach.
  bool get isDraining => drainIds.isNotEmpty;

  /// Returns this seat narrowed to [ids].
  RosterSeat draining(Set<String> ids) => RosterSeat(spec, drainIds: ids);
}

/// The runtime-attached roster as an observed tree value.
class AttachedRoster {
  /// Creates an immutable roster over [seats].
  AttachedRoster(List<RosterSeat> seats)
    : seats = List<RosterSeat>.unmodifiable(seats);

  /// The empty attached layer.
  static final AttachedRoster empty = AttachedRoster(const <RosterSeat>[]);

  /// Seats in attach order.
  final List<RosterSeat> seats;

  /// The seat named [name], or null when no attached seat has that name.
  RosterSeat? seatOf(String name) {
    for (final seat in seats) {
      if (seat.spec.name == name) return seat;
    }
    return null;
  }
}

/// The drain narrowing observed by [SubstationWork].
class SubstationDrain {
  /// Creates a narrowing to [beadIds]; empty means not draining.
  const SubstationDrain(this.beadIds);

  /// Work-bead ids still permitted to mount.
  final Set<String> beadIds;

  @override
  bool operator ==(Object other) =>
      other is SubstationDrain &&
      other.beadIds.length == beadIds.length &&
      other.beadIds.containsAll(beadIds);

  @override
  int get hashCode => Object.hashAllUnordered(beadIds);
}
