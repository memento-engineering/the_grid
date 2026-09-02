---
status: accepted
date: 2026-06-15
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a32-m3-dispatch-ownership-a-bead-shaped-predicate-shared-rig
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A32"
---
## A32 (2026-06-15) — M3 dispatch ownership: a bead-shaped predicate + shared rig allow-set + a single bd write chokepoint

**Decision (M3 discovery, drafted in ADR-0006 Decisions 1+2 and `docs/M3-BUILD-ORDER.md` Tracks 4/5):** M3's dispatcher **cannot** reuse M2's `OwnsRigs.owns(Convergence)` — that predicate reads `convergence.metadata.rig` (`grid_reconciler/lib/src/runtime/ownership.dart:51`), a key gc's `withEventRig` stamps **only** into convergence beads, while `readyBeads` returns `List<Bead>` of plain work beads with **no such key** (so `OwnsRigs` is structurally uncallable on the dispatcher's actual input — an adversarial-critic catch). M3 therefore introduces a **new** `BeadOwnershipPredicate` / `OwnsBead.owns(Bead)` deriving a bead's rig from the **issue-id prefix and/or `metadata.rig`/label** (ADR-0002 D2; the exact axis is an open decision for Nico). The shared artifact between dispatch and the M2 convergence actuator is the **rig allow-set `Set<String>`** (one source of truth), **not** the predicate object — `OwnsRigs(Convergence)` governs actuation, `BeadOwnershipPredicate(Bead)` governs dispatch, both built from the identical allow-set so they cannot drift. Second line of defense: a single `GridBeadWriter` chokepoint re-checks ownership **fail-closed before every** session/recovery `create`/`update --metadata`/`close`/`delete`, refusing any write whose target rig is absent/not-owned. A no-rig/no-prefix bead is not-owned, fail-closed.
**Why:** the ADR-0003 D6 single-writer partition must be **mechanically** enforced at dispatch, not only at convergence actuation; the existing predicate cannot do it for a plain `Bead`, so a new bead-shaped gate sharing the allow-set is required to keep the_grid from ever spawning against (or mutating) a gc-owned bead.
**Affects (if promoted):** ADR-0006 (Proposed) Decisions 1+2; new code `grid_runtime` `BeadOwnershipPredicate` + `GridBeadWriter`, sharing the allow-set with `grid_reconciler` `OwnsRigs`.
**Status:** **ratified (Nico, 2026-06-15)** — ownership axis = issue-id **prefix** (primary) + optional `metadata.rig == tgdog`; promoted into **ADR-0006 (Accepted)** Decisions 1+2.

