# Changelog

## 0.2.0

- PROMOTED from 0.2.0-rc.6. This is the stable release of the 0.2.0 line; the code is the
  candidate's, unchanged. Every intra-family dependency constraint is rewritten from its
  prerelease form to the stable one, because pub refuses a stable package that depends on a
  prerelease.
- Consumers on a `^0.2.0-rc.N` constraint resolve this automatically: a caret range admits the
  release above its own prereleases, so no downstream pubspec edit is required to pick it up.

## 0.2.0-rc.6

- Added: the committee-report fold records per-rule shadow committee-selection evidence read off `step.transition`, so the shadow route's verdict is auditable rule by rule (tg-ix55, #382).

## 0.2.0-rc.5

- Breaking: `ShadowCompare.compare` gains a `corroboration` parameter, `ShadowMismatchClassifier` takes a `ShadowMismatchSubject` and answers a `ShadowClassification`, and `TrajectoryLogReader` gains `epochClaims()` (tg-ilug, #342). Migration: every `ShadowCompare` implementer adds `ShadowCorroboration corroboration = const ShadowCorroboration.none()` to `compare`, every injected classifier is re-shaped on the subject, and every `TrajectoryLogReader` implementer adds `epochClaims()`.
- `traj shadow-diff` names a cause only on evidence (tg-ilug): the `non_atomic_crash` class is assigned when the row's attempt shows a started-without-exited, a lease swept by a successor boot, or an unregained liveness loss; a new `lost_append` class names a loss the recorder counted (`--dropped`/`--suppressed`, now joinable to a row via the new `--epoch` flag) or a claimed epoch the log holds zero rows for; everything else is `unexplained` and blocks the cut. Every row prints its basis. `ShadowMismatchClassifier` now takes a `ShadowMismatchSubject` (attempts, epochs, corroboration) and answers a `ShadowClassification`; `ShadowCompare.compare` gains a `corroboration` parameter; `TrajectoryLogReader` gains `epochClaims()`; the mount-ordinal lane runs the injected classifier instead of hardcoding a class. Breaking for classifier injectors and `ShadowCompare`/`TrajectoryLogReader` implementers.
- `ObligationAppend` and `TickAppender.append` carry an optional `occurredAt`, so a tick repair that testifies to a fact with a known instant (the ledger's `closed_at` for a reconciled terminal, tg-ffl6) lands with that instant instead of the append's.

## 0.2.0-rc.4

- The capability-failure kind introduced by grid_engine 0.3.0-rc.15 rides the trajectory's failure records (tg-e32f, #309). No wire change for readers that ignore the new field.

## 0.2.0-rc.3

- `traj replay` reshapes `proj_session_head` when it still spells the substation identity `seat`: `substation` joins `projSessionHeadCutColumns`, a DDL-coverage test pins that every column the fold writes is a cut column, and `--check` reports the projection half as pending beside the journal rename (tg-0zop, #306). Before this, a home that had run the tg-j1zn journal rename died on `Unknown column 'substation' in 'proj_session_head'`.

## 0.2.0-rc.2

- Added: `bead_round_fold` — one round's lane verdicts folded from the trajectory, the substrate the new `grid bead round` read verb projects (tg-wk3j, #304).
- The guard pins are calibrated from five interleaved probes of the unchanged bare round trip, and the w6 shared-runner bands are widened to the calibrated distribution with headroom for normal runner swing; failures and green measurements both report the raw and calibrated ratios (tg-2zao, #298; tg-shry, #303).

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
