## 0.5.0-rc.5

- `StationEventLog` + `CompositeExplorationTransport`: a durable, cursored
  sink over the existing `ExplorationTransport.flare` seam, composed beside
  `StationDiagnosticsReporter` (tg-fqif).
- Threshold-gated offline `dolt gc --full` in the up lifecycle (tg-zc6x).

  NOTE: the previous version was published and the package then kept accruing
  source without a bump, so the hosted archive and the in-repo sources at that
  version differed. Local builds passed on path overrides while hosted
  resolves got stale code. This release re-syncs them.

# Changelog

## 0.5.0-rc.4

- Breaking (tg-at3r): the `Resident*` prefix is swept off the vended shell —
  `ResidentUpCommand`→`UpCommand`, `ResidentDownCommand`→`DownCommand`,
  `ResidentStatusCommand`→`StatusCommand`,
  `ResidentStationConfig`→`StationConfig`,
  `ResidentGridRunner`→`GridRunner`,
  `ResidentGridDelegateFactory`→`GridDelegateFactory`, and
  `ResidentLockResource`/`ResidentGridResource`/`ResidentControlResource`/
  `ResidentDevModeResource` drop the prefix. Filenames follow
  (`resident_up_command.dart`→`up_command.dart`, …). Behavior — exit codes,
  stderr text, event and teardown order — is unchanged.
- Breaking (tg-at3r): the delegate contract left this package —
  `ResidentGridDelegate` is folded into grid_sdk's `GridDelegate` (subclass
  that instead), and its supporting types (`StationView`, the
  `StalenessPosture` family, `StationRefusal`, `SubstationConfig`) ride
  grid_sdk's barrel.

## 0.5.0-rc.3

- `StationDiagnosticsReporter` — the ratified diagnostics reporter, armed:
  engine flares as JSON lines + the shared `TreeProjector` feeding `/stream`
  (tg-j4ym); works in JIT and AOT.
- `StationStatus` gains the `sync` payload (per-store `GraphSyncStats` + the
  federation freshness vector) — WHY a sync did or did not happen (tg-zd4v).
- `StationControl`'s internal_error responses carry the bounded exception
  detail instead of a bare 'Command handler failed.'.

## 0.5.0-rc.2

- Fixed: `grid link ls` / `link` / `unlink` crashed with `bd type discovery
  field "custom_types" was not a list` against any store that has no custom
  types. `bd types --json` OMITS an empty group rather than emitting an empty
  list, so the absent key was read as malformed. Absent now means none.
- Fixed: on a store whose types do not include `link`, the scoped read that
  replaced the whole-store export was refused by bd (`invalid issue type`)
  where the export had simply found nothing. A store without the `link` type
  cannot hold link beads, so `link ls` now reports an empty listing and
  `unlink` reports no match, instead of erroring.

## 0.5.0-rc.1

- Breaking: tracks the beads_dart 0.2.0-rc.1 wave. `grid link`, `grid link ls` and
  `grid unlink` are migrated off `BdCliService.exportAll` onto scoped reads, and
  construct `StationBeadWriter` with the required `reader:`.

## 0.4.1

- Bump the family floors onto the 0.2.0 substrate wave: `grid_engine`,
  `grid_exploration`, `grid_sdk` `^0.2.0`; `grid_diagnostics_contract` `^0.2.0`.
  No API changes.

## 0.4.0

- Breaking: `acquire()` establishes and verifies station-owned process
  groups — resident stations own their spawn tree, and `down` kills only the
  station's own group. Callers embedding grid_cli must not assume the old
  detached-spawn behavior.
- Breaking: the exploration surface speaks the `ext.leonard.*` VM-service
  namespace (protocol version 2) via `leonard_contract`; `ext.exploration.*`
  is gone. Attach tooling must be on `leonard_*` 0.2.x.
- Fix: link authoring compiles against the published `beads_dart` — the
  retired `IssueType.link` constant is replaced by the grid-owned
  `GridIssueTypes.link` vocabulary (0.3.0 was broken here at load time).
- Diagnostics ride the `genesis_foundation` substrate (typed tree snapshots
  over the station door).

## 0.3.0

- **Breaking:** `commandHandler` is now REQUIRED on `StationControl.start`.
  Migration: pass the handler vended by grid_sdk ≥0.1.1 —
  `StationControl.start(..., commandHandler: workRuntime.commands)`.
- Added the vended resident station verbs — `ResidentUpCommand`,
  `ResidentDownCommand`, `ResidentStatusCommand`, the resident flag surface,
  and state-workspace/lock resolution — parameterized over a `GridDelegate`
  factory and a verb-name string, so a station composed directly on the_grid
  no longer copies ~1000 lines (the_grid #112).
- Added the fenced station command route on `StationControl` with
  bearer-first routing, monotonic fencing, and cached idempotent dispatch
  (the_grid #106).
- Station control serves tree snapshots; headless projection reads and
  count-gated snapshot streams are fenced by tests (the_grid #110, #113,
  #114, #115).
- Added attributed beyond-cap rework; open gate beads are trusted during
  rework (the_grid #101, #102).

## 0.2.0

- **Breaking:** `StationLockService.acquire` no longer takes a `pgid`
  parameter — the service now establishes the station's own process group
  itself (setsid-own-group before the lock write) and refuses via
  `StationRefusal` when the resolved pgid is not the station pid.
  Migration: drop the `pgid:` argument from `acquire(...)` call sites; if you
  were computing a group id to pass in, delete that code — the recorded
  `pgid` is now always the station's own, verified group.
- `stop()` gains a pgid-gated group signal: when the lock's recorded `pgid`
  matches the live process group, teardown signals the whole group; on
  mismatch it falls back loudly to the previous pid-scoped SIGTERM.
- New: `establishStationProcessGroup` (re-exported), with
  `ProcessGroupController.resolvePgid` as the single source of process-group
  identity; regression test boots from a non-leader parent and asserts the
  recorded group is the station's own tree.

## 0.1.0

- Initial tagged release (tag-pattern version solving).
