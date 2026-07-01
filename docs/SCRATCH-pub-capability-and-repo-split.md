# The Pub config (typed domain information) + the repo split (design note)

**Status:** DESIGN — from the direction session with Nico (2026-07-01), after the Dart-runner-model
landed + pushed. **Not an ADR, not ratified.** Doc-before-code; Nico ratifies. Sequences before the
physical repo split it enables; refines the split-deferral notes in
`docs/SCRATCH-dart-runner-and-cli-sdk.md`.

## Why — the linkage reality (surveyed)

- **One pub workspace, `any` internal deps.** All 10 packages resolve each other locally via the
  root `workspace:` + `dependency: <pkg>: any`. Clean *within* one repo.
- **`genesis_tree` is the live pain.** Hosted `^0.1.3`, but developing it alongside the_grid needs a
  `dependency_overrides: genesis_tree: { path: ../genesis/... }` — which **breaks in a per-bead
  worktree** (`.grid/worktrees/<sub>/<bead>` is a deep checkout where `../genesis` doesn't resolve).
  So it's hand-toggled between path (dev) and hosted (worktree / stable).
- **The split makes it structural.** `power_station` → `the_grid`; `space_station` → both. A single
  workspace + `any` can't span three repos — each needs path deps (dev) or hosted/git refs (stable) +
  overrides, and the **self-hosting loop builds in deep worktrees** where relative paths don't
  resolve. Managed by hand across three repos, this doesn't scale.

## The Pub domain = typed CONFIGURATION + env, NOT tools (Nico redline, 2026-07-01)

- **Agents don't invoke it — at the moment.** The first framing ("a capability agents invoke") was
  wrong. What Nico wants is **configuration and env**, not tool calls: the domain's value is
  **serializing/deserializing its OWN information with structure + type safety** (the house freezed
  + json_serializable codec style), where the loose alternative is untyped metadata.
- **The natural store is the bead** — "that's really what it would be": the pub-linkage information
  hangs on a bead, typed by the domain's codec. A full "Pub domain" may be **overkill**; it earns
  itself only through the typed codec + the pure context-application logic, not through machinery.
- **Two open sub-problems it must settle:** WHERE the serialized domain information is stored (which
  bead — the substation/config bead, since linkage is project-level not per-work-bead? what key
  namespace — disjoint from the `grid.cursor.*`/`grid.result.*` codec, and NEVER a gc-owned key), and
  **pack/asset versioning** (a domain's serialized shape evolves with its pack version — the codec
  needs a version discriminator).
- **Tool exposure, if ever, rides the shared/exported Commands** (the CLI-SDK model — command
  sharing); **MCP maybe in the future; NO tools now.**
- **The layering requirement (Nico — applies to ALL exported Commands):** the functionality behind a
  Command must be layered so **a Flutter app could execute it via UI** — logic is NEVER coded
  directly on the CLI Command. A Command is a thin adapter (a *view*, in predictable-flutter terms)
  over reusable lib logic (services/interactors). *Audit note: `StationRunCommand`→`runGridTree`
  already complies (thin over a lib function); `LeaseCommand`/`ServeCommand` currently inline their
  logic in `run()` — an extraction follow-up.*

## What the typed config does

Given a **context** — local dev / deep per-bead worktree / stable — the pure logic derives the
correct linkage for each cross-repo dep (**path override for dev, hosted/git ref otherwise**) and
materializes it (a `pubspec_overrides.yaml`, which pub honors from any depth and which melos 7 no
longer owns — see below). That dissolves the `genesis_tree` hand-toggle, the deep-worktree `../`
break, and the post-split cross-repo linkage: **the config is data on a bead; applying it is a pure
function + a file write.** Do the config FIRST, split SECOND.

## The repo split (target — physical move is the second step)

| Repo | Holds |
|---|---|
| `the_grid` | kernel + SDK + core toolchain (engine/controller/runtime/reconciler/exploration/devtools/federation) + the **CLI-SDK** (grid_cli's `StationRunCommand`/`composeStation` lib) |
| `power_station` | first-party assets: `grid_assets` (code/compute), `butane_grid_assets` (burn), **`dart_grid_assets`** (the Pub capability + build/test), `flutter_grid_assets`; **`CodeRunCommand` moves here** (the `grid_cli`↔`grid_assets` cycle resolves once the CLI-SDK is a `the_grid` lib `power_station` depends on) |
| `space_station` | memento's runner (`main.dart`) + config — assembles the Commands it wants, AOT-compiled |

**Split mechanics (resolved, Nico 2026-07-01): PER-REPO workspaces.** Melos does NOT do cross-repo:
melos 7 dropped its own linking (`pubspec_overrides.yaml` generation) and rides **pub workspaces**,
which are strictly single-tree (a package finds its workspace by walking UP parent directories, so
members must live under the root). The only pub mechanisms that cross a repo boundary are
`pubspec_overrides.yaml` path overrides (honored from any depth, can point anywhere) and hosted/git
deps — exactly what the typed Pub config manages. An umbrella-root workspace spanning the clones is
expressible but wrong (the umbrella isn't a repo; one coupled constraint-solve; a deep per-bead
worktree still falls outside it). So: **each repo its own pub workspace + melos; cross-repo linkage =
the Pub config applied by context** (the genesis ADR-0001 D8 path-dev/published-stable convention,
made data + a pure function).

## The re-targeted first live-arm (downstream — noted, not this note's scope)

**mac + iPad over REAL BLE, LOCAL lease on this box.** Leverages the single-station core lease
(no cross-machine bus) + butane's native macos/ios targets + Apple-native BLE (mac↔iPad, no Linux
BlueZ) — sidesteps the entire Linux env risk. Still needs the burn's live entry point built
(an asset run-command + a real macOS `FollowerLauncher` + a `ProcessLeonardDrive` adapter over
lenny's `leonard_drive` binary). The live burn stays the **human gate**.

## Build order

1. **Prototype the typed DART-domain config** — **in `grid_assets`, split later (Nico)**: the
   freezed value types (per-dep linkage: package, hosted constraint, dev path, git ref) + the
   versioned **`grid.dart` envelope codec** (serialize/deserialize off the WORK bead's metadata;
   `assets_version` discriminator) + the PURE context-application logic (context →
   `pubspec_overrides.yaml` content) + a thin exported `Command` over a lib-layer service (the
   UI-drivable layering). the_grid READS the envelope at provision time (A37: never a controller
   write to the foreign work bead). Offline: temp pubspecs/worktrees; no live `pub publish`.
2. **The repo split** (`the_grid`/`power_station`/`space_station`) — per-repo workspaces; cross-repo
   linkage via the Pub config; `CodeRunCommand` → the code asset; the CLI-SDK extraction; the config
   prototype moves to `dart_grid_assets`.
3. **(Downstream)** the mac+iPad real-BLE burn arm (local lease on this box).

## Resolved (Nico, 2026-07-01)

- **Not tools — configuration + env.** Agents don't invoke it (now); typed serialize/deserialize is
  the point; the bead is the store. Tool exposure, if ever, via the shared/exported Commands; MCP
  maybe later.
- **Layering:** Command logic must be UI-drivable (a Flutter app could execute it) — thin Commands
  over lib logic, never logic on the Command.
- **Prototype in `grid_assets`, split later.**
- **Per-repo workspaces** (melos has no cross-repo; pub workspaces are single-tree).

## Resolved round 2 (Nico, 2026-07-01)

- **Storage home = the WORK BEAD** (bead/work information) — NOT the substation/config bead. The
  substation already defines its location and the bead defines its own worktree; **those are
  projections**. The config declares only "the desire to dev-time link the two." Consequence: it is
  part of the **work definition** (authored with the bead, like `design`/`validation_plan` were on
  tg-sm4); the_grid only **READS it at provision time** — so **A37 holds by construction** (never a
  controller write to the foreign work bead).
- **Namespace = `grid.dart.*`** (or `grid.dart.pub.*` if the extra level is needed). The load-bearing
  point: **Pub domains/commands don't work without Dart domains/commands** — Pub is subordinate to
  the DART domain; the Dart domain is the unit.
- **Versioning — the metadata facts (verified):** no custom bead columns (bd owns the schema; no SQL
  writes). One `metadata` JSON object per bead, `Map<String, dynamic>` (nested values fine), and bd's
  `--metadata '<json>'` **merges at TOP-LEVEL-KEY granularity** — so *everyone can get a slot* (per
  top-level key). Grades are flat `grid.result.{nodePath}.{field}` keys precisely because concurrent
  critics need per-field slots. **Rule of thumb:** concurrent-writer state → FLAT dotted keys (the
  cursor/result pattern); single-writer domain config → **one ENVELOPE key per domain** (Nico's
  sketch), replaced whole on write:
  ```json
  {
    "grid.dart": { "assets_version": "0.0.1", "payload": { } }
  }
  ```
  (`assets_version` = the pack's codec version discriminator. **`packs_version` corrected (Nico,
  round 3): it belongs ONLY to TOML packs implementing the gc packs protocol — a plain Dart-asset
  domain like `grid.dart` does not carry it**; a future TOML codec adds it. The envelope machinery is
  SHARED (`grid_assets/src/domain/domain_envelope.dart`, power_station-common at the split) and the
  version gate rides `pub_semver` — no hand-rolled semver.) Mechanical note: the chokepoint types metadata
  `Map<String, String>` today (BdCliService already takes `Map<String, dynamic>` + jsonEncodes) — a
  small widening if a CONTROLLER write ever carries an envelope; for THIS config it's read-only to
  the_grid, so no chokepoint change is needed.
- **`LeaseCommand`/`ServeCommand` extraction = a SEPARATE cleanup.** "The interface implementations
  should be thin and the repos/state should be elsewhere. We still write maintainable software here."

## Safety rails (carried)

Offline (temp pubspecs/worktrees; no live `pub publish`/network); doc-before-code; **Nico ratifies**;
the live mac+iPad burn is the human gate.
