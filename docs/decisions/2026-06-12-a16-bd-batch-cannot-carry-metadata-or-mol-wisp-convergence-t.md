---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a16-bd-batch-cannot-carry-metadata-or-mol-wisp-convergence-t
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A16"
---
## A16 (2026-06-12) — `bd batch` cannot carry `metadata` or `mol wisp`; convergence transition writes rely on the write-ordering invariant, not batch atomicity

**Decision:** the M2 actuator does **not** route convergence transition metadata through `bd batch`. bd 1.0.5's `batch` grammar (`cmd/bd/batch.go`) is a narrow subset — `close` / `update <id> <key>=<value>` (keys: **status, priority, title, assignee only**) / `create <type> <priority> <title>` / `dep add|remove` — and explicitly rejects `mol wisp`, `--graph`, and any `metadata=` update ("complex create flows … NOT accepted"; verified: `update … metadata=… → unsupported key "metadata"`). Transition metadata writes (the 16 `convergence.*` keys) therefore go through `bd update <id> --metadata <json>` (which round-trips a multi-key JSON object atomically per bead, verified) — one bd spawn per metadata-bearing bead, **not** one batch per transition. Crash-safety across the resulting non-atomic multi-write transition is provided by ADR-0003's **write-ordering invariant** (invariant 2: `last_processed_wisp` written LAST = the commit point; `gate_outcome_wisp` last in gate persistence) and idempotency keys (invariant 3) — exactly the gc machinery that already assumes writes are not one atomic unit. **Correction (2026-06-13):** the original "burn-and-repoint as `close` + `dep` ops" example is wrong — a speculative-wisp **burn is `bd delete`** (post-order subtree, `deleteBeadSubtree` handler.go:919-933), never `close` (closing a speculative wisp permanently inflates the closed-wisp-count iteration derivation, invariant 4). `bd batch` has **no delete verb** either, so burns are per-bead `bd delete` spawns. Net: of convergence's multi-write shapes, `bd batch` carries essentially none (no metadata, no delete, no `mol`/`--graph`) — it is retained only for incidental `close`+`dep` groupings, and convergence transitions are sequenced `bd update --metadata` / `bd delete` / `bd close` calls ordered by the write-ordering invariant.
**Why:** ADR-0003 D4 states "multi-write transitions (metadata sets + close, burn + repoint) go through `bd batch` — one dolt transaction, one commit … exactly one dirty signal back into our own controller." The "metadata sets + close" half is not achievable on bd 1.0.5 — batch has no metadata verb. This is a ratified-doc/reality mismatch, so it is recorded here rather than silently corrected in D4. The good news: D4's *correctness* goal never depended on batch — the invariants do — so the impact is confined to write-amplification and dirty-signal coalescing (a metadata-bearing transition emits one dirty signal per `bd update`, harmlessly coalesced by the controller's 150ms quiet window and the snapshot diff), not to crash-safety. Re-examine if a future bd adds a batch metadata verb (would restore the single-signal property).
**Affects (if promoted):** ADR-0003 D4 (amend the batch claim: metadata transitions use `bd update --metadata`; batch covers close/dep multi-writes; correctness rests on the write-ordering + idempotency invariants, not batch atomicity). `docs/M2-BUILD-ORDER.md` Track E. Code (M2): `grid_reconciler` actuator; `grid_controller`'s `BdCliService` may need an `update(..., metadata:)` path if not already present.
**Status:** **promoted → ADR-0003 Decision 4 (Nico, 2026-06-14)** — batch carries no metadata; transitions are invariant-ordered `bd update --metadata`/`delete`/`close`; raw SQL stays excluded. Future re-examine: an upstream `bd batch` metadata verb.

