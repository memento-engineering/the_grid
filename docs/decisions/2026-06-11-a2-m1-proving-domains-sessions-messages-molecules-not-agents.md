---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a2-m1-proving-domains-sessions-messages-molecules-not-agents
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A2"
---
## A2 (2026-06-11) — M1 proving domains: sessions + messages + molecules (not agents/sessions/rigs)

**Decision:** Swap M1's proving domains for the projection mechanism to **session, message, molecule/step** — the domains that actually exist as beads in the live city. Flag `agent`/`role`/`rig`/`convoy` projections as *pending an upstream-representation investigation*.
**Why:** Fixture capture (2026-06-11, bd 1.0.5, city HQ) found **zero** agent/rig/role/convoy/gate beads: 34,588 task, 692 session, 390 chore, 1 molecule, 1 step, 1 bug. In current gc, agents/rigs/roles appear to be config/registry-derived (`city.toml`, `~/.gc/cities.toml`), not beads — the_grid's `types.custom` anticipates them, but there is nothing to pin mappings against. ADR-0002's mapping table is unaffected as a target; only the M1 proving set and its fixtures change.
**Affects (if promoted):** ADR-0002 Decision 2 consequences (proving trio); PDR §6 acceptance criterion 8 (`agentsProvider/sessionsProvider/rigsProvider` → `sessionsProvider/inboxProvider/moleculesProvider`); M1-BUILD-ORDER Track E.
**Status:** promoted → ADR-0002 Decision 2 + PDR §6.8 (2026-06-11).

