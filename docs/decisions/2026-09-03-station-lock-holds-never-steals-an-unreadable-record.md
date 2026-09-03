---
status: accepted
date: 2026-09-03
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: station-lock-holds-never-steals-an-unreadable-record
  surfaces:
    - "packages/grid_cli/lib/src/station_lock.dart"
    - "packages/grid_cli/lib/src/station_attach.dart"
  obsoletes: []
  updates:
    - adr-0014-the-resident-station
  obsoleted-by: null
  updated-by: []
  bead: tg-o2fy
  legacy-id: null
---

# The station lock publishes atomically, and HOLDS — never steals — an unreadable record

## Context and Problem Statement

ADR-0014 D-A1 fixes the mechanism: exclusive-create
`<grid home>/.grid/station.lock`, "Stale detection: pid-liveness probe — dead
holder → steal + LOUD log; live holder → `StationRefusal` naming the pid and
the `space status` attach hint." It says nothing about a record with no
readable pid, and the implementation filled that silence with "unreadable means
a torn write from a crashed acquire — steal it".

That inference was unsound while a LEGITIMATE acquire could be observed
unreadable. `acquire` exclusive-created the lock, awaited a `chmod` SUBPROCESS,
and only then wrote the JSON: a process-spawn-wide window in which the file was
present and empty. A second acquirer read it, failed to parse, called it
corrupt, and DELETED the winner's lock — two supervisors over one state store,
which is exactly the invariant D-A1 exists to hold.
`updateControl`/`updateVmService` reopened the same window with
truncate-then-write, `release` deleted without checking whose record was on
disk, and a failed `chmod` only logged, so the RS-4 bearer token could be
written into a world-readable file.

The repo already held the opposite posture on the same file: `traj quiesce`
(`packages/grid_trajectory/lib/src/cli/traj_quiesce.dart`) refuses when the
lock "names no readable pid — a torn lock cannot prove the station is down".
Only the acquire path inferred a crash from unreadability.

## Considered Options

* `flock`/`O_EXCLUSIVE` advisory locking, retiring exclusive-create.
* A new owner-nonce field on `StationLockRecord`.
* Keep exclusive-create; make the POPULATE atomic and never steal an
  unreadable record.

## Decision Outcome

The third option (Nico, tg-o2fy interview, 2026-09-03). D-A1's mechanism is
unchanged and this entry does not replace it.

1. **Publish atomically.** The exclusive-create stays the ownership CLAIM; the
   record is written to a sibling temp (`<lock>.tmp.<pid>`), chmod 0600 BEFORE
   any content, then `rename(2)`d over the claim. A reader sees the lock absent
   or complete, never empty or partial. Every rewrite goes the same way — no
   truncate-then-write survives in the file.
2. **Hold, never steal, an unreadable record.** It is young-or-mid-populate,
   not evidence of a crash. The acquirer re-probes on a doubling backoff
   (100 ms, bounded by a 2 s accounted window) and then REFUSES loudly, naming
   the path. A human deletes it; the grid never does. Only a record that PARSES
   and whose pid is dead is stolen — D-A1's rule, applied literally. This
   aligns the acquire path with `traj quiesce`'s already-shipped posture.
3. **The nonce is the pair already on disk.** Ownership is `pid` + `startedAt`
   from the record minted at acquire, re-verified before every rewrite and
   before the release delete. `StationLockRecord` gains no field: tg-vg5k
   (2026-08-01) pinned it byte-for-byte, and the RS-4 token does not exist
   until `updateControl`, so it cannot be the nonce.
4. **A failed chmod is terminal.** It throws a `StationRefusal` and aborts the
   acquire before any content exists — the guard is LOUD or gone (ADR-0008 D3
   amendment), and a bearer token must never land in a file whose mode is
   unknown.

### Consequences

* Good, because the invariant D-A1 names — one supervisor per state store — can
  no longer be broken by two well-behaved acquirers racing.
* Good, because the acquire path and `traj quiesce` now read the same file with
  one rule.
* Bad, because an operator who finds a genuinely corrupt lock must remove it by
  hand. That is the intended trade: an automatic delete cannot distinguish
  corruption from a supervisor two milliseconds into its own acquire.
* Bad, because the ownership re-read before each rewrite is a
  time-of-check/time-of-use check, not mutual exclusion: it makes a lost lock
  LOUD and fail-closed, it does not make the rewrite serialisable. The
  exclusive-create remains the only mutual exclusion, per D-A1.
* Readers (`space status`, `space down`, the reload client, the command client)
  are unaffected: they already treat an unreadable lock as "no station", and
  they never arbitrate.

## Not this

`docs/design/trajectory/trajectory-schema.md` (the unbuilt Stage-0 contract
owned by tg-zfek) declares
`authority.epoch.advanced … steal_reason:enum(stale,corrupt)`. Under this
decision the station lock never steals a corrupt record, so the `corrupt` arm
becomes unreachable from the lock path. Whether that enum arm is dropped or
re-homed is tg-zfek's call when it implements Stage 0; nothing is changed here.
