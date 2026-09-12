# THE CUT — wiring design for the trajectory/ledger split — **r6: TWO WAVES — the wave-2 appendix becomes a design**

**Revision seat output, 2026-09-01 (r5). Repo: `engineering.memento/the_grid`, `main` @ `efe9795`.**
**r6 design round, 2026-09-07 — worktree `grid/cut-wiring-r6` @ `c28fd25` (main + the two wave-2 register entries, #341, #342, #345). Wave-1 text is untouched except the C3/C4 rollback amendment ruling Q2 requires.**

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
- **WAVE 2 (the flip — old C5, C6, C7, C9):** the **APPENDIX** below. r3–r5 carried it
  DESIGN-INCOMPLETE with its unresolved r2 blockers as entry criteria; **r6 turns it into a
  design**: every criterion E1–E10 carries a ratified ruling (Q1–Q12, two register entries)
  and a carrier bead, the carried majors are adjudicated, and the sketches are corrected
  designs. The lever, the breaker and the fold-backed disposition are buildable now; every
  write retirement and the flip stay gated on the soak certificate (§W2.5) and die on the
  kill date (§W2.6).

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

r5 → r6 (wave 2 only): the wave-2 entry worksheet (lunar_station
`docs/trajectory-spike/07-wave2-entry-worksheet.md`) verified every entry criterion against
`main @ 3617066` and put twelve rulings on a docket; the operator ruled all twelve
(`docs/decisions/2026-09-05-wave-2-flip-scope-soak-and-kill-date.md`, tg-whf6;
`docs/decisions/2026-09-06-wave-2-entry-criteria-rulings.md`, tg-dme1). r6 folds them in:
one lever (Q2), the breaker under cut (Q3), quiesced restore (Q4), the NARROW KEPT set as a
named §9 exception (Q5/Q10), bd as a terminal input (Q6, landed as tg-ffl6 #341), the
ratified refusal key (Q7), fold-backed disposition on C3 (Q8, tg-6zan), the open-retired
shape (Q9), break-glass (Q11), the kill date (Q12), and — because lunar's first true observe
boot (epoch 50) proved the Q1 wording unreachable — a SCOPED cut signal with a concrete
certification table (§W2.5). Every wave-2 `file:line` was re-verified in this worktree;
r6's own findings the rulings did not see (the `gated`/`ready` KEPT collisions, the shipped
`reconstructed` provenance, the soak window) are marked "r6 design, not ruled" and logged.
Receipts in the ADJUDICATION LOG — r6 (design round).

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
  (`startedAt: envelope.occurredAt`, `substation`, `headEpoch` — `:113-129`), and today that
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
`traj shadow-diff` per round, same shape coverage as C2's gate.
**Rollback (pre-cut only):** under `shadow`, demote to `dualRead: observe` (config/env,
one line) — instant, and legacy is still fully written.
Under `cut` there is no `dualRead` demotion; post-cut rollback is the
quiesced flip back to `shadow`, never a posture change on a live station.

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
as C3's; shape coverage must include at least one gate-park + re-arm cycle.
**Rollback (pre-cut only):** under `shadow`, `dualRead` demotion makes the step axis
observe while the legacy cursor remains fully written.
Under `cut` there is no `dualRead` demotion; post-cut rollback is the
quiesced flip back to `shadow`, never a posture change on a live station.

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
today. **`off` = byte-equivalent to main EXCEPT TWO reviewed bug fixes, adjudicated as the
stated exceptions (r14, operator): (a) C8a's flare delivery, and (b) C0's gc
disable-on-deny — main's cadence retries a permanently-denied `CALL DOLT_GC()` every
5 minutes forever (tg-3o6b's live finding); latching it off once with a named flare is
the fix, deliberately posture-independent.**
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

# WAVE 2 — THE FLIP (old C5, C6, C7, C9) — **r6: THE APPENDIX BECOMES A DESIGN**

> ## r6 STATUS — DESIGNED; BUILDABLE IN PART; THE FLIP ITSELF GATED ON THE SOAK
>
> r5 preserved this appendix as an uncorrected corpus with three gate items. r6 (design
> round + verify pass 1, 2026-09-07, worktree `grid/cut-wiring-r6`) turns it into a design the
> way r2–r5 turned wave 1 into one: every entry criterion E1–E10 carries its RULED
> disposition, every carried major is adjudicated, and the r2 sketches W2-A..W2-E are
> rewritten as corrected designs. Every `file:line` below was re-verified in this worktree;
> none is copied from the entry worksheet (three PRs landed after it was written).
>
> **THE WAVE-2 GATE, r6 status:**
> 1. **Wave 1 soaked** — ACCRUING, not met. lunar epoch 50 (2026-09-06) was the FIRST boot
>    that actually armed `dualRead: observe` (the runner never fed the process environment
>    to the config before; epochs 5–10 were space-fed). Its receipt shows Q1's cut signal is
>    unreachable AS WORDED — 601 of 632 fallbacks are legacy-era sessions that will never
>    fold — so §W2.5 scopes the signal and states the certification table. `primary` has
>    never booted.
> 2. **A dedicated wave-2 design round** — THIS revision, plus VERIFY PASS 1: two
>    adversarial judges returned 12 blockers and 18 majors, each was re-verified against this
>    worktree, and the confirmed ones are fixed in the text below (one blocker REFUTED at the
>    tree). The adjudication is the last table in this document.
> 3. **Operator ratification** — DONE. Two register entries rule every docket row:
>    `docs/decisions/2026-09-05-wave-2-flip-scope-soak-and-kill-date.md` (bead tg-whf6:
>    Q1, Q5, Q6, Q12) and `docs/decisions/2026-09-06-wave-2-entry-criteria-rulings.md`
>    (bead tg-dme1: Q2, Q3, Q4, Q7, Q8, Q9, Q10, Q11). Each criterion below cites its
>    ruling by slug and line.
>
> **Buildable NOW (no soak prerequisite — they are posture-neutral or read-side):** tg-rcm3
> (the lever, E1), tg-ppo5 (accounting split + `appendAcked` + the breaker, E2/E5), tg-6zan
> (fold-backed disposition/fences on C3, E8). Already LANDED: tg-ffl6 (#341, E6) and tg-ilug
> (#342, the comparator's cause labelling). **Gated on the soak certificate (§W2.5):** the
> write retirements and the flip (W2-A's R-set branches, W2-B, W2-C). **Gated on their own
> soak under cut:** W2-D, then W2-E last.
>
> **Vocabulary note.** The r2 sketches cited §0.5 (append discipline) and §0.6 (the KEPT
> table); neither section exists in the wave-1 text any more. r6 carries both HERE: the
> append discipline under cut in W2-A, the KEPT table in §W2.2.

## W2.0 The rulings, one line each, and the carrier of each

| Q | Ruling (entry) | Carrier |
|---|---|---|
| Q1 | Soak on lenny + butane only, observe then primary, after tg-ilug; signal = fallbacks 0 + unexplained 0 across three clean boots covering the named shapes (`wave-2-flip-scope-soak-and-kill-date`, "Q1 — the soak re-arms on target seats after the comparator fix") | §W2.5 — the SCOPED signal (r6 design, not ruled: the receipt proves the unscoped wording unreachable) |
| Q2 | One lever: `TrajectoryConfig` discipline `{shadow, cut}`; `cut` implies `dualRead: primary` on both axes + `mode: required`; disagreement refuses by name; C3/C4 rollback is pre-cut only (`wave-2-entry-criteria-rulings`, "Q2 — one cut lever (E1)") | tg-rcm3 |
| Q3 | Accounting split; only decision-bearing drops feed health; under cut `compromised` = breaker (halt admission, drain, gate, `trajectory.halted`), never a demotion; `appendAcked` sealed `{Acked, Dropped, Suppressed}` always completes; `_rearm`'s failure = gate (same entry, "Q3 — `compromised` under cut halts admission (E2, E5)") | tg-ppo5 |
| Q4 | Restore under cut is a quiesced void-and-redrive; no head-stamp detector; M6c stays at Stage 4 (same entry, "Q4 — restore under cut is a quiesced void-and-redrive (E3, shape b)") | W2-A runbook (§W2.4) — unfiled |
| Q5 | Narrow: retire only `running`, `pending`, `gated` step writes; `complete`/`failed` KEPT until Stage 2/4 (`wave-2-flip-scope-soak-and-kill-date`, "Q5 — wave 2 is narrow") | §W2.2 KEPT table; W2-A |
| Q6 | bd remains an input to terminal truth; the terminal append becomes acked; a tick obligation reconciles ledger-closed/P1-open (same entry, "Q6 — bd remains an input to terminal truth under cut") | tg-ffl6 (#341, LANDED); the acked half rides W2-A |
| Q7 | The ratified `refused:<bead>:<clause>:<snapshotRev>` key is NOT amended; W2-B uses it (`wave-2-entry-criteria-rulings`, "Q7 — the `admission.refused` idempotency key is not amended (E7)") | W2-B |
| Q8 | Fold-backed `sessionDispositionOf`/`staleFences` ride C3 now (same entry, "Q8 — fold-backed disposition rides C3 now (E8)") | tg-6zan |
| Q9 | The open-retired P1 shape is accepted; accretion fixed at the missing terminals; P6 eviction bounded on `last_seq` age (same entry, "Q9 — the open-retired P1 shape is accepted (E9)") | tg-ffl6 (the source fix); W2-A (the eviction bound) |
| Q10 | The KEPT-writes coexistence is a NAMED exception to §9's cuts-whole rule, exactly the narrow set (same entry, "Q10 — the KEPT-writes coexistence is a named exception to §9") | §W2.2 |
| Q11 | Break-glass: resolved once at assembly before any posture read; both bypass targets read the resolved value; loud provenance; permanent archaeology guard (same entry, "Q11 — the break-glass contract") | W2-A |
| Q12 | Kill date 2026-10-02 — a deadline on the whole; past it, wave 2 re-scopes to the bd ledger with retention and the comparator is deleted (`wave-2-flip-scope-soak-and-kill-date`, "Q12 — the kill date is 2026-10-02") | §W2.6 |

## W2.1 ENTRY CRITERIA — ruled dispositions (E1–E10)

Format per criterion: **Was** (the r2 blocker, condensed — the verbatim text is in the r5
appendix, preserved in git history) · **Tree** (verified r6 @ `c28fd25`) · **Ruled** (Q +
entry) · **Design (r6)** · **Carrier**. Anything the ruling did not supply and r6 had to
decide is marked **r6 design, not ruled**.

### E1 — `[ordering-rollback B1]` no interlock between the cut lever and `dualRead`

- **Was.** `g1=cut` + `dualRead=observe` is a permitted boot that retires step writes while
  decisions still read the retired carrier; C3/C4's documented rollback lands exactly there.
- **Tree.** No cut lever exists: `G1Discipline`, `GRID_G1`, `CutPostureRefused`,
  `appendAcked` appear in no `packages/*/lib` source (grep empty). `dualRead` is one
  three-value field (`grid_sdk/lib/src/trajectory/trajectory_config.dart:156`, default `off`
  at `:63`; `DualReadMode {off, observe, primary}` at
  `grid_engine/lib/src/domain/session_head_read.dart:57`) that BOTH axes read — the session
  pass and the step pass take the same posture — so "primary on both axes" is one field, not
  two. The `mode` dartdoc (`trajectory_config.dart:16-18`) pins that a trajectory failure
  never blocks a boot; that is why the refusal cannot ride a harness throw (C-M2).
- **Ruled.** Q2 (`wave-2-entry-criteria-rulings`): one lever, `cut` implies `primary` +
  `required`, disagreement refuses by name, C3/C4 rollback pre-cut only.
- **Design (r6).** `TrajectoryConfig.discipline {shadow, cut}`, default `shadow`, beside
  `mode` (the FIELD at `:67`, ctor param `:54` — `:19` is the enum declaration, a cite the
  first draft got wrong) and `dualRead` (`:156`). The implication is RESOLUTION, not
  validation, in ONE place: a cut config reports `dualRead == primary` and `mode ==
  required` whatever was requested, so no caller can observe a weaker cut.
  **THE DRY-ARM RULE (verify-1 — r6 design, not ruled).** `asDisabled` (`:203-215`), the
  seam a dry arm uses to force the no-write posture, also forces `discipline: shadow`. A dry
  arm writes nothing, so it is shadow-era by definition; carrying `cut` through that seam
  would yield a config that is `cut` with a DISABLED harness — a direct contradiction of the
  invariant above — and would leave `appendAcked`'s answer at `disabled` (a silent no-op,
  `trajectory_harness.dart:1179-1183`) undefined, where BOTH answers are wrong: `Dropped`
  halts admission on every dry probe (and a dry arm is the standard probe), `Acked` silently
  loses a decision-bearing record under cut. tg-rcm3's ACs gain the rule.
  **TWO REFUSALS, TWO SITES (verify-1 — C-M2/C-m4 restated).** The first draft made them one
  check; they cannot be:
  1. **The REQUESTED-posture disagreement** is a pure config predicate. It is validated at
     ASSEMBLY, in the same resolution step Q11 fixes for break-glass, BEFORE any mutation,
     and throws the typed `CutPostureRefused` naming both values. Placed after `start()` it
     would refuse a runtime that is already half-started: `start()` sets `_started = true` on
     its second line (`grid_sdk/lib/src/work/work_assembly.dart:264-266`), the store handles
     attach during assembly (`:418-432`), `_sourcesStart` and the epoch claim have run — and
     because `start()` is idempotent BY FLAG, a caller that catches the refusal and retries
     gets a clean early return and then boots cut with no refusal and no flare.
  2. **The harness-not-`live`-under-cut refusal** genuinely needs the harness, so it stays
     AFTER `trajectory.start()` returns (`:273`) and BEFORE `_driver.start()` (`:304`). It
     LATCHES — a second `start()` after a refusal re-throws rather than returning early —
     and its unwind is stated: shut the trajectory down, release the epoch, rethrow.
  **The caller obligation.** `CutPostureRefused` and `DisciplineQuiesceRefused` MUST
  propagate out of `start()` and ABORT the boot; a runner that swallows either into a
  warning line is out of contract. `start()`'s house style DOES swallow subsystem failures
  (`:271-279` trajectory, `:298-302` teardown) — these two are deliberately not of that
  class — and the in-repo AC tg-rcm3 gains is that `start()` THROWS rather than degrades.
  The runner half is space's `up` (one session, one repo) and is named as a follow-up, not
  assumed. A shadow boot is byte-identical to today (tg-rcm3 AC-6). The env key that names
  the lever on a real boot is the space half; r2's `GRID_G1` is carried as the proposal
  only. **C3/C4 rollback text: amended in wave 1 to "pre-cut only" (this
  revision) — post-cut rollback is W2-C's flip-back through the quiesce rule (O-M3), never
  a `dualRead` demotion.**
- **Carrier.** tg-rcm3 (open, wired as tg-ppo5's blocker).

### E2 — `[ordering-rollback B2]` + `[completeness B4]` `compromised` demotes to a dead carrier under cut

- **Was.** One global `_dropped` counter, bumped by fire-and-forget drops, latches
  `compromised`; under cut that demotes step-state decisions onto a cursor with no writer.
- **Tree.** Confirmed at the current lines: `_dropped`
  (`grid_sdk/lib/src/trajectory/trajectory_harness.dart:452`) is bumped at `:1200` (queue
  overflow), `:1252` (reconnect), `:1322` (grant refused), `:1332` (append failed), `:1344`
  (the belt-and-braces throw), `:1449` (shutdown drain remainder); each calls
  `_latchMirrorCompromised` (`:1010`), whose own dartdoc (`:1004-1009`) states the wave-1
  reason: "which projection the lost record would have touched is exactly what the harness
  cannot know". `_suppressed` (`:453`, bumped at `:1189`, `:1195`, `:1644`, `:1659`) is the
  "not a drop" precedent. Under wave 1 the latch is CORRECT (legacy is fully written);
  under cut it is backwards.
- **Ruled.** Q3 (`wave-2-entry-criteria-rulings`): split the accounting; only
  decision-bearing drops feed health; under cut `compromised` is a breaker — no new work
  admitted, running sessions drain to terminal, a station gate opens, `trajectory.halted`
  flares; never a demotion. This is also O-M2's storm budget.
- **Design (r6).** (1) Two counters — `decisionBearingDropped`, `fireAndForgetDropped` —
  classified from the REQUEST, not the site: `TrajectoryAppendRequest` (`:82`) gains a
  `decisionBearing` flag that the recorder sets at exactly the named sites (§W2.2's
  retiring set: `stepRunning`, `stepRearmed`; the session terminals under Q6) and nowhere
  else. **`admission.refused`/`admission.restored` are NOT decision-bearing** (verify-1 —
  a correction to the first draft, which listed the barrier's refusal here): the refusal
  DECISION is taken synchronously by the eligibility clause and the record only WITNESSES
  it, so a lost record loses an audit row the next evaluation re-emits. Classing pure
  telemetry decision-bearing would halt the station on an append-side blip — and, with the
  key defect W2-B now carries (O-M6/C-M5), would make that halt near-certain. Only the first counter reaches
  `_latchMirrorCompromised`; `/status` and the round summary keep a TOTAL equal to their
  sum so no reader loses a number. `_suppressed` stays as it is. (2) Under
  `discipline == cut` a decision-bearing `Dropped`/`Suppressed` HALTS: an
  `admission-halted` latch that `composeMountEligibility` reads as a refusing clause at
  both its sites (`grid_engine/lib/src/seeds/work_list.dart:303`,
  `grid_engine/lib/src/kernel/station_admission_authority.dart:671`), one operator-visible
  gate, and its OWN flare `trajectory.admissionHalted{reason, recordClass}`.
  **NOT the existing `trajectory.halted`** (verify-1, a correction to the first draft): that
  flare fires exactly once from `_latchHalted`, under `if (_latched) return;`, and the same
  latch SUPPRESSES every subsequent append (`trajectory_harness.dart:1655-1664`) — so
  reusing it would either freeze the appender the drain still needs or overload a name whose
  established meaning is "the log is presumed damaged", leaving a genuine second halt
  flareless. Two states, two causes, two recoveries, two names.
  **The gate seam is not one seam (r6 design, not ruled).** `createGate`
  (`grid_runtime/lib/src/lifecycle/station_bead_writer.dart:630-646`) takes
  `{substation, sessionId, nodePath, reason}`, dedupes on (session, node), and calls
  `_assertGateSessionOpen` (`:646`; the refusal at `:1393-1400`). A STEP-class loss
  (`stepRunning`/`stepRearmed`) has a session AND a node and its session is still open, so
  it mints there — the `persistRaisedEscalation` pattern
  (`grid_engine/lib/src/circuit/capability_host.dart:145`). A TERMINAL-class loss lands
  AFTER the KEPT bd close, so the session bead is closed and `createGate` throws
  `SessionClosedRefused`; and the station-wide halt itself has no node at all. r6 verified
  there is NO station-scoped gate seam in the tree. W2-A therefore needs one — a
  station-scoped gate on `StationBeadWriter` keyed on the boot epoch, not on (session,
  node). **Carrier: UNFILED; file it before the breaker's gate half is built.** Until it
  exists the halt's durable artifacts are the flare plus the latched admission clause, and
  attaching the halt to an arbitrary open session is FORBIDDEN: that gate closes when its
  session drains, silently retiring the halt's only durable artifact while admission stays
  latched. Running sessions
  reach their own terminal (the terminal is acked; if THAT ack is also lost, the bd close
  is KEPT and tg-ffl6's obligation infers the terminal on the next healthy boot — Q6's
  belt). The latch is per boot, like `compromised`: the operator clears it by bouncing
  after reading the flare. (3) Under `shadow` nothing changes (tg-ppo5 AC-7). **r6
  design, not ruled:** the clause name `admission-halted` and the request-level flag.
- **Carrier.** tg-ppo5 (open, blocked by tg-rcm3).

### E3 — `[ordering-rollback B3]` restore + replay silently regresses decision state

- **Was.** The stale-fold guard is intra-db and both the fold deltas and `applied_seq` ride
  the append transaction, so a restored-behind db is internally consistent and the guard
  can never fire; under cut the lost records are step facts with no second carrier.
- **Tree.** Confirmed: the fold delta and the `proj_meta.applied_seq` upsert ride the
  append transaction (`grid_trajectory/lib/src/append/trajectory_appender.dart:641-652`,
  COMMIT at `:656`; the header at `:29-31` states the order). No external anchor exists: no
  `grid.head.*` stamp is written to the session bead (grep empty); M6c stays parked.
- **Ruled.** Q4 (`wave-2-entry-criteria-rulings`): shape (b) — restore is a quiesced event
  that voids every session open at the snapshot and re-drives them from bd; no detector;
  M6c stays at Stage 4.
- **Design (r6) — the RESTORE RUNBOOK, quiesce-only.** (1) Station DOWN, proved by the
  same two witnesses `traj replay` already demands — the RS-2 lock read by path and the
  `traj_epoch` fence (`grid_trajectory/lib/src/cli/traj_quiesce.dart:1-30`). (2) Restore
  the trajectory database. (3) `traj replay` (C0, quiesce-only) so the fold equals the
  restored log. (4) VOID EVERY OPEN SESSION in the ledger — not only the ones P1 shows
  open: a session minted after the snapshot has no P1 row at all and would otherwise boot
  as a post-epoch miss on a live session, exactly the class the cut cannot serve. The void
  is the KEPT `#void-` re-key through bd (R3 — a bd CLI write, allowed in wave 2),
  performed BY HAND: the station is down, so no engine machinery runs at this step.
  **Correction (verify-1).** The first draft named a deadness proof `_refuseVoidMint`; NO
  such symbol exists anywhere in `packages/*/lib` (grep empty — the name survives only in
  this document's frozen wave-1 lines and the old transition inventory). The fence check is
  STATION-SIDE and runs at the NEXT BOOT, not at step 4: `staleFences(...).where(_liveness)`
  gating the remint fork
  (`grid_engine/lib/src/kernel/station_admission_authority.dart:555-557`, `:809-817`), with
  the `session.voidRefused` flare (`:1363-1371`). At step 4 deadness is true BY
  CONSTRUCTION — the station is down, so every process group it owned is dead — and the
  identity triple stays legible on the KEPT carrier for that next boot to read
  (`startedIdentityMetadata`, `grid_engine/lib/src/domain/session_bead.dart:518-526`; the
  triple's fence half is re-stated on `attempt_id` when W2-E retires the token). **The tool
  gap is real and named:** an unbounded set of hand `#void-` re-keys through bd, at the
  cut's worst failure mode, with no verb and no chokepoint — while wave-1 constraint 3 wants
  bd-side repairs to ride `StationBeadWriter`. A void-every-open-session verb is WANTED and
  **UNFILED**; file it with W2-A, because the runbook is not operable at scale without it.
  (5) Boot. tg-ffl6's obligation
  (`grid_runtime/lib/src/trajectory/stage1_obligations.dart:320`) appends each voided
  session's terminal (`lost` for a void key, per its notes), and the work beads re-mint
  through the existing remint-on-void fork. Under narrow (Q5) the `complete`/`failed`
  facts on the beads survive the boundary, so a re-driven bead resumes with its result
  keys and breaker count intact. **r6 design, not ruled:** step (4)'s "every open session,
  not only P1-open"; and an OPTIONAL belt that is NOT a head stamp — the cut-posture check
  may refuse a boot whose `proj_meta.rebuilt_at` is newer than the previous epoch's
  clean-down while any ledger session is open (the operator skipped step 4). Not in the
  buildable set; recorded so the re-judge can weigh it.
- **Carrier.** W2-A (runbook text rides its PR); no bead filed.

### E4 — `[fold-fidelity B2]` + `[completeness B1]` the KEPT-writes set retires and keeps the same write

- **Was.** R8's failure persist IS R11's restartCount/cooldown persist (one
  `writer.update`); `_persistReady`/`_persistComplete` merge `grid.result.*`; retiring the
  call zeroes the rework cap; retiring only the state key keeps the churn.
- **Tree.** Confirmed at the current lines (`grid_engine/lib/src/circuit/capability_host.dart`):
  `_persistFailureClassed` `:839`, its single update `:869-877` via `_moleculeMetadata(...
  restartCount: next, cooldownUntil: cooldown ...)`; `_persistReady` `:710-719` and
  `_persistComplete` `:738-745` both merge `nodeResultMetadata`; `_persistFailure` `:776`
  is the breaker entry the recursion guard protects (`:547-550`). `_moleculeMetadata`
  (`:651-671`) always writes `restartCount` (a COPY of the node's current value when the
  caller passes none) and `startedAt` for a non-terminal write. **Two further sites the
  worksheet did not enumerate, verified here:** the `gated` write at the exhaustion park
  carries `restartCount: attempts` + `failureReason` (`:940-945`), and the route-escalate
  park merges `ResultKeys.routeVerdict` (`:1057-1062`); both flow through
  `persistRaisedEscalation` (`:105`, update at `:135`, `stepGated` at `:136`, gate bead at
  `:145`); a third `gated` site re-projects the whole node
  (`grid_engine/lib/src/circuit/session_scope.dart:1291`).
- **Ruled.** Q5 (`wave-2-flip-scope-soak-and-kill-date`): NARROW — retire only `running`,
  `pending`, `gated`; `complete`/`failed` stay KEPT until Stage 2/4. Q10
  (`wave-2-entry-criteria-rulings`): the coexistence is a named §9 exception, exactly that
  set.
- **Design (r6).** The KEPT table is §W2.2. Two findings the rulings did not see, both
  **r6 design, not ruled — a one-line Q5 amendment is requested:** (a) `gated` at the two
  `capability_host.dart` park sites has the SAME one-call-one-map shape as
  `complete`/`failed` — the exhaustion park is the SOLE carrier of the exhausted
  `restartCount` (the park RETURNS at `capability_host.dart:857-865`, before the `failed`
  write at `:869-877`), and the route park is the sole carrier of the route verdict; r6
  therefore carries `gated` as **KEPT-PENDING-RULING** at all three sites (uniform rule; the churn cost is 288 of 18,796
  step writes, 1.5%) and the retirement that is buildable regardless is `running` +
  `pending` (8,868 of 18,796, 47%). (b) `ready` (a positive terminal with a rendezvous
  payload, `capability_host.dart:703-709`) is unnamed by Q5; r6 carries it KEPT with `complete` — same shape.
  The B-M2 durability requirement is met trivially under narrow: the tg-0zq8 breaker's
  count never leaves the bead.
  **THE AMENDMENT GATES THE BUILD (verify-1).** "KEPT-PENDING-RULING" is not a disposition
  the build may proceed under: Q5 and Q10 name a retiring set that includes `gated`, so
  until the one-line amendment is ruled, §W2.2 and W2-A disagree with a ratified entry and
  the retiring set is UNDETERMINED. So: (i) "the Q5/Q10 amendment on `gated` and `ready` is
  ruled" is an explicit item of W2-A's gate and of W2-C's pre-flip evidence pack; (ii) both
  branches are written out in §W2.2, because if the operator DECLINES the amendment, `gated`
  retires and the exhausted `restartCount` and the route verdict each need a second carrier
  BEFORE that branch is built.
- **Carrier.** §W2.2 + W2-A (the branch sites).

### E5 — `[fold-fidelity B3]` a suppressed append hangs an awaited ack; `_rearm` has no breaker

- **Was.** An awaited ack has a third outcome (suppressed under `degraded`/`fencedOut`/
  `halted`) that never completes; `_persistFailure` is private while R10's site is
  `SessionScope._rearm`, whose only failure path is a retryable flare.
- **Tree.** Confirmed: `enqueue` is `void` (`trajectory_harness.dart:1178`); the suppress
  arms are `:1183-1191` (mode) and `:1194-1196` (shutdown). `_rearm` is
  `session_scope.dart:1525`; its bead write is state-only
  (`{MoleculeStepKeys.state: pending}`, `:1566-1569`) followed by `stepRearmed`
  (`:1574`); every failure path is `_flareRearmFailed` (`:1538`, `:1545`, `:1587`; defined
  `:1598`). No `appendAcked` exists.
- **Ruled.** Q3 covers it (same entry): sealed `{Acked, Dropped, Suppressed}` that always
  completes; decision-bearing sites treat `Dropped`/`Suppressed` as the breaker, never a
  retry; `_rearm`'s failure path becomes a gate.
- **Design (r6).** `appendAcked` sits BESIDE `enqueue`, never replaces it (C-M1: the
  recorder stays `void` for everything else).
  **THE COMPLETION CONTRACT IS ON THE REQUEST LIFECYCLE, NOT ON THE HARNESS MODE
  (verify-1 — a correction to the first draft, which offered the per-mode table as the
  proof).** A table taken at CALL time says nothing about a request ACCEPTED at `live` and
  destroyed later, in bulk: `_latchFencedOut` (`trajectory_harness.dart:1642-1652`),
  `_latchHalted` (`:1655-1664`) and `_degrade` (`:1669-1676`) each do
  `_suppressed += _queue.length; _queue.clear();`, and the shutdown drain's timeout arm does
  `_dropped += _queue.length` then `_queue.clear()` (`:1449-1455`). Under cut a mid-flight
  latch would leave an awaited ack pending FOREVER at a decision-bearing site whose bead
  write was already skipped — a wedged circuit, strictly worse than the loss the ack exists
  to detect. The contract is therefore: **every accepted request completes exactly once** —
  `Acked` at the transaction COMMIT (`trajectory_appender.dart:218`, `:656`), `Suppressed`
  at EVERY queue-destroying site above, `Dropped` at the queue-overflow arm (`:1200`) and
  the drain remainder. tg-ppo5's AC-5 keeps its per-mode table and GAINS the lifecycle case:
  *a request queued at `live` whose queue is then cleared by a latch completes with
  `Suppressed`; no future is left pending.*
  **AND A DEADLINE (verify-1 — r6 design, not ruled).** "Always completes" is not "completes
  soon": the live path waits on the queue drain and one serialized COMMIT with no bound, so
  a degraded-but-live harness (deep queue, slow dolt) would stall every process start.
  `appendAcked` carries a deadline of one tick interval (`trajectory_config.dart:55`) and a
  breach completes as `Dropped` — the E2 halt then catches it and the halt reason names the
  timeout — rather than adding a fourth case to the sealed set. F-M4's `append_ack_p99_ms`
  measures the same path: the BUDGET is a soak finding, the DEADLINE is the runtime defence. Under cut, `_rearm`'s `Dropped`/`Suppressed` opens the
  E2 gate — the halt — instead of clearing the guard for a retry; under shadow
  `_flareRearmFailed` is unchanged. The recursion-guard secondary (C-B1) is MOOT under
  narrow: `failed` stays a bd write with a fire-and-forget append, so no failing append can
  be `_persistFailure`'s own.
- **Carrier.** tg-ppo5.

### E6 — `[fold-fidelity B5]` `attempt.terminal` is decision-bearing under cut but fire-and-forget

- **Was.** The tick reap and the barrier key on a P1-terminal session; a dropped terminal
  strands the worktree and disarms the barrier meant to catch it.
- **Tree.** The terminal sites moved: `sessionVoided` at `session_scope.dart:724`, `:854`,
  `:971`; `sessionCompleted` at `:1216`; `sessionEscalated` at `:1684` — all after the bd
  close, fire-and-forget. **LANDED (tg-ffl6, #341):** `ExternalCloseTerminalObligation`
  (`stage1_obligations.dart:320`; dartdoc `:286-306`) is a posture-independent tick query
  fed by `SessionClosureProbe` (`:84`) over the state snapshot, with the rollback switch
  `TrajectoryConfig.reconcileLedgerCloses` (`trajectory_config.dart:64`, `:168`, default
  ON at every posture) and the idem key `terminal-reconcile:<attemptId>` (`stage1_obligations.dart:306`).
- **Ruled.** Q6 (`wave-2-flip-scope-soak-and-kill-date`): bd remains an input to terminal
  truth; the terminal append becomes acked; a tick obligation reconciles ledger-closed/
  P1-open into an `attempt.terminal`; the reap and barrier read P1 only once that input is
  complete.
- **Design (r6).** Two halves. (1) DELIVERED: the obligation. One vocabulary correction
  the re-judge must see: the ruling says `provenance=inferred`; the shipped obligation
  writes `provenance='reconstructed'` (`stage1_obligations.dart:442-443`), deliberately — it shares the C2 heal's
  idem grammar and the `reconstructedTerminal` adjudication class, and the settlement
  exclusion (`t.provenance != 'reconstructed'`, `:231`) then keeps a healed terminal from
  ever being settled over. `inferred` is the tick's vocabulary for SETTLEMENTS (`:273`).
  r6 records the shipped word; a one-word amendment to the entry is requested, and it rides
  W2-A's doc list as a **BLOCKING** item (verify-1) — until it lands, this design states a
  word a ratified entry contradicts, and no reader should have to reconcile the two. Census
  correction from #341's review: 161 of the 267 orphans are retired `#rN` rounds the fold
  keeps OPEN by design (E9); 36 heads heal; 70 attempt-less heads stay open by rule (Q-A,
  open). (2) W2-A: under cut the three terminal appends become `appendAcked` (E5 class,
  `decisionBearing`); a lost terminal ack HALTS (E2) — but the bd close already happened,
  so the obligation closes the loop on the next boot. "Read P1 once the input is
  complete" is made concrete in W2-B: the barrier's terminal predicate is P1-terminal OR
  ledger-closed (the joined projection's `isTerminal`), so the 90 s heal grace is never a
  window in which a closed session's live worktree can be mounted over.
- **Carrier.** tg-ffl6 (closed, #341); the acked half rides W2-A.

### E7 — `[completeness B3]` the `admission.refused` idem key

- **Was.** r2 changed the ratified level-shaped key to a reason-keyed form without an
  amendment; the ratified form is what makes refuse→restore→refuse re-latch.
- **Tree.** The ratified key stands: `refused:$workBeadId:$clause:$snapshotRev`
  (`grid_trajectory/lib/src/codec/records/admission_records.dart:269-270`), `restored:`
  at `:320-321`; `mountAttemptId` and `snapshotRev` are REQUIRED constructor fields
  (`:218-225`) and the envelope requires `mount_attempt_id` (`:233-238`, "minted per
  admission evaluation — grant OR refusal"). The schema pins the key at
  `trajectory-schema.md:269` and `:1050`. No recorder derivation for `admission.refused`
  exists yet (grep for `admissionRefused` across `grid_runtime`/`grid_sdk`/`grid_engine`
  is empty) — by staging: the barrier and its refusal record arm TOGETHER at the cut
  (`trajectory-schema.md:1936-1942`, `:1892-1897`).
- **Ruled.** Q7 (`wave-2-entry-criteria-rulings`): no amendment; W2-B uses the ratified key
  with `snapshotRev` from the joined snapshot the authority evaluated; A-M4, B-M3, F-m3
  close as "the tree is right".
- **Design (r6).** W2-B sources every required field (O-M6/C-M5 answered there). **The three staging sites are NOT
  yet in agreement (verify-1 — a false cite in the first draft, corrected here).** What each
  actually says: `trajectory-schema.md:1371-1373` (§9's Stage-1 bullet) still reads "the
  authority's eligibility re-evaluation and its `admission.refused`/`admission.restored`
  records move to **Stage 3** with their family"; `:1892-1897` (audit-round-2 item 5) says
  the same, with only the BARRIER half struck through; `:1936-1942` (the Stage-1 build
  amendment, 2026-08-31) is the superseding text — "the barrier's LOGIC and its refusal
  RECORD now arm together at the **cut**", superseded "at all three sites it appeared". The
  amendment settles the staging; the two standing Stage-3 sentences are stale text about the
  same record family. W2-B's doc fix is therefore not a cross-reference: it **STRIKES** the
  superseded clause at `:1371-1373` and `:1892-1897` and points at `:1936-1942` and at this
  appendix. And, since Q10 says "no other partial cut is implied": arming `admission.refused`
  at the cut is NOT a second partial cut of §9 — it is the schema's own 2026-08-31 amendment,
  which moved a record family's arming point, and it retires no bd write.
- **Carrier.** W2-B.

### E8 — adoption half of `[B5 / completeness B2]`: cursor consumers adopt a fold read before any retirement

- **Was.** `sessionDispositionOf` and `staleFences` read the bead-projected cursor; they
  must read the fold (with pgid/pid/token fence inputs) before R8 retires anything.
- **Tree.** `sessionDispositionOf` (`grid_engine/lib/src/domain/session_disposition.dart:86`;
  pure/total by its dartdoc `:82-85`; cursor walk `:112`; the empty-cursor rule
  `:116-125`) is called at `session_scope.dart:424`, `:1552`, `:1740`;
  `work_list.dart:376`, `:425`, `:519`; `linked_sessions.dart:49`, `:115`;
  `station_admission_authority.dart:352`, `:408`, `:537`; the metadata twin at
  `restart_reconciler.dart:645`, `:661`, `:708`. `staleFences` (`session_disposition.dart:139`,
  walk `:142`) at `station_admission_authority.dart:555`, `:569`, `:809`, `:1246`. The C3
  splice overrides exactly four fields (the rule at `station_join_bridge.dart:369-374`,
  spliced at `:375-378`) and the C4 splice attaches `trajCursor`/`trajStepViews` as separate
  fields (`:379-394`, the `copyWith` at `:391-394`) — both cites tightened in verify-1. P1
  carries `pgid`, `pid`, `attempt_id`, `held`, `outcome` (`trajectory_schema.dart:35-53`).
- **Ruled.** Q8 (`wave-2-entry-criteria-rulings`): fold-backed disposition and fences ride
  C3 NOW as a wave-1 extension under `dualRead: primary`, with a counted legacy fallback;
  the empty-cursor voiding rule is re-derived from P2 the same way.
- **Design (r6).** As tg-6zan states it: under primary, when `trajCursor` is attached, both
  functions derive from P2 + the P1 head; under `off`/`observe` byte-identical to today;
  fallback counted on `DualReadAccounting` (`session_head_read.dart:648`), never a second
  accounting; both functions stay pure (posture arrives as data on the projection); the
  comparator (`dual_read_pass.dart:229`) gains a dedicated cause for disposition/fence
  disagreement so the soak certifies this field set like the four. Its soak evidence joins
  §W2.5's table as `disposition` and `fences` divergence fields.
  **THE FENCE HALF IS A CARDINALITY CHANGE, AND IT MUST BE ADDITIVE (verify-1 — r6 design,
  not ruled; an amendment to tg-6zan's plan is requested).** `staleFences` is the fail-closed
  "never double-run a survivor" proof: it walks EVERY `running`/`ready` node's pgid+pid+token
  and dedupes by pgid, falling back to the session scalar ONLY when that per-node set is
  empty (`session_disposition.dart:139-158`). P2 carries no pgid/pid/token column at all
  (`trajectory_schema.dart:171-182`) and P1 carries ONE pgid/pid/attempt_id per session
  (`:44`), cleared on process exit — so a fold-backed derivation returns AT MOST ONE fence,
  which is exactly what tg-6zan's plan and its AC-2 say today. A session with two live
  process groups (parallel capability steps — the case the pgid dedupe exists for) would
  then prove one dead and read as "no live fence" at `_hasLiveFence`
  (`station_admission_authority.dart:1246`) and at the remint fork; and Q8 puts this in
  WAVE 1, live before any write retires. The rule is therefore: **the fold-backed fence set
  is a UNION with the legacy per-node set and never returns FEWER fences than legacy does
  today.** Per-node fold fences need P6 (`proj_process_identity`, the only per-attempt
  pid/pgid carrier, `trajectory_schema.dart:254-268`), whose mirror W2-A builds — so the
  honest ordering is union now, per-node fold fences when P6 lands. tg-6zan's AC-2 gains the
  two-live-group case.
  **A THIRD CURSOR CONSUMER, MISSED BY THIS CRITERION'S FIRST ENUMERATION (verify-1).**
  `ProcessLeaseVendor.sweepOrphanedLeases` reads the step bead's state RAW — not through a
  projection, not through `effectiveStepCursor` — off the reconciler's state snapshot
  (`restart_reconciler.dart:1055-1071` builds each candidate's `metadata` from
  `bead.metadata`; `process_lease_vendor.dart:746-748` derives
  `spawned = state == running || ready`). Only a `spawned` step whose lease keys are
  entirely absent raises the LOUD `onOrphan` report that tells an operator a surviving
  process group cannot be found or killed. Under cut `_persistStarted` skips the bead
  update, the bead reads `pending`, `spawned` goes false, and that report goes SILENT — a
  decision-bearing fact with no second carrier once `running` retires. The closed set of raw
  `MoleculeStepKeys.state` readers under `packages/*/lib` is three: `molecule_codec.dart:221`
  (the decoder feeding the projection C4 overlays), `process_lease_vendor.dart:728`
  (`_isLatchedStepState` — UNAFFECTED: `pending` and `running` are both non-latched,
  `:556-564`), and `process_lease_vendor.dart:746` (AFFECTED); plus
  `grid_cli/lib/src/traj_legacy_session_reader.dart:142`, the deliberate legacy oracle,
  which stays. E8's adoption set GAINS the sweep: either the candidate's state is routed
  through the fold under primary, or `running` does not retire until it is. It is a W2-A
  gate item rather than a wave-1 one, but it is named here because E8 is the criterion that
  owns "every cursor consumer adopts a fold read BEFORE any retirement".
- **Carrier.** tg-6zan (open, approved; wave 1) — the fence union and the two-live-group AC;
  the lease sweep's adoption rides W2-A with the retirement it gates.

### E9 — schema half of `[fold-fidelity B1]`: retired-rework P1 rows stay open forever

- **Was.** `roundRetired` bumps round only; open-retired rows accrete per rework; a
  head-closing record may be wanted; F-m5's P6 eviction bound rides on it.
- **Tree.** `AttemptRoundRetired` → round bump only
  (`grid_trajectory/lib/src/fold/session_head_delta.dart:217-220`); the schema says so
  (`trajectory-schema.md:215`). The r5 winner rule already makes retirement legible (§0.2).
- **Ruled.** Q9 (`wave-2-entry-criteria-rulings`): accept the shape; no head-closing
  record; accretion fixed at its source (the missing terminals, tg-ffl6); P6 eviction
  bounded on `last_seq` age, never on "open in P1".
- **Design (r6).** P6's `last_seq` is a real column
  (`trajectory_schema.dart:264`); the W2-A P6 mirror evicts rows whose `last_seq` is older
  than the mirror's retention horizon (a count of records, r6 default 50,000 ≈ one lunar
  week at the measured rate — **r6 design, not ruled**) **AND whose `worktree_state` is not
  `live`**. ONE predicate, stated once (verify-1 — the first draft said "regardless of P1
  status" here and "never evicts a live row" in W2-A's test plan; both cannot hold): a
  `worktree_state='live'` row with a stale `last_seq` IS the stranded-worktree class Q9
  bounded, and is exactly the row W2-B's barrier refuses on, so evicting it would disarm the
  barrier for the one case the barrier exists to catch. Live rows are therefore deliberately
  UNBOUNDED by the horizon and bounded instead by the tick reap, whose zero-stranded-worktrees
  count is already a W2-C gate. Neither arm keys on "open in P1", so Q9 holds.
  **Correction (verify-1):** the first draft claimed "§W2.5 scopes [the epoch-50 residue of
  52 `retirementLag` entries] out of the gate". It did not — §W2.5's table gated
  `retirement_lag_open = 0` UNSCOPED, against a measured open residue of 63. §W2.5 now
  scopes the lag rows to the soak window exactly as it scopes the miss rows, and that is the
  row this residue is read against.
- **Carrier.** tg-ffl6 (source fix, landed); W2-A (the bound).

### E10 — `[W2-E]` `GRID_INSTANCE_TOKEN` retirement

- **Tree.** Still dual-exported: `capability_host.dart:405` (token; the "stays: Stage 1
  dual-exports, and retiring the token is a cut change" comment at `:411`) and `:413`
  (`GRID_ATTEMPT_ID`); the minter is `grid_runtime/lib/src/runtime/incarnation_env.dart`
  (`:35` mint, `:57`, `:69`); consumers `grid_engine/lib/src/sdk/allocation.dart:724`,
  `grid_engine/lib/src/molecule/station_process_transport.dart:70`; the fields
  `grid_engine/lib/src/sdk/cursor.dart:42`,
  `grid_engine/lib/src/domain/session_projection.dart:79`, `session_bead.dart:45`
  (written `:525`, read `:494`).
- **Ruled.** None needed (the worksheet asked for none). Stays in wave 2, LAST — a
  bd-write vocabulary change that buys nothing before the cut.
- **Carrier.** W2-E, behind W2-D's gate.

## W2.2 THE KEPT-WRITES TABLE — the named §9 exception (Q5, Q10)

Schema §9's rule: a record-type group "cuts whole, never per-field, never dual-written"
(`trajectory-schema.md:1301-1302`). Q10 admits EXACTLY ONE exception, named here and
nowhere else. The `StepState` vocabulary is `{pending, running, ready, complete, failed,
gated}` (`grid_engine/lib/src/sdk/circuit.dart:46-68`); the recorder's step records are
`stepRunning` (`grid_runtime/lib/src/trajectory/station_trajectory_recorder.dart:1151`),
`stepReady` (`:1183`), `stepComplete` (`:1212`), `stepFailed` (`:1268`), `stepGated`
(`:1302`), `stepRearmed` → `pending` (`:1333`, `:1348`).

| Step write | Site(s) | Facts the ONE map carries beyond `state` | Census share | r6 disposition |
|---|---|---|---|---|
| `running` | `capability_host.dart:684-688` (`_persistStarted`, `:673`) | `startedAt`; `restartCount` as a COPY of the node's value (`_moleculeMetadata`, `:651-671`); AND the `spawned` input the lease sweep reads RAW (`process_lease_vendor.dart:746-748` — E8) | 8,764 / 18,796 (47%) of RECORDS (below that in bd writes — see the note under this table) | **RETIRES under cut (Q5), behind the lease sweep's adoption (E8).** The acked `stepRunning` (`:693`) is the transition; P2 carries `started_at`. |
| `pending` | `session_scope.dart:1566-1569` (`_rearm`) | none — state only | 104 (0.6%) | **RETIRES under cut (Q5).** The acked `stepRearmed` (`:1574`) is the transition (the I-14 kill). |
| `gated` | `capability_host.dart:940-945` (exhaustion park: `restartCount: attempts`, `failureReason`); `:1057-1062` (route-escalate park: `ResultKeys.routeVerdict`); `session_scope.dart:1291` (whole-node re-projection); all through `persistRaisedEscalation` `:105`/`:135` | the EXHAUSTED breaker count (sole carrier — the park RETURNS at `:857-865`, before the `failed` write at `:869-877`); the route verdict result key | 288 (1.5%) | **UNDETERMINED UNTIL THE Q5/Q10 AMENDMENT IS RULED — and the amendment GATES W2-A and W2-C** (verify-1). *If amended:* KEPT with `complete`/`failed`, uniform rule, 1.5% of churn forgone. *If declined:* `gated` retires as Q5 says, and the exhausted `restartCount` and the route verdict each need a SECOND CARRIER designed and built before that branch is written. The gate BEAD (`createGate`, `:145`) is a separate bd write and KEPT either way. |
| `ready` | `capability_host.dart:710-719` (`_persistReady`; rendezvous payload merged via `nodeResultMetadata`) | `grid.result.*` (the daemon's published endpoint, read pull-free by dependents — D-5) | 0 in the measured window — daemon steps only. It IS a `step.transition` state (`stepReady`, `station_trajectory_recorder.dart:1183-1201`; the P2 enum lists it, `trajectory_schema.dart:174`); the census simply had no row for it (verify-1 wording fix) | **KEPT, pending the same Q5/Q10 amendment** (r6 design, not ruled — unnamed by Q5; same one-call-one-map shape as `complete`). |
| `complete` | `capability_host.dart:738-745` (`_persistComplete`) | `grid.result.*` (grade, pr_url — the rework cap's evidence and the route step's input) | 9,062 (48%) | **KEPT until Stage 2/4 (Q5).** |
| `failed` | `capability_host.dart:869-877` (`_persistFailureClassed`, `:839`) | `restartCount: next`, `cooldownUntil`, `failureReason` — the tg-0zq8 breaker (R11) | 578 (3%) | **KEPT until Stage 2/4 (Q5).** R8 and R11 are the same write; "R11 KEPT" is now consistent because R8 does not retire this site. |

Session-family writes (R1–R7, the re-keys, the gate sweep inputs) stay KEPT exactly as the
MOVED-OUT table below states; wave 2 adds ONE session-bead key at mint —
`grid.session.discipline` — beside the existing `SessionBeadKeys` vocabulary
(`session_bead.dart:40-50`), written by `createSession`
(`grid_runtime/lib/src/lifecycle/station_bead_writer.dart:301`), because the quiesce rule
(W2-A) needs to know a session's write era from the ledger alone.

**What this buys and what it does not.** The retiring set is 47–49% of `step.transition`
RECORD volume — the churn motive's largest single site. **The bd-WRITE share it removes is
strictly smaller (verify-1).** The 8,764 is a census of `step.transition(running)` RECORDS,
and the recorder emits a SECOND, inferred running record from `stepComplete` when no running
transition was remembered (`site: 'stepRunningBeforeComplete'`, provenance `inferred`,
`station_trajectory_recorder.dart:1225-1245`) which corresponds to no `_persistStarted` bead
write at all. "One write per process start" is the right shape and an overstated number;
re-measure the retiring set by distinct `site='stepRunning'` records before quoting a
percentage at anyone.
The `complete`/`failed`/`ready`/`gated` half keeps its bead and its per-step dolt commit
until Stage 2/4; the audit's "half the win" is the honest description.

## W2.3 CARRIED MAJORS — adjudicated

| Finding | r6 disposition (verified) | Ruling / bead |
|---|---|---|
| O-M1 / F-B3 | `_persistFailure` stays private and is never the ack-failure route. Under narrow the ONLY decision-bearing step appends are `stepRunning` and `stepRearmed`; their `Dropped`/`Suppressed` halt (E2), so no site needs a path into the breaker. `_rearm` gets its own gate under cut. | Q3; tg-ppo5 |
| O-M2 | Storm budget = the halt: no new mounts until the operator clears it; one gate, ONE flare — its OWN, `trajectory.admissionHalted`, never the harness's `trajectory.halted` (verify-1: that one fires under `_latchHalted`'s `_latched` guard and suppresses every subsequent append, `trajectory_harness.dart:1655-1664`) — and running sessions drain. The gate SEAM is not `createGate` for the terminal class or for a station-wide halt (E2); a station-scoped gate on `StationBeadWriter` is WANTED and UNFILED. A blip under cut is one bounce, never a demotion storm. | Q3; tg-ppo5 |
| O-M3 | Abort/flip-back = the same halt, operator-invoked: freeze admission → drain to zero open cut-era sessions → `down` → boot `shadow`; the quiesce check refuses a shadow boot while any `grid.session.discipline=cut` session is open. One rule, both directions (W2-C). A StationControl verb to invoke the halt is wanted and UNFILED. | Q2 (rollback pre-cut only); W2-C |
| O-M4 | W2-D gets its own gate: three clean boots UNDER CUT on the §W2.5 table plus a stranded-worktree count of zero from the reap obligation, plus operator ratification of the deletion set. | W2-D |
| O-M6 / C-M5 | `mountAttemptId` is NOT nullable — required by the record (`admission_records.dart:218-225`) and the envelope (`:233-238`, "minted per admission evaluation — grant OR refusal"); the barrier mints one per evaluation through the authority's existing minter without writing a reservation (reservations are grant-side, `station_admission_authority.dart:623-642`). `substation` is SERVICE-DERIVED from the store prefix — the envelope's own words at `grid_trajectory/lib/src/codec/envelope.dart:107-110` ("service-derived from the store prefix — §2.6 rule 7"), which is the same value the seat config carries as `substationConfig.substationId` (`grid_engine/lib/src/domain/substation_config.dart:17`, referenced at `work_list.dart:48`); the first draft cited `work_list.dart:304`, which is the RESIDENT clause and names no substation (verify-1). **`snapshotRev` is UNRESOLVED and the first draft's substitution is withdrawn (verify-1).** Q7 says "`snapshotRev` from the joined snapshot the authority evaluated"; `JoinedSnapshot` carries no revision (`grid_engine/lib/src/domain/joined_snapshot.dart` — no `version`/`rev` field) and the bridge mints none. `snapshot_version` is NOT that value: it is `TrajectoryHeadSnapshot.version`, whose own dartdoc reads "Bumped on every published change" (`grid_engine/lib/src/domain/trajectory_views.dart:174-176`) — the P1 MIRROR's publish counter, which churns on every fold apply and would re-key `refused:<bead>:<clause>:<snapshotRev>` on an unchanged basis while missing a changed bd basis whose mirror did not move. That destroys the level shape the ratified key exists for. The design is therefore: source `snapshotRev` from a BEAD-SCOPED ELIGIBILITY BASIS REVISION — a bridge-side value that changes only when the joined snapshot's content for THAT candidate changes — which does not exist and must be added. **Carrier: UNFILED; file it with the comparator bead, ahead of W2-B.** Until it exists, W2-B keeps the 30 s per-bead dedupe (below) and `admission.refused` is not decision-bearing (M-6/E2). If no such revision can be built before the flip, Q7 re-opens rather than being satisfied with a fold-side counter. | Q7; W2-B |
| O-M7 | ONE site: `GRID_G1_BREAK_GLASS` is resolved into the config at assembly, in the same resolution step as E1's implication, BEFORE any posture read; the two bypass targets — the `CutPostureRefused` check and the quiesce check in `StationWorkRuntime.start()` — read the RESOLVED discipline only. | Q11; W2-A |
| F-M4 | Disclosed as the cut's price: `appendAcked` inverts stage1-wiring §2.5's "enqueue, never await" (`stage1-wiring.md:41`, `:406-412`) at exactly the named decision-bearing sites and nowhere else. Budget (r6 design, not ruled): one ack = one serialized transaction COMMIT (`trajectory_appender.dart:218`/`:656`); the probe-anchored basis is ~23 ms fenced + one projection (`trajectory-schema.md:1689-1691`); the soak measures an `append_ack_p99_ms` counter (to add beside `append_queue_depth`, `session_head_read.dart:125`) with a p99 ceiling of 250 ms; a breach is a soak FINDING to fix, never a halt. **The BUDGET is not the runtime defence (verify-1):** `appendAcked` also carries a DEADLINE of one tick interval whose breach completes as `Dropped` and so rides the E2 halt (E5). Without it "always completes" bounds nothing and a degraded-but-live harness stalls every process start. Stage-0 measurement 3 (under bd load) is thereby finally run. | Q3; tg-ppo5 (counter unfiled) |
| F-M5 | Does not arise under narrow: `complete` stays a KEPT bd write with a fire-and-forget append; nothing routes a complete-ack failure anywhere. Re-opens only if Q5 is ever widened to "whole". | Q5 |
| F-M6 | Put to the operator as an EXCEPTION and ruled as one; §W2.2 names the set and cites Q10. | Q10 |
| C-M1 | `appendAcked` on the recorder for the named sites only; the recorder's surface stays `void` everywhere else (tg-ppo5 AC-4 pins it). | Q3; tg-ppo5 |
| C-M2 | TWO refusals, two sites (verify-1 — the first draft made them one): the REQUESTED-posture disagreement is a pure config predicate validated at ASSEMBLY, before any mutation (`start()` sets `_started = true` on its second line, `work_assembly.dart:264-266`, and its idempotent early return makes a caught-and-retried refusal boot cut silently); the harness-not-`live`-under-cut refusal stays post-`start()` (`:273`), LATCHES so a retry re-refuses, and states its unwind. Both are typed and both MUST propagate out of `start()` and abort the boot — a runner that swallows them is out of contract. The harness itself still never throws (`trajectory_config.dart:16-18`). | Q2; tg-rcm3 |
| C-M3 | Schema §7 drops "escalation/void/decline merges" from the head (`trajectory-schema.md:1224-1225`) while R2/R7 stay KEPT at Stage 4 (G1b). Amendment: §7's drop row reads "at Stage 4, with R2/R7"; the held derivation lives on the KEPT stamps until then. The amendment text rides the W2-A PR (this round edits cut-wiring.md only). | tg-dme1's closing sentence ("adjudicated as written there"); W2-A |
| C-m4 | First-boot order restated on the actual `start()` sequence (`work_assembly.dart:264-304`), with the posture check moved OFF it (C-M2): **assembly: resolve discipline + break-glass, then the requested-posture check** → `_sourcesStart` → `trajectory.start()` (`:273`) → **harness-not-`live` check** → `_freshnessBarrier` (`:280`) → `reconcile` (`:281`) → `replayTeardownTail` (`:300`) → **quiesce check** → `_driver.start()` (`:304`) → the caller's `runGrid`. The quiesce check runs AFTER the teardown replay so a session finished off mid-teardown does not count as open. | Q2; tg-rcm3 (posture) / W2-A (quiesce) |
| C-m2 | Still true: `settleSessionForTerminalWork` (`station_bead_writer.dart:463`) makes no recorder call; the settled terminal is appended by `UnknownTerminalSettlementObligation` (`stage1_obligations.dart:188`, provenance `inferred` `:273`), not at the writer stage1-wiring `:317` names. Doc fix to stage1-wiring §2.3 rides the W2-A PR. | standing doc gap; W2-A |
| F-m3 | NOT dissolved — reduced to a doc edit W2-B must MAKE, not cite (verify-1, correcting the first draft's "they already agree"): `trajectory-schema.md:1371-1373` and `:1892-1897` still carry standing Stage-3 text for the `admission.refused`/`.restored` family; `:1936-1942` (the 2026-08-31 Stage-1 build amendment) supersedes it with "arm together at the **cut**". W2-B strikes the superseded clause at the first two sites. | Q7; W2-B |

## W2.4 THE CHUNKS — corrected designs

### W2-A (old C5) — Cut posture + quiesce + break-glass + acked appends + the P6 mirror/tick reap

**Buildable now:** the lever (tg-rcm3) and the breaker (tg-ppo5). **Gated on the §W2.5
certificate:** everything that branches a write. **Also gated, on a RULING rather than the
soak (verify-1):** the write-branch half waits on the Q5/Q10 amendment that disposes `gated`
and `ready` (E4), because until it is ruled the retiring set is undetermined. **Also gated
on two UNFILED carriers named in this round:** the station-scoped gate seam the breaker's
gate half needs (E2) and the bead-scoped eligibility basis revision W2-B's refusal key needs
(§W2.3 O-M6/C-M5).

1. **The lever (E1/Q2).** `TrajectoryConfig.discipline {shadow, cut}` as E1 states it;
   `cut` ⇒ `dualRead: primary` + `mode: required`, resolved once, and `asDisabled` forces
   `discipline: shadow` so a dry arm is never cut (E1's dry-arm rule). TWO refusals, two
   sites (E1/C-M2): the requested-posture disagreement is validated at ASSEMBLY before any
   mutation; the harness-not-`live`-under-cut refusal sits after `trajectory.start()`
   (`work_assembly.dart:273`), latches so a retry re-refuses, unwinds by shutting the
   trajectory down and releasing the epoch, and rethrows. Both MUST propagate out of
   `start()` and abort the boot.
2. **The session stamp.** `createSession` (`station_bead_writer.dart:301`) writes
   `grid.session.discipline` = the resolved discipline. A session with no stamp is
   shadow-era.
3. **The quiesce rule, both directions, placed (C-m4).** After `replayTeardownTail`
   (`work_assembly.dart:300`), before `_driver.start()` (`:304`): a `cut` boot refuses
   while any OPEN session bead lacks `discipline=cut` (its step facts live on a carrier
   the cut no longer writes — the operator drains under shadow first); a `shadow` boot
   refuses while any OPEN session bead carries `discipline=cut` (its `running`/`pending`
   facts were never written to the bead — a legacy read would re-run its nodes). Typed
   `DisciplineQuiesceRefused`, naming the offending session ids.
   **The carrier, named (verify-1).** `grid.session.discipline` is bead METADATA and
   `SessionProjection` has no metadata map (`grid_engine/lib/src/domain/session_projection.dart`
   is a freezed value with named fields only) — so the check reads the SESSION BEADS off the
   reconciler's fresh STATE snapshot, exactly the way the lease sweep builds its candidates
   (`restart_reconciler.dart:1055-1063`), not off a projection. It is a read, never a write,
   and it needs no new projection field.
   **The scope, picked (verify-1).** The predicate quantifies over EVERY open session bead
   on the station, not only the target seats: `discipline` is one station-wide config value
   (`trajectory_config.dart:54-67`), so a single long-open session on a non-target seat —
   the_grid's own included, which Q1 forbids driving — refuses the cut boot until it is
   drained or voided. W2-C's checklist is corrected to match: the drain covers every attached
   seat, and un-stamping the non-target seats only stops NEW work mounting there.
4. **Break-glass (Q11, O-M7).** `GRID_G1_BREAK_GLASS=<reason>` (the name is r2's; the
   space half may rename the env) is resolved at assembly into the config BEFORE any
   posture read: it forces `discipline: shadow` for the boot and carries the reason. Both
   bypass targets (items 1 and 3) read the resolved value. A break-glass boot with
   cut-era sessions open does NOT run them under legacy reads: it VOIDS them first (the
   E3 runbook's step 4, automated for this case — their processes are dead, the fence
   triple is on the KEPT carrier), stamping each `grid.voided_reason`
   (`session_bead.dart:89`) as `break-glass:<reason>`. Loud provenance: the banner line,
   one `trajectory.breakGlass{reason, voided}` flare, `grid.session.break_glass=<reason>`
   on every session minted in that boot, and an `attempt.note(channel='break-glass')` on
   each such session (`AttemptNote` requires a session id — C-M4 — so the note rides the
   sessions, exactly like the round summary). The archaeology guard — the stamp keys and
   the quiesce refusal that reads them — is PERMANENT (W2-D never deletes it). **Break-glass
   is DESTRUCTIVE by construction and is not a debugging boot (verify-1):** the void-on-entry
   rule means every in-flight cut-era session is voided and re-driven from bd, so it is a
   break-the-glass posture in the literal sense. **And what it means AFTER W2-D (verify-1 —
   r6 design, not ruled, and part of what O-M4's ratification covers):** W2-D deletes the
   `shadow` write arm at the retired sites, so post-W2-D there is no legacy step writer for a
   shadow boot to use and "forces the surviving `shadow` posture" buys nothing. Post-W2-D,
   `GRID_G1_BREAK_GLASS` selects no write posture at all: it is an ADMISSION-FROZEN
   archaeology boot — void the cut-era sessions on entry, mount nothing, keep the stamps, the
   flare, the notes and the quiesce refusal — and the deletion set must be read with that
   exception in it. **r6 design, not ruled:** the void-on-entry rule, the stamp names, and
   the post-W2-D meaning.
5. **Acked appends and the R-set branches (E2/E5/Q3, Q5).** Under `cut`:
   - `_persistStarted` (`capability_host.dart:673`) skips the bead update (`:684-688`) and
     awaits `appendAcked(stepRunning)`; `_rearm` (`session_scope.dart:1525`) skips
     `:1566-1569` and awaits `appendAcked(stepRearmed)`; the three session terminals
     (`session_scope.dart:724`/`:854`/`:971` voided, `:1216` completed, `:1684`
     escalated) await their ack AFTER the KEPT bd close, exactly as today's order. Every
     other recorder call stays `enqueue` (C-M1).
   - `Acked` ⇒ continue. `Dropped`/`Suppressed` ⇒ the HALT (E2): admission latched, the
     gate minted through whichever seam the class allows (E2 — step class through
     `createGate`, terminal class and station-wide through the UNFILED station-scoped seam),
     `trajectory.admissionHalted{reason, recordClass}` flared, no retry, no demotion. The
     running session continues to ITS terminal; its terminal's bd close is KEPT, so
     tg-ffl6's obligation repairs a lost terminal ack on the next healthy boot. Every
     accepted request completes exactly once, including one destroyed by a later latch
     (E5's lifecycle contract), and an ack that misses its one-tick deadline completes as
     `Dropped`.
   - **`running` does not retire until the LEASE SWEEP adopts a fold read (E8).** Its
     `spawned` derivation reads the step bead's state raw (`process_lease_vendor.dart:746-748`
     over `restart_reconciler.dart:1055-1071`), and a `pending`-reading bead silences the
     loud unfindable-process-group report. Adopt, or keep the write.
   - `complete`/`failed`/`ready`/`gated` sites are untouched (§W2.2) — subject to the Q5/Q10
     amendment: if it is DECLINED, `gated` retires and its two sole-carrier facts need a
     second carrier designed first.
   - Under `shadow` every site is byte-identical to today (tg-ppo5 AC-7; tg-rcm3 AC-6).
6. **The P6 mirror + the tick worktree reap (single home, O-B4).** Wave 1 built no P6
   mirror; W2-A seeds one from `proj_process_identity`
   (`trajectory_schema.dart:254-268`; `worktree_state` at `:262`, `last_seq` at `:264`),
   maintained post-ACK like P1/P2 (§0.2), evicted on `last_seq` age AND
   `worktree_state != 'live'` — E9's single predicate; live rows are unbounded by the
   horizon by design and bounded by the reap below. Under cut the
   inline reap in `_completeAndClose` (`session_scope.dart:1153-1185`) branches OUT and a
   tick obligation reaps: for each P6 row `worktree_state='live'` whose session is
   TERMINAL — P1 `status='closed'` OR the ledger says closed (`SessionClosureProbe`,
   `stage1_obligations.dart:84` — Q6's input) — reap through the `ReapWorktree` seam
   (`session_scope.dart:80`, `:126`), then append `worktree.reaped`/`worktree.held` keyed
   on disk state, exactly the shape `WorktreeReapedBackfillObligation`
   (`stage1_obligations.dart:462`; SQL `:479-486`) already runs for the record-only half —
   its dartdoc names the live reap as "the CUT's live-reap obligation" (`:459-461`). Under
   shadow the backfill obligation keeps running and the inline reap keeps reaping.
7. **The restore runbook (E3/Q4)** is W2-A's operator text, verbatim from E3.
8. **Docs riding the PR:** the §7 amendment (C-M3), the stage1-wiring §2.3 settle row
   (C-m2), the §9 exception cross-reference to §W2.2 (Q10), the `required` contract line,
   the break-glass ladder, and — **BLOCKING (verify-1)** — the one-word Q6 amendment on
   `inferred`/`reconstructed` (E6-a) plus the Q5/Q10 amendment on `gated`/`ready` (E4).

**Test plan (additions to tg-rcm3/tg-ppo5's ACs):** quiesce both directions with stamped and
unstamped fixtures; break-glass voids cut-era sessions and stamps every listed key; a
lost `stepRunning` ack halts admission while the running session still reaches its
terminal and the bd close lands; the tick reap reaps a P6-live row under a ledger-closed/
P1-open head (the 90 s grace) and never a row whose disk path is gone; P6 eviction fires on
`last_seq` age only for a non-`live` row and never on a `live` one (E9's single predicate);
a request queued at `live` and destroyed by a later latch completes `Suppressed` and leaves
no pending future; an ack past its one-tick deadline completes `Dropped` and halts; a dry
arm (`asDisabled`) resolves to `shadow` and refuses nothing; a caught-and-retried
`CutPostureRefused` re-refuses instead of no-opping; the lease sweep still raises its loud
orphan report for a spawned step under cut; shadow-posture parity suites unchanged.

**Rollback:** pre-flip, `discipline: shadow` = today (the wave-1 story). Post-flip, W2-C's
flip-back — never a `dualRead` demotion.

### W2-B (old C6) — The worktree-outstanding barrier (P6 + P1 + ledger consumer)

Synchronous mount-eligibility clause over the ambient P6 + P1 mirrors and the joined
snapshot at both `composeMountEligibility` sites (`work_list.dart:303`,
`station_admission_authority.dart:671`): REFUSE when the candidate bead has any P6
`worktree_state='live'` row whose session is terminal — **P1 `status='closed'` OR the
joined projection's `isTerminal` (the KEPT ledger close; Q6)** — with
`clause='worktree-outstanding'`.
**The join and its multiplicity rule, stated (verify-1).** P6 carries NO work-bead column
and no index on one (`proj_process_identity`, `trajectory_schema.dart:254-268`: PK
`attempt_id`, `KEY ix_session`, `KEY ix_worktree`), so "the candidate bead has a P6 live
row" is a JOIN — P6.`session_id` → P1.`session_id` → P1.`work_bead_id`, served by P1's
`ix_bead` (`trajectory_schema.dart:52`) — evaluated synchronously inside a clause. And under
E9's ACCEPTED open-retired shape one bead legitimately owns MANY P1 rows across rounds, so
the multiplicity rule is decision-bearing and is fixed here: **every P1 row for the bead
counts, retired rounds INCLUDED** — a stranded worktree on a retired round is exactly the
class the barrier exists to catch, and excluding it would reintroduce the window. If the
join proves too costly in the clause, the alternative is a derived bead key on the P6 mirror
at seed time; that is a build choice, not a semantics choice. The OR is what makes "read P1 once its input is complete"
true at every instant: during the 90 s heal grace the ledger half fires; after the heal
both do. Staleness: the clause reads the tick-stamped mirror `heartbeatAt`; it fails
CLOSED only when the harness itself is wedged (no beat for three tick intervals — the same
90 s the heal uses), and an idle-healthy station admits. **The refusal record (E7/Q7):**
`admission.refused` through a NEW recorder derivation (none exists today — verified),
armed ONLY under `cut` (`trajectory-schema.md:1936-1942`), with the RATIFIED key
`refused:<bead>:<clause>:<snapshotRev>` (`admission_records.dart:269-270`),
`mountAttemptId` minted per evaluation, `substation` service-derived from the store prefix,
and `snapshotRev` from a bead-scoped eligibility BASIS revision that **does not exist yet and
is UNFILED** (O-M6/C-M5 in §W2.3 — the first draft's substitution of the P1 mirror's publish
counter is withdrawn). Consequently the 30 s per-bead dedupe r2 wanted is **KEPT** until that
revision lands: the "the level-shaped key dedupes an idle ineligible bead by construction"
argument (`trajectory-schema.md:269`) holds only for a LEVEL-shaped `snapshotRev`, and a
churning one would mint a fresh non-dedupable record per candidate per
`composeMountEligibility` pass, overflow the 4,096-deep queue
(`kDefaultTrajectoryQueueBound`, `trajectory_config.dart:40`; the drop at
`trajectory_harness.dart:1200`) and — were the refusal decision-bearing — halt admission
station-wide. It is not decision-bearing (E2/M-6), and it does not arm until the basis
revision exists. Restoration appends `admission.restored` (`admission_records.dart:320-321`) when
the P6 row flips to `reaped`.
**AN OBSERVE-FORM COUNTING ARM, SO THE FLIP IS NOT THE CLAUSE'S FIRST EXECUTION (verify-1 —
r6 design, not ruled).** Every wave-2 mechanism keys on `discipline == cut`, so without this
the acked appends, the two write retirements, this barrier, the new refusal derivation and
the tick reap ALL execute for the first time in the same boot, on the target seats, with a
rollback that has itself never run. So: under `shadow` the clause IS composed, in OBSERVE
form — it evaluates its predicate and COUNTS would-refuse decisions on the round summary,
and changes eligibility not at all and emits no `admission.refused` record (which stays
armed at the cut, per the schema's 2026-08-31 amendment). Stage 1's "changes NOTHING about
what mounts" headline is untouched by a counter. Its count is a §W2.5 row, reported not
gating, and the flip boot is then the SECOND time the clause runs.
**Gated on the §W2.5 certificate**, and on the unfiled basis revision above. Doc fix: strike
the superseded Stage-3 clause at `trajectory-schema.md:1371-1373` and `:1892-1897` and point
both at `:1936-1942` and at this appendix (E7 — they do NOT already agree).

### W2-C (old C7) — THE FLIP (default discipline → `cut`)

One small PR: `TrajectoryConfig.discipline` default `shadow` → `cut` — which by E1's
resolution ALSO makes `primary` + `required` the default; no second lever to flip (O-B1
closed). **Pre-flip evidence pack:** the §W2.5 certificate (three clean primary boots on
lenny + butane with shape coverage) ∧ W2-A ∧ W2-B landed with their suites ∧ one
break-glass drill on the scratch home (boot cut with a cut-era session open, break-glass
in, verify the void + stamps) ∧ one restore drill on the scratch home (the E3 runbook end
to end, verify zero re-drive of completed work) ∧ `traj show` lifecycle sample ∧ **the
Q5/Q10 amendment on `gated`/`ready` RULED** (E4 — without it the retiring set is
undetermined and W2-A's branch list is unfixed) ∧ **the Q6 one-word amendment on
`inferred`/`reconstructed` ruled** (E6-a) ∧ **zero open shadow-era sessions ANYWHERE on the
station, not only on the target seats** (verify-1: the quiesce quantifies over every open
session bead, so one long-open session on a non-target seat refuses the boot) ∧ the barrier
clause's observe-form counters from the shadow boots (W2-B).
**First-boot sequence (C-m4):** exactly `StationWorkRuntime.start()`'s order as §W2.3
states it; the operator watches for `CutPostureRefused`/`DisciplineQuiesceRefused` in the
banner, then the first `dual-read-round-summary` note with `discipline=cut`. **Soak gate
under cut (feeds W2-D):** three clean boots on the §W2.5 table with `discipline=cut`, one
deliberate bounce, zero stranded worktrees (the reap obligation's counters), zero
unplanned halts, gates closing at terminal as today. **Rollback (O-M3):** invoke the halt
(the Q3 breaker, operator-triggered — verb unfiled; until it exists, `down` at the next
idle fixpoint is the manual form) → drain to zero open cut-era sessions → `down` → boot
with `discipline: shadow` (env or config) → the quiesce check passes because nothing
cut-era is open; closed cut-era sessions read terminality first
(`session_disposition.dart:86`), so their missing `running`/`pending` bead facts are
never consulted, and their KEPT `complete`/`failed` facts make rework under shadow
work. Drain is observable in bd because terminal facts are KEPT. **Gated on the §W2.5
certificate; dies with the kill date (§W2.6).**

### W2-D (old C9) — The stated deletions

Only after W2-C's OWN soak gate (three clean boots under cut, above) AND operator
ratification of the deletion set (O-M4). Deletion set = the `running`/`pending` posture
branches at their two sites + the inline-reap branch + the `shadow` arm of `discipline` at
those retired sites + the step-axis divergence compare for the retired states.
**What break-glass means once that arm is gone (verify-1 — the first draft said it "forces
the surviving `shadow` posture for one boot", which after this deletion buys nothing: there
is no legacy step writer left for a shadow boot to use).** Post-W2-D `GRID_G1_BREAK_GLASS`
selects no write posture. It is an ADMISSION-FROZEN archaeology boot: void the cut-era
sessions on entry, mount nothing, and keep the stamp keys, the flare, the notes and the
quiesce refusal — all of which stay PERMANENT and are explicitly OUTSIDE the deletion set.
The quiesce does simplify to one direction (there is no shadow era left to refuse into), and
the grep pin is restated accordingly: no `discipline == shadow` branch survives at a RETIRED
WRITE SITE — the break-glass and quiesce paths are not retired write sites. The session-axis compare STAYS
(bd session facts still legacy-written; it is G1b's future evidence stream) and so does
the compare for the KEPT step states. Teardown replay, `sessionsAwaitingTeardown`
(`restart_reconciler.dart:614`, `:623`) and every terminal-write site are NOT deleted
(moved out). The boot-time `_reconcileWorktree` reap (`restart_reconciler.dart:901`,
`:1359`) is the W2-D-review call (r1 FINAL Q5): belt over the tick's suspenders.

### W2-E (was wave-1 C8b) — `GRID_INSTANCE_TOKEN` retirement (last)

`attempt_id` becomes the freshness fence. Sites as E10 verifies them:
`capability_host.dart:405` export + the `:411` comment; `allocation.dart:724`;
`station_process_transport.dart:70`; `incarnation_env.dart` (`:35`, `:57`, `:69` — mint +
env key deleted). Token fields on `cursor.dart:42`, `session_projection.dart:79`,
`session_bead.dart:45` (`:494`/`:525`) retire with their freezed regens — a bd-write
vocabulary change, which is WHY it is last — with the E3 restore runbook's fence sentence
RE-CUT onto `attempt_id` in the same PR (verify-1: step 4 describes a pgid/pid/token triple
that this chunk retires) — with the adopt-fence and `_staleFencesAreDead`
suites proving adoption/refusal and the void-remint fence check on `attempt_id` equality
FIRST. Source pin: `GRID_INSTANCE_TOKEN` absent from `packages/*/lib`. Behind W2-D.

## W2.5 Q1 — THE CUT SIGNAL, SCOPED, and the soak certification table

**Why the ruling's wording is unreachable.** lunar epoch 50's boot-final summary
(`.grid/seats/governor/first-true-observe-boot-epoch-50.md` in lunar_station): `fallbacks
632`, `miss_legacy_era 601`, `miss_post_epoch 8`, `p1_orphan 11`, `terminal_lag 257
(open 20)`, `retirement_lag 63 (open 63)`, `cardinality_breaches 23`; the cumulative
counters on the first post-terminal note (`passes 177`): `divergences 74`, `unexplained 73`,
by field `retirementLag 52` (legacy retired rounds — the Q9 shape), `terminalLag 20` (heads
with no terminal — the heal's class), `isTerminal 1`, `completed 1` (operator edit). 601
sessions predate the trajectory and will NEVER fold; the 52 are open-retired legacy rounds
the heal skips by rule (Q9). As worded, "fallbacks 0 + unexplained 0" is unreachable by
construction.
**The fallback taxonomy, re-derived from the tree (verify-1 — the first draft wrote
`fallbacks 632 = miss_legacy_era 601 + miss_post_epoch 8 + p1_orphan 11`, which is wrong
twice).** `fallbacks` has THREE increment sites and `p1Orphan` is not one of them:
(1) the health-disengage arm, `fallbacks += sessions.length` — the whole boot demoted to
legacy (`dual_read_pass.dart:179`); (2) the P1 MISS, classified `legacyEra`/`postEpoch` only
(`:204-214`); (3) the CARDINALITY class, `fallbacks += 1` per comparison
(`session_head_read.dart:883-884`). `p1Orphan` is bumped on a different arm entirely
(`dual_read_pass.dart:369`) and is a separate gauge. So epoch 50 reads
`632 = 601 legacy-era + 8 post-epoch + 23 cardinality-class`, with `p1_orphan 11` beside it
and NOT inside it. The safety argument below is stated against that taxonomy, so a reader
can audit the gate rows against it.

**The scoped signal (r6 design, not ruled — an amendment to Q1's wording is requested).**
Two facts make the scoping SAFE rather than convenient: (1) the cut retires WRITES going
forward; every fact written before the cut stays on its bead forever, so a fallback for a
session whose writes all predate the cut reads a COMPLETE carrier — legacy-era misses
are safe under cut by construction; (2) a P1 row with no legacy counterpart never reaches
a decision (§0.2), so `p1_orphan` is inert. The UNSAFE classes are therefore THREE, one per
fallback site: a POST-EPOCH session with no P1 row (or with fold gaps) — `miss_post_epoch`
and `p2_miss`; a CARDINALITY-class fallback — `cardinality_breaches`; and a HEALTH-DISENGAGE
boot — `health`/`health_transitions`. The table gates all three (verify-1: the first draft
named only the first and called it "the ONLY class", which the tree contradicts).
**Therefore no backfill is required**: seeding pre-trajectory sessions into the fold would
add rows nobody decides on.
**THE TWO STRUCTURAL ZEROS (verify-1 — r6 design, not ruled).** `classifyDualReadMiss`
(`session_head_read.dart:591-609`) returns `legacyEra` when `legacy.startedAt == null`
(`:596-597`) AND when `firstEpochClaimedAt == null` (`:601-602`, an unseeded snapshot).
Both branches are reachable on a live POST-EPOCH session, and the second makes
`miss_post_epoch` structurally 0 for the WHOLE boot — the gate row satisfied by construction
on a boot where every decision rode a fallback. Under cut those fallbacks read a carrier
with no `running`/`pending` writer. So both become GATING rows of the table below:
`null_started_at = 0` and `first_epoch_claimed_at != null`. A null epoch anchor refuses
certification outright; it is not a class to report beside the gate. (Wave 1 was right to
keep `nullStartedAt` out of the post-epoch gate — under cut the calculus inverts, because
the fallback carrier is no longer complete.) The divergence counters need the same scoping: the comparator gains an in-window
twin of each cumulative divergence counter, scoped to heads with `head_epoch >=
soakWindowEpoch` (`proj_session_head.head_epoch`, `trajectory_schema.dart:49`), where
`soakWindowEpoch` is a new `TrajectoryConfig` field (default 0 = unscoped = today) that
the runner sets to the first epoch at which #341, #342 and tg-6zan were all live on that
home; the out-of-window residue is reported beside it as `historical`. **Carrier: UNFILED — and
it is FIRST in the wave-2 order (verify-1).** One comparator bead against
`session_head_read.dart`'s accounting (never a second accounting) carries: the in-window
divergence twins, the cumulative `miss_post_epoch_total`/`p2_miss_total` twins, the scoped
lag and cardinality rows, the `soakWindowEpoch` config field, and `append_ack_p99_ms`. It is
posture-neutral and read-side, exactly like tg-6zan, so nothing waits on it — but EVERYTHING
waits on it, because without it §W2.5 has no instrument and no certificate can be issued.
Between filing it and a soak boot lie a build, a release and a lunar adopt, against a
calendar deadline (§W2.6): file it before anything else in this wave.

**How to read.** One note per session terminal plus one boot-final note (§0.4); counters
marked `cumulative` in `kDualReadCounterSemantics` (`session_head_read.dart:73-125`)
accumulate per boot and gauges are per pass, so: read the LAST note of the boot whose
`passes > 1` (a `passes: 1` row is the boot walk, written before the comparator has
counted anything — the epoch-50 correction), never SUM the notes.
**THE GATE ROWS ARE NOT A LAST-PASS READ (verify-1 — the first draft's read rule made a
false green MANDATORY on the one row the whole flip hangs on).** `miss_post_epoch` and
`p2_miss` are declared `gauge` (`session_head_read.dart:78`, `:109`) and
`DualReadAccounting.beginPass()` ZEROES them on every join emission (`:816-829`), so a boot
in which fifty post-epoch sessions fell back mid-boot certifies clean if the last pass
happens to be quiet. The cut signal is therefore gated on a CUMULATIVE, event-deduped TWIN —
`miss_post_epoch_total` / `p2_miss_total`, deduped on `sessionId` the way `divergences`
dedupes on `noteEvent` keys (`:805-813`) — with the gauge kept as the per-pass read-out.
Same for the two lag gauges, which the table now scopes. The twins ride the same unfiled
comparator bead as the in-window divergence twins; until they exist the certificate cannot
be issued, and that is a build item, not a soak outcome (§W2.6).

**The certification table — three CONSECUTIVE clean boots, `mode=primary`, on lenny +
butane only (Q1), each boot with at least one session terminal, preceded by at least one
`observe` boot after the comparator fixes (#341, #342, tg-6zan) that classifies honestly:**

| Counter (summary key) | Axis | Gate value | Why |
|---|---|---|---|
| `mode` | — | `primary` | the served posture, `session_head_read.dart:997` (the five-number gate dartdoc at `:975-979` supports the lag/miss/overlay rows, not this one) |
| `overlay_engaged` | session | `true` | a boot that quietly rode legacy certifies nothing (`:1003`) |
| `health` | — | `live` at boot-final; `health_transitions` empty | no latch during the boot (`:797-799`) |
| `miss_post_epoch_total` (new cumulative twin) | session | `0` | THE scoped cut signal (replaces `fallbacks = 0`). The shipped `miss_post_epoch` is a per-pass GAUGE (`:78`, zeroed at `:816-829`) and is reported beside it, never gating |
| `null_started_at` | session | `0` | a null `startedAt` classifies a post-epoch miss as legacy-era (`:596-597`) — a structural zero in the signal |
| `first_epoch_claimed_at` | session | NOT null | an unseeded snapshot classifies EVERY miss legacy-era (`:601-602`), making the signal 0 by construction for the whole boot |
| `unexplained_divergences` (in-window twin) | session | `0` | replaces the unscoped cumulative |
| `divergences` by field, in-window: `isTerminal`, `completed`, `humanHeld`, `closedAt`, `disposition`, `fences` | session | `0` | the four overlaid fields + tg-6zan's two |
| `terminal_lag_open`, `retirement_lag_open`, IN-WINDOW | session | `0` at round end | lag classes zero (§0.3 gate arithmetic) — **scoped to `head_epoch >= soakWindowEpoch` like the divergence twins (verify-1)**: epoch 50 measured `retirement_lag_open 63` and `terminal_lag open 20` on legacy shapes the doc elsewhere says will never heal, so an UNSCOPED row is unreachable and the certificate could never be issued. Out-of-window residue is reported as `historical` |
| `cardinality_breaches`, IN-WINDOW | session | `0` | a real double-mount dirties the round — same scoping, same reason (epoch 50 measured 23 on legacy rows) |
| `p2_miss_total` (new cumulative twin) | step | `0` | the step-axis post-epoch miss (never omitted from `effectiveCursor`); the shipped `p2_miss` is a gauge (`:109`) and is reported beside it |
| `step_unexplained_divergences` (in-window twin) | step | `0` | C4's gate |
| `step_lag_open` | step | `0` at round end | (r5 step-axis arithmetic) |
| `append_drops`, `append_suppressed`, `append_refused_testimony` | harness | `0` | a lossy boot certifies nothing |
| `traj shadow-diff` per boot | offline | `lost_append = 0`, `unexplained = 0` in window | tg-ilug's corroborated classes (`traj_shadow_diff_command.dart:53`) |
| `append_ack_p99_ms` (new, F-M4) | harness | ≤ 250 ms, REPORTED not gating | the latency budget's first measurement (the runtime defence is the one-tick DEADLINE, E5) |
| `barrier_would_refuse` (new, W2-B observe form) | admission | REPORTED not gating | the barrier clause runs under shadow in counting form, so the flip boot is the SECOND time it executes, not the first |

**Reported beside the table, never gating:** `miss_legacy_era`, `p1_orphan`, the per-pass
`miss_post_epoch`/`p2_miss` gauges, `reconstructed_terminals`, `heals_appended`/`heals_skipped`,
`step_fold_absent`, `incumbent_adjudications`, the `historical` divergence residue, and
the compare-only columns (pgid/pid presence, `workTerminalReason`).

**Shape coverage (Q1: a checklist, driven deliberately, not a wait):** across the three
boots — at least one rework, one void, one escalation or decline, one gate-park + re-arm
cycle, and one deliberate bounce (the bounce is what proves the seed/reseed path; a boot
after it counts). Any in-window divergence: the fold is presumed wrong (incumbent rule,
except the adjudication classes), fix, restart the count of three.

**Seat scoping:** `up --substation` is append-only; the non-target seats are un-stamped
(their beads carry no `grid.approved_*`) so only lenny/butane work mounts. Never on
the_grid (Q1). **Scoping bounds what MOUNTS, not what the comparator WALKS (verify-1):**
`proj_session_head` carries every seat's history, so un-stamping the_grid leaves its legacy
rows in every counter — which is why the gate rows are scoped by `head_epoch`, not by seat.
And it does not bound the QUIESCE either: that predicate quantifies over every open session
bead on the station (W2-A item 3), so pre-existing open sessions on non-target seats must be
drained or voided before the flip boot, not merely un-stamped.

## W2.6 THE KILL DATE (Q12) and the F6 fallback

**2026-10-02** is a deadline on the WHOLE (`wave-2-flip-scope-soak-and-kill-date`, "Q12"):
the emitter fixes, the r6 design and the buildable beads may land early, and the soak ends
the moment its count criterion is met — it is not a soak length. The clock is the
calendar, not the round count.

**First, distinguish the two ways the date can pass (verify-1).** §W2.5's instruments — the
in-window divergence twins, the cumulative miss twins, the scoped lag rows, `soakWindowEpoch`
and `append_ack_p99_ms` — are UNFILED as of this revision, and between filing them and a soak
boot lie a build, a release and a lunar adopt. If what missed the date is the INSTRUMENT
rather than the FOLD — the counters were never shipped, so the certificate was never
measurable — the operator RE-CLOCKS: ship the comparator bead and set a new date. The
fallback below fires only when the instrument existed and the fold failed to certify against
it three times consecutively. The two call for opposite responses (ship the counter versus
delete the comparator), so the trigger names which one it saw.

**If the date passes without a certificate (§W2.5 not met three times consecutively):**

1. Wave 2 RE-SCOPES to "keep the bd ledger with retention" (the grid stack audit's F6
   fallback): the step-write churn is addressed on the bd side by a retention policy over
   step/molecule beads, designed then; no write retires; §9's cuts-whole rule is never
   invoked and the Q10 exception lapses unused.
2. The comparator is DELETED, not maintained: the session pass, the step pass and `traj
   shadow-diff` leave the tree; `dualRead` collapses to `off` (the wave-1 default since
   r13); the P1/P2 mirrors stay only if a read surface other than the overlay still
   consumes them (today: `traj show`, the round summaries) — otherwise they go too.
3. What STAYS regardless: the trajectory as the Stage-1 shadow-window journal (its
   writes never stopped), `traj replay`/`traj gc`/`traj show` (C0), the tick obligations
   that landed as bug fixes (#341's external-close terminal, the settlement, the reaped
   backfill), tg-rcm3's lever (inert at `shadow`) and tg-ppo5's accounting split (correct
   at every posture).
4. This document's wave-2 half is marked SUPERSEDED-BY-DATE with the retention design
   cross-referenced; the wave-1 half stands.

**If the certificate lands before the date:** W2-A's gated half, W2-B and W2-C proceed in
that order; W2-D and W2-E each behind their own gate (§W2.4), with no date of their own —
the kill date bounds the FLIP, not the deletions.

## MOVED OUT OF THE CUT ENTIRELY — named stages + blocking reasons (r2, ratified frame; r6 annotations)

| Item (r1 chunk) | Destination | Blocking reason |
|---|---|---|
| R1 terminal stamp+close, R4 settle, R6 close-half | **Stage 4 (G1b)** | gate-sweep eligibility reads closed-card + held state (`station_bead_writer.dart:372-390` at r2; **r6: drifted — the eligibility fork is now `:399-408` over `GateSweepSessionDisposition` (`:106`, rule at `:110-130`)**); the sweep must read P1 before its inputs retire — A-B1 |
| R2 escalation stamps, R7 decline merge | **Stage 4 (G1b)** — **r6: RESOLVED (C-M3) — §7's merge-drop row is amended to Stage 4, rides the W2-A PR** | `sessionHeld`/`humanHeld` safety inversion otherwise — A-B2 |
| R3 `#void-` re-key, R5 `#rN` re-key | **Stage 4 (G1b)** | rework's single-session invariant + round cap + remint fork parse the mutable key; fold-aware rework needs P5 — A-B3, B-B1, B-B2; constraint 7 |
| R11 restartCount recovery-read + persist retirement | **Stage 2** — **r6: RESOLVED (Q5 narrow) — R8 does not retire the `failed` site, so R11 stays KEPT with it (§W2.2)** | the tg-0zq8 circuit breaker — B-M2 |
| M6c head re-stamp tick obligation | **Stage 4 (G1b)** — **r6: confirmed parked by Q4** | would fight the KEPT live legacy writer; A-M8 self-comparison vector |
| Teardown-replay + `sessionsAwaitingTeardown` deletion | **Stage-2 ∧ Stage-4 join** | arm (a) keys on outcome stamps, arm (b) on open molecules — A-B4, B-M1; falsifier clause-2 checkpoint re-homes there (FINAL Q4 — **r6: rides this round, see FINAL**) |
| `#rN` synthesis view (r1 FINAL Q8) | moot until G1b | re-keys are KEPT |
| `_reconcileWorktree` boot-reap deletion (r1 FINAL Q5) | W2-D-review call | boot-time belt over tick suspenders (`restart_reconciler.dart:901`, `:1359`) |

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
| B-M3 | FINAL Q2 named the wrong CHECK; `ck_substation` bites | ~~A-F~~ → **r3 correction: `ck_substation` half stands, but the idem-key half of the r2 disposition is REOPENED with A-M4 (C-B3); substation/attemptId/snapshotRev sourcing also open (O-M6/C-M5)** | |
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
| O-M6 | No substation for a pre-mount refusal | **A-W2** | carried majors table (with C-M5) |
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

1. ~~**Ratify the two-wave structure as the standing scope**~~ **RATIFIED (r6) by the two
   register entries `wave-2-flip-scope-soak-and-kill-date` (tg-whf6) and
   `wave-2-entry-criteria-rulings` (tg-dme1): the two-wave structure is the standing scope,
   and every heavy ratification listed below is ruled — the KEPT table + §9 EXCEPTION (Q5/Q10),
   the break-glass contract (Q11), the cut-posture `required` contract (Q2's implication).**
   Original text: (this document's frame). Wave 1
   requests no §9 exception — it is read-side + tools against an untouched write path, an
   extended shadow-compare window. The heavy ratifications r2's FINAL carried — the G1a/G1b
   split wording, the KEPT-writes table, the §9 coexistence EXCEPTION (F-M6's honest
   framing), the break-glass contract, the cut-posture `required` contract — all move to the
   wave-2 design round and are NOT ratified by a yes here. Confirm.
2. **The WS branch.** The C2+ soak gates read space_station `grid/stage1-runner`'s `/status`
   trajectory block as the live surface; the in-log round notes are the always-available
   fallback. Who lands the WS branch, and before or in parallel with C2?
   **(r6 note: ruling Q1 (tg-whf6) names the in-log round summaries as THE soak evidence,
   "read from the log, not the terminal" — so the `/status` block is a convenience, not a
   precondition. The branch question itself is not ruled; left as asked.)**
3. **`outcome='unknown'` ⇒ held (fail-closed) until settlement heals it** (§0.3). In wave 1
   this shapes only the overlay's served disposition (bd is still fully written); cheap to
   change now, expensive after wave 2. Confirm the fail-closed choice.
4. ~~**Falsifier clause-2 re-homing**~~ **RIDES r6 — landed in W2-D (§W2.4): teardown replay
   and `sessionsAwaitingTeardown` are NOT in W2-D's deletion set; they delete at the Stage-2
   ∧ Stage-4 join with the checkpoint covering both arms (MOVED-OUT table, r6 annotation).
   No §13 clause text is renegotiated (`trajectory-schema.md:1681-1693` stands).** Original:
   teardown replay deletes at the
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

## ADJUDICATION LOG — r6 (design round, 2026-09-07)

The wave-2 design round. Basis: worktree `grid/cut-wiring-r6` @ `c28fd25`; the entry
worksheet (lunar_station `docs/trajectory-spike/07-wave2-entry-worksheet.md`, verified at
`3617066`); the two register entries; the epoch-50 soak receipt. Every cite below was
re-verified in this worktree, not carried from the worksheet. Verdicts: **RULED** = a docket
ruling settles it, cited · **RULED+r6** = ruled, with design detail the ruling did not
supply (marked "r6 design, not ruled" in the text) · **r6-FINDING** = new, surfaced by this
round, needs a ruling · **LANDED** = shipped on main.

| finding | disposition | ruling / bead / landing |
|---|---|---|
| E1 (O-B1) no lever×dualRead interlock | **RULED** — one lever; `cut` ⇒ `primary` + `required`, resolved once; `CutPostureRefused` after `trajectory.start()` (`work_assembly.dart:273`); C3/C4 rollback amended to pre-cut only (this revision) | Q2 (`wave-2-entry-criteria-rulings`); tg-rcm3 |
| E2 (O-B2 / C-B4) `compromised` demotes to a dead carrier under cut | **RULED+r6** — accounting split from the REQUEST (`decisionBearing` flag on `TrajectoryAppendRequest`, `trajectory_harness.dart:82`); only decision-bearing drops latch (`:1010`); under cut = HALT via an `admission-halted` clause at both `composeMountEligibility` sites (`work_list.dart:303`, `station_admission_authority.dart:671`), one gate, the existing `trajectory.halted` flare (`trajectory_harness.dart:1663`) | Q3; tg-ppo5 |
| E3 (O-B3) restore+replay regresses silently | **RULED+r6** — quiesced void-and-redrive runbook (W2-A item 7 / E3): station down by `traj_quiesce.dart`'s two witnesses → restore → `traj replay` → void EVERY open ledger session (not only P1-open) → boot; tg-ffl6 heals, remint-on-void re-drives. Optional `rebuilt_at` belt recorded, not built | Q4; W2-A (unfiled) |
| E4 (F-B2 / C-B1) KEPT set retires and keeps the same write | **RULED+r6** — NARROW: `running` (`capability_host.dart:684-688`) + `pending` (`session_scope.dart:1566-1569`) retire; `complete` (`capability_host.dart:738-745`), `failed` (`:869-877`) KEPT; §W2.2 names the set and cites Q10 | Q5, Q10; §W2.2 |
| E4-a `gated` carries KEPT facts | **r6-FINDING** — the exhaustion park (`capability_host.dart:940-945`) is the SOLE carrier of the exhausted `restartCount` (the `failed` write is skipped on that branch, `:860-866`); the route park (`:1057-1062`) carries `routeVerdict`; both through `persistRaisedEscalation` (`:105`/`:135`). Carried KEPT-PENDING-RULING (1.5% of churn); Q5 amendment requested | needs a ruling |
| E4-b `ready` unnamed by Q5 | **r6-FINDING** — `_persistReady` (`:710-719`) merges a rendezvous payload via `nodeResultMetadata` (D-5); carried KEPT with `complete` | needs a ruling (or silent acceptance at re-judge) |
| E5 (F-B3) suppressed ack hangs; `_rearm` has no breaker | **RULED** — sealed `{Acked, Dropped, Suppressed}` beside `enqueue` (`trajectory_harness.dart:1178`), always completes; `_rearm` (`session_scope.dart:1525`) failure = gate under cut; recursion-guard secondary moot under narrow | Q3; tg-ppo5 |
| E6 (F-B5) `attempt.terminal` decision-bearing but fire-and-forget | **LANDED + RULED+r6** — `ExternalCloseTerminalObligation` (`stage1_obligations.dart:320`, #341); the acked half rides W2-A at `session_scope.dart:724/:854/:971/:1216/:1684`; the barrier's terminal predicate = P1-closed OR ledger-closed | Q6; tg-ffl6 |
| E6-a provenance vocabulary | **r6-FINDING** — Q6 says `inferred`; #341 writes `reconstructed` (`stage1_obligations.dart:442-443`) so the settlement exclusion (`:231`) protects the heal; r6 records the shipped word | one-word entry amendment requested |
| E7 (C-B3 / F-M3) `admission.refused` idem key | **RULED** — no amendment; ratified key at `admission_records.dart:269-270`; no recorder derivation exists today (verified) — W2-B adds it, armed at the cut (`trajectory-schema.md:1936-1942`) | Q7; W2-B |
| E8 (O-B5 / C-B2 adoption half) cursor consumers | **RULED** — fold-backed `sessionDispositionOf` (`session_disposition.dart:86`) / `staleFences` (`:139`) on C3 under primary, counted fallback on `DualReadAccounting` (`session_head_read.dart:648`); all 14 + 4 call sites re-verified | Q8; tg-6zan |
| E9 (F-B1 schema half) open-retired rows | **RULED+r6** — shape accepted (`session_head_delta.dart:217-220`); P6 eviction on `last_seq` age (`trajectory_schema.dart:264`), r6 default horizon 50,000 records | Q9; tg-ffl6 (source), W2-A (bound) |
| E10 (W2-E) `GRID_INSTANCE_TOKEN` | **N** — sites re-verified (`capability_host.dart:405/:411/:413`, `allocation.dart:724`, `station_process_transport.dart:70`, `incarnation_env.dart:35/:57/:69`); last, behind W2-D | none needed |
| O-M1 / F-B3 ack-failure routing has no seam | **RULED** — no site routes into `_persistFailure`; decision-bearing loss halts | Q3 |
| O-M2 breaker storm | **RULED** — the halt IS the budget | Q3 |
| O-M3 abort has no freeze | **RULED+r6** — flip-back = halt → drain → down → shadow boot; quiesce refuses otherwise; halt verb wanted, UNFILED | Q2/Q3; W2-C |
| O-M4 C9 gated on one round | **RULED+r6** — W2-D gets its own three-boot gate under cut + ratification | W2-D |
| O-M6 / C-M5 refusal sourcing | **RULED+r6** — `mountAttemptId` REQUIRED (`admission_records.dart:218-225`, `:233-238`), minted per evaluation; `substation` from seat config (`work_list.dart:304`, `envelope.dart:107-109`); `snapshotRev` from the bridge snapshot version — no such field on the authority today (verified) | Q7; W2-B |
| O-M7 break-glass site list | **RULED+r6** — one resolution site; both targets read the resolved value; void-on-entry of cut-era sessions + stamp names are r6 design | Q11; W2-A |
| F-M4 acked appends invert §2.5 | **RULED+r6** — disclosed; p99 ≤ 250 ms budget on a new `append_ack_p99_ms` counter, reported not gating | Q3; counter unfiled |
| F-M5 complete-ack re-drives | **RULED** — does not arise under narrow | Q5 |
| F-M6 §9 exception | **RULED** — named in §W2.2 | Q10 |
| C-M1 recorder is `void` | **RULED** — `appendAcked` at named sites only | Q3; tg-ppo5 |
| C-M2 refusal can't ride a throw | **RULED** — post-`start()` check | Q2; tg-rcm3 |
| C-M3 §7 Stage-3 vs Stage-4 | **RULED+r6** — §7's drop row (`trajectory-schema.md:1224-1225`) amended to Stage 4; text rides the W2-A PR | tg-dme1 closing sentence; W2-A |
| C-m4 first-boot order | **RULED+r6** — restated on `StationWorkRuntime.start()` (`work_assembly.dart:264-304`); quiesce after `replayTeardownTail` (`:300`) | Q2; tg-rcm3 / W2-A |
| C-m2 settled derivation doc gap | **N (standing)** — still true at `station_bead_writer.dart:463`; the settled append rides `UnknownTerminalSettlementObligation` (`stage1_obligations.dart:188`); stage1-wiring §2.3 fix rides the W2-A PR | W2-A |
| F-m3 three staging sites | **N** — dissolved; the schema's three sites agree (`trajectory-schema.md:1370-1373`, `:1892-1897`, `:1936-1942`) | Q7 |
| Q1 cut signal unreachable as worded (epoch-50 receipt) | **r6-FINDING, designed** — scoped to `miss_post_epoch = 0`, `p2_miss = 0`, in-window divergence twins keyed on `head_epoch >= soakWindowEpoch` (`trajectory_schema.dart:49`); legacy-era / P1-orphan / historical residue reported separately; NO backfill (safe by construction: pre-cut writes stay on complete carriers); certification table in §W2.5 | Q1 wording amendment requested; comparator bead unfiled |
| MOVED-OUT row R1/R4/R6 cite | **cite drift** — `station_bead_writer.dart:372-390` is now the gate-sweep eligibility at `:399-408` (`GateSweepSessionDisposition`, `:106`); row annotated | editorial |
| FINAL 1 | **RATIFIED** by the two entries | tg-whf6, tg-dme1 |
| FINAL 2 | evidence-surface half covered by Q1 (the log is THE surface); the branch question left as asked | Q1 |
| FINAL 3 | untouched — no ruling covers it | — |
| FINAL 4 | **RIDES r6** — landed in W2-D's not-deleted set + the MOVED-OUT join row; no §13 text renegotiated | W2-D |

r6 author: the design seat (subagent), 2026-09-07. Nothing above is disposed silently —
every "r6 design, not ruled" item is listed for the operator.

### r6 VERIFY PASS 1 — the adversarial re-judge, adjudicated (2026-09-07)

Two judges (ordering/rollback/completeness; fold-fidelity/migration/operations) returned 12
blockers, 18 majors and 10 minors against the design round above. Every one was re-verified
against the worktree tree and the two register entries before disposition — a judge's
rationale is evidence, not fact — and the CONFIRMED findings are fixed in the text above,
in this revision. Verdicts: **CONFIRMED-FIXED** · **REFUTED** (with the receipt that refutes
it) · **CONFIRMED-OPEN** (true, and the fix needs an operator ruling or a bead this round may
not file). Duplicate findings across the two judges are adjudicated once and cross-named.

| finding | verdict | what the tree said, and what changed |
|---|---|---|
| B1 (ordering) `appendAcked` still hangs: the mode table is not the proof | **CONFIRMED-FIXED** | `_latchFencedOut` (`trajectory_harness.dart:1642-1652`), `_latchHalted` (`:1655-1664`) and `_degrade` (`:1669-1676`) each do `_suppressed += _queue.length; _queue.clear();`, and the drain timeout does `_dropped += _queue.length` (`:1449-1455`) — four paths that destroy a request ACCEPTED at `live`. E5 now states the completion contract on the REQUEST LIFECYCLE (complete exactly once; `Suppressed` at every queue-destroying site) and asks tg-ppo5's AC-5 for the latch case |
| B2 (ordering) the halt's gate cannot be minted through the named seam; the flare is overloaded | **CONFIRMED-FIXED** | `createGate` (`station_bead_writer.dart:630-646`) requires `{substation, sessionId, nodePath}` and `_assertGateSessionOpen` (`:646`, refusal `:1393-1400`); a terminal-class loss lands after the KEPT bd close, so the session is CLOSED and the mint throws. `trajectory.halted` fires once from `_latchHalted` under `if (_latched) return;` and that latch suppresses every later append. E2 now splits step-class (`createGate`) from terminal/station-wide (a station-scoped seam, **UNFILED and named**) and gives the breaker its own flare `trajectory.admissionHalted` |
| B3 (ordering) / M6 (fold) the cut signal is a per-pass gauge | **CONFIRMED-FIXED** | `'miss_post_epoch': 'gauge'` (`session_head_read.dart:78`), `'p2_miss': 'gauge'` (`:109`), zeroed by `beginPass()` (`:816-829`). §W2.5 now gates on cumulative event-deduped TWINS and says the gate rows are explicitly not a last-pass read |
| B4 (ordering) two structural zeros in the scoped signal | **CONFIRMED-FIXED** | `classifyDualReadMiss` returns `legacyEra` on a null `startedAt` (`:596-597`) AND on a null `firstEpochClaimedAt` (`:601-602`) — the second zeroes the gate for a whole boot. `null_started_at = 0` and `first_epoch_claimed_at != null` are now GATING rows |
| B5 (ordering) / B4 (fold) `snapshotRev` sourced from a field that is not the ruled one | **CONFIRMED-FIXED (design), CARRIER UNFILED** | `JoinedSnapshot` has no revision (no `version`/`rev` field); `snapshot_version` is `TrajectoryHeadSnapshot.version`, "Bumped on every published change" (`trajectory_views.dart:174-176`) — the P1 mirror's publish counter, which churns per fold apply and breaks the ratified key's level shape. The substitution is WITHDRAWN; §W2.3 now names a bead-scoped eligibility basis revision that must be added (unfiled), W2-B KEEPS the 30 s dedupe until it lands, and Q7 re-opens rather than being satisfied by a fold-side counter |
| B6 (ordering) E3 cites a deadness proof that does not exist | **CONFIRMED-FIXED** | `grep -rn refuseVoidMint packages` is EMPTY; the fence check is station-side `staleFences(...).where(_liveness)` + `_reportVoidRefused` (`station_admission_authority.dart:555-557`, `:809-817`, `:1363-1371`) and runs at the NEXT boot. E3 step 4 is restated as a HAND bd re-key with deadness true by construction, and the missing verb is named UNFILED |
| B1 (fold) retiring `running` strands the lease sweep's orphan detector | **CONFIRMED-FIXED** | `process_lease_vendor.dart:746-748` derives `spawned = state == running \|\| ready` from RAW bead metadata built at `restart_reconciler.dart:1055-1071`; under cut the bead reads `pending` and the LOUD unfindable-process-group report goes silent. `:728`'s `_isLatchedStepState` is unaffected (`:556-564`). E8's adoption set and W2-A item 5 now gate `running`'s retirement on the sweep adopting; the closed set of raw readers is enumerated |
| B2 (fold) the cut-era P2-miss fallback re-creates the I-10 double-run | **REFUTED** | The named mechanism does not follow: the frontier treats `pending` and `running` IDENTICALLY — `StepState.pending => true` AND `StepState.running => true` (`frontier.dart:113-114`) — so a fallback reading `pending` instead of `running` changes no runnability, and the P2-MISS RULE's hazard is an OMITTED node, which does not occur (the node is present, with a state). The real residue of this finding is the raw-state reader in B1 (fold), which is fixed |
| B3 (fold) fold-backed `staleFences` collapses a fence SET to one scalar | **CONFIRMED-FIXED** | `staleFences` walks every running/ready node's triple, deduped by pgid, scalar only when empty (`session_disposition.dart:139-158`); P2 has no pgid/pid/token column (`trajectory_schema.dart:171-182`) and P1 one per session (`:44`) — and tg-6zan's plan/AC-2 return exactly one fence. E8 now requires the fold fence set to be a UNION with the legacy per-node set (never fewer), with per-node fold fences deferred to the P6 mirror; tg-6zan's AC-2 gains the two-live-group case |
| B5 (fold) three gate rows unscoped against known legacy residue | **CONFIRMED-FIXED** | epoch 50 measured `retirement_lag 63 (open 63)`, `terminal_lag open 20`, `cardinality_breaches 23` on legacy shapes; the table gated all three at 0 UNSCOPED, so the certificate was unreachable and the kill date would fire by default. The lag rows and `cardinality_breaches` are now scoped by `head_epoch >= soakWindowEpoch` like the divergence twins, and E9's false "§W2.5 scopes it out" sentence is corrected |
| B6 (fold) the three schema staging sites do NOT all say "at the cut" | **CONFIRMED-FIXED** | `trajectory-schema.md:1371-1373` and `:1892-1897` still carry standing Stage-3 text for the `admission.refused`/`.restored` family, with only the BARRIER half struck; `:1936-1942` is the 2026-08-31 amendment that supersedes it. E7 quotes each site, names the superseding one, and W2-B's doc fix now STRIKES rather than cross-references. Arming the record at the cut is that amendment, not a second §9 partial cut |
| M-1 (ordering) / M1 (fold) `gated` KEPT-PENDING-RULING leaves the retiring set undetermined | **CONFIRMED-FIXED** | Q5 and Q10 name `running`/`pending`/`gated`; the E4-a finding is true at the tree (`capability_host.dart:857-865` returns before the `failed` write at `:869-877`) but the disposition widened a ratified set by fiat. The amendment is now an explicit gate item on W2-A AND on W2-C's pre-flip pack, and §W2.2's row states BOTH branches |
| M-2 (ordering) the quiesce input is not on the surface it reads | **CONFIRMED-FIXED** | `SessionProjection` is a freezed value with named fields and no metadata map, so `grid.session.discipline` is invisible there. W2-A item 3 now names the carrier: the session BEADS off the reconciler's state snapshot (the shape `restart_reconciler.dart:1055-1063` already uses), no new projection field |
| M-3 (ordering) a dry arm under cut is unspecified and both answers are wrong | **CONFIRMED-FIXED** | `asDisabled` forces `mode: disabled` and carries `dualRead` (`trajectory_config.dart:203-215`); at `disabled` `enqueue` silently returns (`trajectory_harness.dart:1179-1183`). E1 now makes `asDisabled` force `discipline: shadow` — a dry arm writes nothing, so it is shadow-era by definition |
| M-4 (ordering) / M2 (fold) `CutPostureRefused` has no unwind and depends on an out-of-repo caller | **CONFIRMED-FIXED** | `start()` sets `_started = true` on its second line and returns early forever after (`work_assembly.dart:264-266`); its house style swallows subsystem failures (`:271-279`, `:298-302`). E1/C-M2 now split the two refusals — requested-posture at ASSEMBLY before any mutation, harness-not-`live` post-`start()` with a LATCH and a stated unwind — and state the caller obligation plus the in-repo AC that `start()` throws |
| M-5 (ordering) W2-B's P6 predicate has no key to the candidate bead | **CONFIRMED-FIXED** | `proj_process_identity` has no work-bead column (`trajectory_schema.dart:254-268`). W2-B now states the join (P6.session_id → P1.session_id → work_bead_id over `ix_bead`) and fixes the multiplicity rule: every P1 row for the bead counts, retired rounds included |
| M-6 (ordering) the barrier's refusal is telemetry, not a carrier | **CONFIRMED-FIXED** | The refusal decision is taken synchronously by the clause; the record witnesses it. E2's `decisionBearing` set is now `stepRunning`, `stepRearmed` and the session terminals only — `admission.refused`/`.restored` explicitly excluded |
| M-7 (ordering) / M4 (fold) P6 eviction stated two incompatible ways | **CONFIRMED-FIXED** | E9 said "regardless of P1 status", W2-A's test plan said "never evicts a live row". One predicate now: evict on `last_seq` age AND `worktree_state != 'live'`; live rows are unbounded by the horizon and bounded by the reap, whose zero-stranded count is already a W2-C gate. Neither arm keys on P1 openness, so Q9 holds |
| M-8 (ordering) §W2.5's fallback enumeration is false at the tree | **CONFIRMED-FIXED** | Three `fallbacks` sites — health-disengage (`dual_read_pass.dart:179`), P1 miss (`:204-214`), cardinality class (`session_head_read.dart:883-884`) — and `p1Orphan` (`dual_read_pass.dart:369`) is not one. The epoch-50 arithmetic is restated as `632 = 601 + 8 + 23 cardinality` with `p1_orphan 11` beside it, and the safety argument now names all three unsafe classes |
| M-9 (ordering) nothing exercises the new machinery before it all arms at once | **CONFIRMED-FIXED** | W2-B's clause is now composed under `shadow` in OBSERVE form: it counts would-refuse decisions, changes eligibility not at all and emits no record (which stays armed at the cut). `barrier_would_refuse` is a §W2.5 row, reported not gating |
| M-10 (ordering) the kill date bounds a certificate whose instruments are unfiled | **CONFIRMED-FIXED** | The comparator/counter bead is now named FIRST in the wave-2 order, and §W2.6 distinguishes "the instrument missed the date" (re-clock) from "the fold failed to certify" (the F6 fallback) |
| M-11 (ordering) the quiesce scope is stated two ways | **CONFIRMED-FIXED** | `discipline` is one station-wide config value; the predicate quantifies over ANY open session bead. W2-A item 3 states it station-wide, W2-C's checklist is corrected to "anywhere on the station", and the seat-scoping paragraph says plainly that scoping bounds what mounts, not what the quiesce or the comparator walks |
| M3 (fold) `appendAcked` has no deadline | **CONFIRMED-FIXED** | `enqueue` returns after `_queue.add` + `_pump` (`trajectory_harness.dart:1178-1209`) and the ack waits on a serialized COMMIT (`trajectory_appender.dart:218`) with no bound; F-M4's budget explicitly never halts. E5 now gives `appendAcked` a one-tick deadline whose breach completes as `Dropped` and rides the E2 halt |
| M5 (fold) W2-D deletes the shadow arm while break-glass forces a shadow boot | **CONFIRMED-FIXED** | Both texts verified in place. W2-D now states what break-glass MEANS post-deletion — an admission-frozen archaeology boot selecting no write posture, with the stamps/flare/notes/quiesce explicitly outside the deletion set — and the grep pin is restated to "no `discipline == shadow` branch at a RETIRED WRITE SITE" |
| M7 (fold) `substation` sourcing contradicts the envelope rule it cites | **CONFIRMED-FIXED** | `work_list.dart:304` is `dispatchableWorkClause(resident: …)` and names no substation; `envelope.dart:107-110` says the value is service-derived from the store prefix (§2.6 rule 7). §W2.3 now says so, with `substationConfig.substationId` (`substation_config.dart:17`) named as the same value |
| m-1 / m4 `mode (:19)` is the enum, not the field | **CONFIRMED-FIXED** | `trajectory_config.dart:19` is the enum, `:54` the ctor param, `:67` the field. Fixed in E1; **tg-rcm3's body carries the same stale cite and should be corrected when it is next edited** |
| m-2 the exhaustion-park cite is `:857-865`, not `:860-866` | **CONFIRMED-FIXED** | The park's `if` is at `:857` and returns at `:864`; the `failed` write is `:869-877`. Fixed in E4 and in §W2.2's row |
| m-3 E6 contradicts a ratified sentence until the amendment lands | **CONFIRMED-FIXED** | The amendment is now a BLOCKING item on W2-A's doc list |
| m-4 / M7 `work_list.dart:304` cited for the substation name | **CONFIRMED-FIXED** | Folded into M7 above |
| m-5 the E3 fence triple goes stale when W2-E lands | **CONFIRMED-FIXED** | W2-E's list now includes re-cutting the E3 runbook's fence sentence onto `attempt_id`, and E3 says so at the site |
| m1 (fold) `ready` IS a `step.transition` state | **CONFIRMED-FIXED** | `stepReady` emits `state: StepState.ready` (`station_trajectory_recorder.dart:1183-1201`) and the P2 enum lists it (`trajectory_schema.dart:174`); the census simply measured 0. The row is reworded |
| m2 (fold) the 47% counts RECORDS, not bead writes | **CONFIRMED-FIXED** | `site: 'stepRunningBeforeComplete'` emits a second, inferred running record with no `_persistStarted` write (`station_trajectory_recorder.dart:1225-1245`). §W2.2's "what this buys" says so and asks for a re-measure by `site='stepRunning'` |
| m3 (fold) the `mode` gate row cites the lag dartdoc | **CONFIRMED-FIXED** | `:975-979` is the five-number gate and never mentions `mode`; the row now cites `:997` and the dartdoc is left supporting the rows it does support |
| m5 (fold) the C3/C4 splice cites start on comment lines | **CONFIRMED-FIXED** | The four-field rule is `station_join_bridge.dart:369-374` (splice `:375-378`); C4 is `:379-394` with the `copyWith` at `:391-394`. Both tightened in E8 |

**What verify-1 leaves for the operator (nothing else is open):** the Q5/Q10 amendment on
`gated`/`ready` (E4 — now a gate item, not a disposition), the one-word Q6 amendment on
`reconstructed` (E6-a), Q7's re-opening if no bead-scoped basis revision can exist before the
flip (§W2.3), and three UNFILED carriers this round names rather than files — the comparator/
counter bead (§W2.5, FIRST in the order), the station-scoped gate seam (E2), and the
void-every-open-session verb (E3). Verify pass 2 may proceed on this text.
