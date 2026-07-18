# DESIGN tg-pm6 — beads all the way down (canonical build design)

**Status:** CANONICAL for the tg-pm6 build. Synthesized 2026-07-17 from two
independent proposals against `SCRATCH-beads-all-the-way-down.md` (the epic; its
8-item "Decided" checklist is BINDING) and `SCRATCH-declarative-routing.md` (the
routing detail this rides on). Every file:line below was re-verified in this
worktree, not carried from memory.

**The build is ADDITIVE (drain migration).** The flat-cursor model keeps working
byte-for-byte untouched; the molecule model arrives alongside it behind an
explicit mint-mode. In-flight sessions finish on the old model; new sessions
mint on the new. Nothing existing may break.

---

## 1. The model in one paragraph

The in-memory engine — `NodeCursor` / `CircuitCursor` (`sdk/cursor.dart:26,134`),
`eligibleSteps` (`sdk/frontier.dart:134`), `CircuitScope`
(`circuit/circuit_scope.dart`) — is UNCHANGED. Only the persistence substrate
changes: flat `grid.cursor.{nodePath}.{field}` keys on ONE session bead become a
**molecule of durable beads** — one `type=molecule` bead per circuit instance,
one `type=step` bead per step — whose native deps carry the graph structure and
whose metadata carries the irreducible non-native residue. Both substrates
PROJECT to the identical in-memory `CircuitCursor`, so `CircuitScope` and
`frontier.dart` are consumed unchanged in both modes. Forward eligibility stays
the zero-write `depsSatisfied` read (`frontier.dart:64`); backward motion
becomes its exact mirror pointed down `transitiveDependents` (`rewind.dart:23`)
— a pure INVALIDATION derivation that DELETES today's rewind write cascade
(`session_bead.dart:364`, materialized at `capability_host.dart:540-602`).
Process identity (pgid/pid/token) stops being node-owned cursor state and
becomes a LEASE from an ambient vendor. A circuit is a **Dart-implemented
formula**; mounting it plays **cook**'s role — it instantiates the molecule. A
fan-out is a **swarm**; the committee is one swarm type of several to come.

## 2. Corrections both proposals needed (verified here)

- **`packages/grid_sdk` EXISTS** (both proposals denied it). It is the
  station-composition CLI-SDK (`composition/run/stores/work`), not the engine
  SDK. The engine SDK is `grid_engine/lib/src/sdk/`. All new molecule code
  homes under **`packages/grid_engine/lib/src/molecule/`** — one auditable
  directory = the whole new model; `sdk/` and `circuit/` files are edited only
  in the two wiring rungs (host, drain).
- **`circuit_migration.dart` does NOT exist on disk.** The doc's "four frozen
  shapes" are the two `lastIndexOf('.')` flat-cursor parses at
  `domain/session_bead.dart:465,508`. R5's "retire the migration guard" means:
  the molecule path simply never uses that parse. Doc-drift, noted, not a file
  to edit.
- **`StationServices.writer` IS `StationBeadWriter`**
  (`kernel/station_services.dart:43`; grid_engine already depends on
  grid_runtime). So no new writer interface: stamping a step bead is the
  EXISTING chokepoint `writer.update(stepBeadId, metadata)`; the only new
  writer surface is `createMolecule` + `reapMolecule` (R6). The house fake
  boundary is `BdRunner` (`RecordingBdRunner`,
  `lib/src/testing/engine_fakes.dart:128`), not a writer interface.
- **`CircuitStep` declares no critic→target relation**
  (`sdk/circuit.dart:160-227`: stepId/capabilityId/params/dependsOn/kind only).
  The `validates` edge is minted from a declarative params convention (§R1),
  keeping the engine domain-free and committee content in power_station.
- **The build-time read path was unspecified in both proposals.** The flat
  cursor arrives via `joined?.cursor` (`session_scope.dart:667`, projected by
  `projectCircuitCursor`, `session_bead.dart:459`). Molecule beads live in the
  same state store and must reach `SessionScope.build` through the join: the
  projection grows a molecule bucket (§R5a, its own rung).

## 3. Conflict resolutions (the synthesis picks)

| # | Conflict | Pick | Why |
|---|---|---|---|
| 1 | File homes: all-in-`molecule/` (A) vs spread over `sdk/`+`circuit/` (B) | **A** | one directory = the whole additive model; `sdk/`/`circuit/` provably untouched until the wiring rungs |
| 2 | Mode detection: child-sniffing self-description (A) vs explicit `grid.session.model` key (B) | **B** | A has a real failure mode: `createSession` lands, the molecule pour crashes, restart sniffs "no molecule child" and adopts down the FLAT path. B's key is stamped in the same `createSession` metadata; a molecule-with-no-molecule is detected and the dedup probe re-pours. Absent key ⇒ flat: every in-flight session stays flat by construction |
| 3 | Writer seam: reuse `StationBeadWriter` (A) vs new `MoleculeWriter` interface (B) | **A** | verified: grid_engine already holds the concrete writer ambiently; step stamps are plain `update(stepBeadId, …)`; Fakes live at the `BdRunner` boundary (house pattern) |
| 4 | `InheritedCircuit.==`: over (root, cursor) (A) vs root-only (B) | **A** | root-only equality would never notify dependents on a state change; (root, cursor) notifies exactly when projected state changes and never on a same-state re-provide (the `SessionHandle` discipline, `session_handle.dart`) |
| 5 | Persisted `rewindCount`: kept in the key set (A, self-contradictory) vs removed (B) | **B** | DECIDED item 7 is binding: incarnation is derived from stamps. Supervision keys are `restartCount` + `cooldownUntil` only |
| 6 | pgid/pid/token: vendor-written durable breadcrumb (A) vs removed from durable state entirely (B) | **A**, hardened | full removal breaks crash-adopt: `adoptable` (`lease.dart:108`) needs a durable prior handle to prove fresh. Resolution: a DISTINCT `grid.lease.*` namespace on the step bead, written ONLY by the vendor, never read by the cursor codec — leased, not node-owned, and structurally testable |
| 7 | `supersedes` edges between rework incarnation beads (both gestured) | **RESERVED, not minted in v1** | derived generation re-keys the SAME step bead (demoted to pending); minting per-round incarnation beads would grow the molecule unboundedly and reshape identity. `supersedes`/`until` are documented edge vocabulary for future rounds-materialization / daemon-lifetime work |
| 8 | Derivation surface: separate `liveFrontier` re-implementation (both) | **effectiveCursor collapse** (stronger than either) | projection + invalidation demotion + derived generation compose into ONE effective `CircuitCursor`; `liveFrontier` = the UNCHANGED `eligibleSteps` over it, and the UNCHANGED `ValueKey('$path#$restart.$rewind')` (`circuit_scope.dart:100`) re-keys because the projected `rewindCount` field carries the derived generation. Zero edits to `frontier.dart` and `circuit_scope.dart` |
| 9 | Build order: R6 after R5 (A) vs framed-late (B) | **R6 BEFORE R5** | `_mintMolecule` calls `createMolecule`; the drain seam cannot land without the minter. R6's "gating write-cost validation before any live arm" is satisfied by its tests |
| 10 | Collection: `reapMolecule` writer method (A) vs `MoleculeReaper` class (B) | **A** | fewer moving parts, same chokepoint; triggered from the session-close path the engine already owns (`session_scope.dart:716` `_scheduleClose`) |
| 11 | Swarm typing: open enum `SwarmKind` (B) vs id slot only (A) | **open string vocabulary** | `MoleculeStepKeys.swarm` (`'committee'` first). The doc forbids hardcoding committee-as-the-swarm; a closed enum reintroduces that as rework |

## 4. R1 — the bead schema

**New files** `packages/grid_engine/lib/src/molecule/molecule_schema.dart`
(key namespaces + value vocabulary) and `molecule_codec.dart` (pure builders +
projection). Never edits `session_bead.dart`.

### Native structure (the mandate: mostly native vocabulary)

- `IssueType.molecule` (`beads_dart/.../issue_type.dart:28`) = a circuit
  instance; `IssueType.step` (`:33`) = a step. Both NON-driveable by
  construction: `driveableTypes = [task,bug,feature,chore]`
  (`domain/driveable_work.dart:7`), double-gated at
  `seeds/work_list.dart:317-318` (`type.isCore && (!resident ||
  type.isDriveable)`). Molecule beads can NEVER mount an agent — no
  mount-boundary change needed (epic finding 1, verified).
- Nesting (session→molecule, molecule→step, molecule→sub-molecule):
  `DependencyType.parentChild` (`dependency_type.dart:10`).
- A step's `dependsOn` barrier: `DependencyType.blocks` (`:9`) — dependent step
  depends-on its prerequisite sibling, so the forward frontier is native
  dep-resolution. Read by the projection; never gates a mount (beads don't
  mount).
- Critic→build target: `DependencyType.validates` (`:28`) — the edge the
  backward invalidation keys on. Minted from the params convention
  `kValidatesParam = 'validates'`: a step whose `params['validates']` names a
  sibling stepId gets a validates edge to it. The convention is declared by the
  circuit content (power_station opinion); the engine stays domain-free.
- `supersedes` (`:20`) and `until` (`:26`): RESERVED vocabulary (§3.7).
- Coarse state: bd STATUS (open = pre-terminal, closed = positive-terminal /
  reaped). Fine state (`StepState` is 6-valued; bd status is 2-valued) lives in
  metadata.

### Metadata (the irreducible non-native core)

```dart
/// Keys on a `type=molecule` bead (a circuit instance).
abstract final class MoleculeCircuitKeys {
  static const prefix = 'grid.circuit.';
  static const formula = 'grid.circuit.formula'; // the Circuit id instantiated
  static const session = 'grid.circuit.session'; // owning session bead id (join key)
  static const crumb = 'grid.circuit.crumb';     // canonical BeadPathKey string (R7)
}

/// Keys on a `type=step` bead.
abstract final class MoleculeStepKeys {
  static const prefix = 'grid.step.';
  static const stepId = 'grid.step.id';          // sibling-unique step id (item 4)
  static const capability = 'grid.step.capability';
  static const kind = 'grid.step.kind';          // job | daemon
  static const path = 'grid.step.path';          // engine nodePath (in-run coordinate)
  static const state = 'grid.step.state';        // fine StepState string
  static const restartCount = 'grid.step.restartCount'; // supervision (R4, non-native)
  static const cooldownUntil = 'grid.step.cooldownUntil';
  static const failureReason = 'grid.step.failureReason';
  static const swarm = 'grid.step.swarm';        // swarm type when fan-out member
  static const session = 'grid.step.session';    // owning session bead id (join key)
  static const crumb = 'grid.step.crumb';        // canonical BeadPathKey string (R7)
  static const startedAt = 'grid.step.startedAt';   // FT-1 telemetry, capture-only
  static const finishedAt = 'grid.step.finishedAt';
  static const durationMs = 'grid.step.durationMs';
}

/// Vendor-owned adopt breadcrumb (R3). ONLY the process-lease vendor writes
/// these; the cursor codec NEVER reads them (structurally tested).
abstract final class LeaseKeys {
  static const prefix = 'grid.lease.';
  static const pgid = 'grid.lease.pgid';
  static const pid = 'grid.lease.pid';
  static const token = 'grid.lease.token';
}
```

There is deliberately **no `rewindCount` key** (item 7: derived) and **no
per-key `{nodePath}` infix** (the bead IS the node). `ResultKeys`
(`session_bead.dart:170`) is REUSED VERBATIM on the step bead — the disjoint
result namespace already exists; only its host bead moves.

### The formula → molecule instantiation (cook's role)

```dart
/// A circuit is a Dart-implemented FORMULA; mounting plays cook's role — this
/// is the compile step that instantiates the molecule (durable, never
/// ephemeral: item 1).
GraphApplyPlan instantiateMolecule(
  Circuit circuit, {
  required String sessionId,
  required BeadPathKey root,      // work ⇄ session crumb so far
  required String nodePath,       // engine coordinate root
  Circuit? Function(String id)? circuitById, // sub-circuit resolution
});
```

Pure. Walks `Circuit.steps` (`sdk/circuit.dart:230`); emits one `GraphNode`
per molecule/step (recursing into `SubCircuitStep`), one `GraphEdge` per
nesting / `dependsOn` / validates-convention. Rides
`GraphApplyPlan`/`GraphNode`/`GraphEdge`
(`beads_dart/.../models/graph_apply_plan.dart:20,59,115`) verbatim. A swarm
fan-out mints one step bead per member with the member's distinguisher (the
rubric id) as its sibling-unique `stepId` and `swarm` stamped.

### The projection (the additivity story)

```dart
/// Projects a molecule's beads to the SAME in-memory shape the flat codec
/// yields (the mirror of projectCircuitCursor, session_bead.dart:459).
({CircuitCursor cursor, Map<String, String> beadIdByNodePath})
    projectMoleculeCursor(Iterable<Bead> moleculeBeads);
```

Per step bead: nodePath from `MoleculeStepKeys.path`; `StepState` from
`MoleculeStepKeys.state` (falling back to coarse-from-status); counts/cooldown
/telemetry from its keys; results from `ResultKeys`. NOTE: the projected
`NodeCursor.rewindCount` here is 0 — the derived generation is layered on in
R4's effective cursor.

**Tests** (`test/molecule/molecule_codec_test.dart`, pure, offline): golden
round-trip `stepBeadMetadata → projectMoleculeCursor == original NodeCursor`
(mirrors the flat codec tests); `instantiateMolecule(kCodeCircuit-shaped
fixture)` → expected node+edge set including the validates-convention edge; a
swarm of same-capability critics yields DISTINCT sibling step ids (item 4);
structural tests that no `grid.lease.*` key is read by the codec and no durable
key the derivation reads carries prose (institutionalizes pow-hf2's
boolean-not-prose rule).

## 5. R7 — `BeadPathKey`, the canonical string (built FIRST — R1 depends on it)

**New file** `packages/grid_engine/lib/src/molecule/bead_path_key.dart`.

```dart
/// Ordered, DE-DUPLICATED breadcrumb of stable bead ids (item 2):
/// work bead ⇄ session ⇄ molecule ⇄ nested step. Bead ids never reshape, so
/// this is topology-stable BY CONSTRUCTION (Q3 dissolves).
class BeadPathKey {
  final List<String> crumbs;
  /// The DURABLE identity (item 3): a deterministic canonical string, NEVER a
  /// hash. "Hash for the tick, string for the record."
  String get canonical => crumbs.join(kBreadcrumbSeparator);
  // operator == : STRUCTURAL over crumbs.
  // hashCode    : within-run reconcile convenience ONLY — never written down.
}

/// Not legal inside a bd id and not `.` — the lastIndexOf('.') ambiguity
/// (session_bead.dart:465) never enters the molecule path.
const kBreadcrumbSeparator = '/';
```

The last crumb-adjacent identity slot is the sibling-unique step id (item 4).
No GlobalKeys (item 6): identity is derived from the beads in play.

**Tests** (`test/molecule/bead_path_key_test.dart`, pure): cross-run canonical
stability (a golden string literal); structural `==`; de-dup preserves
first-occurrence order; separator never collides with fixture bead ids.

## 6. R2 — `InheritedCircuit` (the storage seam)

**New file** `packages/grid_engine/lib/src/molecule/inherited_circuit.dart`.
An ambient VALUE (config-is-values; the writer stays the ambient
`StationServices.writer` chokepoint — DI, not carried here). Imitates the
`SessionHandle`/`Workspace`/`SiblingView` discipline
(`session_scope.dart:742-755`).

```dart
class InheritedCircuit {
  final BeadPathKey root;
  /// nodePath → durable step-bead id: the lookup CapabilityHost uses to target
  /// its persists at the step bead instead of the session bead.
  final Map<String, String> beadIdByNodePath;
  /// The projected EFFECTIVE cursor (R4) — the same shape CircuitScope consumes.
  final CircuitCursor cursor;
  // == structural over (root, cursor): notifies exactly when projected state
  // changes; a same-state re-provide never notifies.
}
```

Provided as a 4th nested `InheritedSeed<InheritedCircuit>` at the
`session_scope.dart:742` return — ONLY in molecule mode. Flat sessions provide
nothing new; `CapabilityHost` falls back to `_sessionId`
(`capability_host.dart:87`) — the additive fork.

**Tests** (`test/molecule/inherited_circuit_test.dart`): via
`FakeTreeContext.provide<InheritedCircuit>` (`engine_fakes.dart:345,385`) a
step resolves its own bead id by nodePath; `==` proves a same-state re-provide
does not notify (mirrors the session-handle equality test).

## 7. R3 — the process-lease vendor

**New file** `packages/grid_engine/lib/src/molecule/process_lease_vendor.dart`.
Reuses the lease family verbatim (`sdk/lease.dart:72` `LeaseCapability`,
`:118` `LeaseAllocation`, `:148` `startOrAdopt` no-adopt-on-faith).

```dart
/// pgid/pid/token as a LEASE the step acquires, addressed by the stable
/// step-bead id (item 5/8's "stable pointer") — not node-owned durable state.
class ProcessHandle {
  final int pgid; final int pid; final String token;
}

abstract class ProcessLeaseVendor {
  LeaseCapability<ProcessHandle> leaseFor(String stepBeadId, StepArgs args);
}
```

- `adoptable` reads `LeaseKeys.*` off the step bead (the vendor-persisted adopt
  breadcrumb) and returns a `LeaseBound` iff re-addressable; `proveFresh` = pid
  liveness via `StationServices.liveness`
  (`kernel/station_services.dart:49-50`) — the same seam the I-10 dead-fence
  probe uses. Daemon-only adopt, exactly per `lease.dart`'s existing contract.
- `acquire` spawns and writes the `LeaseKeys` breadcrumb (the ONLY writer of
  that namespace); `release` is idempotent and clears it. Teardown's
  `LeaseAllocation.dispose` releases the lease — the residue the old rewind
  write existed to prevent is closed by the dispose, not a durable node write.
- **LOUD-or-GONE (item 5):** on the molecule path, a process-backed
  CapabilityHost asserts
  `dependOnInheritedSeedOfExactType<ProcessLeaseVendor>() != null` and THROWS
  when absent. A `SelfManagedProcessVendor` is the only degraded fallback and
  must be explicitly mounted — never a silent default.
- Provided once at the kernel root beside `CapabilityRegistry`
  (`kernel/station_kernel.dart:130-137`).

**Tests** (`test/molecule/process_lease_vendor_test.dart`): a fake vendor over
a String-handle `LeaseCapability` (mirrors `lease_allocation_test.dart`'s
`_FakeLeaseCap`): daemon adopt-on-proveFresh-true with no re-spawn; job never
adopts; missing vendor throws; release clears the breadcrumb.

## 8. R4 — the thin frontier derivation (the risk lens)

**New file** `packages/grid_engine/lib/src/molecule/live_frontier.dart`.
COMPOSES over `frontier.dart` and `rewind.dart`; edits neither.

```dart
/// Backward motion as the exact mirror of depsSatisfied (frontier.dart:64),
/// pointed down transitiveDependents (rewind.dart:23). Reads ONLY structured
/// stamps: the grade enum + an actionable-finding boolean — never prose
/// (pow-hf2). A `validates` source whose stamp invalidates marks its target's
/// transitive-dependent closure (∪ the target itself) invalidated.
Set<String> invalidatedNodes(Circuit circuit, CircuitCursor projected,
    CircuitResults results, String nodePath,
    {required Circuit? Function(String) circuitById});

/// The derived incarnation axis (item 7): a deterministic count of the
/// invalidation rounds observed against this node's stamps — NOT a persisted
/// rewindCount.
int derivedGeneration(String path, CircuitResults results, ...);

/// Projection ∘ invalidation ∘ generation: the projected cursor with every
/// invalidated node DEMOTED to pending and NodeCursor.rewindCount carrying
/// derivedGeneration. CircuitScope + eligibleSteps consume it UNCHANGED.
CircuitCursor effectiveCursor(Circuit circuit, CircuitCursor projected,
    CircuitResults results, String nodePath, {required circuitById});

/// = eligibleSteps(circuit, effectiveCursor(...), ...). Pure, total, cheap,
/// idempotent (Q4). No signal, no RouteVerdict, no route naming a step
/// (item 7; tg-ie8 falls out for free).
List<CircuitStep> liveFrontier(...);

/// The rework-cap belt, derived: at kMaxReworkRounds the derivation STOPS
/// demoting and surfaces the node for escalation through the existing
/// firstBrokenNode/_scheduleEscalation path — no router-side check.
({String path, String reason})? derivedEscalation(...);
```

**What a pure derivation cannot express — and the compensation (the four
irreducible engine-side nuances):**

1. **Live teardown / re-key of a still-mounted incarnation flipped stale
   mid-flight.** A pure derivation bumps nothing, so
   `ValueKey('$path#$restart.$rewind')` (`circuit_scope.dart:100`) would leave
   a stale daemon mounted. COMPENSATION: `effectiveCursor` writes
   `derivedGeneration` into the in-memory `rewindCount` field → the key
   changes because the DERIVED count changed → keyed reconcile tears down and
   remounts, `LeaseAllocation.dispose` (`lease.dart`) releases the process
   lease. NO persisted write; zero edits to `circuit_scope.dart`.
2. **Restart budget** (`isStepBroken`, `frontier.dart:93`): no native home;
   `restartCount` persists per step bead; read over the projection, unchanged.
3. **Cooldown backoff** (`_runnableState`, `frontier.dart:107-121`):
   `cooldownUntil` persists per step bead; unchanged.
4. **Broken-vs-done / retire** (`firstBrokenNode` / `isCircuitComplete`, read
   at `session_scope.dart:697-717`): derived over the projected cursor exactly
   as today.

This per-node bookkeeping is precisely what keeps R4 "bead graph + a THINNER
engine derivation", not "pure `bd ready`" (model item 5).

**Tests** (`test/molecule/live_frontier_test.dart`, pure golden, mirrors
`rewind_set_test` / `rewind_arm_test`): forward AND backward both fall out of
`liveFrontier`; a downstream invalidating stamp derives its `validates` target
(and closure) live with NO cursor write; `derivedGeneration` increments
monotonically on repeated invalidation and re-keys a `_daemonSpec`-style
daemon fixture (mirrors `rewind_arm_test.dart`); the cap surfaces
`derivedEscalation` instead of demoting; totality/idempotency on
partial/missing stamps (Q4).

## 9. R6 — the chokepoint mint + collection (BEFORE the drain seam)

**Modify** `packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart`
— the missing graph-shaped mint, parallel to `createSession` (`:131`) /
`createGate` (`:178`):

```dart
/// One `bd create --graph` pour = one Dolt transaction (applyGraph,
/// beads_dart/.../services/bd_cli_service.dart:284, ephemeral: FALSE — item 1).
Future<Map<String, String>> createMolecule(GraphApplyPlan plan, {
  required String substation, required String sessionId,
});

/// Session-close collection (item 1; `bd purge` reaps only ephemerals — we own
/// this): closes the molecule's step+circuit beads via the grouped batch path.
Future<void> reapMolecule({required String sessionId, ...});
```

- `_assertOwned` per node BEFORE the wire (`:252,269,282` pattern; a batch is
  one transaction, so one unowned target poisons the whole pour — fail-closed).
- Serialization via `_serializedMulti` (`:299`) across every minted id; the
  per-id `_tail` chain (`:110`) is already bead-id-keyed, so N beads changes
  how many chains one transition touches, not the primitive.
- **Mint-dedup on re-entry:** probe by session id + root crumb (the
  `_findOpenGate` precedent, `:196,348`) so a crashed/re-entered mint never
  duplicates a molecule.
- **Write-cost validation (reframed by epic findings 2+3, NOT "N× worse"):**
  the rewind cascade (N×3 keys per invalidation) is DELETED by R4; steady
  state is one stamp per step completion — the same EVENT count as today,
  landing on N beads instead of N key-groups of one bead. Merge isolation
  SIMPLIFIES the D-1 race: separate beads share no metadata blob to clobber.
- Bound: live molecule beads ≈ max-agents × nodes-per-circuit ≈ 100 at peak;
  `reapMolecule` at session close keeps the state store from accumulating.

**Tests** (`grid_runtime` `test/.../molecule_mint_test.dart`, over
`RecordingBdRunner`): one pour = one `applyGraph` invocation with
`ephemeral: false`; an unowned node fails the whole batch; dedup on re-mint;
`reapMolecule` closes exactly the molecule set and nothing else.

## 10. R5a — the join substrate (the read path neither proposal specified)

**Modify** `domain/session_bead.dart` (additive keys only) +
`domain/session_projection.dart` / `domain/joined_snapshot.dart`:

- `SessionBeadKeys.model = 'grid.session.model'` (`flat` | `molecule`; ABSENT
  ⇒ flat). Stamped in `createSession`'s mint metadata when molecule-minting.
- The join buckets state-store beads of `IssueType.molecule`/`IssueType.step`
  by their `MoleculeStepKeys.session` / `MoleculeCircuitKeys.session` stamp
  into the session's projection (`SessionProjection.moleculeBeads`, empty for
  flat sessions). Flat projection fields are byte-for-byte untouched.

**Tests**: a snapshot containing one flat session + one molecule session
projects both correctly; molecule beads never leak into work/drive projections
(the `work_list.dart:317` gate holds — regression-tested at the projection
level too).

## 11. R5b — CapabilityHost molecule targeting (the write fork)

**Modify** `circuit/capability_host.dart` — the minimal fork:

- Every `_persistX` resolves its target: ambient `InheritedCircuit` present →
  `beadIdByNodePath[_nodePath]` with the per-bead (no nodePath infix) molecule
  metadata builders; absent → today's `_sessionId` + flat builders,
  byte-for-byte unchanged.
- `_persistRewind` (`:540`) is NEVER invoked in molecule mode (backward motion
  is derived); the rewind write cascade is dead code on that path.
- Process-backed capabilities consult `ProcessLeaseVendor` (throw-required,
  §R3); pgid/pid/token no longer ride the started-stamp
  (`nodeStartedMetadata`, `:298-309`) on the molecule path — the vendor owns
  `LeaseKeys`.

**Tests**: under `FakeTreeContext` with/without `InheritedCircuit`: stamps land
on the step bead id vs the session id; the flat path issues IDENTICAL writes
to today (RecordingBdRunner transcript equality); molecule path never writes a
`rewindCount` or `grid.cursor.*` key.

## 12. R5 — the drain seam (last)

**Modify** `circuit/session_scope.dart`:

- `enum CircuitMintMode { flatCursor, molecule }` read off ambient config
  (`SubstationConfig` via `_ctx`/`_services`, `:180-190`). Default
  `flatCursor` — the existing path untouched.
- `_mint()` (`:260`) branches AFTER the void-retire block: flat → today's
  `writer.createSession` (`:300`) untouched; molecule → `createSession`
  (stamping `grid.session.model=molecule`) THEN
  `createMolecule(instantiateMolecule(seed.circuit, …))`. The mint-retry
  budget (tg-6nf, `:92-128`) covers both.
- `build()` (`:660-755`): flat → `joined?.cursor` into the UNCHANGED
  `CircuitScope` — byte-for-byte today's code; molecule →
  `effectiveCursor(projectMoleculeCursor(projection.moleculeBeads), results)`
  into the SAME `CircuitScope`, wrapped in the 4th
  `InheritedSeed<InheritedCircuit>`. Broken/complete/gate re-arm reads
  (`:678-717`) run over whichever cursor — both are `CircuitCursor`.
- Session close (`_scheduleClose`, `:425,716`): the molecule arm additionally
  fires `reapMolecule` (item 1's collection).
- `derivedEscalation` feeds the existing `_scheduleEscalation` path.

**Drain proof (Q3 dissolves):** adoption short-circuits at `initState`'s
`LiveSession()` arm (`:202-216`) BEFORE any mode check — an in-flight flat
session never re-enters `_mint()` and is never reinterpreted. A molecule
session's live node resolves off its own step bead; bead ids never reshape, so
identity is topology-stable by construction. DRAIN, never convert.

**Tests** (`test/molecule/drain_seam_test.dart`, mirrors
`track_c_session_scope` / adopt tests): a flat `sessionBead` fixture
(`engine_fakes.dart:510`, no model key) mounts through the unchanged flat path
and completes; a molecule-mode `NoSession()` pours the graph once; a flat
session mid-flight adopts with ZERO molecule writes; a flat and a molecule
session coexist in one snapshot; RecordingBdRunner proves the flat path issues
the identical writes it does today; close fires the reap.

## 13. The 8 BINDING "Decided" items — honored where

| # | Decided | Honored |
|---|---|---|
| 1 | Durable-until-session-close, not wisps | R6: `applyGraph` `ephemeral: false`; `reapMolecule` at positive terminal |
| 2 | Identity = ordered de-duplicated breadcrumb of bead ids | R7 `BeadPathKey.crumbs` |
| 3 | Durable identity = canonical string, NEVER a hash | R7 `canonical` (`/`-joined, dot-free); `hashCode` within-run only |
| 4 | Sibling uniqueness = Flutter's rule; fan-out by sibling-unique step id | R1 `MoleculeStepKeys.stepId`; swarm members carry their distinguisher (rubric id) as step id |
| 5 | Process identity leased; throw-required if absent | R3 `ProcessLeaseVendor` + LOUD-or-GONE assert; `SelfManagedProcessVendor` only as an explicit mode |
| 6 | Not GlobalKeys — identity from the beads in play | R7: key derived from crumbs; `ValueKey` composition unchanged |
| 7 | Durable = stamped state; live = derivation; backward = INVALIDATION | R4 `invalidatedNodes`/`effectiveCursor`/`liveFrontier`; no `RouteVerdict`, no persisted rewindCount, no signal |
| 8 | bd-native naming EXTENDS bd's concepts | `type=molecule/step`; `parent-child`/`blocks`/`validates` (+ `supersedes`/`until` reserved); circuit = Dart FORMULA, `instantiateMolecule` = cook's role; fan-out = SWARM, committee one swarm type (open vocabulary) |

Naming law: `BeadPathKey`, `InheritedCircuit`, `ProcessLeaseVendor`,
`liveFrontier`, `instantiateMolecule` — genesis-tree/Dart idioms and bd
extensions, never agent-nouns; "extension" never "plugin".

## 14. Build order

R7 (`BeadPathKey`) → R1 (schema/codec/instantiate) → { R4 (derivation) ∥ R2
(seam) ∥ R3 (lease) } → R6 (mint — the gating write-cost validation) → R5a
(join) → R5b (host fork) → R5 (drain seam). Every rung offline-testable with
Fakes (`engine_fakes.dart`) before any IO; gate per rung:
`dart analyze && dart test` in every touched package.
