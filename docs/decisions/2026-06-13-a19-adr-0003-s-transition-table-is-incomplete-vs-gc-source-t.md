---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a19-adr-0003-s-transition-table-is-incomplete-vs-gc-source-t
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A19"
---
## A19 (2026-06-13) — ADR-0003's transition table is incomplete vs gc source; Track B must reduce from the Go

**Decision:** the state-machine table in ADR-0003 Decision 2 omits transitions that gc's `handler.go`/`manual.go`/`trigger.go`/`create.go` actually perform; Track B (the reducer) ports the **Go**, with the table as orientation only. The gaps: (a) a **trigger-gated CREATE** goes straight to `waiting_trigger`, never passing through `active` (create.go:133-149); (b) a **pour/sling failure** on a non-terminal outcome transitions `active → waiting_manual` with `waiting_reason=sling_failure` (handler.go:370-374, 713-726) — absent from the table; (c) **operator stop is valid from `waiting_trigger`** too (manual.go:258), and `StopHandler` first **drains** an already-closed-but-unprocessed active wisp through the full `HandleWispClosed` (a possibly-multi-minute fresh gate eval) before deciding no-op vs force-close (manual.go:272-314) — the grid models this split as `RequeueAction(OperatorStopEvent(postDrain: true))`, the drain pipeline followed by a re-entered stop whose `postDrain` marker lets the reducer resolve `drainTerminated` (wire `stopped`) vs the fresh-stop error path that the snapshot alone cannot distinguish. **Write-ordering nuance:** `last_processed_wisp` is "written LAST" but in terminal transitions that means **after `CloseBead`** (handler.go:699-704, manual.go:90-109/415-439), with the close *between* the metadata writes; operator approve/stop **skip** the write when there is no prior wisp; operator iterate writes **no** dedup marker at all. **Replay nuance:** gc replays `gate_outcome` **verbatim, unvalidated** (handler.go:282) — the set is closed at write time, open at replay time; the codec marks out-of-set outcomes malformed but keeps the raw string available for byte-faithful event reconstruction.
**Why:** an adversarial fidelity verifier diffing the table against source found these; a reducer built from the table alone would mis-handle trigger-gated creation, sling failures, stop-during-drain, and terminal write ordering. Recorded as pending because it corrects a *ratified* doc.
**Affects (if promoted):** ADR-0003 Decision 2 (replace the transition table + invariant-2 wording with the corrected version). Code: Track B (built from the Go per this note); the `requeue`/`postDrain` carrier already exists in Track A.
**Status:** **promoted → ADR-0003 Decision 2 (Nico, 2026-06-14)** — table augmented + invariant-2 corrected.

