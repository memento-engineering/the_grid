---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: ["governor (station seat)"]
informed: []
register:
  spec: 1
  slug: terminal-provenance-word-is-reconstructed
  surfaces:
    - "packages/grid_runtime/lib/src/trajectory/stage1_obligations.dart"
    - "docs/design/trajectory/cut-wiring.md"
  obsoletes: []
  updates:
    - "wave-2-flip-scope-soak-and-kill-date"
  obsoleted-by: null
  updated-by: []
  bead: tg-t9wl
  legacy-id: null
---

# A healed terminal carries `provenance=reconstructed`, not `inferred`

## Context and Problem Statement

`wave-2-flip-scope-soak-and-kill-date` Q6 ruled that under cut a tick
obligation reconciles "session bead closed, P1 open" into an `attempt.terminal`
with `provenance=inferred`. What shipped in #341 — `ExternalCloseTerminalObligation`
in `stage1_obligations.dart` — writes `reconstructed`, and the settlement
exclusion in the same file keys on that shipped word so the heal is never
settled away. cut-wiring round 6 recorded the mismatch as E6-a and asked for a
one-word amendment; W2-A's docs item was told to record the shipped word and
flag it if the amendment stayed unruled.

## Decision Outcome

The provenance word is `reconstructed`. Q6 reads `provenance=reconstructed`
wherever it said `inferred`; the shipped code is ratified as-is and no rename
is made. W2-A's docs cite this entry instead of flagging the word. Any future
reader that classifies healed terminals matches `reconstructed`.

### Consequences

* Good, because the register follows the tree with a one-word change and the protective settlement exclusion is untouched.
* Bad, because two documents (the Q6 ruling and cut-wiring E6) carried the other word for a week, and any note written from them in that window must be read against this entry.
