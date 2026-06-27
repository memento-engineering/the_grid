import 'package:state_notifier/state_notifier.dart';

import '../domain/substation_config.dart';

/// The observable source of the **config axis** for one rig — a [StateNotifier]
/// `SubstationScope` observes.
///
/// Distinct from the work/snapshot axis: config and work are observed by
/// *different* nodes, so a work tick never rebuilds the config scope and a
/// config tick never starts/stops a work effect (the two-axis separation
/// ADR-0007 §6.1 hangs on).
class SubstationConfigNotifier extends StateNotifier<SubstationConfig> {
  /// Creates the notifier seeded with [initial].
  SubstationConfigNotifier(super.initial);

  /// Pushes a new config value (the config source's only write path).
  void push(SubstationConfig config) => state = config;

  /// The current value, read through the public listener API (the `state`
  /// getter is `@visibleForTesting`): subscribe, capture synchronously, remove.
  SubstationConfig get current {
    late SubstationConfig value;
    addListener((config) => value = config, fireImmediately: true)();
    return value;
  }
}
