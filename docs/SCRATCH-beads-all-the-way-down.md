# Beads all the way down — the circuit engine as a durable bead molecule

**Status:** DRAFT, from a design conversation (Nico + Claude, 2026-07-17).
**Review pass 1 (fresh focus, same day) DONE** — findings grounded in code, §below.
Next: compact, then a `fable` ultracode workflow builds it (Nico triggers). This is
the bigger idea the declarative-routing epic (tg-ie8) grew out of; tg-ie8 becomes
a *consequence* of this, not a sibling.

## Thesis

A circuit stops being flat `grid.cursor.{path}.*` keys on one session bead and
becomes a **molecule of durable beads — one bead per circuit and per step**,
where each bead's own type / deps / status IS the step's role, its dependencies,
and its state. The frontier is dep-resolution over that bead graph; identity is a
breadcrumb of stable bead ids; and **declarative routing falls out for free** —
there is no `RouteVerdict` to emit, because "what is live" is just which beads are
ready.

The reentrant engine is already "turtles all the way down" (ADR-0008 D4). This
makes the *durable structure* turtles too: **beads all the way down.**

## Why this is coherent — and what it reopens

**Grounded in ratified doctrine + native beads primitives:**
- ADR-0008 D4 — the reentrant engine ("turtles"); the top-level model *observe bd
  mutations → diff → reconcile* applied at every depth, with no second mechanism.
- **molecule** — beads' OWN parent + direct-children grouping (a circuit = a
  molecule). `MoleculeID`, direct-children scoping. (Nico: "mol comes from beads.")
- **dep resolution over the graph** — `bd ready` already resolves
  `COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)`, so a
  graph of beads with deps and a ready-frontier is substantially NATIVE, not new
  engine.
- **the lease family** (ADR-0009 D6, "leasing is core") — adopt-or-reacquire with
  `proveFresh`; the model this borrows for process identity.

**What it REOPENS (name it, don't dodge it):** ADR-0008 D3 deliberately chose
flat keys on ONE session bead for merge safety ("two concurrent leaf hosts
writing disjoint keys never lose a write"). Beads-per-node changes that trade
rather than dodging it — separate beads are inherently merge-isolated (no shared
metadata blob to clobber), at the cost of N× more writes through the A32
chokepoint. This is a real re-decision, made with eyes open, not a free win.

## Fresh-review grounding (pass 1, 2026-07-17 — verified in code, not memory)

1. **State-store circuit/step beads can NEVER mount an agent — fail-closed
   already.** The mount boundary is a positive allow-set, not a deny-list:
   `driveableTypes = [task, bug, feature, chore]`
   (`grid_engine/lib/src/domain/driveable_work.dart:7`), double-gated in
   `work_list.dart:317` (`type.isCore && (!resident || type.isDriveable)`), doc
   comment: *"Fail-closed: an unrecognised custom type does NOT mount."* `step`
   is even already a declared custom type. The design's scariest operational
   hazard — molecule beads leaking into a drive frontier — is structurally
   absent.
2. **Backward motion today is a WRITE CASCADE; the target model deletes it.**
   Rewind writes three keys per node (`state=pending`, bumped `rewindCount`,
   `restartCount=0`) onto every node in (targets ∪ transitive dependents ∪
   self) — `domain/session_bead.dart:364`, materialized in ONE chokepoint
   `writer.update` (`circuit/capability_host.dart:583`). Today's cost: N×3 keys
   riding 1 bead-write.
3. **"Declarative routing falls out" is now GROUNDED, not aspirational.**
   Forward motion is already a zero-write derivation in production:
   `depsSatisfied` (`sdk/frontier.dart:74`) gates a node by READING its
   dependencies' cursors (`isPositiveTerminal`) — nothing writes a "hold" onto
   the waiting node. Backward invalidation is the exact mirror: point the same
   neighbor-stamp read down `transitiveDependents` instead of `dependsOn`. The
   residue that is NOT free: the re-key/teardown. Today the written
   `rewindCount` bump re-keys a still-mounted incarnation
   (`ValueKey('$path#$restart.$rewind')`); a pure derivation bumps nothing, so
   incarnation identity must be derived from the stamps (already decided) AND a
   live effect flipped stale mid-flight needs a derived teardown path. → R4.
4. **bd 1.0.5 is more native than this doc credits — R1 reconciles, it does not
   invent.**
   - `bd mol` — molecules are work TEMPLATES with `--mol-type`
     swarm | patrol | work. A committee fan-out IS a swarm. R1 must pick what a
     circuit instantiates.
   - `bd cook` — *"compile a formula into a proto (ephemeral by default)"*. bd
     owns the word **formula** and a compile step; circuit→molecule
     instantiation may BE cook, or must be named so it doesn't collide.
   - Dep types are semantic: `parent-child` (nesting), `validates`
     (critic→build), `until`, `supersedes` (rework rounds). Most of R1's edge
     schema is native vocabulary, not new metadata.
   - The wisp layer we decided against is fully native (`--ephemeral`,
     `--wisp-type`, `promote`, `purge`) — and `purge` reaps ONLY ephemeral
     beads. **Durable-until-close therefore means we own the collection**:
     closed circuit beads accumulate in the state store
     (~nodes-per-circuit × sessions). A named cost; it does not reverse the
     decision. → R6.

   **Resolved (Nico, review pass 1): our names EXTEND these concepts** —
   circuit = Dart-implemented formula (mount plays cook), fan-out = swarm with
   committee as one swarm type of several to come. See R1 + the checklist.

## The model

1. **A circuit is a molecule of durable beads.** One bead per circuit node
   (sub-circuit) and per step. The bead's type/metadata encodes its ROLE; its dep
   edges encode `dependsOn`; its status encodes cursor state; its result fields
   carry the structured verdict (grade/finding).
2. **Durable-until-session-close (DECIDED).** NOT ephemeral wisps. They survive a
   restart, so respawn-or-skip / adopt reconstructs a session's progress from the
   bead graph — crash-recovery works, and the live-bead count is bounded by live
   sessions (~max-agents × nodes-per-circuit ≈ 100 at peak). Collected when the
   session's work bead reaches a positive terminal.
3. **Identity = a breadcrumb of stable bead ids.** An ordered, de-duplicated list
   of the beads in play (work bead ⇄ session bead ⇄ nested circuit/step beads).
   Bead ids never reshape, so this is topology-stable BY CONSTRUCTION — Q3 (the
   migration-strand proof) dissolves. The DURABLE identity is a **deterministic
   canonical string** serialization, NEVER a hash (`Object.hash` is per-run
   seeded; `String.hashCode` isn't cross-run stable either). A typed
   `BeadPathKey`'s `==` is structural; any `hashCode` is a within-run reconcile
   convenience and is never written down. *Hash for the tick, string for the
   record.*
4. **Sibling uniqueness is Flutter's rule, inherited.** Siblings must have unique
   keys, full stop. A fan-out of same-role beads (the committee — N `critic`s in
   parallel) is legal because each carries its distinguisher (the rubric id is its
   sibling-unique step id). The identity slot is the sibling-unique step id, not
   the bare capability role.
5. **The frontier = bead dep-resolution + a THIN engine derivation.** `bd ready`
   over the molecule gives the dep structure and state; the supervision nuances
   (restart budget, cooldown backoff, broken-vs-done, the re-key) stay
   engine-derived over the bead state. So it is "bead graph + a thinner engine
   derivation", not "pure `bd ready`".
6. **Declarative routing falls out.** A step returns OK/Error (execution only);
   its content is a STRUCTURED stamp on its own bead; re-run is DERIVED — a
   downstream verdict invalidates an upstream bead (flips it non-terminal) and the
   frontier re-mounts it. No `RouteVerdict`, no route naming a step, no signal.
   The re-run incarnation is derived from the stamps, not a persisted `rewindCount`
   a route bumps. (The routing detail lives in `SCRATCH-declarative-routing.md`;
   this doc is the structure it rides on.)
7. **`InheritedCircuit` (NEW) is the storage seam.** A step Seed looks up its
   ambient `InheritedCircuit` (`dependOnInheritedSeedOfExactType`) to read/write
   its own bead — the one genuinely new piece. Config-is-values: the circuit bead
   is an ambient VALUE, the writer is DI.
8. **Process identity is LEASED from a vendor, not node-owned.** `pgid/pid/token`
   stop being durable node state and become a lease the step acquires from an
   ambient process vendor, addressed by the step's bead id (the stable pointer).
   Reuse the lease family's adopt-or-reacquire (`proveFresh` = pid liveness), which
   also closes the deferred "adopt-a-live-process" item. **Throw-required** if no
   vendor is in the tree (LOUD-or-GONE); lossy self-manage only as an explicitly
   named degraded mode, never a silent fallback.

## What it dissolves

- `RouteVerdict.Rewind` + its stepId naming; the frontier reads results instead.
- **The fold** — nothing names `agent`, so it need not be a sibling of a route.
- **The circuit-migration guard** — bead ids don't reshape, so no cursor keys
  strand; `circuit_migration.dart`'s four frozen shapes can retire.
- **The flat-cursor codec** + the `lastIndexOf('.')` parse.
- **pow-bxu** — its fold+migration scope evaporates; the revise arm becomes a
  derivation over the review bead's stamp.

## Decided in this conversation (the fresh-review checklist)

- [x] Circuit-beads durable-until-session-close (not wisps). *(Cost accepted in
      review pass 1: collection at session-close is ours to build — `bd purge`
      reaps only ephemerals.)*
- [x] Identity = ordered de-duplicated breadcrumb of bead ids.
- [x] Durable identity = deterministic canonical string, NEVER a hash.
- [x] Sibling uniqueness = Flutter's no-dup-key rule; fan-out by sibling-unique
      step id.
- [x] Process identity leased from a vendor; throw-required if absent.
- [x] Not GlobalKeys — identity derived from the beads in play.
- [x] Target routing model: durable = stamped structured state; what's-live =
      derivation; backward motion = INVALIDATION, not a signal.
- [x] bd-native naming: our concepts EXTEND bd's. A circuit is a
      **Dart-implemented formula** (mounting plays cook's role — it
      instantiates the molecule); a fan-out is a **swarm**; the committee is
      ONE swarm type, more to come. Never fork or parallel-name a bd concept.
      (Nico, review pass 1.)

## Open questions / rungs (for the review + the build)

- **R1 — the bead schema.** Exactly what fields on a circuit-bead / step-bead
  encode role, deps, cursor state, result. How the molecule's parent/child edges
  map to `dependsOn` + sub-circuit nesting. **bd-native reconciliation DECIDED
  (Nico, review pass 1): our names EXTEND bd's concepts — never fork, never
  parallel-name.** A circuit is a **Dart-implemented formula**; mounting it for
  a session plays cook's role — it instantiates the molecule (durable-until-
  close where cook's protos default ephemeral: an extension the flags permit).
  A fan-out step instantiates a **swarm**; the committee is ONE swarm type and
  more are expected — do not hardcode committee-as-the-swarm. The semantic dep
  types (`parent-child`, `validates`, `until`, `supersedes`) are the edge
  vocabulary.
- **R2 — `InheritedCircuit`.** Its shape; how a step reads/writes its bead through
  it; the write path through the A32 chokepoint (now per-bead, not per-key).
- **R3 — the process-lease vendor.** The vendor seam, addressing by bead id, the
  adopt-or-reacquire `proveFresh` over pid liveness; the throw-required policy.
- **R4 — the thin frontier derivation.** What of the current `frontier.dart`
  (budget, cooldown, broken, re-key) stays engine-side over the bead graph vs.
  what `bd ready` covers. **Includes the backward mirror** (finding 3): extend
  the eligibility read down `transitiveDependents` — the proven `depsSatisfied`
  shape pointed the other way — plus the derived re-key/teardown for a live
  incarnation flipped stale by a dependent's stamp (the one thing the rewind
  write used to do that a pure derivation doesn't).
- **R5 — the migration from flat-cursor.** In-flight sessions on the flat-cursor
  model: DRAIN (finish them on the old model; new sessions mint on the new) vs.
  convert. Drain is almost certainly right (no live conversion).
- **R6 — chokepoint write-cost.** Validate the write volume against the
  serialization gate; confirm merge-isolation actually simplifies the D-1 race.
  **Reframed by findings 2+3 — the comparison is not "N× worse":** the target
  model DELETES today's rewind write-cascade (N×3 keys per invalidation)
  and replaces it with a zero-write derivation. Steady-state stamping is one
  write per step completion — same event count as today, but landing on N beads
  instead of N key-groups of one bead. Also size the closed-bead accumulation
  in the state store (finding 4: `purge` won't reap durables).
- **R7 — canonical string format.** The exact serialization of the breadcrumb +
  step id → the durable key; dot-free discipline retained.

## Relationships

- **tg-ie8 (declarative routing)** — a CONSEQUENCE of this, not a peer. Recommend
  reframing it as "the routing that falls out of the bead-molecule engine" or
  folding it under this epic in the review.
- **tg-dca (`external` cross-substation primitives)** — answered by the SAME
  mechanism: cross-substation coupling is deps across stores in the molecule; a
  breadcrumb spans stores natively.
- **pow-bxu / tg-26j / pow-99g** — parked; pow-bxu is superseded by this.

## Build note

Intended for a `fable` ultracode workflow after two review passes. The build
needs, at minimum: R1 (schema) and R2 (`InheritedCircuit`) decided first (they
are the foundation), then R3/R4 in parallel, then R5 (drain migration), with R6
as a gating validation before any live arm. Everything offline-testable with
Fakes (house rule) before IO is wired.
