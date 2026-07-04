/// the_grid **CLI SDK** — the reusable CLI components a station runner assembles
/// (the Dart runner model — see `docs/SCRATCH-dart-runner-and-cli-sdk.md`).
///
/// `the_grid` is a framework, not a turnkey tool: a station is a user-composed,
/// AOT-compiled runner (`main.dart` + `dart compile exe`) that builds a
/// `CommandRunner` from the Commands it wants — the generic ones here plus its
/// assets' Commands. There is no baked-in `grid run` and no run BASE CLASS
/// (ADR-0008 Decision 2, amended 2026-07-02 — consumers compose, never
/// subclass): an asset's runner calls the station-runner LIBRARY PIECES in
/// order — `addStationFlags`/`StationArgs` → `validateArming` →
/// `discoverWorkspaces` → `buildControllers` → `buildLiveWiring` → its OWN
/// `ServiceBundle` → `composeStation` (+ `wrapRoot` for its ambient config
/// providers) → `driveStation`. (`CodeRunCommand` lives in `power_station`'s
/// `grid_assets`; `ServeCommand`/`LeaseCommand` live in its
/// `federated_grid_assets` (AL-5b, D-A9); memento's assembled runner is
/// `space_station`.)
library;

// The station-runner library pieces (the composition inversion, 2026-07-02).
export 'src/station_attach.dart';
export 'src/station_control.dart';
export 'src/station_lock.dart';
export 'src/station_runner.dart';

// The generic, asset-agnostic driving commands.
export 'src/watch_command.dart';
export 'src/gate_command.dart';
export 'src/rework_command.dart';
export 'src/demo_command.dart';
