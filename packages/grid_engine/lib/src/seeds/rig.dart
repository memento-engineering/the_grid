import 'package:genesis_tree/genesis_tree.dart';

import '../domain/rig_config.dart';
import 'work_list.dart';

/// A single rig's work root. Reads its ambient [RigConfig] (provided by the
/// enclosing `RigScope`) and builds the rig's [WorkList].
///
/// It does NOT observe the work/snapshot axis — so a work tick never rebuilds
/// it (the derailment-invariant-1 guardrail: only the observing node, the
/// `WorkList`, marks dirty). A config change reaches it via the
/// `InheritedSeed<RigConfig>` dependency (`dependencyChanged`), the config
/// axis, which is exactly when it *should* rebuild.
class Rig extends StatefulSeed {
  /// Creates a rig node, optionally [key]ed.
  const Rig({super.key});

  @override
  State<Rig> createState() => _RigState();
}

class _RigState extends State<Rig> {
  late RigConfig _config;

  @override
  void didChangeDependencies() {
    // Reading RigConfig here (not initState) registers this branch as a
    // dependent of the ambient InheritedSeed<RigConfig>, so a config change
    // re-runs didChangeDependencies and rebuilds — the config axis.
    _config = context.dependOnInheritedSeedOfExactType<RigConfig>()!;
  }

  @override
  Seed build(TreeContext context) {
    // Pass config DOWN as data: the WorkList depends on the work axis only, not
    // on the RigConfig inherited value, so config and work stay separate.
    return WorkList(rigConfig: _config);
  }
}
