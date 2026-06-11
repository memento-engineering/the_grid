/// Exploration-protocol host for the_grid.
///
/// Hosts a GridControllerPlugin speaking lenny's `ext.exploration.*` wire
/// protocol (handshake / get_stable_observation / namespaced tools) via
/// `dart:developer` service extensions. Until lenny's exploration_contract
/// extraction lands (lenny M0), wire shapes are mirrored here and verified
/// against lenny source. See ADR-0001 Decision 6.
library;

export 'src/grid_controller_plugin.dart';
export 'src/grid_exploration_host.dart';
export 'src/grid_exploration_protocol.dart';
