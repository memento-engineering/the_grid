# M4 scoping — usage-driven, sub-milestoned, adopted through fs

**Status:** Ratified 2026-06-11 (ADR-0000 A6/A7 promoted: A6 → PDR §5 + this doc; A7 → ADR-0003 Decision 6)
**Date:** 2026-06-11

## The strategy

M4 ("gc replacement proper") is NOT scoped like M1–M3 — those port known subsystems and got one ADR each. M4 is scoped by **what the city actually exercises**, measured, then decomposed into sub-milestones whose ADRs are written **just-in-time** (each as its predecessor lands, informed by what M1–M3 taught us). Scoping it fully today would be speculative waterfall against a moving target we ourselves intend to change (the upstream RFC).

## The measured surface (audited 2026-06-11, live city HQ)

This is the parity checklist. Not gc's 343k LOC / 70+ commands — the running city uses:

- **12 gc command families** referenced by hooks/orders/pack scripts: `handoff, prime, nudge, mail, session, rig, bd, config, events, hook, dolt, doctor`
- **13 agent templates**: gastown 7 (boot, deacon, dog, mayor, polecat, refinery, witness) + factoryskills 6 ephemeral pool workers (architect, bitsmith, critique-1..4)
- **1 named_session** (mayor, mode=always)
- **35 orders** (3 city, 28 system-pack, 4 factoryskills-city: route-projection, chair-exec, land-sweep, marshal-sweep)
- **33 formulas** (17 system, 16 factoryskills)
- **6 rigs** (2 active: factoryskills, lenny; 4 suspended incl. the_grid)
- **Packs**: system (core, gastown, dolt, bd) + factoryskills city/rig packs
- **Conspicuously absent** (≈ free non-goals): k8s provider, HTTP API consumers, multi-provider, convoys in primary workflows, web-UI write paths

**Load-bearing undocumented behaviors** (each needs a home in some sub-ADR): `formula_v2=true`; the ephemeral-pool-worker pattern (`GC_SESSION_ORIGIN=ephemeral`, routed-work gates, NOT named_sessions); dolt auto-GC disabled + explicit `CALL dolt_gc()` orders; the city-pack vs rig-pack order-copy split (gc 1.2.0 duplication trap); mayor as template-only named_session; `GC_MANAGED_SESSION_HOOK=1` lifecycle hooks; bitsmith worktree provisioning via rig `pre_start`.

## Sub-milestones and just-in-time ADRs

| Sub | Scope | ADR | Written when |
|---|---|---|---|
| M4a | Config model: city.toml progressive activation, packs/imports/overrides, rig registry | ADR-0005 | as M2 lands |
| M4b | Topology reconciler: desired sessions from config (`build_desired_state`), pool demand, ephemeral workers | ADR-0006 | with M3 (pairs with runtime) |
| M4c | Orders/triggers: cooldown/cron/condition/exec, the 35-order corpus as conformance set | ADR-0007 | after M4a |
| M4d | Sling/dispatch + formula_v2 execution, hooks (`prime`/`nudge`/`mail`/`handoff` command parity) | ADR-0008 | after M4b |
| M4e | Health patrol (probe → threshold → restart over Session projections) | ADR-0009 | after M4b |
| M4f | **Cutover**: one real rig runs on the_grid with gc retired for that rig | ADR-0010 | last |

**M4 acceptance is the cutover test, not feature parity**: Nico's daily factory workflow on one rig, gc off for that rig, parity checklist green.

## The fs adoption ladder (answers "when can I use this?")

the_grid enters service **per milestone**, inside the running factory, long before M4:

| Rung | Milestone | What fs gets | Write authority |
|---|---|---|---|
| **Observe** | **M1** | `grid watch` + DevTools/exploration attached to any rig's workspace: factory beads (specify → build → critique → land) moving in real time, molecule progress, inboxes, ready queues — the `/factory` operator window made reactive, sub-second instead of polled | Read-only (plus manual bd-mediated mutations via grid_cli if asked) |
| **Shadow** | **M2** | grid_reconciler runs against live convergence traffic in **shadow mode**: computes every transition gc would make, diffs against what gc actually did, reports divergence — conformance testing on production traffic | None (read + report) |
| **Drive one rig** | **M3** | the_grid runs the pool for ONE rig — the natural dogfood target is **the_grid rig itself** (currently suspended in city.toml): ready bead → dispatch → spawn worker in grid-owned tmux → supervise → close. *The grid builds the grid.* | Full, for beads/sessions it owns |
| **Replace** | **M4f** | Cutover rig by rig; gc retired per rig as parity holds | Full |

**Coexistence partition rule (hard invariant):** gc's convergence handler assumes a single writer per bead. While both orchestrators run, the_grid must own a **disjoint bead/rig set** from gc's reconciler — partitioned by rig and/or an ownership marker — and shadow mode is strictly read-only. Violating this corrupts convergence state for both.

## What this does NOT decide

Per-sub-milestone design (that's ADR-0005..0010, just-in-time), the upstream RFC content, and whether some surface (e.g. `gc dolt` maintenance) stays on gc-provided tooling indefinitely.
