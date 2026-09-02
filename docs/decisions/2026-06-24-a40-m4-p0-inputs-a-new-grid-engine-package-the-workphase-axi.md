---
status: accepted
date: 2026-06-24
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a40-m4-p0-inputs-a-new-grid-engine-package-the-workphase-axi
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A40"
---
## A40 (2026-06-24) — M4 P0 inputs: a new `grid_engine` package, the WorkPhase axis, belt-and-suspenders durable completion, P0 Riverpod scope, minimal extension kernel

**Decision (grounding `docs/M4-P0-BUILD-ORDER.md` via a 7-track source-recon sweep; the four forks ratified by Nico 2026-06-24, the WorkPhase *shape* AI-proposed/pending):**
- **Engine package = a NEW `grid_engine`** (not a `grid_runtime` layer) — amends **ADR-0002** topology; acyclic `grid_engine → {grid_controller, grid_runtime}`; the engine's minimal import surface *is* the enforcement of derailment-invariant 1 (it cannot import the detection pipeline). **(Nico)**
- **Durable completion = belt-and-suspenders** — the agent advances its terminal phase as its last act **and** the controller writes a durable done-marker on observed clean completion (robust to a flaky one-shot **and** a controller restart that misses the event). **(Nico)**
- **Riverpod = bridge-only in P0, full purge in the M4 DoD** — P0 wraps `repository.snapshots` (already a plain `Stream`) into a `StateNotifier`; `grid_controller`'s 9 internal `AsyncValue` files are purged as tracked DoD work, not dropped. **(Nico)**
- **Extension scope = minimal** — landing-as-an-EffectSeed + a compiled `DefaultExtension`; the TOML `PackInflater` / full `GridExtension` interface = **P1 / ADR-0008**. **(Nico)**
- **WorkPhase axis (corrected & ratified, Nico 2026-06-24).** The phase cursor lives on **the_grid's OWN session/lifecycle bead in the state store** (`tgdog`), keyed by `work_bead == <id>` — **not** on the work bead. *(The v1 "`grid.phase` on the work bead, advanced through the chokepoint" shape was AI-proposed and **superseded by a 5-lens hardening pass** that caught it was incompatible with the proven **A37** split-store topology: the work bead lives in the pristine foreign source the_grid cannot write, and the A32 chokepoint writes only the owned store — so the work-bead write had no valid target. Caught before code.)* Phase values **`implement | verify | land`** (`verify` not `gate` — avoids colliding with the M2 convergence gate-eval, a different axis on `type=convergence` beads). **`phaseOf` is derived by a JOIN** (work-bead presence/status from the read workspace + the session cursor from the state store): no cursor + freshly-entering-ready ⇒ `implement`; a **positive terminal** (work bead `closed` **or** session cursor terminal) ⇒ done/unmount; **never** ready-set exit (the_grid never marks a bead in-progress, so set-exit ≠ completion — treating it as done would kill a live agent). Advanced through the A32 chokepoint **on the session bead** (belt-and-suspenders: agent's chokepoint-mediated last-act advance + the controller's done-marker, same key+value, idempotent). `type=convergence`/infra beads are excluded at the mount boundary (M2 owns them — a true two-writer collision otherwise).
**Why:** the recon found ~70% of P0 is rewiring proven M1/M3 parts; these inputs let the build-order land with zero open questions (doc-before-code). The WorkPhase shape was the one genuinely new domain semantics and the one most likely to be wrong — so it was AI-proposed/pending and hardened before ratification; the hardening earned its cost (it was wrong, and the corrected session-bead-cursor shape is *more* A37-consistent).
**Affects:** **ADR-0002** (new `grid_engine` row — amend on the build-order landing); `docs/M4-P0-BUILD-ORDER.md` (v2, hardened); code: the new package + the `WorkPhase` value type + the join-based `phaseOf` (work `Bead` + its session-bead cursor projection) + the bridge's join layer.
**Status:** four forks **+ the corrected (session-bead-cursor) WorkPhase shape** = **Nico's decision, 2026-06-24**. (The v1 work-bead WorkPhase shape was AI-proposed and is superseded — recorded so the divergence isn't silently inherited.)

