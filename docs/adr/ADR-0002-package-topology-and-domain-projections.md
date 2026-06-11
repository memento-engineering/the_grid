# ADR-0002 — Package topology and reactive domain projections

**Status:** Proposed
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
| **`grid_runtime`** | M3: runtime providers (tmux, subprocess) — see ADR-0004. | M3 | Pure Dart. |

Dependency direction (longevity outward-in, per predictable-flutter):

```
grid_cli ──┐
grid_exploration ──┤──► grid_controller ◄── grid_reconciler ◄── grid_runtime (actions spawn sessions)
grid_devtools ─────┘         (sdk)
```

Internal layout of `grid_controller` follows the skill: `lib/src/{models,services,repositories,interactors,selectors,providers}`, public API through the barrel only.

Not packages: the porting skill (`skills/`), docs, fixtures.

## Decision 2 — Reactive domain projections for every domain

The bead graph is the *storage* model; it is not the *domain* model. the_grid's beads carry typed domains via `issue_type` + metadata — the workspace already declares them (`types.custom`): **agent, role, rig, session, molecule, convoy, message, event, gate, merge-request, spec, convergence, step**.

Requirement (Nico, 2026-06-11): every domain gets reactive typed views/transformations — agents, agent sessions, rigs, etc. — not ad-hoc bead filtering at call sites.

Mechanism — one generic projection pattern, instantiated per domain:

```dart
/// A typed, reactive view over beads of one domain.
abstract interface class DomainProjection<T> {
  IssueType get type;                       // which beads belong to this domain
  T fromBead(Bead bead, BeadMetadata meta); // decode (freezed value type)
}
```

- Each domain is a **freezed value type** (`Agent`, `AgentSession`, `Rig`, `Role`, `Convoy`, `Molecule`, `Gate`, `MergeRequest`, `Spec`, `Convergence`, `Step`, …) decoded from the bead + its metadata namespace.
- Each domain gets **Selectors** exposed as providers, derived from the single `GraphSnapshot` via `select` (rebuild only on relevant change): `agentsProvider`, `agentProvider(id)`, `sessionsProvider`, `sessionsForAgentProvider(agentId)`, `rigsProvider`, `convergencesProvider`, … — list and per-id family per domain, plus domain-specific derived views (e.g. sessions by state, convergences by `convergence.state`).
- **Domain events**: M1 ships the generic `GraphEvent` stream; domain-scoped event streams (e.g. `SessionStateChanged`, `ConvergenceIterated`) are *Transformers* over `GraphEvent` filtered by projection, added in M2 alongside the reconciler, which is their first consumer.
- Field mappings for gc-authored domains (agent/session/rig metadata conventions) are captured as **fixtures from the live city** and ported per-domain; unknown metadata keys are preserved in a raw map so projections never lose data.

Consequences:
- The snapshot composition MUST include the metadata column and infrastructure beads (SQL reads do naturally; the CLI fallback uses `bd export --include-infra` — ADR-0001 Decision 4 amendment).
- M1 ships the mechanism plus three proving domains: **agents, sessions, rigs**. Remaining domains land with their first consumer (most arrive in M2 with the reconciler).

## Decision 3 — grid_devtools rides the exploration protocol only

`grid_devtools` never links `grid_controller` for live data — it attaches to the process VM service and consumes the same `ext.exploration.*` surface as lenny's tooling (handshake → observation → tools). This keeps one protocol (ADR-0001 Decision 6) and makes the panels work against any future grid process (reconciler daemon, runtime supervisor) for free.

---

## Alternatives considered

- `beads_client`/`beads_controller` split (original draft) — superseded by Nico's naming; the substrate services live inside `grid_controller` as its service layer. Extract a riverpod-free `grid_beads` later only if a non-Riverpod consumer actually appears.
- Raw bead access at call sites (no projections) — rejected: every consumer re-implements metadata decoding; domain semantics drift.
- Generic `Map`-based domain views — rejected: loses freezed pattern-matching and compiler exhaustiveness, the house style (ADR-0001 Decision 1).
