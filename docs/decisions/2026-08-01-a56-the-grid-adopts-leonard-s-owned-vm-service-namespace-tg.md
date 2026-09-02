---
status: accepted
date: 2026-08-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a56-the-grid-adopts-leonard-s-owned-vm-service-namespace-tg
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A56"
---
## A56 (2026-08-01) — the grid adopts leonard's owned VM-service namespace (tg-4a78)

**Decision (AI; pending Nico promotion; revised pre-promotion — see Revision).** The `ext.leonard.*` VM-service namespace is OWNED BY LEONARD — the contract authority that publishes the protocol as `leonard_contract`. the_grid is a conforming implementer, not the owner. tg-4a78 changed the VALUE of the grid's own constants from the historical `ext.exploration.*` to `ext.leonard.*` and aligned the protocol version from `1` to `2`, but those local constant declarations are a TEMPORARY re-declaration of a name the grid does not own — a staging artifact with a named retirement: tg-99rr (deferred pending the `leonard_contract` 0.2.0 publish) collapses them onto leonard_contract's exported constants, after which the grid imports the owned name and deletes its local declaration. The resulting methods are `ext.leonard.core.handshake`, `ext.leonard.core.get_stable_observation`, and `ext.leonard.grid.<tool>`. The `extensions` wire key and existing method suffixes remain unchanged. `grid_devtools` mirrors the prefix locally today and pins it against `grid_exploration` in dev tests; post-tg-99rr it mirrors the imported constant, preserving its protocol-only runtime boundary.

**Why.** The anonymous exploration prefix has no owner. The published package family is consistently named `leonard_*`, and the_grid already treats leonard's published read contract as authoritative. This differs from the rejected `ext.flutter.exploration.*` by consent and by intent, not by shape: that name squatted on a foreign framework's reserved prefix with no path to ownership; here the owner renamed in the same coordinated wave (lenny-uoiw landed the same night as tg-4a78) and the grid's local re-declaration is explicitly interim. Held indefinitely, a local re-declaration of another project's namespace WOULD be the Decision-6 sin — this entry is only coherent with tg-99rr's retirement path attached.

**Scope and promotion.** tg-4a78 changed only the value of the_grid's own constants; tg-99rr transfers the declaration itself. Per the register preamble and the A33/A50 precedents, ADR-0001 Decision 6 remains untouched now. Upon Nico's promotion, its one-line prefix/version amendment should record leonard as the namespace owner and the grid as a conforming implementer, and repoint the dead `lenny-wisp-41rdl` reference to `lenny-uoiw`.

**Revision (2026-08-01, governor, pre-promotion).** The original text called the prefix "the_grid's locally owned" while the title assigned ownership to leonard — two conflicting ownership claims in one entry (Nico's catch). Rewritten so ownership is unambiguous: leonard owns `ext.leonard.*`; the grid's constants are an interim re-declaration retired by tg-99rr.

**Status:** PROMOTED (Nico, 2026-08-01) into ADR-0001 Decision 6 as the ext.leonard.* ownership amendment.

