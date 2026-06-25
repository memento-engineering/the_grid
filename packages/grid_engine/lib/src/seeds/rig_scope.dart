import 'package:genesis_tree/genesis_tree.dart';
import 'package:state_notifier/state_notifier.dart';

import '../domain/rig_config.dart';
import '../notifiers/rig_config_notifier.dart';
import 'rig.dart';

/// The per-rig **config scope** — an ancestor of the rig's work nodes
/// (ADR-0007: config nodes are ancestors of work nodes).
///
/// It OBSERVES the rig's [RigConfigNotifier] (the config axis, separate from
/// the work/snapshot axis) and re-provides the current [RigConfig] ambiently
/// via `InheritedSeed<RigConfig>` to the work subtree below it.
///
/// Because the config and work axes are observed by *different* nodes, a work
/// tick never rebuilds this scope ([buildCount] stays put), and a config tick
/// never starts/stops a work effect. That separation is the load-bearing claim
/// of ADR-0007 §6.1.
///
/// P0 assumption: the [RigConfigNotifier] *instance* is stable for the scope's
/// lifetime (the kernel builds it once). genesis `State` has no
/// did-update-config hook, so a swapped notifier instance would not re-bind;
/// that does not occur in P0.
class RigScope extends StatefulSeed {
  /// Creates a scope driven by [configNotifier]. Key it by rig id at the Grid
  /// level so a rig add/remove mounts/unmounts exactly this scope.
  const RigScope({required this.configNotifier, super.key});

  /// The config-axis source this scope observes.
  final RigConfigNotifier configNotifier;

  @override
  State<RigScope> createState() => _RigScopeState();
}

class _RigScopeState extends State<RigScope> {
  RemoveListener? _remove;
  late RigConfig _config;

  @override
  void initState() {
    _config = seed.configNotifier.current;
    _remove = seed.configNotifier.addListener(
      (config) => setState(() => _config = config),
      fireImmediately: false,
    );
  }

  @override
  void dispose() {
    _remove?.call();
    _remove = null;
  }

  @override
  Seed build(TreeContext context) {
    return InheritedSeed<RigConfig>(
      value: _config,
      child: Rig(key: ValueKey('rig.${_config.rigId}')),
    );
  }
}
