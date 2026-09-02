---
status: accepted
date: 2026-06-25
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a41-m4-p0-mount-boundary-type-gate-is-a-fail-closed-allow-li
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A41"
---
## A41 (2026-06-25) — M4 P0 mount-boundary type gate is a fail-closed ALLOW-list (`IssueType.isCore`), refining A40

**Decision (AI; surfaced by the Track A adversarial-hardening pass, applied in `grid_engine`):** the `WorkList` predicate that decides which beads mount a `WorkBead` (and thus spawn a coding agent) is an **ALLOW-list of core work types** — `IssueType.isCore` = {task, bug, feature, chore, epic, decision, spike, story, milestone} — **not** a deny-list of excluded types.
**Why:** A40 named the mount exclusions as "`type=convergence`/infra" — a *deny-list*. The hardening pass empirically proved (a scratch test mounting owned, ready beads) that a deny-list is unsafe: **`bd ready` does not narrow to plain work** — `ready_work` excludes only `{merge-request, gate, molecule, message, agent, role, rig}`, so the_grid's orchestration/coordination customs **`convoy`/`event`/`step`/`spec`/`convergence`** leak into the ready set. A deny-list that lists only `{convergence, session, infra}` would let an owned, ready `convoy`/`spec`/`event`/`step` mount a `WorkBead` and **spawn an `implement` agent on a non-work bead** — latent in the thin genesis/`tgdog` arms, but **live for the carried lenny arm** (gc actively creates open `convoy`/`spec`/`event`/`step` beads beside which lenny reads). The allow-list excludes every non-core type (all the_grid customs, all gc orchestration nouns, all infra) **by construction**, and is **fail-closed** for an unrecognised custom type (it does NOT mount). This is the build-order's own `plain-work-type` intent (§3), now actually achieved.
**Consistency with A40:** a strict *refinement*, not a reversal — A40's named exclusions (`convergence`, infra) are all non-core, so they remain excluded; the allow-list additionally fences the orchestration nouns A40's wording missed.
**Sub-question (resolved with the ratification, 2026-06-25):** whether `epic`/`milestone`/`decision` — aggregates/planning rather than concrete coding targets — should be narrowed OUT of the allow-list. **`isCore` stands** (epic/milestone/decision retained); revisit only if a real over-dispatch appears. The proven arms only ever dispatched `feature`/`task`, both retained.
**Not in scope (carried, separate gate):** the live-arm **blessed-bead drive-list** (`--bead`, A35/A36 — a human gate on *which specific* owned beads may be driven in the first live arm) is **not** a P0 tree-engine concern; the offline P0 boundary is ownership + this type allow-list. The drive-list is re-added at the live-arm boundary (ADR-0006), orthogonal to A41.
**Affects:** `grid_engine` `WorkList._isDispatchableWork`; `docs/M4-P0-BUILD-ORDER.md` §3 (deny→allow note); a Track A test locking every the_grid custom type to zero mounts.
**Status:** **Ratified (Nico, 2026-06-25)** — read and accepted. The `isCore` allow-list stands; the epic/milestone/decision sub-question is resolved (retained at `isCore`).

