# grid_engine

The M4 tree engine — **`genesis_tree` IS the engine** (ADR-0007, Accepted
2026-06-24; ADR-0009 adds the third tree). `build(observed)` reconciles the
running system: keyed reconcile + `Branch` lifecycle = the work lifecycle
(**mount = spawn, unmount = kill**, a cursor tick = a reconcile transition).
The kernel is opinion-light — a work bead's running subtree is contributed by
an extension via a `SessionResolver`; the engine holds no landing / VCS /
provider opinion.

**Engine-private by intent** (ADR-0008 D1/D2): the authoring surface is
`grid_sdk` — consumers *compose*, they never import `grid_engine` or subclass
its Seeds. The author-facing value types are fenced under `lib/src/sdk/` so the
public/private split stays a move, not a rewrite.

## The tree

```
Station → SubstationScope → Substation → WorkList → WorkBead
  → (SessionResolver) → SessionScope → CircuitScope → CapabilityHost → Allocation
```

Config flows down the *ancestors* (`SubstationScope`/`Substation`); the work
axis is observed by **exactly one node, `WorkList`** (derailment-invariant 1).
The `StationJoinBridge` is the only subscription into the snapshot pipelines
(A39); `FederatedSnapshotSource` fans N local beads workspaces into the ONE
`SnapshotSource` the bridge's work axis observes.

## Circuits, steps, capabilities, allocations

A `Circuit` is the value-typed step-graph the engine inflates into a reconciled
subtree — the depth-analogue of the work lifecycle. The author composes
`Circuit`/`CircuitStep` value types + opaque `Capability` leaves and **never a
`Seed`**; that holds the four derailment-invariants at depth by construction.
Each inflated node's progress is a `StepState` cursor
(`pending / running / ready / complete / failed / gated`): `ready` and
`complete` are the two positive terminals that satisfy a `dependsOn`; `failed`
routes to supervision (re-key within the `Backoff` budget — the kernel owns the
cooldown Timer — then escalation). The cursor persists as a **molecule of
durable beads** on the_grid's OWN session bead — never the foreign work bead
(A37); `(tg-eli, 2026-07-19)` the flat, merge-safe `grid.cursor.{nodePath}.*`
key model this section previously described has been removed — molecule is
the only circuit engine. `CircuitScope` re-keys a node on
`ValueKey('$path#$restartCount.$rewindCount')`, so a supervised restart or a
routing rewind tears down the still-mounted effect instead of leaving a stale
incarnation alive.

The engine ships three `Capability` families — `ProcessCapability` (a spawned,
supervised process), `ServiceCapability` (an async body over `ServiceBundle`
collaborators), `LeaseCapability` (a held lease) — and the class is deliberately
NOT sealed: dispatch is polymorphic through `createAllocation` (the
`createRenderObject` analogue, ADR-0009 D4), so a new family is an addition,
not a core edit. An `Allocation` is the_grid's **third tree** on `genesis_tree`:
a persistent, addressable managed object holding the live effect, with four
lifecycle verbs — `startOrAdopt` / `update` / `dispose` (kill) / `detach`
(leave running). The effect layer holds **no writer** (invariant 2): the
Allocation *reports* through its sink; the engine-private `CapabilityHost`
persists off-build through the single `StationBeadWriter` chokepoint.

## The molecule model

`(tg-eli, 2026-07-19)` The only circuit engine — `SubstationConfig.circuitMintMode`
and the `flatCursor` opt-in it once gated are deleted; there is no mint-mode
switch. Every session's circuit instantiates as **beads** —
one `type=molecule` bead per circuit instance and one `type=step` bead per leaf
`CapabilityStep` — under the `grid.circuit.*` / `grid.step.*` metadata
namespaces (the bead IS the node, so there is no `{nodePath}` infix). Spawned
process identity (`pgid`/`pid`/`token`) stops being `NodeCursor` state and
becomes a **lease** vended by the ambient `ProcessLeaseVendor`, addressed by
the durable step-bead id — so the handle survives a rework re-key untouched.
`grid.lease.*` has exactly one writer (`StationProcessLeaseVendor.acquire`
writes the breadcrumb, `release` clears it); `requireProcessLeaseVendor` throws
LOUD when no vendor is mounted — the degraded no-adopt
`SelfManagedProcessVendor` is a composer's explicit choice, never a silent
fallback.

## The opinion-free kernel

`StationKernel` assembles the ambient providers over the `Station`, mounts the
tree, and drains one batched microtask flush per dirty edge —
`root.markNeedsRebuild()` is never called. The OPINIONS (agent/verify/land, the
`code` circuit, the git `SourceControl`) live in the `grid_assets` package,
**never in the engine** — a structural fence (ADR-0007 §1) keeps them out. The
engine knows `SourceControl` / `DeliveryMethod` / `EscalationHandler` in
*concept* only; impls ship in asset packs (a null `delivery` means commit-only,
a null `escalation` means the human gate).

## Key symbols

| Symbol | Where | What |
|---|---|---|
| `Station` | `src/seeds/station_seed.dart` | Root `MultiChildSeed`; its children ARE the substations |
| `SessionResolver` | `src/kernel/session_resolver.dart` | The opinion-light seam: work bead (+ linked session) → the Seed that runs it |
| `Circuit` / `StepState` | `src/sdk/circuit.dart` | The authored step-graph + the 6-valued per-node cursor state |
| `Capability` | `src/sdk/capability.dart` | The opaque leaf (Process/Service/Lease families); mints its `Allocation` |
| `CapabilityHost` | `src/circuit/capability_host.dart` | Engine-private carrier: kick sync → run async → report push → persist off-build |
| `Allocation` | `src/sdk/allocation.dart` | The third tree's node — the live effect, `startOrAdopt`/`update`/`dispose`/`detach` |
| `ProcessLeaseVendor` | `src/molecule/process_lease_vendor.dart` | Vends `LeaseCapability<ProcessHandle>` per step bead; sole `grid.lease.*` writer |
| `StationKernel` | `src/kernel/station_kernel.dart` | Composes the ambient providers + drives the batched flush loop |

## House conventions

Dart `^3.11`, pub workspace + melos, `publish_to: none`, `resolution:
workspace`. **freezed** sealed unions + `json_serializable`; exhaustive
`switch`; **Fakes, not mocks**; the derailment invariants are enforced as
mutation-verified tests, not comments.
