# THE CUT — wiring design for the trajectory/ledger split — **r5: TWO WAVES**

**Revision seat output, 2026-09-01 (r5). Repo: `engineering.memento/the_grid`, `main` @ `efe9795`.**

**OPERATOR SCOPE DECISION (final): the cut lands in TWO WAVES.**

- **WAVE 1 (this design, converged to landable detail):** C0 (traj replay + traj gc +
  gc disable-on-deny), C1 (P1 read surface + mirror + winner rule), C2 (session dual-read
  OBSERVE + durable round summaries), C3 (P1-primary OVERLAY on the narrow field set), C4 (P2
  step-cursor dual-read), C8a (the onFlare null-sink fix, riding C0). **r4: C8b
  (GRID_INSTANCE_TOKEN retirement) is OUT of wave 1 — it changes bd writes (J7-B3); it
  moved to the wave-2 appendix as W2-E.**
  **NO G1 write changes, NO posture lever, NO deletions.** The ledger keeps writing exactly as
  today — wave 1 is read-side + tools only. Rollback at every point is trivial: config off =
  today.
- **WAVE 2 (the flip — old C5, C6, C7, C9):** moved whole into the **GATED APPENDIX** below,
  marked **DESIGN-INCOMPLETE**. Its unresolved r2 blockers are its entry criteria, quoted
  verbatim. Nothing in the appendix is buildable until wave 1 has soaked AND a dedicated
  wave-2 design round adjudicates every entry criterion. No wave-2 blocker is fixed in r3 —
  deliberately.

r2 → r3: three adversarial judges returned needs-revision on r2 (15 blockers / 18 majors /
16 minors), clustered on the FLIP chunks — lever interlock, compromised-health-under-cut,
KEPT-writes self-contradictions, the `admission.refused` idem key, `attempt.terminal`
decision-bearing. The two-wave split removes the flip from this design's blast radius; r3
fixes in wave-1 text every finding that touches C0–C4/C8, each re-verified against source
(receipts in the ADJUDICATION LOG, judge-3/4/5 tables). The r2 shrink (G1a/G1b, KEPT-writes)
survives as the appendix's frame.

r3 → r4: two adversarial judges returned needs-revision on r3 (8 blockers / 11 majors),
all wave-1 text. r4 lands SEVEN fixes, each re-verified against source (Judge 6/7 tables
in the ADJUDICATION LOG): (1) pgid/pid leave the C3 override set — both judges proved the
overlaid nulls disarm the I-10 void-remint kill fence; (2) the fold-generation reseed
contract is respecified on the ACTUAL `proj_meta` shape (the columns already exist; the
guard now watches the full per-projection row set) and C0 aligns to the in-tree
DELETE-in-transaction replay pattern; (3) C8b moves to the wave-2 appendix (W2-E) — it
changes bd writes, which wave 1's headline invariant forbids; (4) the reconciler's silent
bd-terminal site gains its observer append in C2, so the soak gates are satisfiable;
(5) C4's cursor-consumer list gains the two unnamed decision-bearing consumers;
(6) harness SUPPRESSION joins the compromised-health latch; (7) the post-ACK mirror gets
a real seam — the acked envelope rides back on `Appended`. Everything else is stable;
findings not in that set are marked OPEN in the log — r4 disposes nothing silently.

r4 → r5: two adversarial judges returned needs-revision on r4 (5 blockers / 5 majors),
all wave-1 text. r5 lands FIVE fixes, each re-verified against source (Judge 8/9 tables
in the ADJUDICATION LOG): (1) the teardown-replay observer append is split off the
shared site — its own append at exactly the closed-an-open-session arm — and
re-specified as reconstructed testimony: `outcome='unknown'` + `unknown_reason` (the
schema's explicit-unknown vocabulary), `provenance='reconstructed'`,
breadcrumb-recovered attempt id or a counted SKIP, NEVER a minted id; the comparator
classes the shape `reconstructedTerminal` (adjudication, never divergence); (2) C4's
step axis gains C3's protections verbatim-adapted — monotone no-demotion on cursor
state, the per-node P2-miss = bead-read rule, a named `stepLag` class — because every
step persist site writes the bead FIRST and appends after; (3) `traj replay` is
QUIESCE-ONLY, full stop — the r2 rule restored, the live `--swap` language DELETED (the
in-tree replays scan the whole log before their transaction; a live appender races them
undetectably), and the C0 wrapper checks the lock/fence before touching any projection
table; (4) the OVERLAY IDENTITY RULE — P1 facts merge onto a session projection ONLY
when the P1 row's `session_id` equals that projection's own; `byWorkBead` never feeds
the overlay; (5) `workTerminalReason` leaves the C3 override set (final:
`{isTerminal, completed, humanHeld, closedAt}`) and the divergence tuple
(compare-only informational column) — the escalation reason-key asymmetry made the
zero-divergence gates unsatisfiable by construction. Findings not in that set are marked
OPEN in the log — r5 disposes nothing silently.

Authorities: `docs/design/trajectory/stage1-wiring.md` (esp. §2.3, §2.4, §5),
`trajectory-schema.md` §5/§7/§9/§10/§13, the scout inventory, bead tg-3o6b, the r1 judge
verdicts (adjudicated in r2), the r2 judge verdicts (adjudicated in r3), the r3 judge
verdicts (adjudicated in r4) and the r4 judge verdicts (adjudicated here in r5,
line-verified 2026-09-01).

**Ratified constraints this design must not violate (restated, two r3 amendments):**

1. The fold is REBUILDABLE state — every read surface is reconstructible from the log
   (`traj replay`); no fold-only fact may become the sole carrier of something the log does
   not carry. **Corollary (B-B7): no fact enters a decision-bearing mirror before its record
   is durably committed — mirrors apply post-ACK, never at enqueue.**
2. SINGLE FENCED APPENDER — the dual-read adds READERS only; every append rides the harness's
   one queue → one `TrajectoryAppender`. No second writing connection, ever. (Wave 1 adds no
   writer of any kind — acked appends are wave-2 machinery.)
3. bd CLI-only-writes stays for the WORK ledger — every bd-side repair rides the
   `StationBeadWriter` chokepoint. Wave 1 makes **zero** bd write changes.
4. The trajectory service credential NEVER widens — `trajectory`@'%' keeps `trajectory.*`
   only. `traj gc` uses the gridboot credential (tg-3o6b); bd repairs use bd CLI.
5. async/await only; `Future` API limited to statics. Engine hot paths stay synchronous: the
   dual-read is served from in-memory mirrors, never an inline SQL await.
6. Readers REFUSE a stale fold (`trajectory-schema.md:1112-1114`). **r3 honest restatement
   (F-M2, O-m4):** fold deltas and the `applied_seq` cursor commit inside the append
   transaction on ONE shared `'fold'` `proj_meta` row (`trajectory_appender.dart:461-476`),
   so seed-time lag is structurally zero outside a mid-replay boot or an out-of-contract
   writer. The seed check STAYS (cheap; it guards exactly those states). **r5 (J8-B3,
   J9-M2): there is no sanctioned live-replay case any more — `traj replay` is
   QUIESCE-ONLY (C0) and refuses while the harness is armed; the fold-generation reseed
   rule (§0.2) survives as the DETECTOR for an out-of-contract replay, never a license
   for one.**
7. **Immutable `work_bead_id` in P1.** In-tree authority: the fold's own immutability comment,
   `session_head_delta.dart:108-111` (schema §7's card row at `trajectory-schema.md:1210` is
   the bd-side analogue). **r3 phrasing fix (F-m1):** the `#rN`/`#void-` re-key survives
   untouched; P1 simply declines to follow it — retired sessions are matched `bySessionId`,
   never by the mutated bd key.

**Out of scope:** publishing/release train, the space_station WS-branch merge itself, lunar
changes. Everything lands on the_grid `main`. **External precondition:** the C2+ soak gates
read the `/status` trajectory block that exists on space_station `grid/stage1-runner`
(`trajectory_surface.dart:164/:301`, `up_command.dart:798`); the in-repo durable round
summaries (§0.4) are the always-available fallback surface. FINAL Q2.

---

## 0 The load-bearing design decisions (wave 1)

### 0.1 THE TWO-WAVE STRUCTURE

Wave 1 builds and certifies the entire READ side against a fully live incumbent:

- Every bd write in the tree keeps firing, byte-for-byte — the four `grid.step.state`
  persists, the park/re-arm flips, the inline worktree reap, every terminal/held/re-key
  write. There is no R-set in wave 1. There is no posture. There is nothing to quiesce.
- What lands: the operator tools (C0), the P1/P2 mirrors and their winner rule (C1, C4), the
  session dual-read from observe to P1-primary-as-overlay (C2, C3), the durable evidence
  stream (§0.4), and one independently-safe cleanup (C8a, riding C0). C8b is NOT in wave 1
  (r4 — J7-B3): the token is session-bead METADATA (`SessionBeadKeys.token`,
  `session_bead.dart:45`, minted at `:491`, read back at `:461`), so retiring it removes a
  key from a bd write — and the tree pins the homing itself: "retiring the token is a cut
  change" (`capability_host.dart:409-410`).
- Because nothing retires, **every dual-read fallback lands on a live, authoritative legacy
  carrier**. The failure class "demoted onto a dead carrier" (r2 judges O-B2, C-B4) cannot
  exist in wave 1 — that trap is created by the flip, and the flip is wave 2.
- The r2 headline survives as the appendix's frame: the session-terminal write family is
  load-bearing for Stage-2/3/4 consumers (gate sweep, rework, teardown replay) and stays
  KEPT through any future cut; the G1a/G1b narrowing and the §9-exception question ride the
  wave-2 design round (FINAL Q1).

What wave 1 buys: the strongest possible evidence base for wave 2 — a soaked fold certified
against a live oracle on every decision shape (rework, void, escalation, decline, gate-park),
plus the tools (`traj replay`, `traj gc`, durable round summaries) that every later gate
reads. The churn motive (tg-0zq8: 17 GB, 149k dolt commits; the I-14 stale-join loop) is
addressed by wave 2's retirements; wave 1 makes them adjudicable.

### 0.2 In-memory fold mirrors — post-ACK apply, boot-seed refusal, the retirement-legible winner rule, reseed, and wave-1 health

`StationJoinBridge._join` is pure and synchronous; a P1 SQL read is async. The splice is
pre-fetched state, not an inline await:

- **Where the types live (B-m2):** `grid_engine` gains NO new dependency. The engine defines
  the read INTERFACE in its own domain layer (`grid_engine/src/domain/trajectory_views.dart`,
  new): `SessionHeadView` / `StepCursorView` abstract rows + `TrajectoryHeadSnapshot` /
  `TrajectoryStepSnapshot` interfaces (version, health, seededAt, firstEpochClaimedAt).
  `grid_sdk` (already depending on both — `grid_sdk/pubspec.yaml:33`) implements them backed
  by `grid_trajectory`'s fold row types. No `mysql_client` in the engine's transitive set.
  (P6 views are NOT in wave 1 — see C4's homing decision.)
- **Seeded at boot** with one SELECT over `proj_*` on the harness's serialized connection,
  after epoch claim, before the writer loop starts. The seed reads `proj_meta.applied_seq`,
  `MAX(seq)`, `fold_version`, and `rebuilt_at`; lag >512 records or >60 s ⇒ snapshot health
  `refused` + `trajectory.staleFold` flare. Under wave 1 a refused snapshot means
  **legacy-primary for the boot** — loud, never quiet, never boot-blocking (the incumbent is
  a full oracle; there is no cut posture to protect).
- **Fold-generation reseed (r4 form — J7-B2, respecified on the ACTUAL `proj_meta`
  shape):** `proj_meta` ALREADY carries `fold_version`/`applied_seq`/`skipped`/`rebuilt_at`
  (`trajectory_schema.dart:122-128` — no DDL migration is needed), but the rows are
  heterogeneous: the appender maintains ONE shared `'fold'` cursor row and NEVER writes
  `rebuilt_at` (`trajectory_appender.dart:469-475` — `ON DUPLICATE KEY UPDATE applied_seq`
  only), while the three in-tree replay functions stamp `rebuilt_at` + their fold version
  on upsert — `replaySessionHeads` on the shared `'fold'` row
  (`session_head_fold.dart:152-165`), `replayStepCursors` on `'step_cursor'`
  (`step_cursor_fold.dart:109-124`), `replayProcessIdentity` on `'process_identity'`
  (`process_identity_fold.dart:117-133`). The guard is therefore specified over the FULL
  row set: the harness seeds the triple `(projection, fold_version, rebuilt_at)` for
  EVERY `proj_meta` row and re-reads all rows on its existing timer tick; any triple
  differing from the seeded set ⇒ full mirror re-seed + one `trajectory.mirrorReseeded`
  flare. This is real against the tree: every in-tree replay stamps `rebuilt_at`, so a
  live replay of ANY projection trips the guard **(r5 — with `traj replay` QUIESCE-ONLY
  per J8-B3, the guard is DEFENSE-IN-DEPTH against an out-of-contract replay, never a
  sanctioned live path)**. The seed-LAG rule (constraint 6) reads
  the `'fold'` row's `applied_seq` only — the appender's live cursor; the
  `'step_cursor'`/`'process_identity'` rows' `applied_seq` freezes at replay time and is
  not a lag signal.
- **Maintained POST-ACK, never at enqueue (B-B7, ratified-constraint-1 corollary; the
  seam made implementable in r4 — J6-B4):** the writer loop applies the same pure delta
  (`sessionHeadDeltaFor` → `applySessionHeadDelta`) to the mirror only AFTER the append's
  transaction commits. The delta's input is a `TrajectoryEnvelope`
  (`session_head_delta.dart:97-100`) with envelope-derived insert columns
  (`startedAt: envelope.occurredAt`, `seat`, `headEpoch` — `:113-129`), and today that
  envelope is built and discarded INSIDE the appender (`trajectory_appender.dart:320/:332`)
  while the harness sees only `Appended{recordId, seq, epochSeq}`
  (`append_outcome.dart:18-28`). So C1 extends the append contract: **`Appended` gains the
  committed `TrajectoryEnvelope`.** The harness owns both sides of this seam — appender
  and mirror live in one process behind `TrajectoryHarness`, and `AppendOutcome` is an
  in-process type — so this is an INTERNAL contract change, not a schema or wire change,
  and adds no writer. The writer loop then applies
  `sessionHeadDeltaFor(outcome.envelope, decoded: request.record)` at ordinal
  `outcome.seq` — the same transaction wrote `applied_seq = seq`, so
  `mirrorOrdinal ≡ applied_seq` is earned, never reconstructed. `AppendDeduped` applies
  nothing (the original row either landed this boot — already applied — or predates it
  and rode the seed). A dropped, failed, or suppressed append never reaches the mirror.
- **The winner rule, r3 form (fixes F-B1/O-B6; supersedes r2's three-case rule):**
  `proj_session_head`'s PK is `session_id` with non-unique `ix_bead (work_bead_id, status)`
  (`trajectory_schema.dart:130-144`). The key mechanical fact, verified: **P1's `round`
  column is written by exactly one record** — `attempt.round.retired`, whose
  `newRound = oldRound + 1 ≥ 1` (`station_trajectory_recorder.dart:723-743`,
  `session_head_delta.dart:145-149`) — and a never-retired head carries the DDL default `0`
  (`SessionHeadInsert.rowAt` never sets it). Meanwhile `_closeRetiredReworkSession` closes the
  bd bead but emits ONLY `roundRetired` (`session_scope.dart:213-239`), so a retired session's
  P1 row stays `status='open'` forever — **by schema design** (`trajectory-schema.md:215`
  "bumps round only"), not as a gap. Therefore **retirement is legible in the fold**: an open
  row with `round > 0` is a RETIRED head. The mirror keeps two indexes:
  - `bySessionId` — total, the PK, used for all COMPARISONS (like row with like bead; retired
    `#rN`/`#void-` beads match by session id, and for a `#rN`-keyed bead the retired row's
    `round` column equals N — `newRound` names exactly the round the key names, a direct
    parity check);
  - `byWorkBead` — the FRONTIER/CLASSIFICATION view (r5 — J9-B1: it NEVER feeds the
    overlay; the OVERLAY IDENTITY RULE in §0.3 pins the overlay input to `bySessionId`,
    and `byWorkBead` exists only for reads that already handle multiplicity — the
    cardinality sentinel, the orphan/lag classifiers, and any frontier-level view).
    Partition the bead's open rows into CURRENT
    (`round = 0`) and RETIRED (`round > 0`); retired rows never compete:
    **(1)** exactly one CURRENT open row ⇒ it wins. **(2)** more than one CURRENT open row ⇒
    genuine cardinality breach (a real double-mount, never a rework): flare
    `trajectory.dualReadDivergence{field:'cardinality'}`, serve NO row, count `fallback`.
    **(3)** zero CURRENT open rows ⇒ the closed row with the highest `last_seq` (the
    monotone fold-activity cursor), ties by latest `started_at` — both REAL fold columns
    whose mirror copies are byte-identical to the SQL fold under the r4 seam: `last_seq`
    is the acked `outcome.seq`, and `started_at` is the SessionStarted envelope's
    `occurredAt` (`session_head_delta.dart:113-118`) carried back on `Appended`, never
    reconstructed harness-side. r2's "highest round"
    tie-break dies with the round-semantics correction — P1's `round` is the retired-INTO
    marker, never a running round (F-M1), so it cannot rank closed rows.
    A bead with only retired-open rows (rework window, successor not yet minted) serves no
    row — matching the legacy side, which also has no base-key projection there.
- **The overlay never CREATES (r3, O-B6; r5 — J9-B1 closes the reverse direction too:
  the OVERLAY IDENTITY RULE, §0.3, pins every merge to `P1.session_id ==
  legacy.sessionId`, so a SIBLING row can never splice terminality onto a live session
  either):** the dual-read decorates the LEGACY sessions map;
  the join iterates legacy projections. A P1 row with no legacy counterpart never becomes a
  sessions-map entry and never reaches a decision — so the legacy-miss/P1-hit direction is
  structurally inert for decisions, and the engine's remint-on-retired-round fork
  (`work_list.dart:203-217`, `session_scope.dart:1528-1547`) fires exactly as today. Such
  rows are counted `p1Orphan` and classified by the comparator (§0.3 lag classes).
- **Wave-1 health semantics (r4 form — J6-B3/J7-M3):** snapshot health is
  `live` / `compromised` / `refused` (stale seed). `compromised` latches on any append
  **drop OR failure OR SUPPRESSION since boot** — the harness keeps TWO counters and
  suppression is not a drop: `degraded`/`fencedOut`/`halted` and `_isShutdown` bump
  `_suppressed` and return without touching `_dropped`
  (`trajectory_harness.dart:641-651`), so a drops-only latch would let a fenced-out or
  corruption-halted harness freeze the mirror while health still read `live` and C3 kept
  serving the frozen fold as primary. The latch keys on
  `dropped + failures + suppressed > 0`, AND the existing timer tick latches
  `compromised` whenever harness mode has left `live` — one
  `trajectory.dualReadCompromised` flare either way. **Under wave 1 any
  non-`live` health simply disengages the overlay for the boot: decisions ride pure legacy —
  which remains fully written and authoritative, because wave 1 retires nothing — with the
  loud flare, a status line, and a round-summary field.** There is no demotion trap and no
  posture to interact with. What `compromised` means under `cut` is a wave-2 entry criterion
  (appendix: O-B2, C-B4), including the split of decision-bearing vs fire-and-forget drop
  accounting.
- **Memory bound (B-m3):** 1 KB/row budget for `SessionHeadRow`; P1 bounded by sessions. P2
  eviction: rows for sessions closed in P1 evict (the SQL fold keeps history; `traj replay`
  rebuilds). No P6 mirror in wave 1.
- Mirrors are immutable versioned snapshots threaded through `assembleStationWork`
  (`work_assembly.dart:700-735`) into the bridge and the reconciler, plus a change
  `Listenable` so a fold-side fact re-joins promptly.

### 0.3 Dual-read primary = OVERLAY, never replacement — corrected field set, monotone terminality, and the lag classes

The r2 rule stands and is now literally true in wave 1 (r3 fix of C-B2's contradiction):

> **A decision read rides the fold only for facts it is certified for; every other fact keeps
> its ledger read. In wave 1 every legacy carrier keeps its writer — nothing retires — so
> every fallback and every non-overridden field lands on live, authoritative state.** The
> rule's teeth ("a fact whose write retires must first move its readers") are the wave-2
> entry discipline.

Under `dualRead: primary` + snapshot health `live`, the sessions-map entry is the LEGACY
projection as base with P1 overriding exactly the fold-owned fields — **r5-corrected set
(F-M1: `SessionProjection` has no `round` and no held-reason field; J6-B1/J7-B1: pgid/pid
removed; J9-B2: workTerminalReason removed):**

> `{isTerminal, completed, humanHeld, closedAt}`

via `sessionProjectionOverlay(legacy, SessionHeadView)` (new, pure,
`grid_engine/src/domain/session_head_read.dart`). **`pgid`/`pid` are OUT of the override
set (r4 — both judges proved the same fail-open):** `staleFences` falls back to the
SCALAR `session.pgid`/`pid`/`token` whenever the per-node fence list is empty
(`session_disposition.dart:137-146` — and since `SessionProjection.cursor` is never
populated in production, the scalar fallback is the LIVE path), `_staleFencesAreDead`
returns TRUE on an empty fence list (`session_scope.dart:883-889`) and gates
`_refuseVoidMint` on the void re-mint; P1 meanwhile SET-NULLs `pid`/`pgid` on
`attempt.process.exited` — including an `inferred` exit
(`session_head_delta.dart:164-174`), and its `attempt.process.started` stamp is
fire-and-forget and droppable. An overlaid null pgid/pid on a voided head would yield
ZERO fences, vacuously pass the deadness proof, and authorize spawning over a
possibly-live process group — the I-10 "never double-run a survivor" fence turned
fail-open. So the fence identity triple stays WHOLE on its legacy carrier (one
provenance, never spliced across carriers); those two fields keep the bead read for all
of wave 1. The comparator still observes P1's pgid/pid as a presence pair —
compare-only, never served. **`workTerminalReason` is OUT of the override set and the
divergence tuple (r5 — J9-B2):** the two sides do not carry the same fact. Legacy
projects it ONLY from `grid.work_terminal_reason` (`session_bead.dart:448`), which only
the work-bead-closed settle ever writes (`station_bead_writer.dart:227-229/:455-461`;
`restart_reconciler.dart:865-866`), while P1's `work_terminal_reason` takes ANY
terminal's `reason` (`session_head_delta.dart:142`) — and `_escalateAndClose` hands the
breaker reason to the recorder (`session_scope.dart:1607-1613`) while the bead stores it
under a DIFFERENT key (`grid.escalation_reason`, `:1598-1600`) that never reaches the
legacy field. Every escalated session therefore reads legacy `null` vs P1 `<reason>` — a
divergence BY CONSTRUCTION on exactly the shape the C2/C3 gates make MANDATORY coverage,
i.e. the zero-divergence gates were unsatisfiable as escalated; and no in-tree consumer
reads `SessionProjection.workTerminalReason` as decision state. The field moves to a
COMPARE-ONLY informational column beside the pgid/pid presence pair — reported in the
round summary, never served, never counted as a divergence. `token`, `results`,
`startedAt`, molecule/gate attachments,
and the cursor likewise stay from their legacy carriers — all still written. `round` leaves the override set and the comparator tuple entirely: P1's `round` is
the retired-into marker (0 on every live head — `SessionHeadInsert.rowAt` never sets it), so
it cannot carry a running round; round parity is checked `bySessionId` on retired rows
instead (§0.2). On P1 miss ⇒ pure legacy, counted. On health non-`live` ⇒ overlay
disengaged for the boot (§0.2).

**THE OVERLAY IDENTITY RULE (r5 — J9-B1; answers J7-M1; r6 extends to BOTH axes):** the
overlay merges P1 **and P2** facts onto a session projection ONLY when the row's
`session_id` equals that projection's own `sessionId` — the overlay input is always the
same-session lookup (`bySessionId` on the P1 mirror, `byP2SessionId` on the P2 mirror), never a `byWorkBead` winner, on the session axis AND the step axis
(C4's `trajCursor` fill included). `byWorkBead` never splices terminality across sessions; it exists
only for reads that already handle multiplicity — frontier-level views, the cardinality
sentinel, the `p1Orphan`/`retirementLag` classifiers. Which index feeds what, stated
once: `bySessionId` → the overlay and the comparator; `byWorkBead` → classification and
frontier views, never a served decision. Rationale — the verified fail-open the rule
closes: the legacy join keys ONE projection per base work bead
(`station_join_bridge.dart:229-231`, last-writer-wins, empty key skipped) while P1 keeps
EVERY round's row under the immutable base key, so a legacy session with NO P1 row (a
`session.started` dropped in an EARLIER boot — this boot's health latch has no memory of
it — or a legacy-era session) whose bead carries a terminal SIBLING row would have had
winner-rule (3) serve that sibling: a LIVE session overlaid `done`/`held`/`voided` from
a different session's outcome. `done`/`held` blocks and unmounts live work;
`outcome='lost'` maps to voided and routes into `_refuseVoidMint`'s deadness proof,
which with the default-unwired liveness probe (`session_scope.dart:875-889`) passes
vacuously — the live session is `#void-` re-keyed and re-minted, and the identical
`_projectOwnedSessions` overlay lets `_reconcileWorktree`'s done arm reap the live
worktree. Under the identity rule that P1 miss serves PURE LEGACY, counted `fallback` —
and §0.2's "a P1 row with no legacy counterpart is structurally inert for decisions" is
now true in BOTH directions by construction.

**MONOTONIC TERMINALITY (r3, fixes F-B4; enumeration completed in r4 — J7-B4):** every
terminal writes bd FIRST and appends after, fire-and-forget (`_completeAndClose` closes at
`session_scope.dart:1140`, records at `:1147`; `_escalateAndClose` closes at `:1607`,
records at `:1610`; the reconciler's teardown-replay close at `restart_reconciler.dart:707`
— which today appends NOTHING and gains its observer append in C2, see the C2 chunk;
stage1-wiring:215-216). The window
where legacy says terminal and P1 still says open is real. The overlay therefore **never
demotes a terminal-family fact**: if `legacy.isTerminal && p1.status == 'open'`, the overlay
applies NO overrides for that session — pure legacy is served — and the comparator counts
`terminalLag`. Stated generally: `isTerminal` true→false, `completed` true→false, and
`humanHeld` true→false are demotions the overlay never performs; a P1 value that would demote
a legacy terminal fact is a lag signal, never a served decision. **(r8 — V2-B2, the ONE
escalation rule, stated here normatively:) a `terminalLag` entry that persists past the
90 s HEAL GRACE (three tick intervals — an order of magnitude beyond the post-ACK apply
window, so a normal terminal's transit through the window can never trigger anything)
across at least two comparator passes, with the harness reporting no queued append for
that attempt, first gets the C2 `terminal-reconcile` HEAL append; it escalates to a
`dualReadDivergence` flare only if the heal append failed or the entry survives one
further full comparator pass after the heal — escalation signals reconcile failure, never
the normal window** (in wave 1 the terminal record is fire-and-forget and CAN drop; the
heal is the repair, the flare is the detector of the repair itself failing, and bd —
still fully written — remains the decision carrier either way).

**The outcome → disposition mapping, r3-corrected** — P1 outcome enum
`{succeeded, failed, cancelled, lost, escalated, settled, unknown}`
(`trajectory_schema.dart:135`):

| P1 state | overlay effect | resulting disposition (`sessionDispositionOf`) |
|---|---|---|
| `status='open'` | (subject to monotone guard) isTerminal=false | live |
| `held=1`, open (decline's fold twin — `AttemptReworkDeclined` sets `{held,held_reason}` on an OPEN row, `session_head_delta.dart:150-154`; `_declineRework` closes nothing) | humanHeld=true | **live** — r3 correction (F-m4): disposition reads terminality first (`session_disposition.dart:82-91`), so an open held row is `live` on BOTH sides; the marker becomes decision-bearing at terminality (closed + humanHeld ⇒ held). The comparator compares `humanHeld` in the tuple; no divergence |
| `outcome='escalated'` | isTerminal=true, humanHeld=true | held — the fold closes an escalated session with the outcome carrying the hold (`session_head_delta.dart:136-144` sets no `held` column); the mapping recovers what legacy derives from the `grid.escalation` stamp |
| `outcome ∈ {succeeded, settled}` | completed=true | done |
| `outcome='lost'` | completed=false, humanHeld=false | voided (fences read from the legacy base — the WHOLE pgid/pid/token identity triple, r4 §0.3) |
| `outcome ∈ {failed, cancelled}` | completed=false, humanHeld=false | falls through to the cursor/void arms exactly as legacy (`session_disposition.dart:99-115`) — **whose cursor carrier keeps its writer in wave 1**, so the empty-cursor voiding rule (`:107-114`) keeps today's meaning; how that rule survives step-write retirement is a wave-2 entry criterion (O-m6) |
| `outcome='unknown'` | isTerminal=true, humanHeld=true | held — FAIL-CLOSED: never voided, never done; the settlement obligation heals the outcome. FINAL Q3. (r5: a `reconstructed`-provenance unknown never reaches the overlay — the `reconstructedTerminal` class serves pure legacy for that session) |

**C2's comparator, r5 form:** compares the DERIVED tuple
`(isTerminal, humanHeld, completed, sessionId)` after mapping on both
sides (never raw column-vs-stamp), plus pgid/pid as a presence pair and
`workTerminalReason` as a compare-only informational column (r5 — J9-B2: out of the
divergence tuple; the reason-key asymmetry above made it structurally divergent).
`round` is out of the
tuple (F-M1); round parity is the `bySessionId` retired-row check. Beyond `divergence` the
comparator now owns the LAG/ADJUDICATION classes below, so the gates stay evaluable
through normal lifecycle windows (r3, fixes F-B1/O-B6 gate-unsatisfiability):

- `terminalLag` — legacy terminal, P1 open (§ above). Healed by `terminal-reconcile` at
  the 90 s grace; escalates only on heal failure or survival past the heal (r8 — the
  normative rule lives in MONOTONIC TERMINALITY above; there is exactly one escalation
  rule).
- `retirementLag` — a `p1Orphan` CURRENT-open row whose session bead (matched by session id
  across ALL session beads, any key) is `#rN`/`#void-` re-keyed: expected between the re-key
  (`station_command_handler.dart:328-331`) and `roundRetired` landing at the successor-mint
  site (`session_scope.dart:638`). Heals when the row leaves the CURRENT partition.
  Escalates to divergence when the successor session is present in P1 and the row is still
  CURRENT after 90 s (r9 — aligned with Q5's answer; the retire-close runs at that mint;
  its record must have dropped).
  An orphan with NO matching bead at all is a divergence immediately.
- `incumbentAdjudication` (O-m3) — when two same-bead sessions coexist, the legacy incumbent
  `_projectOwnedSessions` picks its winner by map iteration order (its own doc:
  `restart_reconciler.dart:1112-1125`). A winner mismatch in exactly this class is logged
  with both identities and ADJUDICATED, not auto-presumed against the fold — the incumbent
  rule ("the fold is presumed wrong") applies everywhere the incumbent is deterministic.
- `reconstructedTerminal` (r5 — J8-B1/J9-M1; **r7 — V1-B2: keyed on the DURABLE
  column, immune to settlement**) — any compared pair whose P1 head carries
  `terminal_provenance='reconstructed'` (the COLUMN, set once by the delta when a
  reconstructed terminal record lands; wave-1 writers: C2's teardown-replay append and
  the C2 terminal-reconcile append). **Two hard rules make the suppressor durable
  (r9 — V3-B2 re-keyed both off the IMMUTABLE RECORD, not the mutable head flag):
  (1) TRUTH MONOTONICITY (the one statement, superseding every earlier "marked
  forever" phrasing): the mark is set by a reconstructed terminal landing on a
  terminal-less head; a LATER observed terminal — arriving as the appender's
  settling-conversion, below — overwrites the outcome AND clears the mark; the
  settling branch for plain settlements touches neither. (2)
  `UnknownTerminalSettlementObligation`'s SQL excludes ON THE RECORD:
  `t.provenance != 'reconstructed'` in its trajectory-table scan — a reconstructed
  unknown is NEVER a settlement candidate, permanently and immutably, so clearing
  the head mark can never re-expose it and the observed outcome can never be
  clobbered back to `settled`.** The overlay serves PURE LEGACY for such a session — a reconstructed
  outcome is fold bookkeeping, never decision state — and every tuple mismatch in the
  class is reported with both tuples and ADJUDICATED, never counted `divergence`. Its
  skip counter rides the round summary.

**Gate arithmetic:** soak gates count the `divergence` class only; all lag classes must be
zero at round end (reported per-round in the durable summary). A rework round therefore
produces `retirementLag` transients and ZERO divergences — the gates are satisfiable with
the mandatory shape coverage. **(r5)** `stepLag` (C4) joins the lag classes — zero at
round end, same arithmetic; `incumbentAdjudication` and `reconstructedTerminal` are
ADJUDICATION classes: each occurrence needs a logged disposition in the round summary,
but a nonzero count does not dirty the round (a teardown replay after a bounce is
EXPECTED, not a defect).

**The miss classifier (B-M5, unchanged):** bead-projected session with no P1 row is
`legacyEra` iff `startedAt` predates `firstEpochClaimedAt` **or is null**
(`session_projection.dart:105-114`); a null-started post-epoch projection counts under
`nullStartedAt`, classified legacyEra, so corruption is visible without poisoning the
post-epoch-miss gate.

### 0.4 Evidence — durable, decided before the first gate, on a vehicle that exists

r2 chose `attempt.note(channel='dual-read-round-summary')`; r3 fixes the vehicle mismatch
(C-M4): `AttemptNote` REQUIRES a `sessionId` (`attempt_records.dart:701`, envelope-required
`:711`, idem `note:<session>:<ordinal>` `:736`). So:

- At every session terminal: one summary note, `sessionId` = that session, carrying the
  per-boot counters (hits; misses split post-epoch/legacy-era/nullStartedAt; divergences by
  axis and field; lag-class counts and max ages; fallbacks; drops; mirror seed stats; health
  transitions).
- At the clean-down fixpoint: one boot-final summary riding the sessionId of the LAST
  terminal session of the boot. A boot with zero terminal sessions appends no note — nothing
  gate-relevant happened, and every gate round contains terminal sessions by definition.
- **Flagged doc amendment (rides C2's PR):** stage1-wiring:324 currently states Stage 1 arms
  only `channel='obligation-stuck'` notes; the new channel is a stated extension.

Bounces stop resetting the evidence — the wave-1-done gate reads notes across boots via
`traj show`. Every gate has two surfaces: the in-log notes (this repo, always) and the
WS-branch `/status` block (live view, precondition per FINAL Q2).

---

## WAVE 1 — THE CHUNK SEQUENCE

Five landable PRs on the_grid main. C8a rides C0 (r3, O-M5 — the flare fix must precede
the gates that read flares). No chunk changes any bd write — and with C8b moved to wave 2
(r4, J7-B3) that sentence is true without exception.

```
C0 (traj replay + lag rule, traj gc, gc-deny, + C8a onFlare fix)   — land first
C1 (P1 read surface: engine interface + harness mirror + reseed)    — inert plumbing
C2 (session dual-read OBSERVE + durable round notes)                — decisions still legacy
C3 (session dual-read P1-PRIMARY as OVERLAY)                        — the ratified dual-read
C4 (step-cursor dual-read, P2, observe→primary)                     — same pattern, step axis
WAVE-1 DONE (= C4's soak gate) ⇒ the wave-2 entry gate's soak half is satisfied
```

### C0 — Operator tools + the flare fix

**Files/symbols:**
- `grid_trajectory/lib/src/cli/traj_replay_command.dart` (new): a CLI wrapper over the
  THREE replay functions that ALREADY ship in-tree — `replaySessionHeads`
  (`session_head_fold.dart:132`), `replayStepCursors` (`step_cursor_fold.dart`),
  `replayProcessIdentities` (`process_identity_fold.dart:99` — name corrected r5,
  J9-m2). **r4 correction (J7-B2;
  supersedes r3's O-m5 statement):** replay is per-PROJECTION in the tree, NOT
  all-or-nothing — `'step_cursor'` and `'process_identity'` keep their own `proj_meta`
  rows while `replaySessionHeads` upserts the shared `'fold'` row; the verb's default runs
  all three, and a `--projection` partial rebuild IS expressible and allowed. Each replay
  follows the in-tree transaction pattern: `DELETE FROM proj_*` + re-insert + `proj_meta`
  upsert (stamping `fold_version` + `rebuilt_at`) inside ONE `START TRANSACTION` —
  TRUNCATE/RENAME are DDL and cannot ride it, so r3's shadow-table RENAME-swap language is
  dead. **QUIESCE-ONLY, full stop (r5 — J8-B3/J9-M2; restores the r2 rule, which is also
  the tree's own contract):** every in-tree replay scans the WHOLE log BEFORE opening
  its transaction and rewrites the table from that pre-transaction fold
  (`session_head_fold.dart:137-146`, `step_cursor_fold.dart:93-99`,
  `process_identity_fold.dart:100-107` — each doc-commented "Run with the station
  DOWN"), so under a live appender every record committed between the scan and the
  COMMIT has its fold effect silently erased; the appender's next append re-advances the
  shared `'fold'` row's `applied_seq` so the lag rule reads current, and the reseed
  guard would make the mirror ADOPT the truncated fold with health still `live` —
  neither wave-1 detector can see the hole. r4's `--swap` (live replay despite the held
  lock) argued atomicity-to-readers, which does not answer the write-write race; the
  live-`--swap` language is DELETED, not gated. The verb REFUSES while the harness is
  armed: the C0 wrapper checks the station lock/fence BEFORE touching any projection
  table — the RS-2 lock read by PATH from the grid home, not via a `grid_*` dependency
  (grid_trajectory stays a leaf package, same pattern as
  `traj_provision_command.dart:54-55`) — and runs only with the station DOWN or
  trajectory disabled. No `--swap`, no force flag; the fold-generation reseed guard
  (§0.2) stays as DEFENSE-IN-DEPTH against an out-of-contract replay, never a sanctioned
  path. `proj_meta` needs no change — it already carries `fold_version`/`rebuilt_at`
  (`trajectory_schema.dart:122-128`). **(r6, operator: J11-B1) `proj_session_head` DOES
  change in wave 1: it gains nullable `terminal_provenance` and `unknown_reason` columns,
  written by the delta's terminal branch from the record envelope, carried by
  `SessionHeadRow`, seeded into the mirror. This is the fold's own schema, versioned by
  design. **(r7 — V1-B1: the migration is EXPLICIT, because nothing in the tree reshapes
  an existing table — `applyTrajectorySchema` is CREATE-IF-NOT-EXISTS only and
  `replaySessionHeads` is DELETE+re-INSERT at a fixed shape. C0 delivers the reshape as
  a named step: quiesced `DROP TABLE proj_session_head` + re-CREATE at the new shape
  (`proj_%` is `dolt_ignore`'d, so the drop is journal-invisible and cheap) +
  `fold_version` bump + full replay; an ALTER path is deliberately not built.)** The
  earlier "no DDL" sentence was scoped to proj_meta and is superseded for
  proj_session_head. With
  provenance durable in P1, the `reconstructedTerminal` suppressor survives every boot:
  the overlay and comparator read it from the fold, never from process memory.** Includes the reader lag rule (constraint 6's
  honest form, read from the `'fold'` row) + `traj replay --check` reporting current lag
  and the full per-projection generation set without rebuilding. Credential:
  `trajectory` user (GRANT ALL on `trajectory.*`, `trajectory_provisioning.dart:95`,
  covers the replay DML).
- `grid_trajectory/lib/src/cli/traj_gc_command.dart` (new, tg-3o6b item 2): `CALL DOLT_GC()`
  via the **gridboot** credential from `.grid/trajectory/gridboot.secret`.
- `grid_sdk/.../trajectory_harness.dart` `_onGcTimer`/`_runGc` (`:915-930`, tg-3o6b item 1):
  1105 privilege-denied ⇒ flare `trajectory.gcDisabled` once, never re-arm this process;
  other errors keep flare-and-rearm.
- **C8a (moved here, O-M5):** `work_assembly.dart` state-store writer construction
  (`:521-526`, currently `onRefusal` only) gains `onFlare: transport?.flare`, matching the
  work-store writers (`:588`). Without it `session.minted` (`station_bead_writer.dart:325`),
  `gate.autoClosed` (`:430-434`), and `session.workTerminal` (`:467-471`) are null-sunk on
  the state store for the whole soak — the exact evidence the gates assert. Flare-site list
  re-derived at build time (B-m4).
- `stage1-wiring.md` §4: one line — on scoped-grant homes, gc is operator-run.

**Test plan:** tg-3o6b acceptance; verbs against the hermetic scratch dolt server; replay
golden: replay(log) == incrementally folded tables for **all three** `proj_*` tables;
the quiesce fence: a held station lock / armed harness refuses BEFORE any projection
table is touched (J8-B3 regression);
`--check` lag + generation reporting; recording transport asserts each derived state-store
flare surfaces.

**Soak gate → C1:** suites green + one manual `traj replay` on a copy of the live
tranquility trajectory db reproducing all three proj tables byte-equal. **Rollback:**
revert; additive (C8a is one line).

### C1 — The P1 read surface (engine interface + harness mirror)

**Files/symbols:**
- `grid_engine/src/domain/trajectory_views.dart` (new): read interfaces per §0.2 — no
  pubspec change in grid_engine.
- `grid_trajectory/src/fold/session_head_row.dart`: `SessionHeadRow.fromSqlRow` +
  `scanSessionHeads(TrajectoryDb)`.
- `grid_trajectory/src/append/append_outcome.dart` + `trajectory_appender.dart` (r4 —
  J6-B4): `Appended` gains the committed `TrajectoryEnvelope` (built at `:320`, today
  discarded after `_appendInTransaction`). An in-process contract change only — no
  schema, no wire, no new writer (§0.2's post-ACK seam).
- `grid_sdk/.../trajectory_harness.dart`: the P1 mirror per §0.2 — boot seed with stale-fold
  check, POST-ACK delta apply, `bySessionId` + partitioned winner-rule `byWorkBead`,
  fold-generation reseed on the timer tick, snapshot publication + `headChanges` Listenable.
  Health per §0.2's wave-1 semantics.

**Behavior change: none.** Nothing consumes the snapshot yet.

**Test plan:** golden storms — mirror == SQL fold == full replay after every storm; post-ACK
discipline (B-B7 regression: rejected/dropped append leaves the mirror untouched);
seed-then-apply == cold replay; stale-seed refusal at both bound edges; **winner-rule r3
suite: a rework storm (re-key → roundRetired → successor insert → successor terminal) never
produces a cardinality breach and resolves per the partition at every intermediate state;
a genuine two-CURRENT-open plant DOES breach; closed ladder picks highest `last_seq`;
retired-row `round` == the `#rN` suffix**; reseed on a rebuilt_at change;
`fromSqlRow(toSqlParams(row)) == row`.

**Soak gate → C2:** suites green; one live boot on tranquility with seeded snapshot count +
seed lag + fold generation in the boot banner. **Rollback:** revert; inert.

### C2 — Session dual-read, OBSERVE (divergence flares + durable round evidence)

**Files/symbols:**
- `grid_engine/src/bridge/station_join_bridge.dart`: factory + `_join` gain the optional
  snapshot input (pure, synchronous) + `headChanges` re-join subscription. Per bead: match
  the winner row; compare DERIVED tuples per §0.3 (never raw columns); classify into
  divergence vs the lag classes; flare divergences
  `trajectory.dualReadDivergence{work_bead, session_id, field, fold_value, legacy_value,
  snapshot_version, axis:'session'}`. Retired beads compare `bySessionId`. The overlay never
  creates entries (§0.2). Decisions stay legacy.
- `grid_engine/src/domain/session_head_read.dart` (new): `sessionProjectionOverlay` (with
  the monotone-terminality guard) + `compareHeadToProjection` + `DualReadAccounting` (hits,
  missPostEpoch, missLegacyEra, nullStartedAt, divergences, terminalLag, retirementLag,
  p1Orphan, incumbentAdjudication, fallbacks).
- `grid_engine/src/restart/restart_reconciler.dart:1112-1125` (`_projectOwnedSessions`):
  same compare + counters via an injected snapshot getter; its order-dependent incumbent
  class routes to `incumbentAdjudication` (§0.3).
- **`restart_reconciler.dart:706` — the silent bd-terminal site (r4, J7-B4; re-landed
  r5 per J8-B1/J9-M1):** the teardown-replay arm closes an OPEN session bead (`await
  writer.close(session.id)`) and emits NO recorder terminal — the reconciler's only
  recorder terminal today is the settle arm's `sessionSettled` at `:861`. Left alone,
  every teardown replay would produce a permanent P1-open/legacy-terminal head: an
  unhealable `terminalLag` escalating to `dualReadDivergence` at 60 s, making the C2/C3
  zero-divergence gates unsatisfiable. **r4's form was wrong twice (J8-B1):** it passed
  no attempt id — and the recorder MINTS one when none is passed
  (`station_trajectory_recorder.dart:692-717`, `kReconcilerMintedAttemptBasis`), so a
  fresh `terminal:<attemptId>` idem key (`attempt_records.dart:529-531`) dedupes against
  nothing and the record lands unconditionally — and it justified the site with the
  open-branch entry condition alone while the candidate set ALSO contains
  `_closedSessionsWithOpenMolecules` (`restart_reconciler.dart:599-603`, defined
  `:738-758`). The tree itself splits the arms — `_replayOne` early-returns for a
  closed session at `:664-682` (molecule reap only; it never reaches the
  `writer.close`) — but the r4 text never said so, and a settled-outcome append with a
  minted id sits one refactor away from overwriting an `escalated`/`lost` head
  (`session_head_delta.dart:136-144` rewrites `status/outcome/closed_at` wholesale on a
  non-settling terminal). **The r5 form — its own append, split off the shared site:**
  - **Scope — exactly the closed-an-open-session arm.** The append rides ONLY the
    open-session branch, after ITS successful `writer.close` — the one place the bd
    close actually transitions an open bead (entered only for `done`-disposition heads,
    `:613-616/:631-641`). The closed-session early-return arm appends NOTHING, stated
    as a RULE rather than left to the current control flow: an already-closed session
    had its terminal, and that terminal's absence from P1 is not this arm's to invent.
    **(r6/r7, operator: J10-B1 + V1-B3/B4 — escalation is a conversion into divergence,
    not a heal; the heal is `terminal-reconcile`, HOMED IN THE BRIDGE's comparator
    pass, not the tick: the tick's ObligationQuery seam queries the trajectory DB, which holds no beads, so it
    cannot see bead terminality, while the comparator already computes exactly the
    `terminalLag` pair set from the joined snapshot. **(r8 — V2-B1 killed the
    first-observation trigger: the bd-first/append-later window means EVERY normal
    terminal transits terminalLag briefly, and an eager heal races the real terminal
    record.) The heal fires only for a terminalLag entry that has PERSISTED past the
    90 s grace (three tick intervals; the normal window clears in the post-ACK apply
    time, orders of magnitude shorter) across at least two comparator passes, with the
    harness reporting no queued append for the attempt.** The station-side recorder
    then appends the reconstructed close — `outcome='unknown'`,
    `unknown_reason='external-close'`, `provenance='reconstructed'`,
    `provenance_basis='terminal-reconcile'` (its OWN named basis — `ck_prov` requires
    one and this writer is not the reconciler), **idem key
    `terminal-reconcile:<attemptId>` — a DISTINCT key from the real record's
    `terminal:<attemptId>`, so even a pathological race can never dedupe-swallow the
    true outcome in either direction** — attempt id taken from THE P1 HEAD'S OWN
    `attempt_id` column (written at attempt.process.started; the `grid.lease.*`
    breadcrumb is cleared on NORMAL lease release; for abnormal ends it can survive
    — which is fine and unused here: the heal reads the head column either way, and
    the surviving breadcrumb is exactly what lets the reconciler's own settle arm
    recover the attempt id later — r11). When the head predates process start
    (`attempt_id` null), the heal is SKIPPED and counted — `AttemptTerminal.attemptId`
    is required and no id is ever minted here. **(r9 — V3-B1, the guard contract: the
    heal's append PRECONDITION is a `traj_terminal_guard` check — a terminal row
    already existing for the attempt means the real record landed and the head is
    merely folding (pure lag): SKIP and count, no append. The residual check-append
    race is closed INSIDE the single fenced appender by ONE new rule — TESTIMONY
    YIELDS TO OBSERVATION — landed as a LOG-LEVEL decision so replay is
    byte-faithful (r10 — V4-B1: an after-the-insert conversion diverges live from
    replay; the record must be AUTHORED in its final shape). For every terminal
    append the appender performs a RESOLVING PRE-READ at the top of its serialized
    transaction, before the trajectory-row insert: the `traj_terminal_guard` row for
    the attempt, joined to `SELECT record_id, provenance FROM trajectory WHERE seq =
    guard.seq` (the guard carries no provenance itself — the join is the stated
    read). Then: (a) guard row exists + existing record `provenance='reconstructed'`
    + incoming `provenance != 'reconstructed'` (observed AND inferred — r11, V5-B1:
    the reconciler's settle arm emits a NON-settling `inferred` terminal on exactly
    the heal's successor path, and it must convert, not halt) → the envelope is
    REBUILT in settling form
    before insert (`resolvesRecordId` = that record_id, settling idem key) carrying
    the incoming outcome — the LOG holds the settling shape, so live fold and
    `traj replay` decode identically; (b) guard row exists + incoming
    `provenance='reconstructed'` → benign refused-and-counted — the trichotomy is
    EXHAUSTIVE over incoming provenance (r11), a NEW sealed
    `AppendOutcome` member (`AppendRefusedTestimony`), no insert at all; (c) no
    guard row → normal non-settling append. The guard INSERT's 1062 is caught
    LOCALLY as belt only: after the pre-read inside the serialized single writer it
    is reachable only if the serialization invariant itself broke — which stays the
    corruption halt, as does the genuine two-OBSERVED-terminals class. The delta's
    settling branch clears `terminal_provenance` iff the settling record's
    `provenance == 'observed'` (the durable discriminator — NOT the outcome value:
    an observed `settled` must clear; the obligation's own inferred settlements
    must not) and writes the record's outcome; truth-monotonicity lands exactly
    there, on both live and replay paths — and strictly on `observed`: an
    `inferred` settle (the reconciler arm, the obligation) lands as
    `outcome='settled'` with the mark INTACT, keeping the session in the
    `reconstructedTerminal` adjudication class. Implementation note: the in-transaction
    rebuild re-mints `record_id`; `uq_record_id`, `epoch_seq`, and every belt
    predicate read the REBUILT envelope, never the pre-transaction one.)** **TRUTH MONOTONICITY (also resolves the
    V1 note-6 gap): the delta's non-settling terminal branch sets
    `terminal_provenance='reconstructed'` only when the head has no terminal yet; a
    LATER observed/live terminal record for the same head overwrites the outcome AND
    clears `terminal_provenance` — observed truth always supersedes reconstructed
    testimony, testimony never overwrites truth; the settling branch touches neither.**
    Closing the head is durable testimony, never a bd write; for an EXTERNAL close no
    station bd write exists — this is a record about a fact the station OBSERVED in
    the ledger, which is what an observer append is. Escalation: only after a heal
    append was ATTEMPTED and the entry survived one further full comparator pass
    (normative statement in §0.3 MONOTONIC TERMINALITY). Scope claim corrected:
    reconcile covers heads that EXIST; a post-epoch session with no head at all is a
    MISS under gate (c) — that population only arises from dropped appends, which
    disqualify the round independently.)**
  - **The record tells the truth about what the reconciler knows — no live attempt
    exists at this site.** It carries `outcome='unknown'` with
    `unknown_reason='teardown-replay'` (the schema's explicit-unknown vocabulary;
    `ck_unknown` requires the reason — `trajectory_schema.dart:76-77/:94`) and
    `provenance='reconstructed'`, `basis='restart-reconciler'`: reconstructed testimony
    about a session whose attempt the reconciler never observed. `outcome='settled'`
    stays reserved for the settle arm, which EARNS it by joining the attempt row.
  - **NO fabricated attempt id.** The append recovers the attempt id from the
    session's `grid.lease.*` breadcrumb exactly as the settle arm does (`:845-866`);
    if recovery fails the append is SKIPPED and counted
    (`reconstructedTerminalSkipped`) with one
    `trajectory.reconstructedTerminalSkipped` flare — a missing record is a visible
    lag; a minted-id record is an immutable lie that `revert` cannot remove and every
    `traj replay` reproduces. With the recovered id, dedupe is real: a re-run lands
    `AppendDeduped` on `terminal:<recovered-id>`.
  - **The comparator classes the shape `reconstructedTerminal`** (§0.3) — a named
    adjudication class, NEVER a `divergence`; the overlay serves PURE LEGACY for such a
    session. The gates stay satisfiable with the mandatory shape coverage.
  - **Ratified-clause flag (rides C2's PR, same pattern as the stage1-wiring:324
    channel amendment):** schema Q18 pins `reconstructed` as writable "only by the
    migration-import path" (`trajectory-schema.md:1267/:1550`); wave 1 adds TWO named
    writers — the teardown-replay arm (`provenance_basis='restart-reconciler'`) and
    `terminal-reconcile` (`provenance_basis='terminal-reconcile'`) — and the PR carries
    the one-line Q18 amendment enumerating BOTH (r8) —
    an amendment stated as such, never slipped (the C-B3 lesson).
  **Classification unchanged: a trajectory-side OBSERVER APPEND — a new record ABOUT a
  bd write that already happens today; the bd write itself stays byte-identical. It
  does not touch the zero-bd-write-changes invariant.**
- `grid_sdk/src/work/work_assembly.dart:700-735`: thread snapshot + changes into both.
- Durable evidence per §0.4 (terminal + boot-final notes; the stage1-wiring:324 channel
  amendment rides this PR). Config: `TrajectoryConfig.dualRead: observe | primary`
  (default `observe`).

**Explicitly untouched:** `projectSession` (`session_bead.dart:436`), `sessionDispositionOf`,
`staleFences`, everything under `grid_cli/src/traj_legacy_session_reader.dart`.

**Test plan:** planted mismatch flares with payload; escalated session ⇒ ZERO divergence
(B-B4's trap); **a full rework lifecycle ⇒ retirementLag transients, zero divergences, lag
zero at round end; a legacy-terminal/P1-open window ⇒ terminalLag, no flare, pure-legacy
serve; a dropped terminal append plant ⇒ the `terminal-reconcile` heal append at the 90 s
grace under idem key `terminal-reconcile:<attemptId>`, escalation flare ONLY when the heal
is planted to fail (r8); a normal terminal's window transit ⇒ no heal, no flare (the race
regression test)**; era classification incl.
null `startedAt`; a planted teardown replay (open+`done` candidate WITH a lease
breadcrumb) ⇒ the observer append lands under the RECOVERED attempt id with
`outcome='unknown'`/`provenance='reconstructed'`, P1 closes, the comparator classes
`reconstructedTerminal`, ZERO divergence (J7-B4/J8-B1 regression); a planted CLOSED
candidate with open molecules ⇒ NO append (J8-B1 regression); a breadcrumbless open
candidate ⇒ SKIP + `reconstructedTerminalSkipped`, no minted id; snapshot absent ⇒ all-fallback,
zero flares; reconciler mirror tests;
notes land at terminal and at down (idle boot ⇒ none); integration: scratch home, one
session end-to-end, zero divergence, 100% post-epoch hits.

**Soak gate → C3 (the first ratified soak):** 3 consecutive live rounds on tranquility with
(a) zero `divergence`-class events, (b) all lag classes zero at each round end, (c) zero
post-epoch misses, (d) zero drops — read from the round-summary notes via `traj show`
(+ `/status` when the WS branch is on the runner). Rounds must collectively exercise the
decision shapes: at least one rework, one void, one escalation or decline — scripted on the
scratch home if the live board doesn't produce them. Any divergence: the fold is presumed
wrong (incumbent rule, except the `incumbentAdjudication` class), fix, restart the count.
**Rollback:** revert or leave `observe` — passive wiring.

### C3 — Session dual-read, P1-PRIMARY (overlay form)

**Files/symbols:** same files. Under `dualRead: primary` + health `live`: the sessions-map
entry becomes `sessionProjectionOverlay(legacyProjection, bySessionId[legacy.sessionId])`
per §0.3's OVERLAY IDENTITY RULE (r5 — J9-B1: the overlay input is the identity-matched
row, NEVER a `byWorkBead` winner) — legacy base,
P1 overriding exactly the r5 field set (§0.3 — pgid/pid excluded, J6-B1/J7-B1;
workTerminalReason excluded, J9-B2),
monotone-terminality guard active,
`_attachMoleculeBeads`/`_attachGateState` unchanged. P1 miss ⇒ legacy, counted `fallback`.
Health non-`live` ⇒ overlay disengaged for the boot (§0.2). Divergence while primary still
flares — P1 wins the decision within the certified field set, and a divergent round is not
clean. `_projectOwnedSessions` gets the identical overlay. Default stays `observe` in the
PR; the flip to `primary` default is a separable one-line commit attached to the C2 gate
evidence.

**Test plan:** property test — for generated equivalent (record-stream, bead-state) pairs,
`sessionDispositionOf(overlay) == sessionDispositionOf(legacy)` across all dispositions
INCLUDING escalated (held via outcome mapping), declined-open (live on both sides — the
F-m4 row), declined-then-terminal (held), void (outcome=lost, fences with the whole
pgid/pid/token triple from the base — J6-B1/J7-B1 regression: a voided overlaid session
must yield the SAME fence list as pure legacy), unknown (held, fail-closed), settled
(done); **monotone guard: no generated
stream may produce an overlay that demotes a legacy terminal (F-B4 regression)**;
rework-window property: at every intermediate state of re-key→retire→remint the overlay
serves either the legacy projection or nothing new (never a P1-only entry — O-B6
regression); identity-rule regression (J9-B1): a legacy session with NO P1 row plus a
terminal SIBLING row on the same bead ⇒ pure legacy + `fallback`, never a spliced
terminal; escalated session under the r5 tuple ⇒ ZERO divergence with
`workTerminalReason` reported compare-only (J9-B2 regression);
health-disengage; full engine suite green with a fake snapshot in primary.

**Soak gate (wave-2 entry input):** 3 consecutive clean rounds under primary — zero
divergence, zero drops, post-epoch fallback = 0, lag classes zero at round end, clean
`traj shadow-diff` per round, same shape coverage as C2's gate. **Rollback:**
`dualRead: observe` (config/env, one line) — instant, and legacy is still fully written.

### C4 — Step-cursor dual-read (P2) — observe, then primary

Step-state reads become fold-capable and certified — the prerequisite evidence for wave 2's
R8/R9/R10 retirement, which is NOT in this wave.

The cursor is computed at CONSUMERS (`projectMoleculeCursor`; there is no cursor-attach in
the bridge — B-m1). One verified base fact frames the list (r4 — J6-B2/J6-M2):
**`SessionProjection.cursor` is NEVER populated in production** — `projectSession`
deliberately leaves it empty (tg-eli phase 2, `session_bead.dart:426-436`) and
`StationJoinBridge` never attaches it; the real cursor exists only as
`projectMoleculeCursor`'s recompute over the session's own step beads. **The SEVEN cursor
consumers (r4 completes r3's list, which claimed exhaustiveness at five — J6-B2; the
O-B5 log row is corrected accordingly):**

1. `grid_engine/src/circuit/unclaimed_frontier.dart:87` — adopts `effectiveCursor`.
2. `grid_engine/src/domain/wedge.dart:195-198` (recomputes via `projectMoleculeCursor`) —
   adopts `effectiveCursor`. (r3 cite corrections per O-m2.)
3. `grid rework`'s park check, `station_command_handler.dart:289-322` — adopts
   `effectiveCursor`.
4. `sessionDispositionOf` (`session_disposition.dart:100, :107-115`) — **deliberately NOT
   adopted in wave 1**, with the reason CORRECTED in r4 (J6-M2 proved r3's version wrong):
   it does not read `molecule_codec.dart` output — it reads `SessionProjection.cursor`,
   the never-populated field, so its empty-cursor void arm (`:107-114`) is today's LIVE
   behavior for every terminal session that is neither completed nor held. Wave 1 must
   not change that behavior, adopted or not — which is exactly why it stays unadopted;
   a fold-backed disposition (with the void arm's post-retirement meaning) is a **wave-2
   entry criterion** (appendix).
5. `staleFences` (`session_disposition.dart:127-149`) — same status (unadopted; its
   scalar-fallback read is today's live behavior and must not move), same wave-2 entry
   criterion; additionally its per-node pgid/pid/token fence inputs are step-bead facts
   whose fold home (P6/P2) is a wave-2 design question.
6. **(r4, J6-B2)** `session_scope.dart:1733` — `SessionScope.build`'s
   `projectMoleculeCursor(joined.moleculeBeads, …)`, the cursor `CircuitScope`/
   `InheritedCircuit` mount off: the mount-frontier authority and the most
   decision-bearing cursor read in the tree — plus its flat residual at `:1841`
   (`cursor = joined?.cursor ?? {}`). Adopts `effectiveCursor` under the same
   primary+live condition as consumers 1–3; without it the station would run TWO cursor
   truths under primary (the park check and the unclaimed frontier on the fold, the
   scope that actually mounts steps on its own bead recompute).
7. **(r4, J6-B2)** `station_driver.dart:139` — `_scanCooldowns`, which arms the backoff
   timer off `session.cursor.values`. Adopts `effectiveCursor`. OPEN CARRY (J6-M1/
   J7-M5, not silently resolved): this site — and the frontier, consumer 1 — iterates
   the structurally-empty field today, so adoption there is a behavior CHANGE, not a
   pure read swap; `effectiveCursor`'s non-primary branch and the "config off = today"
   rollback claim for these sites need pinning in the C4 PR.

**Files/symbols:**
- `grid_trajectory`: `StepCursorRow.fromSqlRow` + `scanStepCursors(db)`;
  `trajectory_views.dart` gains `StepCursorView` + `TrajectoryStepSnapshot`. **r3 (C-m3):
  the mirror carries P2's FULL column set — state/started/ready/completed/failureClass plus
  `restart_budget`, `cooldown_until`, `incarnation`, `superseded_by_step_round`,
  `attempt_id`, `result` JSON — so wave-2 design starts from an honest inventory; wave-1
  consumers read only the cursor-state fields.**
- Harness: P2 mirror — same seed/post-ACK/health/reseed mechanics; eviction per §0.2.
  **P6 homing decision (r3, resolves O-B4): wave 1 builds NO P6 mirror — C4 needs step-cursor
  rows only, and no wave-1 consumer reads per-attempt process identity. P6's single home is
  the wave-2 tick-reap chunk (appendix W2-A); the barrier chunk (W2-B) consumes it.**
- `SessionProjection` gains optional `trajCursor: Map<String, NodeCursor>?`; the bridge
  fills it from P2 via the mirror's OWN index — **(r7, V1-M5) the P2 mirror defines
  `byP2SessionId: Map<String sessionId, List<StepCursorRow>>` (distinct from P1's
  `bySessionId` head index; the two mirrors never share an index name). The fill for a
  projection: rows where `row.session_id == projection.sessionId`, COLLAPSED per
  `step_path` to the newest incarnation — the row with lexicographically greatest
  `(round, step_round)`, the supersedes ladder's own ordering — one `NodeCursor` per
  node path.** Applied when primary+live — **(r6, operator: J10-B2/J11-B2) the OVERLAY
  IDENTITY RULE applies
  to the step axis VERBATIM: P2 facts merge onto a session projection only when the P2
  rows' `session_id` equals that projection's own; the `byWorkBead` winner NEVER feeds
  `trajCursor`. A projection with no same-session P2 rows takes the per-node P2-miss
  rule (legacy read + counter), never a sibling's rows — a cross-session splice is a
  PROMOTION the monotone rule cannot catch, which is why identity, not monotonicity,
  is the guard here.** Shared
  helper `effectiveCursor(session, stepBeads)` adopted by consumers 1–3. Overlay rule per
  field: state, stepRound, incarnation, supersededByStepRound from P2;
  `restartCount`/`cooldownUntil`/pgid/pid/token stay bead-read (B-M2 — the breaker's read
  never moves in wave 1). `step_round`'s closed-gate-count component derives from bd gate
  beads — untouched.
- **Step-axis protections, C3's verbatim-adapted (r5 — J8-B2):** the tree writes the
  step BEAD first and enqueues the transition record after, fire-and-forget, at EVERY
  step persist site — `_persistReady` (`capability_host.dart:704-727`: awaited
  `writer.update` then `_recorder.stepReady`), `_persistComplete` (`:731-754`),
  `_persistFailureClassed` (`:786-800`) — and the join recomputes ON that bd write
  (`station_join_bridge.dart:36-40`), so at every transition the compare sees legacy
  AHEAD of P2 by construction. The bead-first/append-later window is the step axis's
  exact analogue of the session axis's close-then-record window, and it gets the same
  three protections:
  - **Monotone no-demotion on cursor state:** a bead-terminal step state never demotes
    via P2 — `complete`/`ready` (and a bead `failed` with its restart bookkeeping) are
    never overridden by an older or absent P2 state; a P2 value that would demote a
    bead-carried step state is a lag signal, never served. F-B4's session rule,
    verbatim on the step axis.
  - **The P2-miss rule, per node:** a node with NO P2 row (the GUARANTEED state of every
    step for the whole append round-trip after it transitions) reads the LEGACY BEAD
    for that node and bumps a `p2Miss` counter — never a default, never omission from
    `effectiveCursor`. An omitted node would read as unclaimed at consumer 1
    (`unclaimed_frontier.dart:87`) and consumer 6 (`session_scope.dart:1733`) and be
    re-claimed/re-mounted — a double-run, the exact I-10 class.
  - **`stepLag` — the step axis's named lag class:** legacy step state newer than P2
    (or bead row present / P2 row absent) counts `stepLag`, excluded from the
    `divergence` count, required zero at round end, 60 s escalation to
    `dualReadDivergence{axis:'step'}` naming the probable dropped transition append —
    `terminalLag`'s arithmetic, step-shaped (§0.3 gate arithmetic).
- Compare + counters `axis:'step'`; the round summary gains the step axis; cursor-STATE
  parity is compared per node (fence-input parity — which nodes are live — follows from it,
  and is reported so wave 2 inherits fence evidence); `stepLag` and `p2Miss` per the r5
  rules above.

**Test plan:** cursor parity property storms incl. the gate→rearm→resume shape (I-14) and
supervised restarts (incarnation bumps); step-axis protections (J8-B2): an
append-in-flight window at each of the three persist sites yields `stepLag`, never
`divergence`; a P2-missing node reads the bead and counts `p2Miss` (never omitted from
`effectiveCursor`); no-demotion property: a bead-complete/ready step never demotes via
P2; wedge/frontier/park-check suites under both feeds;
breaker parity: bead-read restartCount/cooldown drive identical decisions under both feeds;
C0's replay rehearsal re-run including P2 on live-copy data.

**Soak gate (wave-2 entry input):** 3 clean rounds step-axis primary — zero step
divergences, zero post-epoch step fallbacks, lag discipline as C3 — may be the same rounds
as C3's; shape coverage must include at least one gate-park + re-arm cycle. **Rollback:**
`dualRead` demotion; step axis observes; legacy cursor still fully written.

### C8b — MOVED TO WAVE 2 (r4, J7-B3)

Removed from wave 1. The token is bd session-bead METADATA — `SessionBeadKeys.token`
(`session_bead.dart:45`), written into the mint metadata map (`:491`), read back at
`:461` — so retiring it CHANGES a bd write, contradicting wave 1's headline invariant
("byte-for-byte", "no bd write changes anywhere") and its rollback story: sessions minted
post-C8b would be durably token-less, so `revert` does not restore the fence input for
beads already written. The tree pins the homing itself: "`GRID_INSTANCE_TOKEN` stays:
Stage 1 dual-exports, and retiring the token is a cut change"
(`capability_host.dart:409-410`). The r3 sketch moves whole to the appendix as **W2-E**;
wave-1 done = C4's soak gate. FINAL Q6 is thereby ANSWERED by the invariant, not by
preference.

### Wave-1 rollback story (whole wave)

Every chunk is read-side or a one-line fix; no bd write changes anywhere (with C8b moved
out in r4, without exception — C2's reconciler append is a trajectory-side observer
record, not a bd write), so no durable damage class exists. At any point:
`dualRead: off` — THE DEFAULT since r13, and therefore the posture main ships in — =
today's decision paths, against a ledger that never stopped being written exactly as
today. **`off` = byte-equivalent to main EXCEPT C8a's flare delivery, a designed fix.**
C8a is ungated on purpose: the state-store writer was null-sinking `session.minted`,
`gate.autoClosed`, and `session.workTerminal`, and repairing that is a reviewed BUG FIX,
not a posture. Everything else the wave adds — the comparator on both axes, the P1/P2
mirror seed/apply/reseed, the bridge's mirror push sources and acked-envelope handbacks,
the observer appends, the boot reshape probe, and the appender's resolving pre-read — is
armed BY the posture and silent under `off` (r13); the soak's `observe` is armed
explicitly by the runner, never inherited from a default. OPEN CAVEAT (J6-M1/J7-M5):
C4's adoption at the frontier/cooldown/flat-residual sites replaces a structurally-empty
read, so "config off = today" needs `effectiveCursor`'s non-primary branch pinned in the
C4 PR — an r4 carry. SECOND CAVEAT (r13): downgrading `observe` → `off` on a home that
already carries observe-era RECONSTRUCTED rows can halt on a late real terminal, because
the resolving pre-read that converts it is posture-gated; bounce back through one
`observe` boot to convert those rows, then `off` is clean.

## Cross-cutting test/CI additions (wave 1)

- **Golden fold invariants:** mirror == SQL == replay per-run in grid_trajectory CI;
  post-ACK (drop never mutates the mirror) as a standing property test; the winner-rule
  rework storm as a standing property test.
- **The oracle fence (A-m2):** CI grep pins that `grid_engine`/`grid_sdk` import neither
  `grid_cli/src/traj_legacy_session_reader.dart` nor grid_trajectory's exported
  `src/shadow/legacy_session_reader.dart` (`grid_trajectory.dart:67`).
- **Decision-shape soak coverage (A-m4):** the gate checklist template names the required
  shapes per gate; scripted scratch-home rehearsals fill what live rounds miss.

## Flare vocabulary added by wave 1

`trajectory.dualReadDivergence` (axis-tagged, incl. `cardinality`),
`trajectory.dualReadCompromised`, `trajectory.staleFold`, `trajectory.mirrorReseeded`,
`trajectory.reconstructedTerminalSkipped` (r5 — C2's breadcrumbless-teardown skip),
`trajectory.gcDisabled`. Reserved for wave 2 (do not emit in wave 1): `mount.refused`,
`g1.breakGlass`.

---

---

# WAVE 2 — GATED APPENDIX: THE FLIP (old C5, C6, C7, C9)

> ## ⚠ DESIGN-INCOMPLETE — DO NOT BUILD FROM THIS APPENDIX
>
> This appendix preserves the r2 chunk sketches and their r2 adjudications AS-IS (known
> defects included, uncorrected — r3 deliberately fixes nothing here). It is not a design;
> it is the corpus the wave-2 design round starts from.
>
> **THE WAVE-2 GATE — all three, in order:**
> 1. **Wave 1 soaked:** 3 clean consecutive live rounds of C2-observe evidence AND the
>    C3-overlay-primary gate evidence (with C4's step axis), shape coverage on record
>    (rework, void, escalation/decline, gate-park + re-arm), all read from the durable
>    round summaries.
> 2. **A dedicated wave-2 design round** that adjudicates EVERY entry criterion below with
>    file:line verification, then re-judges.
> 3. **Operator ratification** of the questions the round surfaces — at minimum the §9
>    coexistence exception (F-M6's honest framing of what r2 called a "narrowing"), the
>    `admission.refused` idem-key question (a ratified-schema clause), and the break-glass
>    contract.

## ENTRY CRITERIA — the unresolved r2 blockers, verbatim

Each of the following blocked r2 and is UNRESOLVED. Quoted verbatim from the r2 verdicts
(judge attribution in brackets); wave 2 cannot be designed past any of them silently.

**[ordering-rollback B1]** NO INTERLOCK BETWEEN `g1` AND `dualRead` — the two levers are
independent and C7 flips only one. C7 (cut-wiring.md:605-607) is 'one small PR —
TrajectoryConfig.g1 default shadow -> cut'. §0.4 forces only `TrajectoryConfig.mode` to
`required` under cut (:235-237); it never forces `dualRead: primary`. C3 explicitly leaves
the primary default to 'a separable one-line commit' (:458-459), and C7's five-item pre-flip
checklist (:610-616) asserts evidence, never config. So `g1=cut` + `dualRead=observe` is a
permitted, unrefused boot in which R8/R9/R10 step writes are retired while step-state
decisions still read the retired bead carrier. Worse, this is the documented rollback: C3's
rollback is '`dualRead: observe` (config/env, one line) — instant' (:473) and C4's is
'`dualRead` demotion' (:513), with no statement that either is valid only pre-C7. An
operator following the design's own abort instructions post-flip lands in the corrupt state.
Fix: make `cut` refuse a boot whose dualRead is not primary on both axes, and restate C3/C4
rollback as posture-conditional.

**[ordering-rollback B2]** AUTOMATIC RUNTIME DEMOTION TO A DEAD CARRIER UNDER `cut` — C1
sets health `live` iff 'zero acked-append failures since boot; drop/failure latches
`compromised`' (:393) and C3 says health `compromised`/`refused` => 'legacy-primary for the
boot' (:455-456). §0.5 keeps fire-and-forget enqueue for flares, notes, worktree receipts
and shadow records (:269-271), and the harness has ONE global `_dropped` counter bumped by
every drop class — queueBound overflow (trajectory_harness.dart:652-657), reconnect-debounce
(:700-706), listener/serialize failures (:731-747, :754-759). So a burst of dropped NOTES
latches `compromised`, which under `cut` silently demotes step-state decisions to a legacy
cursor that has no writer. This is unattended, mid-run, and is not covered by §0.4's
boot-time cut-posture refusals (which handle harness-not-LIVE and stale seed only). Fix:
split decision-bearing drop accounting from fire-and-forget, and under `cut` make
`compromised` a breaker/halt, never a demotion.

**[ordering-rollback B3]** RESTORE+REPLAY SILENTLY REGRESSES DECISION STATE AND THE
STALE-FOLD GUARD CANNOT SEE IT — §0.4 makes 'restore + `traj replay` first' the first rung
of the recovery ladder (:251-252) and C7's soak gate prescribes the drill (:622-625). The
stale-fold rule is intra-db: `proj_meta.applied_seq` vs `MAX(seq)` (:35-38, :129-131).
Verified in trajectory_appender.dart:461-476 — the fold deltas AND the `applied_seq` cursor
ride the SAME transaction as the record INSERT, one shared `'fold'` projection row, single
COMMIT. A restored-then-replayed db is therefore internally consistent at every point and
the refusal can never fire, even though it is behind reality by every record written after
the snapshot. Under `cut` those lost records are step facts with no second carrier (the
shrink dual-carries session facts only), so the boot seeds mirrors missing completed steps;
§0.3's 'On P1 miss => pure legacy, counted' (:183) then routes the decision to a legacy
cursor that under cut reads as never-run. Result: re-drive of completed work, no detector,
no refusal. Nothing bounds restore-point loss, marks post-snapshot sessions suspect, or
refuses a boot on post-epoch misses under cut.

**[fold-fidelity B2]** KEPT-WRITES SET — R8 and R11 are literally the same statement, and
two other R8 sites carry KEPT facts. R8's fourth cite `capability_host.dart:789-798` IS
`_persistFailureClassed`'s single chokepoint `writer.update`, whose metadata map is
`_moleculeMetadata(failed, restartCount: next, cooldownUntil: cooldown, failureReason: …)` —
the exact write the KEPT table ratifies as R11 ("restartCount/cooldown persist … Retires at
Stage 2", the accepted B-M2 fix). One call, one map: it cannot be retired under `cut` and
kept at once. Same collision at :707-715 (`_persistReady`) and :735-741 (`_persistComplete`),
which merge `nodeResultMetadata(_nodePath, payload)` into the same update — the
`grid.result.*` STEP keys that feed the KEPT rework round cap (`reworkVerdictEvidence` reads
`projectCircuitResults(step)`, session_bead.dart:374-386, consumed at
station_command_handler.dart:232-286) and the D-5 sibling view (session_scope.dart:1793).
Retiring the calls zeroes `spentReworkRounds` and makes the cap unbounded — B-B2's failure
through a different door — and blinds `route` steps; retiring only the `state` key leaves
the write in place, and with it the per-step churn the cut exists to kill. §0.6 must say
which, and neither answer is currently consistent.

**[fold-fidelity B3]** DROPPED APPEND — `appendAcked` has a third outcome the design does
not model, and R10 has no breaker to route into. `trajectory_harness.dart:641-645`
SUPPRESSES (`_suppressed += 1; return`) in `degraded`/`fencedOut`/`halted`: the record is
neither enqueued nor dropped, so an awaited ack never completes and the engine path hangs.
§0.5 enumerates only queueBound overflow (:652-658), reconnect-drop (:699-709), and
`AppendInternalError`; §0.4's harness-not-LIVE rule is a BOOT check, and
`fencedOut`/`degraded` are mid-run states. Separately, `_persistFailure` is private to
`CapabilityHost` (capability_host.dart:772-777); R10's site is `SessionScope._rearm`
(session_scope.dart:1482-1506), whose only failure path is `_rearming.remove(nodePath)` +
`_flareRearmFailed` — a retryable flare, i.e. the unbounded-retry shape tg-0zq8 closed, now
sitting on the write that under `cut` IS the state transition. §0.5's "a failed ack routes
into the EXISTING `_persistFailure` breaker … No new loop" is not implementable at that site.

**[fold-fidelity B5]** DROPPED APPEND — `attempt.terminal` becomes decision-bearing under
`cut` while §0.5 classifies it fire-and-forget. §0.5 keeps "shadow records of KEPT writes"
on drop-and-count, and the terminal record at session_scope.dart:1147 / :1610 is exactly
that. But C5's tick reap fires only "for each P6 row `worktree_state='live'` whose P1
session is terminal", and C6's barrier refuses only on a P6-live row *under a P1-terminal
session*. A dropped terminal append therefore strands the worktree AND disarms the barrier
meant to catch it — the precise class §0.1 sells the cut on ("plus the stranded-worktree
class via the barrier + tick reap"). Unlike the `worktree.reaped` receipt, nothing re-probes
and re-appends a lost terminal. Either that record is acked, or the reap/barrier need a
bd-side terminal input.

**[completeness B1]** ADJUDICATION-LOG CONTRADICTION (B-M2, marked A-F) — §0.6's R8 row and
its R11 KEPT row retire and keep THE SAME WRITE. R8 retires "the four `grid.step.state`
persists" naming `capability_host.dart:789-798`; that call is `await
_ctx!.writer.update(_stepBeadId, metadata: _moleculeMetadata(StepState.failed, restartCount:
next, cooldownUntil: cooldown, ...))` — one `writer.update` whose metadata map is built by
`_moleculeMetadata` (capability_host.dart:645, signature takes `restartCount`/
`cooldownUntil`). The KEPT table then lists "`restartCount`/cooldown persist | R11:
`capability_host.dart` `_persistFailure` | its durable count must not move onto a lossy path
(B-M2)", and C4 restates "`restartCount`/`cooldownUntil` ... stay from the KEPT bead writes
until Stage 2". There is no such surviving write: retiring :789-798 IS retiring the
restartCount/cooldown persist. As written, r2 does exactly what its own log says B-M2
forbids — puts the tg-0zq8 circuit breaker's durable count on the append path
(capability_host.dart:524-539 records why that is the 17 GB / 149,420-commit regression).
Secondary: §0.5 routes a failed ack "into the EXISTING `_persistFailure` breaker" without
addressing the tree's own recursion guard at capability_host.dart:541-544 ("[recoverable] is
false at the call sites whose [persist] IS [_persistFailure]") — under `cut` the failing
append can be _persistFailure's own.

**[completeness B3]** VERDICT-WITHOUT-FIX ON A-M4 / B-M3 — C6's stated `admission.refused`
idem key contradicts both the ratified schema and the shipped record class, and no chunk
changes either. C6: "The idem key is `refused:<work_bead>:<reason>` within the dedupe
window — never the snapshot version (the version-keyed form re-created the exact overflow
hazard the authority already fixed)." In tree, `AdmissionRefused.idemKeyText` is hardcoded
`'refused:$workBeadId:$clause:$snapshotRev'` (admission_records.dart:269-270), `snapshotRev`
is a REQUIRED constructor field (:219-225) and a required payload field (:240), and the
ratified schema pins the same key twice with an explicit rationale — trajectory-schema.md:269
("level-shaped key ... (major fix) — it re-fires exactly when the evaluated basis actually
changed, so a bead refused → restored → refused-again on the same clause re-latches
correctly (new snapshot_rev ⇒ new key)") and :1044. r2's reason-keyed form breaks that
re-latch: a refuse→restore→refuse-again on the same reason dedupes to the earlier row, so
P3's clause level (derived from the latest refusal/restore pair per (bead, clause)) reads a
stale "restored". r2 conflated the ADMISSION snapshot_rev with its own trajectory mirror
version. This is a change to a ratified clause presented as a finding fix, with no amendment
text and no FINAL question — unlike the G1a/G1b narrowing, which r2 correctly routes through
FINAL Q1.

**[completeness B4]** NO DEFINED BEHAVIOR FOR `compromised` HEALTH UNDER `cut` — the masking
hole B-B6/B-B7 flagged survives on the step axis. §0.2: "Health: `live` iff mode LIVE and
zero acked-append failures since boot; drop/failure latches `compromised`". §0.3: "On health
`compromised`/`refused` ⇒ legacy-primary for the boot, loudly." C4's rollback: "`dualRead`
demotion; step axis observes." Post-C7 the step axis has no legacy carrier — R8/R9/R10
retired the `grid.step.state` writes, and §0.4 says so itself ("cut-era sessions have no
legacy STEP trail"). So a mid-run `compromised` latch under `cut` demotes step-state
decisions onto beads that are frozen or absent, producing a plausible answer instead of an
error — the precise "stale fold is an error, not a quiet lie" rule r2 ratified as constraint
6 (trajectory-schema.md:1112-1114), which r2 implements ONLY at the boot seed (§0.2) and
only for `refused`. r2 needs a stated cut-posture rule for `compromised`
(halt/refuse/breaker), not a demotion.

**Plus the wave-2 halves of two blockers r3 fixed for wave 1:**

- **[ordering-rollback B5 / completeness B2, adoption half]** `sessionDispositionOf` and
  `staleFences` are cursor consumers whose carrier (`grid.step.state` →
  `molecule_codec.dart:196-226` projection, with the `isClosed ? complete : pending`
  fallback) retires with R8. Before ANY retirement they must adopt a fold-backed read (or a
  fold-backed disposition/fence design), including the per-node pgid/pid/token fence inputs
  (P6/P2 homing) and the empty-cursor voiding rule's post-retirement meaning
  [ordering-rollback m6].
- **[fold-fidelity B1, schema half]** retired-rework P1 rows stay `status='open'` forever
  (`roundRetired` bumps round only, schema:215). Wave 1's winner rule makes this legible;
  wave 2 must decide whether the fold-side shape (open-retired rows accreting per rework)
  is acceptable long-term or whether a head-closing retirement record/amendment is wanted —
  a ratified-schema question, and F-m5's P6-eviction bound ("open in P1" is not a shrinking
  set) rides on it.

## Carried wave-2 majors (summary — full text in the r2 verdicts, adjudicated in the log)

| Finding | One-line substance |
|---|---|
| O-M1 / F-B3 (overlap) | `_persistFailure` is private to CapabilityHost; R10's site is SessionScope — the ack-failure routing has no seam |
| O-M2 | a trajectory blip under cut = station-wide breaker storm; budget/quiesce undesigned |
| O-M3 | abort has no admission freeze/draining posture; the documented rollback may not converge |
| O-M4 | C9 (irreversible) gated on one round of C8; needs its own gate or operator ratification |
| O-M6 / C-M5 | pre-mount `admission.refused` has no seat, no `mountAttemptId`, no `snapshotRev` source |
| O-M7 | break-glass override site list inconsistent (one site vs two bypass targets) |
| F-M4 | acked appends invert stage1-wiring §2.5's never-await + non-fatal invariants, undisclosed, on the hottest path with no latency budget |
| F-M5 | routing a `step.transition(complete)` ack failure into `_persistFailure` re-drives completed work (the `land` step example) |
| F-M6 | the KEPT-writes coexistence is an EXCEPTION to §9's "cuts whole" rule, not a narrowing — must be put to the operator as such |
| C-M1 | the engine's recorder surface is all `void`; no stated mechanism carries an ack Future to engine sites |
| C-M2 | the cut-posture boot refusal can't ride a `trajectory.start()` rethrow — the harness never throws; needs a post-start mode check |
| C-M3 | R2/R7 KEPT row contradicts schema §7's Stage-3 merge drop: held-derivation dies one stage before the sweep reads P1 |
| C-m4 | C7's first-boot sequence doesn't match `StationWorkRuntime.start()` order; the quiesce check is never placed |
| F-m3 | `admission.refused` staging is contradicted at three schema sites; C6 fixes one |
| C-m2 | stage1-wiring §2.3 homes `attempt.terminal(settled)` derivation in a file with no recorder call — standing doc/derivation gap |

## The r2 sketches (UNCORRECTED — carry the defects above)

### W2-A (old C5) — Cut posture + quiesce + break-glass + acked appends
**r3 homing note: the P6 mirror + tick worktree-reap obligation live HERE (single home,
resolving O-B4); everything else as r2 wrote it:** `G1Discipline {shadow, cut}` resolved at
assembly (`TrajectoryConfig.g1` → env `GRID_G1` → default), banner + status lines; R8/R9/R10
sites branch to acked appends under `cut` (`await harness.appendAcked(record)` — same queue,
ack at commit, failure routes to `_persistFailure` [defective per F-B3/O-M1/C-M1/F-M5]);
R-reap block in `_completeAndClose` branches out under `cut`; `createSession` stamps
`grid.session.g1`; quiesce boot check in `StationWorkRuntime.start()` (typed
`G1QuiesceRefused` throw, both directions) [placement defective per C-m4/C-M2]; break-glass
`GRID_G1_BREAK_GLASS=<reason>` boots shadow-discipline with loud provenance (banner, flare,
per-card merge, `attempt.note(channel='break-glass')`) [site list defective per O-M7]; tick
worktree-reap: for each P6 `worktree_state='live'` row whose P1 session is terminal, reap
through the `ReapWorktree` seam, `worktree.reaped`/`worktree.held` appends, keyed on disk
state [dependent on `attempt.terminal` durability — F-B5]; cut posture forces
`TrajectoryConfig.mode: required` + harness-not-LIVE refuses the boot; docs ride the PR
(§9 amendment, `required` contract, break-glass ladder, KEPT-writes table [self-contradictory
per F-B2/C-B1/C-M3]).

### W2-B (old C6) — The worktree-outstanding barrier (P6 consumer)
Synchronous mount-eligibility clause over the ambient P6+P1 snapshots at
`composeMountEligibility` (`work_list.dart:292-294`, decision `:337`): refuse when the
candidate bead has any P6 `worktree_state='live'` row under a P1-terminal session,
`clause='worktree-outstanding'`. Staleness via tick-stamped `heartbeatAt` (fail closed only
when the harness itself is wedged; idle-healthy admits). `admission.refused` through the
recorder seam + 30 s per-bead dedupe [idem key defective per C-B3/F-M3; seat/attemptId/
snapshotRev unsourced per O-M6/C-M5]. Armed only under `cut`. Doc fixes for the three
staging sites [one of three listed — F-m3].

### W2-C (old C7) — THE FLIP (default posture → `cut`)
One small PR: `TrajectoryConfig.g1` default `shadow` → `cut` [no dualRead interlock —
O-B1]. Pre-flip evidence pack: C3 ∧ C4 ∧ W2-A ∧ W2-B gates jointly (soak evidence,
shadow-diff reports, rehearsal + break-glass drill transcripts, `traj show` lifecycle
sample, quiesce drained). First-boot sequence [order defective per C-m4]. Soak gate: 3 clean
rounds under cut + one deliberate bounce + one restore drill [restore drill defective per
O-B3] with zero stranded worktrees, zero unplanted breaker trips, gates closing at terminal
as today. Rollback: flip back; quiesce refuses shadow boot while cut-era sessions open;
drain observable in bd because terminal facts are KEPT [no admission freeze — O-M3].

### W2-D (old C9) — The stated deletions
Only after W2-C soaks [gate defective per O-M4]. Deletion set = R8/R9/R10/R-reap posture
branches + `G1Discipline`/`GRID_G1` + shadow-parity parameterization; `GRID_G1_BREAK_GLASS`
stays (permanent archaeology guard; quiesce simplifies to one direction). Step-axis
divergence compare deletes; session-axis compare STAYS (bd session facts still
legacy-written; the standing compare is the G1b cut's future evidence stream). Teardown
replay, `sessionsAwaitingTeardown`, and every terminal-write site are NOT deleted (moved
out). Grep pin: the posture flag cannot half-survive.

### W2-E (was wave-1 C8b) — GRID_INSTANCE_TOKEN retirement (moved here in r4 — J7-B3)
attempt_id — Stage 1's already-shipped in-tree dual export (`capability_host.dart:403`
`GRID_INSTANCE_TOKEN`, `:410` `GRID_ATTEMPT_ID`; NOT gated on W2-A, despite what r3's
"dual-exported since W2" wording suggested — J7-m1) — becomes the freshness fence.
Sites: `capability_host.dart:403` export + `:409` comment; `allocation.dart:690`;
`station_process_transport.dart:64`; `incarnation_env.dart` (mint + env key deleted).
Token fields on `cursor.dart`/`session_projection.dart`/`session_bead.dart` retire with
their freezed regens — a bd-write vocabulary change, which is WHY it lives in this
appendix — with the adopt-fence and `_staleFencesAreDead` suites proving adoption/refusal
and the void-re-mint fence check on attempt_id equality FIRST. Source pin:
`GRID_INSTANCE_TOKEN` absent from `packages/*/lib`.

## MOVED OUT OF THE CUT ENTIRELY — named stages + blocking reasons (r2, ratified frame)

| Item (r1 chunk) | Destination | Blocking reason |
|---|---|---|
| R1 terminal stamp+close, R4 settle, R6 close-half | **Stage 4 (G1b)** | gate-sweep eligibility reads closed-card + held state (`station_bead_writer.dart:372-390`); the sweep must read P1 before its inputs retire — A-B1 |
| R2 escalation stamps, R7 decline merge | **Stage 4 (G1b)** [vs schema §7's Stage-3 merge drop — UNRESOLVED, C-M3] | `sessionHeld`/`humanHeld` safety inversion otherwise — A-B2 |
| R3 `#void-` re-key, R5 `#rN` re-key | **Stage 4 (G1b)** | rework's single-session invariant + round cap + remint fork parse the mutable key; fold-aware rework needs P5 — A-B3, B-B1, B-B2; constraint 7 |
| R11 restartCount recovery-read + persist retirement | **Stage 2** [entangled with R8's site list — UNRESOLVED, F-B2/C-B1] | the tg-0zq8 circuit breaker — B-M2 |
| M6c head re-stamp tick obligation | **Stage 4 (G1b)** | would fight the KEPT live legacy writer; A-M8 self-comparison vector |
| Teardown-replay + `sessionsAwaitingTeardown` deletion | **Stage-2 ∧ Stage-4 join** | arm (a) keys on outcome stamps, arm (b) on open molecules — A-B4, B-M1; falsifier clause-2 checkpoint re-homes there (FINAL Q4) |
| `#rN` synthesis view (r1 FINAL Q8) | moot until G1b | re-keys are KEPT |
| `_reconcileWorktree` boot-reap deletion (r1 FINAL Q5) | W2-D-review call | boot-time belt over tick suspenders |

---

## ADJUDICATION LOG

Verdicts: **A-F** = accepted, fixed in the named revision · **A-R** = accepted, resolved by
re-scope · **A-W2** = accepted, deferred whole to the wave-2 appendix as an entry criterion
(NOT fixed — r3 fixes no wave-2 finding) · **RS** = re-scoped (finding true in part; design
changed around the verified core) · **N** = noted, no change needed. Every acceptance was
verified against source in its revision session, not taken on the judges' word.

### r1 findings (adjudicated in r2; r3 corrections appended where the r2 disposition was itself found defective)

**Judge 1 (ordering-and-rollback, r1):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| A-B1 | Terminal gate sweep dies at the flip | **A-R** — verified `station_bead_writer.dart:375-390`, `session_scope.dart:192-210` | R1/R4/R6 KEPT; regression test rides W2-A (wave 2) |
| A-B2 | Held sessions silently lose their hold | **A-R** — verified `:372-374` | R2/R7 KEPT; **r3 note: the Stage-3-vs-Stage-4 contradiction in this row's KEPT table is open (C-M3), wave-2 entry criterion** |
| A-B3 | `grid rework` breaks permanently, survives rollback | **A-R** — verified `station_command_handler.dart:204-221`, `session_scope.dart:664-670` | R3/R5 KEPT; fold-aware rework is G1b design work |
| A-B4 | C9 deletion gate vacuous; teardown arm unreplaced | **A-R** — verified `restart_reconciler.dart:600-604`, `:738-758` | teardown replay NOT deleted; checkpoint re-homed (FINAL Q4) |
| A-B5 | Post-cut append loss unrepairable/unswept | **A-F/A-R** | session facts keep bd carriage; **r3 note: the step-fact half (acked appends) is wave-2 and carries open blockers F-B3/F-B5** |
| A-B6 | Compound-failure boot deadlock | **A-F** (r2) → **A-W2** (r3) | break-glass moved whole to the appendix; O-M7/O-B3 open against it |
| A-M1 | `byWorkBead` collapses 1:N with no tie-break | **A-F** — verified PK/ix `trajectory_schema.dart:130-144` | §0.2 winner rule; **r3: superseded by the r3 partitioned form (F-B1) — retired-open rows never compete** |
| A-M2 | No soak gate observable | **RS** — the `/status` block exists on space_station `grid/stage1-runner` | durable in-log round notes (§0.4) + WS-branch precondition (FINAL Q2); **r3: the note vehicle itself was defective (C-M4), fixed in §0.4** |
| A-M3 | Evidence durability decided after the gate needing it | **A-F** | decided in-design; lands in C2; **r3: vehicle corrected per C-M4** |
| A-M4 | `admission.refused` idem key reintroduces the overflow hazard | ~~A-F~~ → **r3 correction: the r2 "fix" contradicted the ratified level-shaped key (`admission_records.dart:269-270`, schema:269/:1044) — verdict-without-fix (C-B3, F-M3). REOPENED as a wave-2 entry criterion; any change to the ratified clause needs its own FINAL question** | |
| A-M5 | Staleness clause wedges an idle station | **A-F** (r2, heartbeat rule) — wave-2 chunk, carried in W2-B | |
| A-M6 | R-set branch recipe vs recorder placement | **A-R/A-F** — terminal sites KEPT | wave-2; §0.5's inversion disclosure was itself incomplete (F-M4) — entry criterion |
| A-M7 | R4 description doesn't match `settleSessionForTerminalWork` | **A-R** | method KEPT whole; **r3 correction (C-m2): the finding's second half — stage1-wiring §2.3 homes `attempt.terminal(settled)` derivation in a file with no recorder call — is a real standing doc/derivation gap, logged, not moot** |
| A-M8 | Oracle fence guards the wrong mechanism | **A-R** | M6c moved out; bd stays an independent session-fact oracle |
| A-m1 | work_list cite drift | **A-F** — verified | corrected cites carried in W2-B |
| A-m2 | Exported legacy reader escapes the fence | **A-F** — verified `grid_trajectory.dart:67` | fence grep extended (wave-1 CI section) |
| A-m3 | "exit-64, lock released" wrong mechanics | **A-F** — verified `work_assembly.dart:188-232` | typed-throw contract (wave-2 sketch); **r3 note: C-M2 shows the rethrow form is ALSO wrong — entry criterion** |
| A-m4 | Soaks never exercise the decision shapes | **A-F** | shape-coverage on the C2/C3/C4 gates |
| A-m5 | Chunk arrows readable as single-gate flip admission | **A-F** | joint-gate statement (now the wave-2 gate) |
| A-m6 | Replay rehearsed on live data for P1 only | **A-F** | C0 covers all three tables |

**Judge 2 (fold-fidelity, r1):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| B-B1 | Rework handshake keyed on the mutable key | **A-R/A-F** — verified `work_list.dart:203-217`, `session_scope.dart:1528-1547` | re-keys KEPT; **r3: the winner-rule/rework interaction r2 built on top was itself broken (F-B1/O-B6) — fixed in §0.2/§0.3's r3 form** |
| B-B2 | Round cap parses `#rN` + `grid.result.*`; post-R5 unbounded | **A-R** — verified | R5 KEPT; **r3 note: F-B2 shows `grid.result.*` STEP keys also ride the R8 sites — wave-2 entry criterion** |
| B-B3 | 1:1 mirror over 1:N projection | **A-F** | superseded by the r3 partitioned winner rule |
| B-B4 | `humanHeld` ≠ P1.held; escalations flare | **A-F** — verified `session_head_delta.dart:136-154` | derived-disposition comparator; C2/C3 tests pin zero-divergence on escalation |
| B-B5 | `grid.result.*` rulings absent from P1 | **A-F** — verified | overlay form; results ride the legacy base; **r3: see C-B2 correction below** |
| B-B6 | No stale-fold refusal | **A-F** | constraint 6; **r3: restated honestly (F-M2/O-m4) — seed-lag is structurally zero outside replay; the live-swap case is covered by the reseed rule (§0.2)** |
| B-B7 | Enqueue-time mirror makes a dropped append durable | **A-F** | post-ACK apply (§0.2); C1 regression test |
| B-M1 | Falsifier checkpoint reads half the union | **A-R** | re-homed with the deletion (FINAL Q4) |
| B-M2 | R11 moves the breaker onto a lossy path | ~~A-F~~ → **r3 correction (C-B1/F-B2): the r2 disposition was self-contradictory — R8's `:789-798` site IS the restartCount/cooldown persist (one `writer.update` via `_moleculeMetadata`); "R11 KEPT" and "R8 retired" name the same write. REOPENED as a wave-2 entry criterion. Wave 1 is unaffected (nothing retires; C4 keeps the breaker read on beads)** | |
| B-M3 | FINAL Q2 named the wrong CHECK; `ck_seat` bites | ~~A-F~~ → **r3 correction: `ck_seat` half stands, but the idem-key half of the r2 disposition is REOPENED with A-M4 (C-B3); seat/attemptId/snapshotRev sourcing also open (O-M6/C-M5)** | |
| B-M4 | Barrier staleness wedges the station | **A-F** (heartbeat) — carried in W2-B | |
| B-M5 | Miss classifier has no null-`started_at` rule | **A-F** — verified `session_projection.dart:105-114` | §0.3 classifier |
| B-M6 | Comparator narrower than the flipped fact set; token lost | ~~A-F~~ → **r3 correction (C-B2/O-B5): the r2 "fix" mislabeled the cursor's carriers as "KEPT or later-staged" while retiring them in the same document, and diagnosed the fence hazard on the wrong field (token, not cursor STATE). Dissolved for wave 1 (nothing retires — §0.3's rule is now literally true); the adoption half is a wave-2 entry criterion** | |
| B-M7 | `settled`/`unknown` have no stated disposition | **A-F** — verified enum + `session_disposition.dart:80-116` | §0.3 table (FINAL Q3) |
| B-m1 | `_attachMoleculeCursors` fabricated cite | **A-F** | C4 rewritten around the real mechanism; **r3: consumer cites corrected again per O-m2** |
| B-m2 | mysql_client into the engine | **A-F** — verified pubspec | engine-side interface form |
| B-m3 | Memory bounds optimistic; P6 unbounded | **A-F** | 1 KB/row; P2 eviction; **r3: P6 mirror left wave 1 entirely; F-m5's bound concern rides the wave-2 schema question** |
| B-m4 | C8a flare-site list stale | **A-F** | re-derived at build (C0) |
| B-m5 | C0 replay spec omits the lag bound | **A-F** | lag rule + `--check` |
| B-m6 | C9 "changes no behavior" false | **A-F** | restated honestly (W2-D sketch) |
| B-m7 | Verified-correct cites | **N** | retained |

### r2 findings (adjudicated in r3)

**Judge 3 (ordering-and-rollback, r2):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| O-B1 | No `g1`×`dualRead` interlock; post-flip rollback lands corrupt | **A-W2** | no posture lever exists in wave 1; quoted verbatim as an entry criterion |
| O-B2 | `compromised` latch (one global drop counter) demotes to a dead carrier under cut | **RS** | wave-1 half **A-F**: §0.2 states the wave-1 rule — non-`live` health disengages the overlay onto a fully-written legacy, loudly; no trap exists. Cut half + drop-accounting split **A-W2** (verbatim entry criterion) |
| O-B3 | restore+replay silently regresses; stale-fold guard blind (verified: fold+cursor same txn) | **RS** | under wave 1 a restore loses only derived read-state against a complete bd — divergence/fallback, loud, no silent re-drive. Cut half **A-W2** (verbatim entry criterion). The same verified substrate drives the r3 honest restatement of constraint 6 |
| O-B4 | P6 assigned to two chunks; C5's gate unachievable | **A-F** | decided: wave 1 builds NO P6 mirror (C4 needs P2 only — stated in C4); P6's single home is W2-A (tick reap), W2-B consumes it |
| O-B5 | `staleFences` + `sessionDispositionOf` are unadopted cursor consumers | **RS** | wave-1 half **A-F**: named in C4 (consumers 4–5). Adoption half **A-W2** (verbatim entry criterion). **r4 correction (J6-B2/J6-M2): r3's "exhaustive at five" claim was FALSE (two decision-bearing consumers unnamed — `session_scope.dart:1733`/`:1841`, `station_driver.dart:139`; added as consumers 6–7) and the stated stay-legacy reason was factually wrong (the read is the never-populated `SessionProjection.cursor`, not `molecule_codec` output); both corrected in C4** |
| O-B6 | Rework's re-key→mint window undefined; gates unevaluable | **A-F** | §0.2 "the overlay never CREATES" + §0.3 `retirementLag` class + the partitioned winner rule; C3's rework-window property test; gate arithmetic counts divergence only, lag must zero by round end |
| O-M1 | `_persistFailure` private; R10 has no path | **A-W2** | carried majors table |
| O-M2 | Trajectory blip under cut = breaker storm | **A-W2** | carried majors table |
| O-M3 | No admission freeze; abort may not converge | **A-W2** | carried majors table |
| O-M4 | C9 irreversible on a one-round gate | **A-W2** | carried majors table |
| O-M5 | C8a scheduled after every gate that needs it | **A-F** — verified `work_assembly.dart:521-526` vs `:588` | C8a moved into C0; ~~C8b stays the wave-1 tail~~ **r4: C8b left wave 1 entirely (J7-B3 — it changes bd writes); now appendix W2-E** |
| O-M6 | No seat for a pre-mount refusal | **A-W2** | carried majors table (with C-M5) |
| O-M7 | Break-glass site list inconsistent | **A-W2** | carried majors table |
| O-m1 | r1-blocker audit: fixes real, new windows opened | **N** | the new windows are exactly r3's fix list |
| O-m2 | C4 cite drift (frontier path/line; wedge line) | **A-F** — verified `circuit/unclaimed_frontier.dart:87`, `domain/wedge.dart:195-198` | corrected in C4 |
| O-m3 | Incumbent non-determinism vs "fold presumed wrong" | **A-F** | `incumbentAdjudication` class (§0.3); the incumbent rule scoped to deterministic incumbents |
| O-m4 | Stale-fold check near-dead as specified | **A-F** | constraint 6 restated honestly; live-swap covered by the reseed rule, not the lag rule |
| O-m5 | `proj_meta` is ONE shared `'fold'` cursor row | **A-F** — verified `trajectory_appender.dart:470-474`; **r4 correction (J7-B2): the all-or-nothing CONCLUSION was false — the three in-tree replay functions keep per-projection `proj_meta` rows (`'fold'`/`'step_cursor'`/`'process_identity'`), so a partial rebuild IS expressible** | C0 rewritten in r4 to the tree's actual per-projection shape |
| O-m6 | Mapping table lacks the empty-cursor row | **A-F** (wave-1 half) | the `{failed,cancelled}` row now states the cursor carrier keeps its writer in wave 1; post-retirement meaning is folded into the O-B5/C-B2 entry criterion |

**Judge 4 (fold-fidelity, r2):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| F-B1 | Retired-rework sessions never close in P1; rule (2) fires on every rework; gates unsatisfiable | **A-F** — verified `session_scope.dart:213-239` (bd close + `roundRetired` only), `session_head_delta.dart:145-149` (round only), recorder `newRound = old+1 ≥ 1`, DDL `round DEFAULT 0` with `rowAt` never setting it | the r3 winner rule: retirement is LEGIBLE (open row with `round>0` = retired head, excluded from the decision partition); breach now fires only on genuine double-mounts; the `#rN`-suffix == P1.round parity check falls out for free; C1's rework-storm suite pins it. The schema-shape half (open-retired rows accrete) is flagged as a wave-2 entry criterion |
| F-B2 | R8 and R11 are the same statement; `grid.result.*` step keys ride R8's sites | **A-W2** | quoted verbatim as an entry criterion; log rows B-M2 (and B-B2's note) corrected above. Wave 1 unaffected: nothing retires, and C4 keeps breaker + result reads on beads |
| F-B3 | `appendAcked`'s suppressed third outcome; R10's flare-and-retry loop | **A-W2** | quoted verbatim as an entry criterion |
| F-B4 | Overlay demotes a legacy terminal back to live in the close→append window | **A-F** — verified close-then-record order (`:1140`/`:1147`, `:1607`/`:1610`) | §0.3 monotone-terminality guard: legacy-terminal + P1-open ⇒ pure legacy served, `terminalLag` counted, 60 s escalation names the dropped append; C3 property test forbids any demoting overlay. **r4 note (J7-B4): the r3 enumeration was incomplete — the reconciler's teardown-replay close (`restart_reconciler.dart:707`) appends nothing; C2 adds its observer append** |
| F-B5 | `attempt.terminal` decision-bearing under cut while fire-and-forget | **A-W2** | quoted verbatim as an entry criterion (wave 1's `terminalLag` escalation is the detector precursor, not the fix) |
| F-M1 | Overlay names fields `SessionProjection` lacks; P1.round is always 0 on a live head | **A-F** — verified no `round`/heldReason field | override set corrected to the seven real fields; `round` out of tuple and override; round parity moved to the `bySessionId` retired-row check. **(r5 note — J8-m2: "seven" is stale; the set narrowed to five in r4 and to FOUR in r5 — §0.3 is the authority)** |
| F-M2 | Stale-fold check dead where implemented; live `--swap` gets no mirror invalidation | **A-F** | constraint 6 restated; fold-generation reseed rule (§0.2) + C1 reseed test; `traj replay --check` reports generation |
| F-M3 | C6 silently overrides the ratified idem key | **A-W2** | with C-B3 (verbatim entry criterion); log row A-M4 corrected |
| F-M4 | §0.5 inverts §2.5's invariants; latency basis withdrawn | **A-W2** | carried majors table |
| F-M5 | Ack-failure routing re-drives completed work | **A-W2** | carried majors table |
| F-M6 | "Alignment with §9" overstates; it is an exception request | **RS** | wave 1 requests NO §9 exception (read-side only; the shadow-compare window extends, flagged in FINAL Q1); the exception request is named as such in the wave-2 gate |
| F-m1 | Constraint-7 cite wrong; "re-key bends" inverted | **A-F** | authority re-cited to `session_head_delta.dart:108-111`; phrasing corrected |
| F-m2 | `:515-540` is `_firePersist`'s doc comment, not the mechanism (`:772-798`) | **A-F** | corrected where wave-1 text cites it; appendix left as r2 wrote it (uncorrected by policy), noted here |
| F-m3 | Three schema sites contradict on admission staging | **A-W2** | carried majors table |
| F-m4 | Mapping table's held row wrong (open+held ⇒ live, not held) | **A-F** — verified disposition reads terminality first (`session_disposition.dart:82-91`) | table row corrected; C3 test covers declined-open vs declined-then-terminal |
| F-m5 | P6 eviction bound inherits F-B1 ("open in P1" not shrinking) | **RS** | P6 out of wave 1; the bound question rides the F-B1 schema-shape entry criterion |

**Judge 5 (completeness):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| C-B1 | R8/R11 retire and keep the same write; log marked it A-F | **A-F** (log) + **A-W2** (design) | log rows B-M2/B-B2 corrected above with the verified substrate (`:789-798` = `_persistFailureClassed`'s single `writer.update` via `_moleculeMetadata`); the design resolution is a verbatim entry criterion. The recursion-guard secondary (`:541-544`) is carried with F-B3 |
| C-B2 | §0.3's rule contradicts its own list (cursor carriers retired at the same cut) | **A-F** (wave 1) + **A-W2** (adoption) | the two-wave split makes §0.3's list literally true (nothing retires); the rule's teeth restated as wave-2 entry discipline; consumers 4–5 named in C4; log row B-M6 corrected |
| C-B3 | A-M4/B-M3 verdict-without-fix on the ratified idem key | **A-F** (log) + **A-W2** (design) | log rows corrected/reopened; verbatim entry criterion; any change to the ratified clause requires its own FINAL question in the wave-2 round |
| C-B4 | No defined `compromised` behavior under cut | **A-F** (wave-1 rule stated in §0.2) + **A-W2** (cut rule) | verbatim entry criterion |
| C-M1 | No ack seam in the engine (`void` recorder surface) | **A-W2** | carried majors table |
| C-M2 | Cut-posture refusal can't ride a rethrow (harness never throws) | **A-W2** | carried majors table |
| C-M3 | R2/R7 KEPT row vs schema §7 Stage-3 slim: held dies a stage early | **A-W2** | carried majors table; flagged on the MOVED-OUT row and on A-B2's log row |
| C-M4 | `AttemptNote` requires `sessionId`; down-fixpoint note has none; channel extension unflagged | **A-F** — verified `attempt_records.dart:701/:711/:736` | §0.4: terminal notes carry their session; boot-final note rides the last terminal session; idle boots append none; the stage1-wiring:324 channel amendment rides C2's PR |
| C-M5 | `mountAttemptId`/`snapshotRev` unsourced for the barrier refusal | **A-W2** | carried majors table (with O-M6) |
| C-m1 | All 41 r1 findings present, one-to-one; failures were disposition, not enumeration | **N** | retained |
| C-m2 | A-M7 half-summarized; settled-derivation doc gap real | **A-F** (log) | A-M7 row corrected; the gap is logged as a standing doc issue for the wave-2 round |
| C-m3 | R8's P2 field list understates the fold | **A-F** (wave-1 mirror spec) | C4 states P2's full column set; the retirement implications ride F-B2's entry criterion |
| C-m4 | C7 first-boot sequence doesn't match `start()`; quiesce never placed | **A-W2** | carried majors table |
| C-m5 | Cite audit — all load-bearing r2 cites verified on main @ efe9795 | **N** | retained; the barrier-record pull-forward confirmation (schema:1869-1875) is kept for the wave-2 round |

### r3 findings (adjudicated in r4)

Two judges (workflow `wf_0db89c04-e1c`), both needs-revision. Every A-F below was
re-verified against source in the r4 session before the fix landed. **OPEN** = accepted
in substance or unrefuted, deliberately NOT fixed in r4 (the seven-fix mandate); carried
to the next round — nothing below is disposed silently.

**Judge 6 (r3):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| J6-B1 | C3's pgid/pid override disarms the void-remint kill fence (scalar fallback + `_staleFencesAreDead` vacuous-true + P1 SET NULL on process-exit) | **A-F** — verified `session_disposition.dart:137-146`, `session_scope.dart:883-889` (gating `_refuseVoidMint`), `session_head_delta.dart:164-174` | pgid/pid dropped from the override set (§0.3); fence identity triple whole on the legacy carrier; comparator keeps the presence pair, compare-only |
| J6-B2 | "five consumers, exhaustive" is false — `session_scope.dart:1733`/`:1841` (the mount cursor) and `station_driver.dart:139` (cooldown scan) unnamed | **A-F** — verified both sites + `projectSession` never fills `cursor` (`session_bead.dart:426-436`) | consumers 6–7 added to C4 with `effectiveCursor` adoption; O-B5 log row corrected; the behavior-change half rides J6-M1 (OPEN) |
| J6-B3 | Suppressed appends bypass the health latch (`_suppressed` is a different counter from `_dropped`); frozen mirror serves as primary with health `live` | **A-F** — verified `trajectory_harness.dart:641-651` | §0.2: `compromised` latches on drops OR failures OR suppressions since boot; the timer tick latches on harness mode ≠ `live` |
| J6-B4 | Post-ACK mirror unimplementable — the envelope is built and discarded inside the appender; the tie-break's `started_at` would be reconstructed | **A-F** — verified `append_outcome.dart:18-28`, `trajectory_appender.dart:320/:332`, `session_head_delta.dart:97-129` | `Appended` carries the committed `TrajectoryEnvelope` (C1; in-process contract change, no schema/wire change); winner tie-break restated on `last_seq` + envelope-carried `started_at` (§0.2) |
| J6-M1 | Frontier/cooldown adoption is a behavior change (the field is empty today); "config off = today" false at those sites; parity suites can't catch it | **OPEN** — flagged in C4 item 7 + the rollback story; `effectiveCursor`'s non-primary branch must be pinned in the C4 PR |
| J6-M2 | The stated deferral reason for consumers 4–5 is factually wrong (they read the never-populated cursor, not `molecule_codec` output; the empty-cursor void arm is today's live behavior) | **A-F** — verified `session_disposition.dart:99-115`, `session_bead.dart:426-436` | C4 items 4–5 rewritten to the verified reality; deferral stands on the corrected ground |
| J6-M3 | Empty-string `work_bead_id` sentinel rows (synthetic/probe sessions) accrete under key `''` and poison the byWorkBead partition / gate arithmetic | **OPEN** — likely fix is excluding `work_bead_id = ''` from `byWorkBead` (legacy skips them, `restart_reconciler.dart:1123`); next round |
| J6-M4 | The durable-evidence channel rides the same lossy queue whose losses it reports; a suppressing boot reads as a clean gate | **OPEN** — partially mitigated by J6-B3's latch (suppression now poisons health, and health transitions ride `/status`), but the note vehicle's self-reference stands |
| J6-M5 | `retirementLag` window mis-modeled — `roundRetired` fires in the same handler as the re-key (`station_command_handler.dart:338`), not at the successor mint; `session_scope.dart:638` emits nothing | **OPEN** (with J7-M6) — the class needs restating as an enqueue-latency window; round-parity substance verified correct by the judge |
| J6-m1–m4 | Cite drift (recorder package, gc lines, attempt_records off-by-2, `work_list.dart:203-217` is a helper not the fork) | **OPEN** — sweep in the next editorial pass |
| J6-m5 | Monotone guard made the fence carrier nondeterministic (flip inside the lag window) | **A-F by consequence** — dissolved with J6-B1: fences never read the overlay |
| J6-m6 | C2's "explicitly untouched" list is source-level only; under C3 those functions' INPUTS change | **OPEN** — one-line restatement wanted in C3 |
| J6-m7 | Verified-correct cite list | **N** — retained |

**Judge 7 (r3):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| J7-B1 | Same fail-open as J6-B1 (I-10 fence; overlaid nulls; no-null-demotion gap) | **A-F** — same verification | Same fix: pgid/pid out of the override set. The general no-demotion-rule phrasing for the remaining override fields rides J7-m7 (OPEN) |
| J7-B2 | Reseed contract specified against a `proj_meta` shape that doesn't exist; O-m5's all-or-nothing claim false; TRUNCATE/RENAME can't ride the stated transaction | **A-F** — verified DDL `trajectory_schema.dart:122-128` (columns already exist — NO migration needed), appender `:469-475` (never writes `rebuilt_at`), all three replay fns (per-projection rows, DELETE-in-transaction, `rebuilt_at` stamped) | §0.2 guard respecified over the FULL `proj_meta` row set; C0 rewritten to wrap the in-tree replay functions; O-m5 log row corrected |
| J7-B3 | C8b changes bd writes (token = session-bead metadata), contradicting the wave-1 invariant; not trivially revertable | **A-F** — verified `session_bead.dart:45/:491/:461`, `capability_host.dart:409-410` ("retiring the token is a cut change") | C8b moved to the appendix as W2-E; FINAL Q6 answered; the invariant now holds without exception |
| J7-B4 | The reconciler teardown-replay close (`restart_reconciler.dart:707`) emits no trajectory record ⇒ permanent terminalLag ⇒ C2/C3 gates unsatisfiable; F-B4's enumeration incomplete | **A-F** — verified `:707` + `_recorder` grep (only `:861` settles), and the `done`-only entry condition (`:613-616/:631-641`) | C2 adds the observer append at the site (`sessionSettled`, inferred, `teardown-replay` reason — classification: trajectory-side append, zero bd-write change); §0.3 enumeration completed; F-B4 log row annotated. **(r5 — J8-B1/J9-M1: that r4 form was itself defective — minted attempt id, unscoped arm, settled outcome; superseded by the r5 form in C2: open-arm-only, `unknown`+`reconstructed`, recovered id or counted skip)** |
| J7-M1 | Winner rule: which index drives the overlay vs the comparator is understated; partitioned `byWorkBead` has no named wave-1 decision it feeds | ~~OPEN~~ → **A-F in r5 (by J9-B1's fix):** the OVERLAY IDENTITY RULE (§0.3) states it — `bySessionId` feeds the overlay + comparator; `byWorkBead` feeds classification/frontier views only, never a served decision |
| J7-M2 | The BRIDGE shares the reconciler's map-order non-determinism (`station_join_bridge.dart:229-231`); `incumbentAdjudication` scoped too narrowly | **OPEN** |
| J7-M3 | Suppression outside the health model | **A-F** — merged into J6-B3's fix |
| J7-M4 | The boot-final summary note is suppressed by `_isShutdown` before the drain (`trajectory_harness.dart:832/:853`) — the stated vehicle can't land where placed | **OPEN** — emit before `shutdown()` is entered; per-terminal notes carry cumulative counters, so the gate is not blind meanwhile |
| J7-M5 | C4 consumer-1 adoption is a behavior change; rollback claim broken there | **OPEN** (with J6-M1) |
| J7-M6 | `retirementLag` window wrong (roundRetired in the same handler) | **OPEN** (with J6-M5) |
| J7-m1 | C8b "dual-exported since W2" reads as appendix-gated | **A-F** — W2-E states the dual export is Stage 1 in-tree, not W2-A-gated |
| J7-m2 | grid_trajectory is a decision-pinned leaf package; the station lock must be read by PATH | **A-F** — stated in C0 (lock read by path, `traj_provision_command.dart:54-55` pattern) |
| J7-m3 | Cite drift list (off by 1–6 lines, substance correct) | **OPEN** — sweep with J6-m1–m4 |
| J7-m4 | C8a's named flare-site trio understates the null-sunk surface (gate.opened, gate.autoCloseFailed, rework.specPreserved) | **N** — B-m4's re-derive-at-build-time rule already governs; the three names are examples, not the set |
| J7-m5 | C1's file list overstates what is new (SessionHeadRow, applySessionHeadDelta, replay* already ship) | **OPEN** — editorial |
| J7-m6 | noteOrdinal rides a FIFO-capped cache; an evicted last-terminal session's restarted ordinal can dedupe the boot-final summary away | **OPEN** — folds into J7-M4's re-placement |
| J7-m7 | Monotone guard should be a general no-demotion rule over the whole override set | **OPEN** — the pgid/pid instance dissolved with J7-B1; the general statement for the remaining five fields is wanted in C3 **(r5: now four fields — §0.3)** |

### r4 findings (adjudicated in r5)

Two judges (workflow `wf_d32729b1-e11`), both needs-revision. Every A-F below was
re-verified against source in the r5 session before the fix landed; **OPEN** rows are
carried, not disposed.

**Judge 8 (r4):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| J8-B1 | The teardown-replay observer append rides a site shared with the closed-session arm; no attempt id ⇒ the recorder mints one ⇒ fresh `terminal:<attemptId>` idem key ⇒ the record lands unconditionally and can overwrite an `escalated`/`lost` head with `settled` | **RS** — the shared-site consequence chain is false against the tree as-is (`_replayOne` EARLY-RETURNS for closed sessions at `restart_reconciler.dart:664-682`, molecule reap only; the `writer.close` at `:706` is reached by open+`done` candidates ONLY), but the minted-id/idem-key chain is verified exact (`station_trajectory_recorder.dart:692-717` `kReconcilerMintedAttemptBasis`; `attempt_records.dart:529-531`), the candidate set DOES contain `_closedSessionsWithOpenMolecules` (`:599-603/:738-758`), and r4's text never scoped the arm | C2 re-landed (r5 form): append split off the shared site — scoped to the closed-an-open-session arm AS A RULE; `outcome='unknown'`+`unknown_reason='teardown-replay'` (explicit-unknown vocabulary, `ck_unknown` — `trajectory_schema.dart:76-77/:94`); `provenance='reconstructed'`; breadcrumb-recovered attempt id or a counted SKIP — never a minted id; `reconstructedTerminal` adjudication class (§0.3); Q18 amendment flagged on the PR |
| J8-B2 | C4's step axis has neither monotone no-demotion nor a P2-miss rule; bead-first/append-later at every persist site makes the zero-step-divergence gate unsatisfiable; a P2-missing node omitted from `effectiveCursor` reads as unclaimed ⇒ double-run (I-10) | **A-F** — verified awaited `writer.update` THEN fire-and-forget `_recorder.step*` at all three sites (`capability_host.dart:704-727/:731-754/:786-800`) and the join recomputing on the bd write (`station_join_bridge.dart:36-40`) | C4 gains C3's protections verbatim-adapted: monotone no-demotion on cursor state, per-node P2-miss = bead read + `p2Miss` counter (never a default, never omission), named `stepLag` class with `terminalLag`'s arithmetic; gate arithmetic amended (§0.3) |
| J8-B3 | `traj replay --swap` races the live appender (whole-log scan BEFORE the transaction) and silently truncates a projection; neither wave-1 detector can see it | **A-F** — verified scan-outside-transaction in all three replay fns (`session_head_fold.dart:137-146`, `step_cursor_fold.dart:93-99`, `process_identity_fold.dart:100-107`), each doc-pinned "Run with the station DOWN" | C0 rewritten QUIESCE-ONLY: the live-`--swap` language DELETED; the wrapper checks the lock/fence before touching any projection table; constraint 6 + the §0.2 reseed guard restated as defense-in-depth. The judge's conditional reopen of O-B3's wave-1 half dissolves with the deleted path |
| J8-M1 | J6-M3 (empty-`work_bead_id` rows) is gate-blocking now: a `''`-keyed P1 row is a `p1Orphan` with no matching bead ⇒ immediate divergence by the §0.3 rule, by construction | **OPEN** (carried with J6-M3) — J9-m3's verification narrows it: the only in-tree emitter requires a non-null work bead (`station_trajectory_recorder.dart:503-538`), so the `''` key is synthetic/test-only; the full fix (exclude `''` from `byWorkBead` AND the orphan classifier) must be stated in C1/C2 next round |
| J8-M2 | `replaySessionHeads` upserts the SHARED `'fold'` row, regressing the appender's live `applied_seq` | **A-F by consequence** — quiesce-only (J8-B3) removes the live-appender case; a down-store replay sets `applied_seq` to its own complete scan point, which the next boot's seed reads consistently |
| J8-M3 | `StationBeadWriter.close` re-stamps `closed_at` at replay time (pre-existing bd write), so an overlaid `closedAt` disagrees with the bead for exactly the teardown-replay sessions | **A-F by consequence** — under the r5 `reconstructedTerminal` rule the overlay serves PURE LEGACY for exactly those sessions; the disagreement is visible only inside the adjudication class, never served |
| J8-m1 | Cite drift (`:706` vs `:707` et al.), substance correct | **OPEN** — folds into the standing sweep (J6-m1–m4/J7-m3); the `:706` form used where r5 rewrote text |
| J8-m2 | F-M1 log row still reads "seven real fields" | **A-F** — row annotated; the set is FOUR as of r5, §0.3 is the authority |
| J8-m3 | The process-exit SET-NULL is `guardAttemptId`-guarded (`session_head_delta.dart:169-173`), not unguarded; §0.3 overstates | **OPEN** — one-line doc correction, next editorial pass (the fail-open argument is unaffected, per the judge) |
| J8-m4 | `retirementLag`'s 60 s escalation is calibrated against a window that doesn't exist | **OPEN** (with J6-M5/J7-M6) |

**Judge 9 (r4):**

| # | Finding | Verdict | Disposition |
|---|---|---|---|
| J9-B1 | OVERLAY IDENTITY GAP — nothing pins `winner.session_id == legacy.sessionId`; winner-rule (3) can serve a SIBLING session's terminality onto a live session (`done`/`held` blocks live work; `lost` ⇒ voided ⇒ `_refuseVoidMint` vacuous-pass ⇒ re-key + re-mint, and `_projectOwnedSessions`' identical overlay reaps the live worktree) | **A-F** — verified the deliberate keying asymmetry: legacy joins ONE projection per base work bead, last-writer-wins (`station_join_bridge.dart:229-231`), while P1 keeps every round's row under the immutable base key | THE OVERLAY IDENTITY RULE (§0.3): merge ONLY when `P1.session_id ==` the projection's own session id; `byWorkBead` never feeds the overlay (frontier/classification only); C3's overlay input restated `bySessionId`; identity regression in C3's test plan; J7-M1 answered by the rule |
| J9-B2 | `workTerminalReason` in the override set + divergence tuple diverges BY CONSTRUCTION on every escalation (legacy reads only `grid.work_terminal_reason`; escalation stores `grid.escalation_reason`; P1 takes ANY terminal's reason) — a mandated gate shape ⇒ gates unsatisfiable | **A-F** — verified `session_bead.dart:448`, `station_bead_writer.dart:227-229/:455-461`, `restart_reconciler.dart:865-866`, `session_scope.dart:1596-1613`, `session_head_delta.dart:142` | Dropped from the override set (final: `{isTerminal, completed, humanHeld, closedAt}`) and the divergence tuple; compare-only informational column in the round summary (§0.3) |
| J9-M1 | Same shared-site/outcome-overwrite class as J8-B1 (adds the `resolvesRecordId`/`isSettling` mechanism: a non-settling terminal rewrites `status/outcome/closed_at` wholesale) | **A-F** — merged into J8-B1's r5 fix |
| J9-M2 | `--swap` specified safe on an atomicity argument that does not answer the write-write race; the tree's own contract is station-DOWN | **A-F** — merged into J8-B3's quiesce-only fix |
| J9-m1 | Health-latch publication window unspecified (snapshot republish at the latch) | **OPEN** — one-sentence tightening in §0.2, next pass (every direction degrades safely in wave 1, per the judge) |
| J9-m2 | `replayProcessIdentity` → `replayProcessIdentities` (`process_identity_fold.dart:99`) | **A-F** — C0 symbol list corrected |
| J9-m3 | J6-M3 closable: the `''` key is reachable only from synthetic construction | Folded into J8-M1's OPEN row (the narrowing is recorded there) |
| J9-m4 | Verified-clean list (suppression counters, the `Appended` envelope seam, the reseed contract, winner-rule mechanics, pgid/pid removal, C8a asymmetry) | **N** — retained |

---

## FINAL — open questions (only the operator can answer; do not build past them silently)

1. **Ratify the two-wave structure as the standing scope** (this document's frame). Wave 1
   requests no §9 exception — it is read-side + tools against an untouched write path, an
   extended shadow-compare window. The heavy ratifications r2's FINAL carried — the G1a/G1b
   split wording, the KEPT-writes table, the §9 coexistence EXCEPTION (F-M6's honest
   framing), the break-glass contract, the cut-posture `required` contract — all move to the
   wave-2 design round and are NOT ratified by a yes here. Confirm.
2. **The WS branch.** The C2+ soak gates read space_station `grid/stage1-runner`'s `/status`
   trajectory block as the live surface; the in-log round notes are the always-available
   fallback. Who lands the WS branch, and before or in parallel with C2?
3. **`outcome='unknown'` ⇒ held (fail-closed) until settlement heals it** (§0.3). In wave 1
   this shapes only the overlay's served disposition (bd is still fully written); cheap to
   change now, expensive after wave 2. Confirm the fail-closed choice.
4. **Falsifier clause-2 re-homing** (unchanged from r2): teardown replay deletes at the
   Stage-2 ∧ Stage-4 join with the checkpoint covering both arms. Its subject is wave-2
   machinery — confirm it rides the wave-2 round, or renegotiate the §13 clause text now.
5. ~~**Comparator escalation grace**~~ **ANSWERED in r8 (V2-B2): `terminalLag` heals via
   `terminal-reconcile` at the 90 s grace (three tick intervals) and escalates ONLY on
   heal failure / survival past the heal — the normative rule lives in §0.3 MONOTONIC
   TERMINALITY. `retirementLag` keeps a symmetric 90 s escalation grace. Operator-set.**
6. ~~**C8b stays in wave 1?**~~ **ANSWERED in r4 (J7-B3): C8b changes bd writes — the
   token is session-bead metadata (`session_bead.dart:45/:491/:461`) — which the wave-1
   invariant forbids. It moved to the wave-2 appendix as W2-E. No operator dial remains;
   re-open only by amending the invariant itself.**

## ADJUDICATION LOG — r6 (operator-authored, 2026-09-01)

| finding | verdict | landing |
|---|---|---|
| J10-B1 / J11-B1 (unhealable terminalLag; reconstructedTerminal not fold-derivable) | ACCEPTED-FIXED | proj_session_head gains terminal_provenance + unknown_reason (fold_version bump, C0 quiesced replay = the migration; the "no DDL" clause was proj_meta-scoped); new tick obligation terminal-reconcile appends a reconstructed close (unknown/external-close) for any bead-terminal session whose P1 head stays open >60s — external closes, operator recoveries, record-less post-epoch terminals all heal durably; the 60s divergence escalation now signals only tick failure. |
| J10-B2 / J11-B2 (step-axis identity gap: trajCursor fed by the byWorkBead winner) | ACCEPTED-FIXED | C4's fill rewritten to bySessionId[legacy.sessionId]; the OVERLAY IDENTITY RULE restated as both-axes; no-same-session-rows takes the P2-miss rule, never a sibling's rows. |

r6 author: the governor (operator), after five agent revision rounds converged 28 -> 15 -> 8 -> 5 -> 2 blockers; the two residuals were mechanically specified by both judges in agreement.

## ADJUDICATION LOG — r7 (operator-authored, 2026-09-01, closing the V1 verify pass)

| finding | verdict | landing |
|---|---|---|
| V1-B1 (migration cannot add columns: CREATE-IF-NOT-EXISTS + DELETE/re-INSERT only) | ACCEPTED-FIXED | C0 names the reshape explicitly: quiesced DROP TABLE proj_session_head + re-CREATE (proj_% dolt_ignore'd) + fold_version bump + full replay; ALTER deliberately not built. |
| V1-B2 (UnknownTerminalSettlementObligation settles the reconstructed close into done; suppressor displaced) | ACCEPTED-FIXED | Suppressor keyed on the durable terminal_provenance COLUMN; delta settling branch never overwrites it; the settlement obligation's SQL excludes terminal_provenance='reconstructed' (final testimony, never settles). Stale single-writer sentences updated. |
| V1-B3 (60s heal always loses the 60s escalation race) | ACCEPTED-FIXED | terminal-reconcile heals on FIRST comparator observation; escalation re-keyed to attempted-heal + one surviving pass (no wall-clock race). |
| V1-B4 (breadcrumb attempt-id provably empty; obligation seam cannot see bead terminality; population over-claims) | ACCEPTED-FIXED | Re-homed to the BRIDGE comparator pass (sees the joined snapshot); attempt id from the P1 head's own attempt_id column; head-less post-epoch reclassified as gate-(c) misses (only reachable via dropped appends, independently disqualifying). C2 test plan gains: external close -> reconstructed close with head attempt_id -> suppressor durable across bounce -> zero divergence. |
| V1-M5 (C4 fill index/round-collapse undefined) | ACCEPTED-FIXED | byP2SessionId defined on the P2 mirror (distinct name); per-step_path collapse = max (round, step_round), the supersedes ladder's ordering. |
| V1 note (external-close rationale clause) | ACCEPTED-FIXED | The observer-append rationale states the external-close case honestly (a record about a ledger fact the station observed). |

ck_unknown admissibility and the append-not-bd-write classification were verified clean by V1 (no amendment needed; ObligationQuery/tick contract honored — now moot for the reconcile, which rides the bridge).

## ADJUDICATION LOG — r8 (operator-authored, closing the V2 verify pass)

| finding | verdict | landing |
|---|---|---|
| V2-B1 (heal-on-first-observation fires inside the normal terminal window; idem-collides with the real record; every terminal becomes reconstructedTerminal and the overlay disengages while gates read green) | ACCEPTED-FIXED | Trigger restored to a persistence grace: 90s + two comparator passes + no queued append for the attempt (normal windows clear in post-ACK time). Idem key changed to terminal-reconcile:<attemptId> - can never dedupe against terminal:<attemptId> in either direction. TRUTH MONOTONICITY rule added: reconstructed sets provenance only on terminal-less heads; a later observed terminal overwrites outcome and CLEARS the mark; settling touches neither. Race regression test added to the C2 plan. |
| V2-B2 (escalation re-key existed only in a parenthetical; four normative sites still said 60s) | ACCEPTED-FIXED | The ONE normative rule now lives in 0.3 MONOTONIC TERMINALITY; the lag-class table row, the C2 test plan, and FINAL Q5 all point at it; Q5 marked ANSWERED. |
| V2 notes 1-6 | ACCEPTED-FIXED | ck_prov basis named (terminal-reconcile); NULL-attempt clause collapsed to skip-only (attemptId required); seam rationale corrected (trajectory DB holds no beads); OVERLAY IDENTITY RULE names byP2SessionId for the step axis; Q18 amendment enumerates both writers; note-6 resolved by the truth-monotonicity rule. |

## ADJUDICATION LOG — r9 (operator-authored, closing the V3 pass)

| finding | verdict | landing |
|---|---|---|
| V3-B1 (distinct idem key routes the both-land collision into traj_terminal_guard PK 1062 -> corruption halt; truth-monotonicity branch unreachable) | ACCEPTED-FIXED | Heal precondition = guard check (existing terminal row => pure lag, skip+count). Residual race closed inside the single fenced appender with ONE rule - TESTIMONY YIELDS TO OBSERVATION: incoming reconstructed on guard collision => benign refused+counted; incoming observed vs existing reconstructed => appender converts to the settling form (resolvesRecordId -> guard UPDATE arm, no PK contention) carrying the real outcome; the delta writes that outcome and clears the mark (truth-monotonicity is now reachable, landing exactly there). Two observed terminals still halt (the genuine class). |
| V3-B2 (mark-clear re-exposes the stale reconstructed unknown RECORD to settlement, which clobbers the observed outcome to settled=>done; "marked forever" contradicted the rule) | ACCEPTED-FIXED | Settlement exclusion re-keyed to the immutable RECORD (t.provenance != 'reconstructed' in the obligation SQL) - permanent regardless of head state; the reconstructedTerminal bullet restated to the single truth-monotonicity rule (no "forever" phrasing anywhere). |
| V3 minor (retirementLag row still 60s) | ACCEPTED-FIXED | 90s, aligned with Q5. |

## ADJUDICATION LOG — r10 (operator-authored, closing the V4 pass)

| finding | verdict | landing |
|---|---|---|
| V4-B1 (conversion after the row insert => log holds non-settling shape => replay diverges from live fold; breaks rebuildability + C0/C1 goldens) | ACCEPTED-FIXED | The conversion is a LOG-level decision: a resolving pre-read (guard row joined to its records provenance via seq) at the top of the appenders serialized transaction, BEFORE the row insert; the envelope is authored/rebuilt in settling form so log, live fold, and replay agree on every path. |
| V4 note 1 (guard row lacks provenance/record_id) | ACCEPTED-FIXED | The stated join IS the resolving read. |
| V4 note 2 (discriminator by outcome value wrongly leaves observed-settled marked) | ACCEPTED-FIXED | Discriminator = settling records provenance == observed (durable in the envelope); outcome value irrelevant. |
| V4 note 3 (1062 handling shape + sealed outcome member) | ACCEPTED-FIXED | Local catch as belt (post-pre-read reachability = serialization broke = halt stays); AppendRefusedTestimony named as a new sealed AppendOutcome member. |

## ADJUDICATION LOG — r11 (operator-authored, closing the V5 pass)

| finding | verdict | landing |
|---|---|---|
| V5-B1 (trichotomy omits inferred: the reconcilers non-settling inferred settle on the heals successor path falls through to the guard 1062 halt) | ACCEPTED-FIXED | Case (a) re-keyed to incoming provenance != reconstructed (observed AND inferred convert to settling form); the deltas mark-clear stays strictly on observed, so an inferred settle lands outcome=settled with the mark intact (adjudication class preserved); the trichotomy is exhaustive and local-1062-as-belt is true as written. The false "provably empty breadcrumb" sentence corrected (abnormal ends can retain it; unused by the heal, load-bearing for the reconcilers own recovery). |
| V5 build note (in-transaction rebuild re-mints record_id) | ACCEPTED-FIXED | Stated: uq_record_id/epoch_seq/belt predicates read the rebuilt envelope. |
