---
status: accepted
date: 2026-09-14
decision-makers:
  - "nico"
consulted:
  - "governor"
informed: []
register:
  spec: 1
  slug: the-soak-clean-row-honours-the-open-retired-shape
  surfaces:
    - "packages/grid_engine/lib/src/domain/session_head_read.dart"
    - "packages/grid_engine/lib/src/bridge/dual_read_pass.dart"
    - "packages/grid_trajectory/lib/src/cli/soak_certificate.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-quwv
  legacy-id: null
---

# The soak certificate's clean row honours the open-retired shape Q9 ruled

## Context and Problem Statement

Two ratified rulings met on the first clean primary soak boot (lunar epoch 77, 2026-09-14) and
disagreed. Q9 of `wave-2-entry-criteria-rulings` (2026-09-06) accepts the open-retired P1 shape:
a session whose round was retired by rework is open in the fold until its terminal, the round
bump is the retirement, and no head-closing record is added. The §W2.5 soak table, delivered as
`traj certify` (tg-2gt1, 2026-09-13), requires the `clean` row's `p2_miss_total` to be zero
across the counted boots. Legacy closes the session bead on a retire, so every retired round is
a legacy-closed session whose fold head is open by design; the join walks those sessions on every
build and each read is counted as a p2 miss. Measured in the trajectory database: 290 legacy-closed
sessions, 155 open in `proj_session_head`, 114 of them retired-round keys, and `p2_miss_total = 93`
on an epoch whose gate sweep had converged. The soak's own human checklist requires a rework inside
the window, so the two rulings cannot both hold as written.

The disagreement is one-sided in the engine. The dual-read comparator already classifies the
shape as `DualReadDivergenceCause.retiredRoundOpenByDesign` and reports it as explained; the
p2-miss gauge that `clean` reads carries no explained bucket.

## Decision Outcome

Q9 stands unchanged. The certificate aligns with it: a p2 miss on a legacy-closed session whose
key is a retired-round key is an EXPLAINED miss, counted in its own gauge and excluded from the
`p2_miss_total` that the `clean` row evaluates, and `certify` prints the explained count on the
epoch line so the exclusion is visible. A miss on any other legacy-closed session — including a
void-rekeyed one — remains a plain miss and still fails `clean`. The retire path, the fold's round
model, and the external-close obligation's skip of retired-round heads are not changed by this
decision. The question of whether a retire should ever write a terminal is carried into the
Stage 2 design, where the retired-round shape is redefined, and is not decided here.

### Consequences

* Good, because the certificate becomes honest about a shape the register already accepts, and
  the G1 soak can be certified without a backfill of 114 historical heads or a change to a
  ratified ruling.
* Good, because the exclusion is narrow and named: void-rekeyed and hand-closed sessions still
  count, so the certificate keeps catching real fold gaps (the 41 found the same night).
* Bad, because the fold and the ledger now permanently disagree about retired sessions by
  design, and every consumer of `p2_miss` must know the explained gauge exists.
* Bad, because the reconciliation is deferred to Stage 2 rather than settled; if Stage 2 keeps
  the open-retired shape, the explained gauge is permanent.

### Confirmation

`traj certify --boots 1` on a fresh primary epoch after the change reports the retired-round
explained count on the epoch line and a `clean` row that names only non-retired causes.
