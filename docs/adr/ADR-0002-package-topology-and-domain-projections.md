# ADR-0002 — Package topology and reactive domain projections

**Status:** Accepted 2026-06-11 (Nico)
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** ADR-0001 fixed the layering and substrate. This ADR fixes the package map (names set by Nico, 2026-06-11) and the requirement that **every grid domain gets reactive, typed views** — not just raw beads.

---

## Decision 1 — Package topology

| Package | Role | Milestone | Notes |
|---|---|---|---|
| **`grid_controller`** | The SDK. Domain models (freezed), services (`BdCliService`, `DoltQueryService`, dirty-signal sources), `BeadsRepository`, interactors, selectors/projections, Riverpod providers. | M1 | Pure Dart, no Flutter. Everything else depends on it. |
| **`grid_cli`** | Management CLI (`grid watch`, later `grid status`, `grid doctor`, …). | M1 | `args`-based; runs under `--enable-vm-service`. |
| **`grid_exploration`** | The lenny plugin: `GridControllerPlugin` + the minimal pure-Dart host registering the three `ext.exploration.*` extensions. | M1 | Depends on lenny's `exploration_contract` (M0 extraction) + `grid_controller`. |
| **`grid_devtools`** | DevTools extension for the grid: events timeline, ready queue, graph/domain inspectors. | Scaffold in M1 (timeline panel); richer panels M2+ | Flutter web (`devtools_extensions`) — the only Flutter-dependent package in the workspace. Talks to the process exclusively over the exploration protocol. |
| **`grid_reconciler`** | M2: the convergence state machine (`DesiredState`, transitions, actions) — see ADR-0003. | M2 | Pure Dart; consumes `grid_controller` events/snapshots, actuates via its mutation services. |
| **`grid_runtime`** | M3: runtime providers (tmux, subprocess) — see ADR-0004. | M3 | Pure Dart; `TmuxProvider` is built on the `tmux` package. |
| **`tmux`** | Standalone, general-purpose tmux client for Dart: command layer (Futures) + reactive layer (Streams) — see ADR-0004 Decision 2. | M3 | **Zero grid dependencies**; pub.dev candidate. |

Dependency direction (longevity outward-in, per predictable-flutter):

```
grid_cli ──┐
grid_exploration ──┤──► grid_controller ◄── grid_reconciler ◄── grid_runtime ──► tmux
grid_devtools ─────┘         (sdk)                                (actions spawn sessions)
```

Internal layout of `grid_controller` follows the skill: `lib/src/{models,services,repositories,interactors,selectors,providers}`, public API through the barrel only.

Not packages: the porting skill (`skills/`), docs, fixtures.

## Decision 2 — Reactive domain projections, grounded in Gas City's primitive model

*(Rewritten 2026-06-11 to ground projections in the documented concept model — [docs.gascityhall.com/concepts/primitives](https://docs.gascityhall.com/concepts/primitives) — rather than generic bead filtering.)*

Gas City's docs define **five primitives** (Session, Beads Store, Event Bus, Config, Prompt Templates) and **four derived mechanisms** (Messaging, Formulas & Molecules, Dispatch/Sling, Health Patrol) — and every derived mechanism is documented as a *composition over beads*: "everything is a bead", differentiated by type, labels, relationships, and metadata. That composition rule is exactly what a projection encodes. the_grid's domain model is therefore not invented here — it is the primitive model, made typed and reactive.

**Primitives → the_grid counterparts:**

| Gas City primitive | the_grid counterpart |
|---|---|
| Beads Store ("the universal persistence substrate") | `GraphSnapshot` + `BeadsRepository` — the substrate everything projects from |
| Event Bus ("reactive watching instead of polling") | the `GraphEvent` stream + domain-event Transformers — we make the beads layer itself reactive, which gc's bus (gc-emitted events only) does not |
| Session ("a live process… work persists in the Beads Store, not the process") | `AgentSession` projection (M1); actuation in `grid_runtime` (M3) |
| Config ("TOML with progressive activation") | M4 |
| Prompt Templates ("the entire behavioral specification for a session") | M3/M4 — rendered at spawn by the runtime |

**Derived mechanisms → projections.** Each projection is a freezed value type decoded from `(bead, metadata, labels, dependencies)` plus *named derived views* encoding that mechanism's documented composition rule:

| Domain (bead type) | Value type | Composition rule (from the docs) | Derived reactive views |
|---|---|---|---|
| `agent`, `role`, `rig` | `Agent`, `Role`, `Rig` | Infrastructure beads; labels drive pool dispatch and rig scoping; issue prefix partitions rigs in one store | `agentsProvider`, `agentProvider(id)`, `rigsProvider`, `agentsInPoolProvider(label)`, `agentsForRigProvider(rig)` |
| `session` | `AgentSession` | "Stable name even as the underlying process restarts"; disposable container, durable identity | `sessionsProvider`, `sessionsForAgentProvider(agent)`, `sessionsByStateProvider` |
| `message` | `Message` | Mail = "bead with `type: message`"; "closing = archiving"; open + addressed = unread | `inboxProvider(agent)`, `threadProvider(id)` (via `replies-to` edges) |
| `molecule` + `step` | `Molecule`, `Step` | "A formula instantiated at runtime: one root bead plus child step beads"; `needs` declares step deps; wisp = ephemeral molecule, TTL'd | `moleculesProvider`, `moleculeProgressProvider(id)` (closed/total steps), `runnableStepsProvider(id)` (needs satisfied), `isWisp` on the value type |
| `convoy` | `Convoy` | "Container bead that groups related work as one tracked batch" | `convoysProvider`, `convoyProgressProvider(id)` (member rollup) |
| `convergence` | `Convergence` | ADR-0003's metadata schema (`convergence.state`, iteration, gate config…) | `convergencesProvider`, `convergencesByStateProvider(state)`, `activeWispProvider(id)` |
| `gate`, `merge-request`, `spec`, `event` | `Gate`, `MergeRequest`, `Spec`, `GridEventRecord` | the_grid `types.custom`; composition rules pinned from fixtures | list + per-id families; derived views added with their first consumer |

**Metadata transformations are first-class.** Raw bead metadata is a JSON blob; each projection owns a **typed metadata codec for its namespace** (e.g. `convergence.*` per ADR-0003), and *Transformers* (predictable-flutter's stream-reshaping role) lift generic `GraphEvent`s into domain events — `SessionStateChanged`, `MessageReceived`, `MoleculeStepCompleted`, `ConvergenceIterated` — by running the projection over the before/after beads. Unknown metadata keys are preserved in a raw map (projections never lose data); decode failures surface as typed `ProjectionError` values, never silent drops.

Consequences:
- The snapshot composition MUST include the metadata column and infrastructure beads (SQL reads do naturally; the CLI fallback uses `bd export --include-infra` — ADR-0001 Decision 4 amendment).
- Mapping fidelity comes from **fixtures captured from the live city per domain** (real agent/session/rig/message/molecule beads), checked in with the gc version recorded — the same pinning discipline as the bd codec fixtures. Health Patrol's composition (probe → threshold → restart) is a *consumer* of these projections and lands with M3.
- M1 ships the mechanism plus the proving trio **sessions, messages, molecules/steps** *(promoted from ADR-0000 A2, 2026-06-11 — the live city holds zero agent/rig/role/convoy beads; in current gc those are config/registry-derived, so there is nothing to pin their mappings against yet)*. `agent`/`role`/`rig`/`convoy` projections remain targets in the table above but wait on an upstream-representation investigation; remaining domains land with their first consumer.

## Decision 3 — grid_devtools rides the exploration protocol only

`grid_devtools` never links `grid_controller` for live data — it attaches to the process VM service and consumes the same `ext.exploration.*` surface as lenny's tooling (handshake → observation → tools). This keeps one protocol (ADR-0001 Decision 6) and makes the panels work against any future grid process (reconciler daemon, runtime supervisor) for free.

---

## Alternatives considered

- `beads_client`/`beads_controller` split (original draft) — superseded by Nico's naming; the substrate services live inside `grid_controller` as its service layer. Extract a riverpod-free `grid_beads` later only if a non-Riverpod consumer actually appears.
- Raw bead access at call sites (no projections) — rejected: every consumer re-implements metadata decoding; domain semantics drift.
- Generic `Map`-based domain views — rejected: loses freezed pattern-matching and compiler exhaustiveness, the house style (ADR-0001 Decision 1).
