/// the_grid **CLI SDK** — the reusable CLI components a station runner assembles
/// (the Dart runner model — see `docs/adr/ADR-0008-authoring-sdk-and-reentrant-engine.md`).
///
/// `the_grid` is a framework, not a turnkey tool: a station is a user-composed,
/// AOT-compiled runner (`main.dart` + `dart compile exe`) that builds a
/// `CommandRunner` from the Commands it wants — the generic ones here plus its
/// assets' Commands. There is no baked-in `grid run` and no run BASE CLASS
/// (ADR-0008 Decision 2, amended 2026-07-02 — consumers compose, never
/// subclass): an asset's runner authors its station as a `GridDelegate`, mounts
/// it with `grid_sdk`'s `runGrid`, and drives its stores off their roots
/// (`grid_sdk` `StoreLocator`). The old `station_runner` boot path
/// (`StationArgs` / `RootSpec` / `discoverWorkspaces` / `buildControllers` /
/// `buildLiveWiring` / `composeStation` / `driveStation`) is DELETED (DoD#6);
/// what survives here are the resident-station RS-2/RS-4 pieces below plus the
/// generic verbs. (`CodeRunCommand` lives in `power_station`'s `grid_assets`;
/// memento's assembled runner is `space_station`.)
library;

// The resident-station survivors (RS-2 lock / RS-4 read-only control / RS-5a
// attach client) an asset runner orchestrates around `runGrid`.
export 'src/station_attach.dart';
export 'src/station_control.dart';
export 'src/station_lock.dart';
// The dev-mode reload client: a JIT station picks up landed code changes over
// its VM service, with no down/up bounce and no killed agents.
export 'src/station_reload.dart';

// The generic, asset-agnostic driving commands.
export 'src/reload_command.dart';
export 'src/watch_command.dart';
export 'src/gate_command.dart';
export 'src/rework_command.dart';
export 'src/demo_command.dart';
