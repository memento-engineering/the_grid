# Changelog

## 0.1.2

- `traj committee-report` folds `step.transition` rows into the lane tables, cost totals, and gate causes, so the report reads the same facts the projections carry instead of waiting on `verify.*` record families that do not exist (#281).

## 0.1.1

- `traj committee-report`: a cross-session, read-only report folding
  verdicts, gates, respec outcomes, and usage into per-lane precision,
  override rate, respec convergence, and cost (tg-9x80, #259).
- Shadow-diff scope excludes incomplete sessions (#251).
## 0.1.0

First release — the trajectory log substrate (tg-zfek). A leaf package: zero
`grid_*` dependencies, by decision (grid-trajectory-leaf-package).

- The §1 envelope and the sealed §2 record codec: 50 record types across the
  attempt, admission, verification, step, and effect families, keyed
  `(record_type, type_version)` with checked-in golden fixtures. Old decoders
  are kept forever — a breaking change ADDS a version, never replaces one —
  and an unknown pair decodes to `OpaqueRecord`, so replay never throws.
- The §5 fenced append client over the §4 DDL bootstrap: epoch claim, T6i
  counter-CAS, the terminal guard, a resolving pre-read, belt predicates, and
  the dolt-commit cadence.
- Fold projections — session-head, step-cursor, process identity — with their
  delta types and lag accounting, plus quiesce-only replay.
- The service tick and its obligation query, the shadow readers, and the
  `traj` verbs: `provision`, `show`, `shadow-diff`, `replay`, and `gc`.
