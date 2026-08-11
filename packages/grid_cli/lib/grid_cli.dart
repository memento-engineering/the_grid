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

export 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;

// The resident-station survivors (RS-2 lock / RS-4 read-only control / RS-5a
// attach client) an asset runner orchestrates around `runGrid`.
export 'src/station_attach.dart';
export 'src/station_control.dart';
export 'src/station_command_client.dart';
export 'src/hooks_resolver.dart';
export 'src/station_lock.dart';
// The dev-mode reload client: a JIT station picks up landed code changes over
// its VM service, with no down/up bounce and no killed agents.
export 'src/station_reload.dart';
// The delegate contract itself lives in grid_sdk (tg-at3r): `GridDelegate`
// absorbed the old `ResidentGridDelegate` hooks, and its supporting types
// (`StationView`, the `StalenessPosture` family, `StationRefusal`,
// `SubstationConfig`) ride grid_sdk's barrel. This library keeps the SHELL:
// the up/down/status commands and their seams.
export 'src/station_flags.dart';
export 'src/state_workspace.dart';
export 'src/state_store_gc.dart'
    show
        DirectorySizeReader,
        MaintenanceClock,
        MaintenanceProcessRunner,
        MaintenanceSink,
        StateStoreGc,
        kStateStoreGcThresholdBytes;
export 'src/up_command.dart';
export 'src/diagnostics_reporter.dart';
export 'src/down_command.dart';
export 'src/status_command.dart';

// The generic, asset-agnostic driving commands.
export 'src/reload_command.dart';
export 'src/watch_command.dart';
export 'src/gate_command.dart';
export 'src/rework_command.dart';
export 'src/bead_command.dart';
export 'src/demo_command.dart';
export 'src/link_command.dart'
    show LinkCommand, LinkEndpointStore, UnlinkCommand, runLink, runUnlink;
