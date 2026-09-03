import 'package:genesis_tree/genesis_tree.dart';
// The SDK already vends this engine-private provider vocabulary as its public
// composition bridge; roster composition uses that same pinned seam.
// ignore: implementation_imports
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:state_notifier/state_notifier.dart' show RemoveListener;

import '../composition/composition.dart' show Substations;
import 'roster_seat.dart';
import 'substation_roster.dart';

/// Builds the substation subtree for one attached [seat].
typedef AttachedSubstationBuilder = Seed Function(RosterSeat seat);

/// Observes a roster and provides only its emitted value to the tree.
class SubstationRosterScope extends StatefulSeed {
  /// Observes [roster] over [child].
  SubstationRosterScope({required this.roster, required this.child, Key? key})
    : super(key: key ?? ValueKey<SubstationRoster>(roster));

  /// The off-tree roster owned by the station runtime.
  final SubstationRoster roster;

  /// The subtree receiving the observed value.
  final Seed child;

  @override
  State<SubstationRosterScope> createState() => _SubstationRosterScopeState();
}

class _SubstationRosterScopeState extends State<SubstationRosterScope> {
  RemoveListener? _remove;
  late AttachedRoster _roster;

  @override
  void initState() {
    var seeded = false;
    _remove = seed.roster.addListener((value) {
      if (!seeded) {
        seeded = true;
        _roster = value;
        return;
      }
      setState(() => _roster = value);
    });
  }

  @override
  void dispose() {
    _remove?.call();
    _remove = null;
  }

  @override
  Seed build(TreeContext context) =>
      Provider<AttachedRoster>.value(_roster, child: seed.child);
}

/// Fans the runtime-attached roster out as keyed substation subtrees.
class AttachedSubstations extends StatelessSeed {
  /// Creates the fan-out using [builder] for each seat.
  const AttachedSubstations({required this.builder, super.key});

  /// Builds one attached substation subtree.
  final AttachedSubstationBuilder builder;

  @override
  Seed build(TreeContext context) {
    final roster = context.watch<AttachedRoster>() ?? AttachedRoster.empty;
    return Substations(
      substations: <Seed>[
        for (final seat in roster.seats)
          Provider<SubstationDrain>.value(
            SubstationDrain(seat.drainIds),
            key: ValueKey<String>('attached:${seat.spec.name}'),
            child: builder(seat),
          ),
      ],
    );
  }
}
