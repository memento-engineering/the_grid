/// the_grid **CLI SDK** — the reusable CLI components a station runner assembles
/// (the Dart runner model — see `docs/SCRATCH-dart-runner-and-cli-sdk.md`).
///
/// `the_grid` is a framework, not a turnkey tool: a station is a user-composed,
/// AOT-compiled runner (`main.dart` + `dart compile exe`) that builds a
/// `CommandRunner` from the Commands it wants — the generic ones here plus its
/// assets' Commands. There is no baked-in `grid run`; the de-opinionated
/// [StationRunCommand] base takes the asset trio (resolver + registry) as
/// configuration, and each asset offers a configured run command
/// ([CodeRunCommand] is the `code` asset's — it moves to `power_station` at the
/// repo split, when the CLI SDK becomes a framework lib the asset can depend on).
library;

// The de-opinionated run base + the pure composition seam (the asset trio in).
export 'src/station_run_command.dart';
export 'src/run_tree_command.dart' show composeStation, runGridTree, TreeRunWiring;
export 'src/run_command.dart' show RuntimeProviderKind;

// The code asset's run command (here for now — the cycle keeps it out of the
// code asset until the split).
export 'src/code_run_command.dart';

// The generic, asset-agnostic driving commands.
export 'src/watch_command.dart';
export 'src/gate_command.dart';
export 'src/serve_command.dart';
export 'src/lease_command.dart';
export 'src/demo_command.dart';
