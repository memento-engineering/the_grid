import 'package:genesis_tree/genesis_tree.dart';

import '../domain/substation_config.dart';
import 'work_list.dart';

/// A single rig's work root. Reads its ambient [SubstationConfig] (provided by the
/// enclosing `SubstationScope`) and builds the rig's [WorkList].
///
/// It does NOT observe the work/snapshot axis — so a work tick never rebuilds
/// it (the derailment-invariant-1 guardrail: only the observing node, the
/// `WorkList`, marks dirty). A config change reaches it via the
/// `InheritedSeed<SubstationConfig>` dependency (`dependencyChanged`), the config
/// axis, which is exactly when it *should* rebuild.
class Substation extends StatefulSeed {
  /// Creates a rig node, optionally [key]ed.
  const Substation({super.key});

  @override
  State<Substation> createState() => _SubstationState();
}

class _SubstationState extends State<Substation> {
  late SubstationConfig _config;

  @override
  void didChangeDependencies() {
    // Reading SubstationConfig here (not initState) registers this branch as a
    // dependent of the ambient InheritedSeed<SubstationConfig>, so a config change
    // re-runs didChangeDependencies and rebuilds — the config axis.
    _config = context.dependOnInheritedSeedOfExactType<SubstationConfig>()!;
  }

  @override
  Seed build(TreeContext context) {
    // Pass config DOWN as data: the WorkList depends on the work axis only, not
    // on the SubstationConfig inherited value, so config and work stay separate.
    return WorkList(substationConfig: _config);
  }
}
