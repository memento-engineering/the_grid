---
status: accepted
date: 2026-09-03
decision-makers:
  - "specify"
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: reason-columns-are-bounded-at-derivation
  surfaces:
    - "packages/grid_trajectory/lib/src/ddl/column_bounds.dart"
    - "packages/grid_trajectory/lib/src/fold/session_head_delta.dart"
    - "packages/grid_trajectory/lib/src/append/trajectory_appender.dart"
    - "packages/grid_sdk/lib/src/trajectory/trajectory_harness.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-kzvs
  legacy-id: null
---

# A free-text reason is bounded to its column at derivation; the column is not widened

## Context and Problem Statement

A `attempt.terminal` whose reason quoted a whole PR payload (~2 KB) exceeded
`proj_session_head.work_terminal_reason VARCHAR(255)`. dolt answered 1105 on
the fold statement inside the appender's transaction, so the `trajectory` row
rolled back with the projection update: the session had no terminal record at
all and the round read as still running (lunar epoch 18, 2026-09-03).

A reason is authored by whatever leg failed. No column width is safe against
it.

## Considered Options

* Widen `work_terminal_reason` to `TEXT`.
* Bound the value where the writer derives it.
* Both.

## Decision Outcome

Bound at derivation, and DO NOT widen. Every column the §4 DDL declares whose
name ends `_reason` is shaped to its declared width — parsed from the DDL, never
a hand-copied list — at the point the writer derives it: the P1 delta function
and the log-row insert. An oversized value keeps its head and gains a visible
` …[truncated from <n>]` marker; truncation is by code point, so no lone
surrogate can reach the server.

Widening is rejected as the primary cure and not adopted alongside it: it moves
the cliff rather than removing it (the next leg quotes more), it costs a
quiesced DROP + re-CREATE + full replay on every provisioned home for a
decoration, and the whole text already survives immutably in the record's
`payload` JSON on the log row — the projection is a rebuildable fold, so the
bounded value is a summary of a fact that was never lost.

Identity-bearing text is explicitly OUT of scope: `idem_key_text`'s SHA-256 IS
`idem_key`, so a bound there would make stored text disagree with the identity
derived from it. Those columns carry service-derived values of known width.

### Consequences

* Good, because a leg's prose can no longer destroy a ledger record; the append
  is shaped to fit, never dropped.
* Good, because the widths are derived from the DDL: a reason column added or
  re-widened is covered without a second edit.
* Good, because the bound sits at the delta's exit, so the incremental fold,
  `traj replay` and grid_sdk's in-process mirror cannot disagree.
* Bad, because an operator reading `proj_session_head` alone sees a truncated
  reason and must read the log row's `payload` for the whole text; the marker is
  what tells them to.
