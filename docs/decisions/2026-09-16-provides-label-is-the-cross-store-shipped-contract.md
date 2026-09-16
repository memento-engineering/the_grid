---
status: accepted
date: 2026-09-16
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor (station seat)"
informed: []
register:
  spec: 1
  slug: provides-label-is-the-cross-store-shipped-contract
  surfaces:
    - "packages/grid_engine/lib/src/domain/external_dep.dart"
    - "packages/grid_engine/lib/src/bridge/federated_snapshot_source.dart"
    - "packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart"
  obsoletes: []
  updates:
    - "the-grid-is-a-beads-controller"
  obsoleted-by: null
  updated-by: []
  bead: tg-hzkv
  legacy-id: null
---

# `provides:<id>` is the cross-store shipped contract, and the station writes it

## Context and Problem Statement

`the-grid-is-a-beads-controller` moved cross-store blocking onto bd's native
`external:<project>:<capability>` rows and named `bd ship` — which labels the
closed provider `provides:<capability>` — as the publish step.
`link-beads-retire-in-one-hard-cut` had the migration verb run `bd ship` for
every already-closed target. Measured on lunar epoch 86 (2026-09-16, grid_engine
0.4.0-dev.9): `bd ship` answers `ship is not supported in proxied-server mode`
on every attached store, no station close path writes the label, and
power_station carried zero `provides:` labels. `applyExternalDeps`
(`external_dep.dart`) therefore held every consumer of a CLOSED target out of
ready — silently, by its own "armed but unshipped" branch — including two
stamped beads for 7–25 hours with no flare and a board that read `ready: true`.

The governor proposed letting the admission read treat an id-shaped capability
as shipped when the target bead is closed. That would make the station's ready
view and bd's own `bd ready` disagree about the same row.

## Decision Outcome

**The label is the contract.** An `external:<project>:<bead-id>` row is
satisfied by exactly what bd's semantic says: a CLOSED bead in the provider
store carrying `provides:<bead-id>`. The admission read does not learn a
second satisfaction rule.

**The station writes the fact bd ship would write.** Every close the station
performs on a work bead — the landing-ready close, the work-terminal close, and
any vended close path — adds `provides:<id>` in the same write. A target
closed by a bare `bd close` is HEALED by the admission pass: an id-shaped row
whose target is closed and unlabelled is classified healable, the label is
written on the provider store as intake refinement (one write, flared once as
`external.shipped`), and the consumer admits on the next pass from the
refreshed snapshot — never in the same pass, so the read stays a read.

**An unshipped hold over a stamped consumer is never silent.** When the target
of an id-shaped row is still OPEN, an otherwise-ready stamped consumer emits a
rising-edge `work.mountEligibilityRefused` with clause
`external-unshipped: <project>:<capability> (target open)`. Named-capability
rows (no bead of that id) keep their silent-until-shipped behaviour, because
"not yet" is a prerequisite's ordinary state.

Until the write and the heal land (`tg-ohrx`), the operator bridge is
`bd -C <provider store> update <id> --add-label provides:<id>` on every
cross-store close.

### Consequences

* Good, because bd's `ready` view and the station's frontier agree on every cross-store row, and the fact is durable in the provider's own store.
* Good, because a hand close no longer strands a consumer forever — the heal converges without an operator ritual.
* Bad, because the admission pass gains a write on a foreign work store (the label), which is intake refinement but is still a write from a read path and must stay one-shot and idempotent.
* Bad, because `bd ship` itself stays unusable in proxied mode; the station reproduces its label write rather than calling it.
