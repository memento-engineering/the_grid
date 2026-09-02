---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a21-db-working-reflects-writes-to-dolt-ignored-wisp-tables-t
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A21"
---
## A21 (2026-06-13) — `@@<db>_working` reflects writes to dolt-ignored wisp tables → the SQL probe is a sufficient wisp-change signal

**Decision:** the server-mode dirty probe `SELECT @@<db>_working` **does** flip on writes to the dolt-*ignored* `wisps`/`wisp_*` tables, so no wisp-specific augmentation is needed for Track G. Dolt's *working* root is content-addressed over all tables in the working set **including ignored ones**; only the *staged*/commit root excludes them (dolt issue #10698; reproduced empirically in embedded mode and in cross-session server mode — a separate probe connection observed the hash change on every wisp INSERT/UPDATE/DELETE by a different writer connection). This closes the shadow-mode hole feared in [[A20]]'s discovery: gc's **cross-workspace wisp closes**, which the `.beads/` file-watcher provably cannot see (it watches only the_grid's own breadcrumbs), DO flip `@@<db>_working` and wake the controller within the ~1s probe interval. Two precision notes for Track G: (1) content-addressing means a wisp pour-then-burn *between* two probe ticks returns the hash to its prior value and is not observed as a delta — acceptable, because the signal need only be **sufficient** (the structural diff is the authority, ADR-0001 D5) and the net state is correct; (2) the probe cannot attribute a flip to wisps vs issues vs other ignored tables — fine for a wake nudge, but Track G must not infer "a wisp changed" from a flip alone.
**Why:** [[A20]] raised the worry that a server-mode grid could hold wisps in its snapshot yet never get the dirty signal to re-capture (the SQL probe being blind to ignored tables). A focused spike (source + dolt-internals + empirical, strictly off the live gascity server per the partition rule) refuted the worry. Pins a Track-G design assumption before it's built.
**Affects (if promoted):** `docs/M2-BUILD-ORDER.md` Track G (probe sufficiency); confirms ADR-0001 D5's "signal need only be sufficient" for the wisp case. Code: none yet (Track G).
**Status:** **promoted → ADR-0001 Decision 5 (Nico, 2026-06-14)** — `@@working` probe flips on ignored wisp-table writes; sufficient for cross-workspace wisp closes.

