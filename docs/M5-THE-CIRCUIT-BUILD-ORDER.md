# M5 — "The Circuit": the verify-first adversarial SDLC workflow (build-order)

**Status: RATIFIED (Nico, 2026-06-28).** Doc-before-code (the gate) — all 10 lettered
decisions + 4 open sub-decisions are settled (D-1 grid_assets in the_grid repo; D-10
hand-written plans; D-7 gate = tgdog `type=gate` bead functionally blocking the_grid's own
session; maiden bead tg-9fl + tg-p9q folded into Track B). Stamped into **ADR-0008**
(Decision 2 + Decision 9 amendments). The offline tracks (A–E) are buildable now; the live
dogfood (Track F) remains the human gate.

**Date:** 2026-06-28
**Author:** drafted by AI per Nico's M5 decisions (verify-first; `grid_assets`
baseline; `power_station` repo; **"The Circuit"** = the SDLC workflow system;
dart-first; gates AND flares as two primitives; Packaged-AI-Assets format).
**Source of record:** ADR-0008 (the asset/engine cluster); the factoryskills study
(`scratchpad/factoryskills-study.md` / memory `reference-factoryskills-workflow-model`);
the Dart/Flutter **Packaged AI Assets** proposal (`flutter.dev/go/packaged-ai-assets`).
**Relates to:** ADR-0008 D2/D3/D4/D5/D7 (assets, reentrant engine, supervision);
ADR-0007 §7 (the four derailment invariants); ADR-0012 (observability — flares).

---

## Context — what we're building and why

The live arm proved the_grid can spawn a coding agent per ready bead and produce a
landable commit (tg-c7l → PR #2, on `main`). But the `verify` step is a placeholder:
`sh -c 'melos test'` — not verification, and worse, an **engine opinion** (it lives in
`grid_engine/lib/src/extension/code_capabilities.dart`). ADR-0008 says the engine
knows domains in *concept*, never *detail*; opinions ship in **assets**.

**"The Circuit"** is the SDLC workflow — factoryskills reborn, grid-themed (work flows a
circuit of stages: discovery → spec → review → build → review → land, with **gates** and
**flares** along the way). Its crown jewel is the **adversarial committee**: one critic
per rubric, in isolation (anti-anchoring), fanned out in parallel, then a **route** step
aggregates verdicts via a deterministic matrix. factoryskills' "molecule = a DAG of steps,
committee = a parallel expansion, route = a join that decides, orders = the loop" maps
**almost 1:1** onto the_grid's reentrant engine — minus two deltas the_grid owns: we
replace factoryskills' cadence ORDERS with **reactive reconcile** (the kernel flush *is*
the loop), and we keep the work source **read-only** (A37) so lifecycle/grades are per-node
`grid.cursor.*` / `grid.result.*` writes on the_grid's OWN session bead.

**Verify-first.** We ship the **code-committee** (the post-build review) first — it is the
self-contained, highest-value upgrade. The spec front-half (discover/architect) is phase 2.
The one consequence: a real code-committee needs beads carrying a **Validation Plan** +
**Implementation Plan** (the architect's output) — handled by D-10.

### What's missing, counted (the compositional inventory)

Today: `agent` ✅ → `verify` = `melos test` ❌ → `land` ✅ (behind `--land`). To make
`verify` a real adversarial committee: **4 code parts** (critic capability, committee
sub-formula, route/aggregate capability, the one engine seam = sibling-read), **1 content
part** (the rubrics), **1 data prerequisite** (validation/impl plan on beads), **+2
primitives** for full fidelity (gate, flare). The only true *engine* change is the
sibling-read seam (D-5); everything else composes at the existing
`CapabilityRegistry` / `FormulaResolver` / `ServiceBundle` seam.

---

## Decisions (D-1 … D-10) — proposals for ratification

### D-1 — Extract the engine's opinions into `grid_assets`; engine ends opinion-free
Move `agent` / `verify` / `land` + `kCodeFormula` out of
`grid_engine/lib/src/extension/code_capabilities.dart` into a **`grid_assets`** package
(the baseline pack, replacing ADR-0008's placeholder `station_grid_assets`). `grid_engine`
keeps only seams (`Formula` / `Capability` / `Service` / the registry/resolver) and ZERO
agent/verify/land/rubric opinions — enforced by the existing structural fence test
(extended: the engine package must not name `claude`, `git`, `melos`, or any rubric).

**Home (DECIDED 2026-06-28, Nico):** `grid_assets` lives **in the_grid repo** — it houses
**all** our grid-asset code for now; split-and-extract to `power_station` later, at
stabilization (the genesis precedent: path-dep during dev → published at stabilization). No
new repo/publish pipeline for the first build.

**Substation-linking (DECIDED 2026-06-28, Nico — forward note, NOT in verify-first scope):**
co-developing two substations (e.g. the_grid + `genesis_tree`) needs pubspec
`dependency_overrides` path-linking between them. A **`dart_grid_assets` capability** should
own that linking — generalizing the manual path-override↔published-dep dance we hit with
`genesis_tree` (ADR-0008 D5 "published-deps build policy"). Recorded for `dart_grid_assets`.

### D-2 — The committee is a reentrant sub-formula (fan-out + join)
The `code` formula becomes:
```
agent  →  committee( critic_a ∥ critic_b ∥ … ∥ critic_n  →  route )  →  land
```
`committee` is a sub-formula the engine inflates (ADR-0008 D4 reentrancy): N **critic**
steps, all `dependsOn: {agent}` and dep-free of each other (so the frontier mounts them in
parallel), plus a **route** step `dependsOn: {all critics}` (the await-all join). **No new
engine machinery** — fan-out + barrier + keyed reconcile are already proven (the Burn,
track J). This is formula wiring in the asset.

### D-3 — The critic capability (one rubric, in isolation)
A `CriticCapability extends ProcessCapability`, parameterized by `rubricId` (a step param):
spawns `claude -p <rubric-templated prompt>` in the bead's workspace, reads the bead + **one**
rubric only (anti-anchoring — never peer rubrics), emits a grade. The grade rides the step's
terminal write to **`grid.result.<nodePath>.grade`** (the `Ok.payload → grid.result.*` path
shipped in tg-c7l) — never a write to the foreign work bead (invariant 4).

### D-4 — The route/aggregate capability + the matrix (asset policy)
A `RouteCapability extends ServiceCapability` reads the N critics' grades (via D-5) and
applies factoryskills' deterministic matrix — **asset policy, not engine**:
```
any gating-F        → block   (→ a gate, D-7)
grade spread ≥ 3    → human   (→ a gate, D-7)
any revise (D/F)    → rework  (re-key the build subtree; bounded rounds)
all pass (A–C)      → advance (→ land)
```
Bounded rework rounds (factoryskills' cap 3). The route capability returns a `StepOutcome`
that advances/blocks/re-keys the formula cursor — it never writes the work bead.

### D-4a — Routing promoted to a FIRST-CLASS engine primitive (RATIFIED — Nico, 2026-07-12)
D-4 framed routing as a `StepOutcome` variant + an asset matrix. Two live sessions with Nico
(2026-07-12) promote it to a first-class primitive — bead **tg-tkm**, building on **tg-o90**
(A47's `Rewind` arm, landed):

- **The route returns a distinct `RouteVerdict {advance, rewind, escalate}`** — NOT a
  `StepOutcome` variant. Ordinary steps keep `{Ok, Failed}`; only a route emits a verdict. One
  engine **router** effects it through the chokepoint (A37). A route is a standalone reactive
  unit: inputs (sibling verdicts via the D-5 `SiblingView`) → one output verdict.
- **`deliver` replaces `land`** and is the ACTUATION of terminal `advance`, not a verdict. The
  engine knows only "actuate the terminal delivery"; the **delivery method is DOMAIN** (asset/
  circuit config): PR / merge-queue / direct-merge for code (tg-hlz), commit-a-chapter / export
  for a book, hand-off for an agent supporting another agent. The `--land` flag is retired →
  per-substation delivery config. `LandCapability → DeliverCapability`.
- **`escalate` raises to a bound HANDLER, not "a human"** — the engine drops the human
  assumption; the handler BINDING is the seam. human-gate (D-7) is the default binding
  (reproduced exactly); parent-router / governor-queue are future handlers. Keep the word
  "escalate".
- **Doctrine:** the engine owns the VERBS (advance/rewind/escalate/deliver); the asset owns the
  TARGETS (delivery destination, escalation authority). `rewind` is the only fully
  engine-internal verb. This is genesis's domain-free doctrine applied to routing — the_grid
  need not be about code.
- **On the CURRENT circuit model.** A47's `Rewind` is re-homed under the router, not ripped out.
  tg-tkm lands on today's circuit model; the **uniform-recursive-circuit** reshaping is its
  foundational follow-on — now **D-4b** below (ratified the same session; bead **tg-w2r**).

### D-4b — The uniform-recursive circuit (RATIFIED — Nico, 2026-07-12)
Makes the circuit model genesis-idiomatic (Seed→Branch uniform recursion) so D-4a's `escalate`
composes across nesting rather than being bolted on. Bead **tg-w2r** (blocks-on tg-tkm) carries
the build; the grid_assets code-circuit migration is a companion (power_station).

- **Collapse `SubCircuitStep` — resolution decides the key.** The `CircuitStep` union becomes ONE
  `Step{id, resolvableId, params, dependsOn}`. The registry resolves the id to a capability OR a
  circuit; `CircuitScope` (`circuit_scope.dart:82`) picks the reconcile key from the RESOLVED
  type — capability → an incarnation-keyed leaf (`#restart.rewind`), circuit → a path-keyed
  nested scope. The static kind-`switch` goes; exec attrs (`kind`/`resources`/`requires`) move
  onto the resolved capability. A `Circuit` is now "a Step that yields Steps" — `Seed→Branch` on
  the work graph.
- **`escalate` propagates as a ROUTED terminal.** A route's `escalate` (D-4a) sets an `escalated`
  circuit terminal; an enclosing route reads it via `SiblingView` (D-5) — the dep already
  resolves through a sub-circuit's terminal (`circuit.dart:157`), so it is child-output →
  parent-input dataflow, no imperative call-up (route = standalone reactive app). It is **routed,
  not barrier-satisfying**: a plain `dependsOn` stays UNSATISFIED on escalate (D-2 preserved);
  only an enclosing route — or, unhandled at the top, the default human-gate handler (D-7) —
  consumes it. This makes D-4a's "bound escalation handler" concrete as the enclosing-route
  chain; "governor-queue" is just a handler that raises to the operator.

### D-5 — The sibling-read affordance (THE one engine change)
The route step must read its **sibling** steps' results. Today a `Capability` sees only its
own sandboxed `CapabilityContext` (no `TreeContext`, no notifier — the invariant-1/2
guard). Add a **read-only `SessionProjection`** (the per-node cursor + `grid.result.*` view
for *this session's* nodes) to `CapabilityContext`, populated for `ServiceCapability`s.
- It is a **read of already-observed state** (the join bridge's last snapshot) — NOT a new
  pipeline subscription (invariant 1 holds) and NOT a write (invariant 2 holds).
- The sandbox stays narrow: a projection value, never the `TreeContext`/writer/notifier.
- Mutation-tested: a route capability that tries to advance on an unread/forged sibling
  grade must fail the acceptance suite.

### D-6 — Rubrics as asset content; `code-validation` is gating and runs the bead's OWN plan
Port factoryskills' `code-review@v1` rubrics into `grid_assets`, re-themed:
**code-validation [GATING]**, spec-adherence, regression-risk, test-coverage. **This is the
answer to "`melos test` isn't verification":** `code-validation` runs the bead's **own
Validation Plan** commands in its workspace (F = any command non-zero, or build/test fails)
→ block. The others grade the diff. Rubrics are asset files (D-9 format), not engine code.

### D-7 — The **gate** primitive (blocking human checkpoint)
**DECIDED (Nico, 2026-06-28).** A gate **functionally blocks** the parked work and must be
**resolved to route back** — via a real `type=gate` bead the_grid mints in its **OWN** store
(tgdog), the factoryskills model. It **NEVER imperatively mutates the foreign work bead's
state** (A37): the gate bead blocks the_grid's **own session bead** (which the engine
tracks), and the mount predicate gains one clause — `ready ∧ owned ∧ ¬circuit-broken ∧
¬gated → mount`. An open gate ⇒ park (non-lossy: subtree keeps its cursor/branch); the
operator resolves it (`bd close` / a `grid gate resolve` shim) ⇒ un-gated ⇒ the formula
re-mounts at the parked cursor and routes on. Pending gates are listable + human-resolvable
via normal `bd`. (`route`'s `block` / human-ultimatum outcomes mint a gate.)

### D-8 — The **flare** primitive (non-blocking signal)
A flare **emits** a signal at a transition and **continues** — the non-blocking half
(distinct from a gate; a flare-as-gate would wrongly halt the loop on every signal).
Minimal version now: emit to the **exploration host event stream** (the existing
out-of-band sink leonard already reads — A39/A40), fire-and-forget. Full observability
(OTel ⊥ perception co-emitted sinks) is ADR-0012; the flare seam is the hook.

### D-9 — Author assets in the Dart/Flutter **Packaged AI Assets** format; dart-first
Rubrics + agent/critic prompts ship as **`extension/mcp/config.yaml`** resources/prompts
(the `package:extension_discovery` format; `flutter.dev/go/packaged-ai-assets`):
files on disk, **mustache-templated** args, `visibility: public|private` (our open/closed
split), **AI-only packages with no Dart code blessed**. We follow it as a **spec** so our
systems use it now AND can pivot if the community adopts it (it dovetails with the_grid's
`extension/` convention + "extension never plugin"). **Dart-first** for the formula +
capabilities (composed at the existing seam); the **TOML `PackInflater`** (parse a
factoryskills-style pack) is low-priority — *just* parse + inflate — and **deferred**.

### D-10 — Validation/Implementation plan prerequisite (the verify-first data dependency)
`code-validation` runs the bead's Validation Plan; spec-adherence grades against its
Implementation Plan — both the architect's output. **DECIDED (Nico, 2026-06-28): blessed
beads carry a HAND-WRITTEN Validation Plan + Implementation Plan** (the smallest path; no new
pipeline stage). A minimal `spec` step (discover/architect front-half) is **phase 2**.

---

## Tracks (dependency-ordered)

| Track | Scope | Decisions | Depends on |
|---|---|---|---|
| **A — engine seams** | the sibling-read affordance + the gate + the flare primitives, in `grid_engine`. Pure engine, offline, **mutation-tested at depth** (the four derailment invariants must still hold with a sibling-reading ServiceCapability + a gate park + a flare emit). | D-5, D-7, D-8 | — |
| **B — opinion extraction** | move agent/verify/land + `kCodeFormula` out of `grid_engine` into the new `grid_assets` package; extend the structural fence (engine names no `claude`/`git`/`melos`/rubric). Behavior-neutral. **Folds tg-p9q:** drop the dangling `grid step --advance` prompt line (completion is observed, not declared) as `buildAgentPrompt` moves. | D-1 | — (parallel with A) |
| **C — the committee** | the critic capability, the committee sub-formula, the route/aggregate capability + matrix, the rubrics — all in `grid_assets`. | D-2, D-3, D-4, D-6 | A (sibling-read), B (the package) |
| **D — asset packaging** | the Packaged-AI-Assets `extension/mcp/config.yaml` format for rubrics/prompts; mustache templating; public/private visibility. | D-9 | B |
| **E — swap + acceptance** | swap the live `code` formula's `verify` → the committee; offline end-to-end acceptance (agent → critics∥ → route → land; a gating-F → gate; all-pass → land); the four invariants hold at depth with the committee mounted. | D-2…D-8 | C, D |
| **F — dogfood (human gate)** | run The Circuit verify-first on the maiden bead **tg-9fl** (orphan-worktree recovery — testable, bounded; D-10 hand-written Validation + Implementation plans); dry-run rehearsal → the LIVE arm. Coexistence-safe (tg read-only, sessions → tgdog). | all | E |

---

## Definition of done

1. **Engine seams** (Track A) land with the sibling-read projection, gate, and flare —
   mutation-tested; the four derailment invariants pass **at depth** with each.
2. **`grid_engine` is opinion-free** (Track B) — the structural fence proves it names no
   `claude`/`git`/`melos`/rubric; agent/verify/land live in `grid_assets`.
3. **The committee runs offline end-to-end** (Track E) — agent → N critics in parallel →
   route → land; a gating-F routes to a **gate** (parks, no auto-advance); all-pass routes
   to **land**; a flare emits on each transition. `code-validation` runs the bead's own
   Validation Plan.
4. **`melos analyze` clean + the full offline suite green** across all packages; rubrics
   author in the Packaged-AI-Assets format.
5. **Dogfood (human gate):** the_grid drives one real `tg` bead through The Circuit
   verify-first and produces a committee-reviewed, landable result. Nico present.

---

## Safety rails / deferred (explicit)

- **OFFLINE-first; the LIVE arm is the human gate** (no live `claude`/`git`/`tg` until the
  dogfood track, Nico present). The M3/live-arm precedent.
- **Coexistence:** tg read-only; sessions → tgdog; gc owns
  {factoryskills,lenny,wedding,butane_flutter,swift-infer}, not tg. The codec boundary
  (`metadata.rig`, convergence schema, `kGridNamespace`) is unchanged.
- **Gates/flares + sibling-read are ADDITIVE** — no NodeCursor/codec churn beyond the
  read-only projection; `grid.cursor.*` / `grid.result.*` namespaces unchanged.
- **DEFERRED:** the spec front-half (discover/architect — phase 2, D-10); the spec-committee
  (the first review point — verify-first ships the code-committee only); the TOML
  `PackInflater` (D-9); the `power_station` repo extraction (D-1; starts in-repo); full
  observability (ADR-0012; the flare seam is the hook); `restForOne` transitive re-keying.

---

## Open sub-decisions

1. ~~**`grid_assets` home** (D-1)~~ — **DECIDED:** in the_grid repo (all grid-asset code), extract later.
2. ~~**Validation-plan source** (D-10)~~ — **DECIDED:** hand-write on blessed beads.
3. ~~**Gate representation** (D-7)~~ — **DECIDED:** a `type=gate` bead in tgdog that
   functionally blocks the_grid's own session (never the foreign work bead), resolved to
   route back. (Full-fidelity primitive — verify-first's happy path doesn't hit it; lands
   just behind the committee.)
4. ~~**The first dogfood bead** (Track F)~~ — **DECIDED:** maiden = **tg-9fl**; **tg-p9q**
   folded into Track B; `tg-xqq` held for later.

*(All sub-decisions resolved — the build-order is ready for the impl.)*
