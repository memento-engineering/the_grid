# Declarative routing — the route layer becomes cursor-only-durable + derived

**Status:** DRAFT, for Nico's ratification. Worked INLINE (Nico + Claude), not
driven by the station. This doc is the working artifact; edit it as the design
settles, then promote the decided parts to an ADR-0007/0008 amendment.

## Thesis

The route layer stops *signalling* navigation and starts *deriving* it. A step
returns only OK/Error; its content is stamped as **structured state** on the
session bead; and **what is live is a pure function of that state**, recomputed
by the reconciler — never pushed by a `RouteVerdict`. This finishes at the route
layer the model the engine is already ratified to hold everywhere else.

## This is not a new bet — the code diverged from ratified doctrine

- **A40 (Ratified, Nico 2026-06-24).** Phase is **derived by a JOIN** of
  work-bead status + the session cursor, and the cursor lives on the_grid's OWN
  session bead — ratified *specifically* because deriving from the session bead
  is what respects the A37 split-store (the work bead is the pristine foreign
  source we cannot write). The v1 "phase on the work bead" shape was AI-proposed
  and superseded before code.
- **ADR-0008, cursor-only-durable amendment (Ratified, Nico 2026-06-28).**
  > persist ONLY the non-derivable state — the per-node cursor + the
  > pgid/pid/token restart fence. Completion, escalation, and
  > "is-this-formula-done" are DERIVED from the cursor, never separately
  > persisted. Everything else … is the ephemeral "wisp" layer: in-memory,
  > re-observed/re-derived, never persisted.

  And: *"factoryskills' cadence **orders** are replaced by **reactive
  reconcile** (the kernel flush IS the loop)."*

So "derive circuit state, don't persist/signal it" is already the law. The
divergence is one primitive: `RouteVerdict.Rewind({stepId})` — an imperative
order that names a step in the surrounding circuit. It is why the `code` route
cannot reach its builder without the fold, and why the fold needs a frozen-shape
migration.

## The asymmetry to remove

- **Forward motion is already derived:** a node's `dependsOn` completes → its
  dependents become mountable. Declarative reconcile, no signal.
- **Backward motion is signalled:** `Rewind({stepId})` reaches out of the
  route and flips cursor nodes to `pending`. Naming the step couples the route
  to the topology → the fold → the migration.

Make backward derived too, and the coupling — and everything built to work
around it — goes away.

## Target model

1. **Step outcome = OK / Error, nothing more.** `RouteVerdict`'s three fused
   concerns split:
   - *did the step execute?* → OK / Error (a critic that grades D executed
     fine; the D is content, not an error; "Error" is "the critic could not
     run").
   - *what did it find?* → a **stamped write** (below).
   - *where does the work go?* → **derived** (below).
2. **Content = structured state on the session bead**, never prose. The
   derivation reads only booleans / enums / counts (`grid.result.*` /
   `grid.cursor.*`). The human-readable rationale is a separate comment / wisp
   the derivation NEVER parses. (The discovery-gate false-hold, pow-hf2, is the
   standing proof of why: a derivation that read "None identified…" as prose
   mis-fired; the fix was a `contradicts` boolean. Institutionalise that.)
3. **What is live = a pure derivation** `liveFrontier(bead, cursor, stamps)`.
   Forward (a dep completed) and backward (a D/F was stamped → build pending
   again) both fall out of the same function. No route emits a navigation
   verdict; the reconciler recomputes the frontier from stable state each flush.
4. **The session is the wisp / live-process record.** Durable = the cursor +
   the pgid/pid/token restart fence. Ephemeral / re-derived every reconcile =
   the live process handle, heartbeat, permits. The branch "gets updates through
   the tree and adjusts" — that is exactly the wisp being re-derived (Seed=desired
   from stamps, Branch=current live processes, reconcile diffs).

## What this dissolves

- `RouteVerdict.Rewind`'s stepId naming → gone (the route names nothing).
- **The fold** — `agent` need not be a sibling of the route, because nothing
  names `agent`; the parent circuit that already contains both derives the
  frontier.
- **The migration guard** — reshaping the derivation function strands no
  persisted cursor keys, because membership is recomputed from stable bead state
  rather than read from position-bound keys. `circuit_migration.dart`'s four
  frozen shapes can begin retiring. **(Claim to prove in build, see Q3.)**
- **pow-bxu** collapses from "Rewind arm + fold + shape-6 migration" to
  "extend the frontier derivation so an open code-finding derives the build step
  live." Most of what it has been grinding on evaporates.

## Scope — SINGLE STATION, SINGLE BEAD, FIRST

The station must reliably finish ONE bead on ONE station again before any
multi-station work. So this epic is scoped to the `code` circuit completing a
single bead cleanly — spec → build → review → (derived revise ↔ build) → land —
with rework expressed as derived state. **Multi-station / cross-store (`external`)
is explicitly OUT and tracked separately** (the `external`-primitives bead).

## Rungs (decomposition — inline, not station-driven)

1. **The stamp schema.** Define the durable structured verdict a step writes:
   grade, an actionable-finding boolean, a finding-ref, a round count. Separate
   the human rationale into a non-derivation comment/wisp. A structural test
   that the derivation reads only the structured keys.
2. **`liveFrontier` — the pure derivation.** One total, cheap, deterministic
   function: (work bead, session cursor, stamps) → the set of nodes that should
   be pending/live. Offline tests (Fakes) prove forward and backward both fall
   out of it.
3. **Collapse the step outcome to OK/Error.** Remove `Advance`/`Rewind`/
   `Escalate` as navigation signals; the "route" node becomes either a pure
   derivation the engine runs or dissolves into the frontier computation (Q1).
4. **Bounded rework as a derivation input.** The round count is a stamped
   value; at the cap the derivation makes the human-gate node live. No
   router-side check, no `kMaxReworkRounds` on the node mutated by a signal.
5. **Dissolve the fold; begin retiring the migration.** Prove no in-flight
   session strands under the derived model (Q3), then remove the fold need and
   start unwinding `circuit_migration.dart`.
6. **The durable/ephemeral barrier.** The `Durable<T>` (or structural test)
   ADR-0008 asked for, so an ephemeral handle can never be accidentally
   persisted — the enforcement the derived model depends on.

## Open questions (resolve inline)

- **Q1.** Does a `route` capability survive as a pure node, or dissolve entirely
  into `liveFrontier`? (Leaning: dissolve — a "route" that emits nothing is just
  the frontier function.)
- **Q2.** How does a stamped finding reach the rewound builder's brief? In the
  signal model, `Rewind.reason` was flared but never parsed. In the derived
  model the finding IS session state the next build brief reads — cleaner. Pin
  the exact carrier key.
- **Q3.** The migration-dissolution claim. Is there ANY reshape under which an
  in-flight session (one with a live process) fails to resolve its live node
  from the new derivation? An in-flight node's cursor is durable; if the
  derivation changes shape, does the live agent's node still map? This is the
  load-bearing proof for "no more migrations."
- **Q4.** Totality/idempotency of `liveFrontier` — it runs every reconcile, so
  it must be pure, total (no throw on partial state), and cheap.

## Non-goals

- Multi-station / cross-store coupling and the `external` primitives — separate,
  deferred bead. Single-station completion lands first.
- Changing the reentrant per-node cursor (ADR-0008 D4). Granularity stays; only
  *how the cursor's backward writes are decided* changes (derived, not signalled).
