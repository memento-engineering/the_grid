# Changelog

## 0.2.0-rc.1

- Silent, artifact-less harness exits (a usage window running out, a network refusal) classify as `infra`: the restart budget is spent with backoff, then the round opens a gate naming the throttle and flares `harness.throttled` with the tail of the agent's output — never a gateless `failed` strand (tg-mbeh, #294; shipped in this rc after the tag was cut from main).
- Breaking: the store-identity column is `substation`, not `seat` — `trajectory.seat`, `proj_session_head.seat` and the `ck_seat` check are renamed, the journal rename is pinned against real dolt, and the wave-1 guard names it (tg-j1zn, #289). Migration: reshape an existing trajectory db with the rename journal before arming dual-read; readers select `substation`.
- Appends with oversized reasons survive: the fold bounds `work_terminal_reason` (and every free-text reason column the schema declares) with a visible truncation marker instead of dropping the whole `attempt.terminal` record (tg-kzvs, #288).
- The W6 drain and Stage-1 fold guard pins are runner-relative on a shared runner (`TRAJ_GUARD_SHARED_RUNNER`), keeping the tight absolute values for local runs (tg-2zao, #292).

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
