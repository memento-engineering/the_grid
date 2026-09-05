## 0.5.0-rc.16

- Added: the `grid/substation/attach` and `detach` control commands decode on the resident door, and `up` renders status from the live roster instead of the launch-time arming (tg-wv9, #282).
- Fixed: `StationDiagnosticsReporter` buckets its 30 s flare rate limit on `nodePath ?? beadId ?? workBeadId ?? sessionId ?? bead`, so refusals for different beads no longer collapse into one line per flare name — the silence that hid two days of mount-eligibility refusals on lunar (tg-ym3t, #333).
- Added: pause and resume verbs for live work sessions (tg-5kb, #334).
- Added: `StationStatus` / `SubstationStatus` carry `mintFailedScopes`, derived from the tree snapshot's `mintFailed` flags, so a dead-minting scope is visible in status (tg-f6r, #335).
- Fixed: `status` distinguishes a slow resident door (`SlowUp`, "station: UP — alive but slow (N s)", soft threshold 3 s, hard bound 15 s, pid probe first) from a dead one, and `/status` serves a cached snapshot refreshed off the request path (tg-k5hl, #337).
- Floors `beads_dart` to `^0.2.0-rc.10`, `grid_engine` to `^0.3.0-rc.20`, `grid_runtime` to `^0.2.0-rc.13` and `grid_sdk` to `^0.3.0-rc.16`.

## 0.5.0-rc.15

- Breaking: `AttachResult.Stale` is replaced by `Starting` (a lock at `acquired` whose pid is alive — the station is booting) and `Unreachable` (a dead pid or an unreachable control endpoint), so a booting station is no longer reported as crashed; every `switch` over the sealed class must name both. Migration: replace the `Stale` arm with `Starting` + `Unreachable`.
- Added: the station lock is stamped with its lifecycle phase — `acquired` at acquire, `live` at `updateControl` (the VM-service attach is an orthogonal flag), `releasing` at release — preserving atomic ownership; `status` reports the phase (tg-g3zx, #322).
- Floor tightened to `grid_diagnostics_contract ^0.2.1`.

## 0.5.0-rc.14

- Added: `asset-catalog` — the union asset catalog served READ-ONLY and resolved offline from the resolved package closure (`AssetCatalogCommand` over `AssetCatalogResolver`), plus the `grid/assets` read on the StationControl surface; `up` composes it (tg-oym2, #320).
- Floors tightened to `grid_sdk ^0.3.0-rc.15` and `grid_engine ^0.3.0-rc.18` so a resolved set is coherent.

## 0.5.0-rc.13

- Added: `grid watch --until <predicate>` — a closed set of typed event predicates with a bounded wait (`--timeout`), distinct exit codes for timeout and broken stream, and NDJSON-safe termination; transition-only semantics, so an operator seat returns when the gate opens instead of polling (tg-u5xt, #297).
- Added: `grid bead board` and `grid bead round` — deterministic operator READ verbs over the resident station (`grid/bead/board` and `grid/bead/round` on the StationControl surface): work across stores with status/blocked/approval filters, and one round's lane verdicts (tg-wk3j, #304).
- `up` retains the Dolt query service's handles until close is confirmed during unwind (tg-gmkt, #296).
- Floors tightened to `grid_runtime ^0.2.0-rc.11`, `grid_engine ^0.3.0-rc.13`, `grid_sdk ^0.3.0-rc.11`, `grid_trajectory ^0.2.0-rc.2`.

## 0.5.0-rc.12

- Breaking: process groups are supervised as groups and exit status is preserved — `SessionOrphaned` is a new `RuntimeEvent` variant (emitted once, NOT terminal: the group stays supervised until it empties or the bounded grace elapses and it is signalled), so exhaustive switches over `RuntimeEvent` need an arm (tg-8kye, #290; `up` supervises process groups). Migration: add `SessionOrphaned()` to every `switch (event)`; power_station#195 is the consumer fix.
- `station.lock` is published atomically: exclusive create, pid/startedAt ownership, hold-never-steal (tg-o2fy, #287).
- Floors tightened to `grid_runtime ^0.2.0-rc.10`, `grid_engine ^0.3.0-rc.12`, `grid_sdk ^0.3.0-rc.10`, `grid_trajectory ^0.2.0-rc.1`.

## 0.5.0-rc.11

- Breaking: `StationKernel` is deleted; `runGrid` is the station's single flush coordinator and now carries the tg-60n fail-closed flush guard (#284). Migration: nothing constructs `StationKernel` in the org — drop any import of it and call `runGrid` (grid_sdk `run_grid.dart`); see decisions/2026-09-02-run-grid-is-the-single-flush-coordinator.
- `up` closes every resident store's query service during unwind (dev-mode dispose, control dispose, grid teardown, projector dispose, then lock release), so the VM exits after `down` instead of idling on ESTABLISHED db-proxy sockets and pinning the VM-service port for the next boot (tg-46q1, #285).
- `stationFlags()` and `UpCommand` take a `defaultHarness`, so a composed station picks its ambient harness independently of the allow list's sort order; the default must be a member of the armed set (#276).
- Floors tightened to `beads_dart ^0.2.0-rc.7`, `grid_runtime ^0.2.0-rc.9`, `grid_engine ^0.3.0-rc.11`, `grid_sdk ^0.3.0-rc.9`, `grid_trajectory ^0.1.2`.

## 0.5.0-rc.10

- Breaking: requires `grid_exploration ^0.3.0-rc.4` (which requires `leonard_contract ^0.2.2` on genesis 0.3.0). Migration: none beyond the constraint. Fixes rc.9, which did not resolve from pub.dev at all: it pinned `genesis_tree ^0.3.0` while `grid_exploration` rc.3 still reached genesis_tree 0.2 through `leonard_contract 0.2.1`, so `dart pub global activate grid_cli 0.5.0-rc.9` failed version solving. The `DevModeHost` import (#249) now also matches the hosted grid_exploration.

## 0.5.0-rc.9

- Breaking: adopts genesis_tree 0.3.0, grid_engine 0.3.0-rc.10 and grid_sdk 0.3.0-rc.8 (#260). Migration: bump `genesis_tree` to `^0.3.0`.
- Trajectory: the Stage 0 substrate (grid_trajectory, the fenced appender, the `traj` verbs, guard CI) and the Stage 1 dual-write shadow window ride the CLI (#241, #242, #245).
- `DevModeSeat` is renamed `DevModeHost` (#249).
- Historical sessions with legacy outcomes are fenced (#232).

## 0.5.0-rc.8

- `VmServiceSession.connect` gains an injectable `VmServiceConnector` seam (defaulting to the existing connector), enabling direct tests of reload-capability classification and isolate selection (#225).

## 0.5.0-rc.7

- `reload` probes the resident's reload capability before sending any reload request and refuses with `ReloadUnsupportedLaunchShape` instead of crashing a non-reloadable resident's kernel service (#219).
- `/status` derives wedge and work visibility from ONE captured snapshot (`wedge.live == work.liveSessions` by construction) and populates per-substation ready/mounted/live rows for every armed store (#221).

## 0.5.0-rc.6

- `up` performs boot-time `types.custom` validation and prints the exact
  missing set beside the banner (#211).
- Floors tightened for train coherence across the rc train:
  `grid_sdk ^0.3.0-rc.5`, `grid_engine ^0.3.0-rc.6`,
  `grid_runtime ^0.2.0-rc.4`, `grid_exploration ^0.3.0-rc.3`,
  `beads_dart ^0.2.0-rc.4`.

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
