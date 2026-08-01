/// Exploration-protocol host for the_grid.
///
/// Hosts a GridControllerPlugin speaking Leonard's `ext.leonard.*` wire
/// protocol through `dart:developer` service extensions. Leonard owns the
/// shared extension prefix and protocol version; grid_exploration owns the
/// grid namespace, host behavior, and grid-specific wire shapes.
library;

export 'package:leonard_contract/leonard_contract.dart'
    show kLeonardExtensionPrefix, kLeonardProtocolVersion;

export 'src/dev_mode.dart';
export 'src/grid_controller_plugin.dart';
export 'src/grid_exploration_host.dart';
export 'src/grid_exploration_protocol.dart';
export 'src/reassemble_tool.dart';
