---
status: accepted
date: 2026-07-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a48-a-closed-session-is-dispositioned-done-held-voided-not-b
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A48"
---
## A48 (2026-07-12) — a CLOSED session is DISPOSITIONED (done | held | voided), not blanket-blocking (tg-4rw / I-10)

**Context.** I-10 (observed 2026-07-03): after the I-8 wrong-mount orphan session (`tgdog-bkv`, `work_bead=tg-1di`) was OPERATOR-CLOSED with its cursor still `state=running`, the resident station mounted `tg-1di` but NEVER minted a session — **62 minutes wedged** (mounted:1, live sessions:0), **silently**. A40's positive-terminal-only unmount reads EVERY closed session as "the work is done", so the adopt-or-mint decision treated the closed-but-in-flight session as unadoptable-**but-blocking**: right instinct (never double-run), wrong outcome (a dead key blocks forever). The operator's only recovery was a hand re-key (`work_bead=tg-1di#void-i8`) + a station restart.

**Decision (AI; `grid_engine`):** the mount boundary reads a pure `SessionDisposition` (a freezed sealed union) instead of the `session.isTerminal` boolean. Three different things close a session, and only two of them mean "done":
- **`done`** — the engine's OWN close path stamped a durable `grid.outcome=complete` marker (new, written through the chokepoint immediately before `bd close`); or, for a LEGACY bead closed before the marker shipped, the cursor is non-empty and every node is a positive terminal. BLOCKS the mount — load-bearing: the work source is read-only (A37), so a landed bead stays open+ready and this latch is all that stops a resident station re-driving finished work.
- **`held`** — the session carries a HUMAN marker (`grid.escalation` / `grid.rework_declined`). BLOCKS, and `WorkList` now says WHY once (`work.held`). Auto-re-minting an escalated round would loop escalate → close → re-mint → fail → escalate, spawning agents forever.
- **`voided`** — closed, no marker, the cursor NOT a positive terminal (including an EMPTY cursor). A DEAD KEY: **never adoptable AND never blocking**. The bead MOUNTS; `SessionScope` RETIRES the dead key (re-keys its `work_bead` to `<beadId>#void-<deadSessionId>` + a `grid.voided_reason`, through the ONE chokepoint on the_grid's OWN bead) and mints a fresh round — `session.voided`, LOUD once.

**The marker, not the cursor, is the `done` evidence.** Cursor shape alone cannot carry it: a session closed BETWEEN steps has every WRITTEN node `complete` while the circuit is nowhere near its terminal, and the mount boundary has no circuit to ask (`isCircuitComplete` needs one). So the engine states its own outcome; the cursor rule is only the legacy fallback.

**The VOID retire EXTENDS A47's re-run taxonomy as a fourth, ENGINE-AUTOMATIC member.** A47 enumerates `Gate` (parks for a human), `grid rework` (the operator verb: retires a round by re-keying `work_bead` to `<beadId>#r<N>`), and `Rewind` (the in-session engine primitive), and makes `domain/rework.dart` "the ONE place the key shape is authored". The void retire borrows `grid rework`'s re-key MECHANIC with no human and no operator verb — so its key shape (`voidKeyFor`) is authored in that same file, and the file's taxonomy doc now names all three key-shaped mechanics. It sits deliberately OUTSIDE the `kMaxReworkRounds` budget (`#void-` never matches `reworkKeyPattern`): a round nobody ran is not a round the operator spent — A47's own two-axis rule.

**A43 is preserved, not amended.** A VOIDED bead has no live session, so it enters A43's `pending` bin by A43's own predicate ("freshly ready, no live session — the only bin the budget gates") and is budget-gated exactly like a fresh bead: a re-mint spawns an agent, so it must cost a slot. Only the bin's ELEMENT TYPE changes (it carries the dead projection down to `SessionScope`); admission stays lowest-bead-id-first, and an already-mounted bead is still never evicted for budget reasons. `WorkList`'s "live session" bin keeps its ROW-shaped meaning (any non-terminal session row, named or not) — the "a projection naming no session bead has nothing to adopt" nuance belongs to the adopt-or-mint decision alone, never to the mount classification.

**Fail-closed against a live orphan.** A void session's recorded fences (a `running`/`ready` node's pgid+pid, or the legacy scalar) are probed through the ambient `StationServices.liveness` seam (ADR-0009 D4's pgid-alive half). Any fence still ALIVE refuses the mint LOUD (`session.voidRefused`) and the scope goes inert. The probe NARROWS the re-mint, it is not its precondition: unwired (the P1 default `neverLive`) the mint proceeds on two structural guarantees — a terminal session's work bead UNMOUNTS (dispose kills the group), and a restart SWEEPS a terminal session's live groups before the tree re-mounts.

**The retire keeps the join single-valued.** Two sessions on one `work_bead` would make the join's winner map-order-dependent (`StationJoinBridge`'s last-writer-wins) and `grid rework` refuses an ambiguous bead — so the dead key is retired BEFORE the mint, mechanizing the I-10 operator workaround.

**Also fixed en route (same failure family):** `SessionScope.build` threaded a MISMATCHED join row's cursor down under its own `SessionHandle` (a fresh session inheriting a dead row's progress); the cursor is now read only from a matching join. The positive-terminal close is wrapped so a throwing bd write flares (`session.outcomeUnmarked` / `session.closeFailed`) instead of surfacing as an unhandled async error on a resident station's root zone (which would terminate the isolate).

**Why:** the bead's own framing ("a closed session is never adoptable AND never blocking") is right for the incident but too broad as written — `done` and `held` closed sessions MUST keep blocking (else landed work re-runs and escalations loop). The disposition is that framing, narrowed to the three real cases, with the engine's own evidence making the distinction explicit rather than inferred.

**Not this:** the join bridge's / `RestartReconciler`'s last-writer-wins pick among multiple sessions per work bead is left as-is (the retire preserves the single-key invariant that makes it moot); a `voided`/`held` block on the RS-4 status surface is not added; `grid rework`, `Gate`, and `Rewind` are unchanged.

**Affects:** `grid_engine`: `domain/session_disposition.dart` (new — the sealed union + `sessionDispositionOf` + `staleFences`), `domain/session_projection.dart` (`completed`/`humanHeld`), `domain/session_bead.dart` (`grid.outcome` + the moved escalation/decline keys + `sessionCompleteMetadata`/`voidRetireMetadata`), `domain/rework.dart` (`voidKeyFor` + the taxonomy doc), `seeds/work_list.dart` (the disposition mount gate + `work.held`), `circuit/session_scope.dart` (disposition-driven adopt-or-mint, the retire, the liveness fence, the outcome stamp, the cursor guard). New tests: `session_disposition_test.dart` (13), `session_scope_void_remint_test.dart` (8, mutation-checked); three terminal-session fixtures migrated to declare WHICH terminal they model. grid_engine **361** offline tests green; full workspace 361/80/63/129/164/13/15, `melos analyze` clean.

**Status:** **Ratified (Nico, 2026-07-12, ADR interview)** — the enduring content accepted: the `SessionDisposition {done, held, voided}` sealed union at the mount boundary (replacing `isTerminal`); done/held BLOCK, voided is a dead key that mounts + retires (`#void-<id>`) + re-mints; **the MARKER (`grid.outcome=complete`), not the cursor, is the `done` evidence** — the ADR-0013 principle (hold state, never infer it from a side channel), BORN here and generalized into the_grid **ADR-0013**; the void-retire as A47's 4th engine-automatic re-run member (key shape in `domain/rework.dart`, outside `kMaxReworkRounds`); the fail-closed live-orphan probe (`voidRefused`); and the two en-route fixes (mismatched-join cursor guard; the positive-terminal close wrapped so a throwing bd write flares, never terminates the isolate). Promote to a home ADR (an ADR-0007 amendment to A40's unmount clause, alongside A47's taxonomy) at will — the disposition + marker-as-outcome stand.

