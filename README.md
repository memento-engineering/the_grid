# the_grid

A Dart-native reactive orchestrator for multi-agent software development, built to
replace [Gas City](https://docs.gascityhall.com) over a [beads](https://github.com/steveyegge/beads)
work graph. Part of a long-term bet on Dart as a full-stack agentic platform:

> Apps are built in Flutter. Lenny drives and debugs the apps. Lenny files bugs as beads
> into the grid. **The grid builds everything.**

the_grid is a **framework, not a turnkey tool**. A deployed station is a user-composed
runner: a `main.dart` that authors its station as a tree on `grid_sdk` and assembles the
CLI commands it wants. The `grid` binary here is deliberately minimal — the generic,
asset-agnostic verbs only.

## The system

- **The work graph is observed, not polled.** A `bd` mutation raises a dirty signal
  (Dolt `@@<db>_working` probe or file watcher) → single-flight re-query → structural
  diff → typed `GraphEvent`s. `grid demo` proves the loop with measured per-event latency.
- **The running grid IS a tree** (ADR-0007/0009). `genesis_tree` is the engine:
  `build(observed)` reconciles the running system — keyed reconcile + Branch lifecycle
  *is* the work lifecycle (**mount = spawn, unmount = kill**). State rides
  `StateNotifier`s provided via `InheritedSeed` (Riverpod was dropped at ADR-0007).
- **Work runs as circuits.** A mounted work bead inflates a `Circuit` — a value-typed
  step-graph — into a reconciled subtree (`SessionScope → CircuitScope → CapabilityHost`);
  steps are nodes driven by opaque `Capability` leaves, so supervision, restart, and
  cursor semantics apply at every depth (ADR-0008's reentrant engine).
- **A resident station drives the ready frontier.** `runGrid(delegate)` mounts the
  authored tree; each substation's open, unblocked, undeferred beads ARE the drive set
  (there is no `--bead` drive-list). Per ready bead the station provisions a git worktree
  (branch `grid/<bead>`), spawns a build agent, gates the result with a committee of
  critic lanes, and lands (rebase → revalidate → commit/push/PR). Delivery is a
  **per-substation binding** authored in the station tree — the old global `--land`
  flag is retired.
- **Beads all the way down.** Sessions, circuit instances, and committee gates are
  themselves beads (per-node progress cursors ride the session bead), written to the
  station's *own* state store through the single `StationBeadWriter` chokepoint (bd CLI
  only, never SQL); work sources are never written (the A37 split). Molecule mode — the
  circuit instance persisted as a durable `molecule`/`step` bead graph — is the live
  default at the work seat.
- **Opinions live in asset packs, never in the engine.** The engine knows source
  control, agents, and trust in *concept*; the code circuit, committee rubrics, landing,
  and agent harnesses ship as `*_grid_assets` packs a station composes in.

## Packages

| Package | Role |
|---|---|
| `beads_dart` | Pure-Dart beads client: `Bead`/`GraphSnapshot` models, envelope codec, bd CLI wrapper + pooled Dolt SQL read path, watchers, structural diff → typed `GraphEvent` stream. Framework-free; pinned against bd 1.0.5 |
| `grid_engine` | The private tree engine (never imported by consumers): the `Station → Substation → WorkList → WorkBead → SessionScope → CircuitScope → CapabilityHost` tree on `genesis_tree`, the join bridge (the lone pipeline subscription), the molecule model, restart respawn-or-skip, wedge detection |
| `grid_sdk` | The public authoring surface: composition Seeds (`RawAssetGrid`/`Station`/`Substations`/`Substation`), `runGrid` + `GridDelegate`, stores-at-roots, the `StationWork`/`SubstationWork` work binding. One import authors a station (re-exports `genesis_tree`) |
| `grid_runtime` | The hands: the `SubprocessProvider` process transport (the only `RuntimeProvider` — ADR-0004's `TmuxProvider` was never built), `StationGitService` git-worktree-per-bead isolation + the land step, lifecycle-as-beads through the `StationBeadWriter` chokepoint |
| `grid_cli` | The CLI SDK a composed runner assembles: the generic verbs (`watch`/`gate`/`rework`/`demo`), the dev-mode `reload` command a runner binds, and the resident-station lock/control/attach pieces. Ships the minimal generic `grid` bin |
| `grid_exploration` | Exploration-protocol host: registers `ext.exploration.*` over the Dart VM service so exploration clients (lenny) can observe and drive a running station; carries the hot-reload `ReassembleTool` |
| `grid_devtools` | DevTools extension (the only Flutter package — test it with `flutter test`, not `dart test`) — attaches over the exploration protocol only, no direct `beads_dart` dependency |

## Quickstart

```bash
dart pub get                   # pub workspace — resolves every package
dart run melos run test        # offline unit suite (integration-tagged tests need bd/Dolt)
dart run melos run analyze

# Zero-setup reactivity proof (needs `bd` on PATH, no credentials):
dart run grid_cli:grid demo

# Watch a real substation's work graph — typed events with reaction latency.
# Takes the substation ROOT (its work store lives at <root>/.beads/):
dart run grid_cli:grid watch <substation-root>
```

`grid gate` lists/resolves the committee gates a circuit parks; `grid rework <bead>`
mints a fresh round for a gated bead. Run a station under
`dart run --enable-vm-service` (JIT) to let exploration tools attach; a composed
runner binds the exported `reload` command to hot-swap a resident JIT station's
sources without a bounce (live sessions are adopted, never killed).

## Reading order

| Doc | What |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Session contract: process rules, conventions, and the running build log |
| [`docs/PDR.md`](docs/PDR.md) | Vision, goals, milestones, acceptance criteria, the gate |
| [`docs/GLOSSARY.md`](docs/GLOSSARY.md) | Status-tagged index of the vocabulary and flows — records where docs and code disagree |
| [`docs/adr/ADR-0000…`](docs/adr/ADR-0000-ai-decision-register.md) | **AI decision register** — pending AI decisions live here until promoted or rejected |
| [`ADR-0001…0004`](docs/adr/) | Foundations · package topology + projections · convergence port · runtime providers/tmux |
| [`ADR-0006`](docs/adr/ADR-0006-dogfood-rig-and-live-write-authorization.md) | Dogfood rig + live-write authorization |
| [`ADR-0007`](docs/adr/ADR-0007-tree-engine-and-genesis-supersession.md) | The engine pivot: `genesis_tree` IS the engine; Riverpod → `StateNotifier` |
| [`ADR-0008`](docs/adr/ADR-0008-authoring-sdk-and-reentrant-engine.md) | Authoring SDK + reentrant engine: Station/Substation/Asset, compose-never-subclass |
| [`ADR-0009`](docs/adr/ADR-0009-the-allocation-tree.md) | The Allocation Tree — the_grid's "third tree" of live effects |
| [`ADR-0011`](docs/adr/ADR-0011-federation-and-asset-management.md) | Federation + asset management (leasing resources across stations) |
| [`ADR-0012`](docs/adr/ADR-0012-observability.md) | Observability (partial — the LAN cockpit slice is ratified) |
| [`ADR-0013`](docs/adr/ADR-0013-state-holding-value-types.md) | State-holding value types (draft direction) |

ADR-0005 was retired by ADR-0007; ADR-0010 is reserved, unwritten. The
`docs/M*-BUILD-ORDER.md` files are the dependency-ordered implementation plans each
milestone executed.

`docs/SCRATCH-*.md` files are **pre-ratification design surfaces** — live working
documents, each carrying its own status line. The lifecycle is deliberate: a design
converges on a SCRATCH surface, its decisions ratify into an ADR, and the surface is
then retired to git history. What you see mid-flight is real, current design work.

## Sibling repositories

the_grid is one repo of the [memento-engineering](https://github.com/memento-engineering)
org. Docs here reference siblings by name:

- [`power_station`](https://github.com/memento-engineering/power_station) — the
  Packaged-AI-Asset packs (the `code` circuit's committee, skills, and overlays).
- [`space_station`](https://github.com/memento-engineering/space_station) — the 
  org's grid *instance*: composition + config over this repo's CLI-SDK.
- [`lenny`](https://github.com/memento-engineering/lenny) — the debugging harness that
  attaches to a running station over the VM service.
- **houston** is not a repo — it is the id prefix of the station's *state store* (the
  Dolt database holding session/lifecycle beads).
- **Gas City** (`gc`) is the predecessor system this project reimplements in Dart. It
  is not ours: see the original project's docs at
  [docs.gascityhall.com](https://docs.gascityhall.com). References here describe port
  lineage, not a dependency.

## License

MIT — see [LICENSE](LICENSE).
