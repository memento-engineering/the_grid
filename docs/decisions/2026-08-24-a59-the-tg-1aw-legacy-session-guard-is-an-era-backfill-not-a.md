---
status: accepted
date: 2026-08-24
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a59-the-tg-1aw-legacy-session-guard-is-an-era-backfill-not-a
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A59"
---
## A59 (2026-08-24) — the tg-1aw legacy-session guard is an era BACKFILL, not a marker-gated read (tg-1aw)

**Context.** tg-1aw (Nico-accepted follow-up to tg-4rw PR #51's regression-risk C) guards against a pre-marker closed session with an OPEN work bead reading `voided` and re-driving possibly-landed work on a bounce. A 2026-07-12 governor refinement in the bead's notes decided a FAIL-CLOSED READ — a closed session carrying no `grid.outcome` marker reads `done`, never `voided`. That decision was never filed in this register, and spec_review's adr-alignment lane (2026-08-24, grade F) correctly refused the spec built on it as an unratified inversion of A48.

**Decision (AI; REVERSES the 2026-07-12 bead-note ruling).** The marker-gated read is rejected as defective, not merely unratified: a MODERN session closed mid-flight (agent crash, operator close-for-re-mint) also carries no `grid.outcome` marker, so under that rule every dead key would read `done`, permanently block its work bead, and disable A48's voided re-mint recovery (405 unmarked closed sessions stand in the lunar state store alone; the voided path re-minted four dead keys on 2026-08-23/24 alone). Absence-of-marker does not distinguish era. The guard becomes: (1) a one-time, idempotent, per-store BACKFILL stamps `grid.outcome=legacy` onto closed sessions that predate the marker — a NEW disjoint metadata key, no cursor rewrite, so the A16 objection the 07-12 note raised against backfill does not apply; (2) `sessionDispositionOf` reads `grid.outcome=legacy` as `done` (blocks mount); (3) A48's voided clause is UNCHANGED for genuinely unmarked sessions, which after the backfill are unambiguously modern mid-flight deaths. On stores younger than the marker (the lunar store: zero pre-2026-07-13 sessions) the backfill is a no-op and nothing changes.

**Why.** A48's `done` latch stops a resident station re-driving finished work; its `voided` arm recovers dead keys. The 07-12 rule preserved the first by destroying the second. An era backfill keeps both: era becomes a durable store fact stamped once, and the disposition read stays pure.

**Affects (if promoted).** `packages/grid_engine/lib/src/domain/session_disposition.dart` (legacy-outcome arm), `session_bead.dart` (legacy constant), a one-time backfill migration tool, and disposition tests covering the currently-untested no-marker empty/stray-cursor case.

**Status:** Promoted — Nico, 2026-08-24 ("i approve that decision", in-session).

