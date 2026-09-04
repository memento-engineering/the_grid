---
status: accepted
date: 2026-09-04
decision-makers:
  - "nico"
  - "governor"
consulted: []
informed: []
register:
  spec: 1
  slug: station-lock-record-carries-an-optional-lifecycle-phase
  surfaces:
    - "packages/grid_diagnostics_contract/lib/src/station_lock_record.dart"
    - "packages/grid_cli/lib/src/station_lock.dart"
  obsoletes: []
  updates:
    - station-lock-holds-never-steals-an-unreadable-record
  obsoleted-by: null
  updated-by: []
  bead: tg-knx0
  legacy-id: null
---

# StationLockRecord carries an optional lifecycle phase

## Context and Problem Statement

`tg-g3zx` asks the station lock to record a lifecycle phase so that a BOOTING
station is distinguishable from a crashed one and `AttachResult.Stale` stops
conflating the two. Its spec-readiness round held: outcome 3 of
`station-lock-holds-never-steals-an-unreadable-record` (2026-09-03) says
"`StationLockRecord` gains no field: tg-vg5k (2026-08-01) pinned it
byte-for-byte", and ADR-0014 records the same pin — so an architect could
neither add the field nor invent a supersession.

Read at the source, the pin is narrower than that sentence. `tg-vg5k` was a
package re-homing (move the tree types to genesis, keep `StationLockRecord`
grid-local); "byte-for-byte unchanged" was the scope statement of that move —
the refactor does not touch the file — not a rule that the record may never
gain a field. The 09-03 outcome cited it while deciding a different question:
whether to add a nonce field for ownership. Its load-bearing reason there is
the other half of the same sentence — the RS-4 token does not exist until
`updateControl`, so it cannot be the nonce; `pid` + `startedAt` already on
disk is the nonce. That reasoning says nothing about a lifecycle phase.

The real constraint is compatibility: the record has external readers
(`grid_cli` attach, DevTools, the cockpit, a downstream station's `status`),
so a new field must be optional with a defined reading when absent.

## Decision Outcome

`StationLockRecord` MAY gain an optional lifecycle `phase`. The byte-for-byte
pin recorded by tg-vg5k and restated in outcome 3 of
`station-lock-holds-never-steals-an-unreadable-record` was the scope of that
re-homing, not a freeze; outcome 3's nonce reasoning stands unchanged and is
not reopened here.

Rules for the field:

1. The phase is optional in the JSON contract. A record without it is a
   legacy record and READS AS `live` — every existing reader keeps parsing.
2. The phases are `acquired` (written at acquire), `live` (written at
   `updateControl` — the control endpoint is what makes a station serve), and
   `releasing` (written at release). `updateVmService` writes the VM-service
   URI as an orthogonal flag and never moves the phase (tg-g3zx ruling,
   option a).
3. `AttachResult.Stale` distinguishes a lock at `acquired` whose pid is alive
   (booting — the caller waits or reports BOOTING) from a lock whose pid is
   dead (crashed).

### Consequences

* Good, because a booting station is no longer misreported as crashed, and the
  distinction rides the record every reader already parses.
* Good, because the 09-03 ownership decision keeps its nonce and hold-never-
  steal posture intact; only the over-broad "gains no field" restatement is
  narrowed.
* Bad, because every reader must treat an absent phase as `live` — one more
  legacy branch until the last pre-phase lock on disk is gone.
