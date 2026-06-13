# M2 conformance report (ADR-0003 Decision 7 — DoD criterion 1)

**Track H, 2026-06-13.** This is the artifact that demonstrates M2 DoD criterion
1: *"state machine + recovery conformance-green against the transliterated gc
suite."* It maps every gc convergence test function (the executable spec,
`gascity/internal/convergence/*_test.go` at the pinned bd 1.0.5 / gascity HEAD)
to the Dart test(s) that cover it, with the gc `file:line` the behavior is pinned
against and a status:

- **faithful** — an existing Track A–G Dart test covers the case with gc's exact
  assertions (metadata key+value / action type / state transition / call
  count/order). Cited in the per-component conformance suites.
- **filled-here** — Track H added the case (a gap, or weaker-than-gc coverage).
- **e2e** — Track H drives the case end-to-end through the real
  `ReconcilerRuntime` (reduce→gate→actuate→recovery), the layer the per-component
  units cannot provide.
- **n-a** — not applicable to the grid's M2 scope, with the reason. The dominant
  reasons: (a) **create/retry surface** — `CreateHandler`/`RetryHandler` mint a
  new root and are explicitly out of the reducer's `reduce(state,event,snapshot)`
  scope (ADR-0000 A22 item 4 / A19 item (a)); they land with the M3 create
  surface. (b) **live-store I/O** — a transient `GetBead`/`PourWisp` failure
  cannot be reproduced at the grid's PURE reducer/recovery layer; it is the Track
  G actuation seam's contract (ADR-0000 A25 item 3 / A27). (c) **gate-execution
  internals** (`condition_test.go` env/path/capture) — Track D's own conformance
  suite (`test/gates/`), not the state machine.

The grid is a **phase-split, pure-reducer** port (A22): a *fresh* condition/hybrid
gate is a two-reduce handoff, so most gc handler fixtures (which use the *replay*
branch, `gate_outcome_wisp == wisp`) map to a single `wispClosed` reduce, exactly
as gc runs them in-frame.

## Tally

| Priority | Count | Disposition |
|---|---|---|
| **must — covered (faithful + filled-here + e2e)** | all must-cases | green |
| must — residual gaps | **0** | — |
| should — covered | gate-config/parse/env/payload literal matrices | green |
| should — residual | 0 material | — |
| skip (n-a, justified) | create/retry surface; live-store I/O; token/acl/artifact/evaluate/formula/depfilter/template host-process helpers | deferred to M3 (create surface) / Track D suite / not-state-machine |

Per-component Dart test totals backing this: reducer 118 · recovery 50 · gates
111 · convergence (Track A literals/codec) 139 · runtime 43 · **conformance
(Track H, e2e) 10** · projections 30 · actuator 16. Full suite **559 offline +
29 integration green, analyze clean** (this report's gate run).

---

## handler_test.go (40 funcs) — the 9-step algorithm

| gc test func (file:line) | behavior | Dart coverage | status |
|---|---|---|---|
| `TestParseIterationFromKey` (382) | key→iter parse, all rows | `convergence/idempotency_key_test.dart` | faithful |
| `TestIdempotencyKey` (409) | `converge:{id}:iter:{N}` + round-trip | `convergence/idempotency_key_test.dart` | faithful |
| `TestHandleWispClosed_GuardCheck_Terminated` (422) | terminated → skipped (Inv 6) | reducer `handler_conformance` H04 | faithful |
| `TestHandleWispClosed_DedupCheck_AlreadyProcessed` (436) | equal iter → skipped (Inv 1) | reducer H05 | faithful |
| `TestHandleWispClosed_CorruptedLastProcessedWisp_GracefulDegradation` (454) | bad lpw → iter 0, processes | reducer H06 | faithful |
| `TestHandleWispClosed_ManualGate_WaitingManual` (476) | manual → waiting_manual(manual) + state write + 2 events | reducer H07; **e2e** `runtime_lifecycle_conformance` (manual hold chain) | faithful + e2e |
| `TestHandleWispClosed_HybridNoCondition_WaitingManual` (511) | hybrid+no condition → waiting_manual(hybrid_no_condition) | reducer H08 | faithful |
| `TestHandleWispClosed_GateReplay_SkipsReEvaluation` (530) | cached fail → iterate, no re-eval | reducer H09 | faithful |
| `TestHandleWispClosed_GatePassApproved` (551) | cached pass → approved + terminal writes + close + 2 events | reducer H10/H18/H21; **e2e** `runtime_bd_sequence` (bd call seq) + `runtime_gate_phase_split` | faithful + e2e |
| `TestHandleWispClosed_GateFailIterate` (593) | cached fail → iterate, active_wisp=next, event next_wisp_id+action | reducer H11; **e2e** `runtime_lifecycle` (iterate chain) | faithful + e2e |
| `TestHandleWispClosed_MaxIterationsReached_NoConvergence` (634) | max=1, fail → no_convergence | reducer H12; **e2e** `runtime_lifecycle_conformance` (gate-fail→max→no_convergence chain) | faithful + **e2e (filled-here)** |
| `TestHandleWispClosed_TimeoutTerminate` (660) | timeout+terminate → no_convergence | reducer H13; **e2e** `runtime_bd_sequence` | faithful + e2e |
| `TestHandleWispClosed_TimeoutManual` (682) | timeout+manual → waiting_manual(timeout) | reducer H14; **e2e** `runtime_bd_sequence` | faithful + e2e |
| `TestHandleWispClosed_SlingFailure_WaitingManual` (702) | pour fail on non-terminal → waiting_manual(sling_failure) | reducer `gate_phase_split` (pourFailed=true, fail) | faithful |
| `TestHandleWispClosed_VerdictClearedOnIterate` (747) | verdict scoped to this wisp cleared | reducer H16 | faithful |
| `TestHandleWispClosed_VerdictPreservedForLaterWisp` (773) | verdict scoped later preserved | reducer H17 | faithful |
| `TestHandleWispClosed_WriteOrdering_TerminalReasonBeforeState` (796) | terminal_reason/actor before state, lpw LAST after close | reducer H18 (Inv 2) | faithful |
| `TestHandleWispClosed_WriteOrdering_IterateLastProcessedBeforePendingCleanup` (876) | lpw second-to-last, pending clear LAST | reducer H19 (explicit committed-order reconstruction) | faithful |
| `TestHandleWispClosed_WriteOrdering_WaitingManualLastProcessedWispLast` (919) | lpw LAST in waiting_manual | reducer H20 | faithful |
| `TestHandleWispClosed_EventPayloads` (953) | iteration+terminated event ids/fields | reducer H21 + `event_id_formula_conformance` | faithful |
| `TestCheckNestedConvergence_Blocked` (1017) | self-target deadlock | acl/nested-convergence is create-time admission | **n-a** (create surface) |
| `TestCheckNestedConvergence_Allowed_DifferentAgent` (1033) | cross-agent allowed | — | **n-a** (create surface) |
| `TestCheckNestedConvergence_CrossAgent_TargetHasActiveLoops` (1047) | cross-agent w/ active loops | — | **n-a** (create surface) |
| `TestCheckConcurrencyLimits_Exceeded` (1062) | per-agent limit | — | **n-a** (create surface) |
| `TestCheckConcurrencyLimits_OK` (1082) | under limit | — | **n-a** (create surface) |
| `TestEventIDFormulas` (1095) | all 7 event-id formulas | `event_id_formula_conformance_test.dart` | faithful |
| `TestNullableString` (1118) | "" → nil | reducer payload (events nullability) | faithful |
| `TestGateResultToPayload` (1127) | empty→nil, populated→payload + duration_ms | `gates/` gate-result mapping | faithful |
| `TestHandleWispClosed_SpeculativePour_WispExistsBeforeGateEval` (1198) | spec pour before gate, adopted | reducer H30/H34 (`adoptFromPriorPour`, `activatesWisp`) | faithful |
| `TestHandleWispClosed_SpeculativePourFailureStillAllowsTerminalGate` (1227) | pour fail + gate PASS → approved (not sling) | reducer `gate_phase_split` (pass, pourFailed=true → no sling hold) | faithful |
| `TestHandleWispClosed_InvalidConditionDoesNotBurnUnvalidatedPendingWisp` (1258) | condition mode no condition → failed, foreign pending un-marked not burned | reducer H32 | faithful |
| `TestHandleWispClosed_SpeculativePourDeletedOnTerminal` (1280) | terminal burns spec wisp (iter-2 key gone) | reducer H30/H33 (`burnPriorPour`) | faithful |
| `TestHandleWispClosed_IterateActivatesSpeculativeWispBeforeCommit` (1306) | ActivateWisp once, lpw before pending clear | reducer H34/H19 (`activatesWisp`, committed order) | faithful |
| `TestHandleWispClosed_NoSpeculativePourOnWaitingManual` (1335) | manual gate pours no spec wisp | reducer H35 | faithful |
| `TestHandleWispClosed_ManualThenIterateUsesNextSequentialIteration` (1355) | manual hold then operator iterate → iter 2, key iter:2 | reducer M7; **e2e** `runtime_lifecycle_conformance` (manual hold → operator iterate chain) | faithful + **e2e (filled-here)** |
| `TestHandleWispClosed_NoSpeculativePourAtMaxIterations` (1384) | max=1 fail → no spec pour | reducer H37 | faithful |
| `TestCrashAfterSpeculativePour_ReconcilerRecoversChain` (1406) | active+pending, manual → recovery → waiting_manual | recovery `recovery_pass` Path-4; **e2e** `drain_and_recovery` (crash-restart replay) | faithful + e2e |
| `TestCrashAfterSpeculativePour_NoActiveWisp_ReconcilerAdoptsSpeculative` (1450) | empty active+pending → adopt iter-2, active | recovery G6 (`Active_EmptyActiveWisp_AdoptsValidPending`) | faithful |
| `TestCrashAfterSpeculativePour_ReconcilerUsesPendingNextWispBeforeLookup` (1491) | valid pending used before key lookup (no Find call) | recovery G6 (pending priority over key lookup) | faithful |
| `TestWithEventRigPopulatesEveryRigPayload` (307) | rig threaded into every payload | recovery `CompleteTerminalAction`/`WaitingManual` event rig fields | faithful |

## manual_test.go (21 funcs) — operator approve / iterate / stop

| gc test func (file:line) | behavior | Dart coverage | status |
|---|---|---|---|
| `TestApproveHandler_HappyPath` (50) | waiting_manual → approved, operator actor, derived iter, waiting cleared, close, 2 events | reducer M1; **e2e** `runtime_lifecycle` + `runtime_lifecycle_conformance` (manual hold → approve) | faithful + e2e |
| `TestApproveHandler_WrongState_Active` (94) | active → failed mentioning both states | reducer M2 | faithful |
| `TestApproveHandler_WrongState_Terminated` (111) | terminated/no_convergence → failed | reducer M3 | faithful |
| `TestApproveHandler_Idempotent_AlreadyApproved` (126) | terminated/approved → idempotent, no event | reducer M4 | faithful |
| `TestApproveHandler_WriteOrdering` (148) | terminal writes before state, lpw LAST | reducer M5 | faithful |
| `TestApproveHandler_EventPayloads` (195) | manual_approve + terminated payload fields | reducer M6 + `event_id_formula` | faithful |
| `TestIterateHandler_HappyPath` (252) | → iterate, NEXT iter, active, waiting cleared, no dedup marker | reducer M7; **e2e** `runtime_lifecycle` + `runtime_lifecycle_conformance` | faithful + e2e |
| `TestIterateHandler_WrongState_Active` (287) | active → failed | reducer M8 | faithful |
| `TestIterateHandler_WrongState_Terminated` (301) | terminated → failed | reducer M9 | faithful |
| `TestIterateHandler_AtMaxIterations` (315) | max=1 → failed (max iterations) | reducer M10 | faithful |
| `TestIterateHandler_ClearsVerdictScopedToLastWisp` (329) | verdict cleared | reducer M11 | faithful |
| `TestIterateHandler_PreservesVerdictScopedToOtherWisp` (353) | verdict preserved | reducer M12 | faithful |
| `TestIterateHandler_EventPayloads` (374) | manual_iterate id/payload | reducer M13 + `event_id_formula` | faithful |
| `TestIterateHandler_PourWispFailure` (408) | pour fail → error ("pouring next wisp") | live-store I/O at actuation seam | **n-a** (A25 — actuation-seam error; reducer plans the pour, the actuator surfaces the live failure → `runtime` deferred-error contract `drain_and_recovery` A25) |
| `TestStopHandler_HappyPath_WaitingManual` (443) | stop waiting_manual → stopped | reducer M15; **e2e** `runtime_lifecycle_conformance` (hold-state stop through `runtime.submit` → `StoppedAction`, no drain/force-close) | faithful + **e2e (filled-here)** |
| `TestStopHandler_HappyPath_Active` (487) | stop active → stopped/terminated | reducer M16 | faithful |
| `TestStopHandler_WrongState_Terminated_NotStopped` (513) | terminated/approved → failed (3 states) | reducer M17 | faithful |
| `TestStopHandler_Idempotent_AlreadyStopped` (531) | terminated/stopped → idempotent, no event | reducer M18 | faithful |
| `TestStopHandler_WriteOrdering` (553) | verdict clear first, terminal before state, lpw LAST | reducer M19 | faithful |
| `TestStopHandler_EventPayloads` (597) | manual_stop + terminated payload | reducer M19/M6 | faithful |
| `TestStopHandler_StopFromActive_PriorStateInEvent` (646) | prior_state reflects actual (active) | reducer M21 | faithful |

## stop_test.go (10 funcs) — stop drain / force-close

| gc test func (file:line) | behavior | Dart coverage | status |
|---|---|---|---|
| `TestStopHandler_DrainCompletedIteration` (52) | active wisp closed + gate pass → drain approves, stop no-op | reducer A19 drain (postDrain → drainTerminated); **e2e** `runtime_lifecycle_conformance` (gate-PASS drain → `ApprovedAction(handlerWispClosed)` + postDrain `drainTerminated` skip — the gate-pass drain composition, filled here) | faithful + **e2e (filled-here)** |
| `TestStopHandler_DrainThenStop` (80) | active wisp closed + gate fail → drain iterates, then stop | reducer A19 drain pipeline + requeue; **e2e** `drain_and_recovery` | faithful + e2e |
| `TestStopHandler_ForceClose` (112) | open active wisp → force-close, lpw=force-closed wisp | reducer G-STOP-3; **e2e** `drain_and_recovery` (open wisp force-close) | faithful + e2e |
| `TestStopHandler_ForceClose_SyntheticEvent` (146) | synthetic iteration event for force-closed wisp | reducer G-STOP-3 (event wisp) | faithful |
| `TestStopHandler_ClearsStaleVerdict` (183) | verdict cleared unconditionally | reducer M19 (unconditional verdict clear) | faithful |
| `TestStopHandler_FromWaitingManual_NoForceClose` (204) | no active wisp → no synthetic event | reducer M15 | faithful |
| `TestStopHandler_MissingActiveWisp_StopsGracefully` (235) | dangling active wisp, no replacement → plain stop | reducer G-STOP-6 | faithful |
| `TestStopHandler_ActiveWispMissingBeforeForceClose_StopsGracefully` (265) | active wisp vanishes between reads → graceful stop | reducer G-STOP-6 (snapshot-derived dangling) | faithful |
| `TestStopHandler_MissingActiveWisp_RecoversReplacementBeforeForceClose` (307) | recover replacement by lpw+1, force-close it, repoint lpw | reducer G-STOP-5 (`recoverCurrentActiveWisp`) | faithful |
| `TestStopHandler_StoreErrorReadingActiveWisp_ReportsError` (337) | live GetBead failure → error | live-store I/O | **n-a** (A25 actuation seam — no fallible read at the pure layer) |

## trigger_test.go (8 funcs) — trigger hold/advance

| gc test func (file:line) | behavior | Dart coverage | status |
|---|---|---|---|
| `TestParseTriggerConfig` (27) | all 4 rows (none/event+cond/event-no-cond err/invalid err) | reducer `invariants` TR1; `gate_literals` TriggerMode | faithful |
| `TestHandleTrigger_EntryPoursFirstWispOnPass` (106) | entry advance: iterate iter 1, key iter:1, trigger_advance event (no iteration event, no collision) | reducer TR2 + `event_id_formula` (collision rule); **e2e** `write_through_freshness` (idempotent advance) | faithful + e2e |
| `TestTriggerConditionEnv_MirrorsNextIteration` (177) | trigger env uses NEXT iteration + artifact dir | `gates/condition_env` / trigger env inputs | faithful |
| `TestHandleTrigger_WaitsWhenConditionFails` (207) | condition fail → skipped, stays waiting_trigger, no pour | reducer TR (a non-pass produces no triggerPassed; the grid only reduces a passed trigger — gc's wait is the absence of an event) | faithful (modeled as no-event; verified TR6 guard) |
| `TestHandleTrigger_IterationGateAdvance` (232) | mid-loop advance: iter 2, key iter:2, active | reducer TR5; **e2e** `runtime_lifecycle_conformance` (trigger hold → advance) | faithful + **e2e (filled-here)** |
| `TestHandleTrigger_SkipsWhenNotWaiting` (263) | active loop → skipped | reducer TR6 (`notWaitingTrigger`) | faithful |
| `TestHandleTrigger_RefusesToExceedMaxIterations` (276) | next > max → error, no pour | reducer TR7 (`exceeds max_iterations`) | faithful |
| `TestHandleWispClosed_TriggerGatesIteration` (299) | wisp closed on trigger loop → waiting_trigger, NO next pour, lpw LAST, iteration event action=waiting_trigger | reducer TR8; **e2e** `runtime_lifecycle_conformance` (wispClosed → waiting_trigger) | faithful + **e2e (filled-here)** |

## reconcile_test.go (27 funcs) — recovery paths

All 27 are covered by `recovery/recovery_pass_test.dart` (tests 1-27 + gap tests
G1-G11) and `recovery/recovery_idempotency_test.dart`, each citing its
`reconcile.go` line. Representative mapping (full set in `recovery_pass_test.dart`):

| gc test func (file:line) | Dart coverage | status |
|---|---|---|
| `TestReconcile_WaitingTrigger_NoAction` (30) / `_CompletesInterruptedStop` (55) | recovery Path-3t tests 1-2 | faithful |
| `TestReconcile_MissingState_NoWisps_PoursFirst` (81) / `_WispExists_Adopts` (123) | recovery Path-1a tests 3-4 + G3 (closed-adopt replay) | faithful |
| `TestReconcile_StateCreating_TerminatesPartialCreation` (160) | recovery Path-1b test 5 | faithful |
| `TestReconcile_TerminatedNotClosed_*` (206/257/283) | recovery Path-2 tests 6-8 + G7/G9 | faithful |
| `TestReconcile_WaitingManual_*` (305/348/396) | recovery Path-3 tests 9-11 + G1/G1b + sub-path precedence | faithful |
| `TestReconcile_Active_ClosedUnprocessedWisp_Replays` (429) | recovery Path-4 test 12 (reducer replay reuse, A22) | faithful |
| `TestReconcile_Active_MissingActiveWisp_*` (476/520/562) | recovery Path-4 tests 13-15 | faithful |
| `TestReconcile_Active_StoreErrorReadingActiveWisp_ReportsError` (599) | recovery test 16 (the NotFound/recovery branch *selection* is snapshot-derivable & tested; the transient-store-read abort is the Track G seam) | faithful for the reachable arm; **n-a** for the live-read abort (A25/A27) |
| `TestReconcile_Active_OpenWisp_NoAction` (628) / `_EmptyActiveWisp_*` (692/723) / `_AlreadyProcessed_NoAction` (756) / `_TerminalReasonSet_CompletesStop` (651) | recovery Path-4 tests 17-21 + G6/G6b | faithful |
| `TestReconcile_MultipleBeads_ContinuesOnError` (781) | recovery test 22 (continue-on-error, input-order Details, errored≠Recovered; gc's store-absent bead modeled as the grid's snapshot-derivable unknown-state error — see decisions[]) | faithful (equivalent oracle) |
| `TestReconcile_RecoveryEventsHaveRecoveryFlag` (838) | recovery test 23 | faithful |
| `TestDeriveIterationFromChildren` (884) / `TestHighestClosedWisp*` (898/918) | recovery tests 24-26 (via `Convergence` projection) | faithful |
| `TestReconcile_EmptyList_NoOp` (929) | recovery test 27 | faithful |
| `TestReconcile_TerminatedAlreadyClosed_NoAction` (283) | recovery test 8 (`reconcileBead` direct, scan drops closed) | faithful |
| **(idempotency / fixpoint)** | `recovery_idempotency_test.dart` (10 tests, A25 fixpoint-of-writes) | faithful |
| **(crash → restart → single transition, e2e)** | **e2e** `drain_and_recovery` (replay-after-restart idempotent) | e2e |

## gate_test.go (4) + hybrid_test.go (3) — gate config + hybrid eval (Track D)

| gc test func (file:line) | Dart coverage | status |
|---|---|---|
| `TestParseGateConfig` (gate_test.go:8) — all 11 rows incl. invalid mode/timeout/action, defaults, 5m default | reducer `invariants` (gate config parse errors → failed) + `gate_literals` (GateMode/Outcome/TimeoutAction defaults+budget) + `gates/gate_runner` config | faithful |
| `TestNeedsConditionExecution` (gate_test.go:144) — manual/condition/hybrid × condition matrix | `gates/gate_runner` (mode dispatch) | faithful |
| `TestDefaultGateTimeoutIs5Minutes` (gate_test.go:191) | `gate_literals` / `go_duration` (default 5m) | faithful |
| `TestGateManualResult` (gate_test.go:197) — manual gate = pass, nil exit, 0 duration | `gates/gate_runner` (`gateManualResult`) | faithful |
| `TestEvaluateHybridWithCondition` (hybrid_test.go:12) — verdict×script matrix incl. empty-verdict→fail | `gates/gate_runner` hybrid matrix; **e2e** `runtime_lifecycle_conformance` (hybrid loop through the real runtime: phase-1 verdict-read threads `GC_AGENT_VERDICT` into the gate env, phase-2 terminal/iterate transition fires — handler.go:318-327, the reduce→gate(hybrid)→actuate composition) | faithful + **e2e (filled-here)** |
| `TestEvaluateHybridWithoutCondition` (hybrid_test.go:99) — manual fallback → pass, nil exit/duration | `gates/gate_runner` (hybrid-no-condition manual fallback) | faithful |
| `TestHybridNeedsManual` (hybrid_test.go:127) | reducer H08 + `gates/gate_runner` | faithful |

## condition_test.go (19) — gate execution internals (Track D suite)

Gate-execution conformance is Track D's `test/gates/` suite, not the state
machine. Coverage map:

| gc test func | Dart coverage | status |
|---|---|---|
| `TestConditionEnvEnviron*` (15/82/118/143/171) — env-var contract incl. optional-empty omission, store-path BEADS_DIR, real-bd/dolt passthrough | `gates/condition_env_test.dart` (24 tests) | faithful |
| `TestResolveConditionPath` (202) — absolute/relative/symlink/traversal/empty/nonexistent + rig-scoped envelope/base + symlink-escape | `gates/condition_path_test.dart` (34 tests) | faithful |
| `TestRunCondition*` (525-887) — pass/fail/timeout/timeout-retry/not-found/capture/truncation/parent-cancel/text-file-busy/workdir/env | `gates/gate_runner_test.dart` (27) + `gates/output_capture_test.dart` (10) + `gates/gate_runner_integration_test.dart` | faithful |
| `TestRunConditionTimeoutRetry` (734) — RetryCount==budget on persistent deadline | `gates/gate_runner`; **e2e** `runtime_lifecycle_conformance` (timeout→retry, 4 spawns) | faithful + **e2e (filled-here)** |
| `TestConditionPATHUsesResolvedToolDirs` (688) | `gates/condition_env` (PATH resolution) | faithful |

## events_test.go (8) + metadata_test.go (6) — payload + scalar codecs (Track A)

| gc test func | Dart coverage | status |
|---|---|---|
| `TestMarshalPayload_*` (events_test.go:9-162) — Created/Iteration/Terminated/WaitingManual/ManualAction payload round-trip + null-field presence | reducer event payload tests + `convergence/convergence_metadata_test.dart` | faithful |
| `TestGateResultPayload_NullExitCode` (164) / `TestGateResultToPayload_WithDuration` (199) | `gates/` gate-result-payload mapping | faithful |
| `TestDeliveryTiers` (186) — critical/recoverable/best_effort | event delivery tier literals | faithful (literal) |
| `TestNormalizeVerdict` (metadata_test.go) | `gate_literals` Verdict.normalize (incl. go1.26 BOM/İ differential) | faithful |
| `TestEncodeDecodeInt` / `TestDecodeIntEdgeCases` | `convergence/go_scalars_test.dart` (go-faithful, pinned to go1.26) | faithful |
| `TestEncodeDecodeDuration` / `TestDecodeDurationEdgeCases` | `convergence/go_duration_test.dart` (ParseDuration/String + overflow) | faithful |
| `TestMetadataPresent` | `convergence/convergence_metadata_test.dart` | faithful |

## create_test.go (10) + retry_test.go (9) — create/retry surface

**n-a — out of M2 reducer scope (ADR-0000 A22 item 4 / A19 item (a)).**
`CreateHandler` and `RetryHandler` mint a *new* convergence root; they are the
create surface, not a `reduce(state,event,snapshot)` transition. The reducer never
*creates* a loop — only the trigger-gated wisp-close *hold* (`TR8`, covered) and
the `triggerPassed` *advance* (`TR2/TR5`, covered) are in it. The create surface
(incl. partial-create cleanup, gate-config validation, trigger-defers-first-wisp,
rig persistence, retry config copy / retry_source / created event) lands with M3.
The grid's recovery pass DOES cover the **partial-creation cleanup** *recovery*
(`StateCreating` → terminate, `reconcile.go:210-236`, recovery test 5) — the
crash-recovery half of create that IS in M2 scope.

## Host-process / admission helpers — n-a (not the state machine)

`acl_test.go` (4: token scrub), `artifact_test.go` (8: dir create/validate),
`capture_test.go` (1: truncate — covered by `gates/output_capture`),
`depfilter_test.go` (6: dependency-filter — ready-work/M2 Decision 5 differential
harness, not the convergence machine), `evaluate_test.go` (8: evaluate-step
resolution — injected create-time step), `formula_test.go` (15: formula
validation — create-time admission), `template_test.go` (8: template context /
ExtractVars — `ArtifactDirFor` + var threading covered via `gates` +
`recovery`), `token_test.go` (5: rig token file I/O). These are host-process,
admission, or ready-work concerns outside the ported state machine; `capture` and
`ArtifactDirFor`/`ExtractVars` that the machine *consumes* are covered where used.

---

## Real bugs found

**None.** Every faithful gc test transliterated or driven end-to-end this wave
passed against the current Dart `lib/` on the first green run; no `reduce` /
recovery / gate / runtime divergence surfaced. The drain-with-fresh-gate
regression that A27 records (the gate-vs-requeue ordering bug) was already found
and fixed in Track G and is regression-guarded by `drain_and_recovery_test.dart`;
Track H re-exercises that path end-to-end via the manual-hold and trigger chains
and confirms it stays green.

**Round-1 conformance-lens fills (composition gaps, NOT code bugs).** Three e2e
compositions the per-component units pinned individually but never actuated
together were added to `runtime_lifecycle_conformance_test.dart`, each green
against the unmodified runtime/reducer (the gap was test coverage, not a
divergence):

1. **Gate-PASS operator-stop drain → approved** (`TestStopHandler_DrainCompletedIteration`,
   stop_test.go:52). The prior drain e2e tests only drove a manual-gate drain
   (short-circuits to waiting_manual) and a default-fail `FakeGate` condition
   drain (iterates) — neither approves. The fill drains a closed-but-unprocessed
   active wisp with a CACHED passing gate (replay branch), asserting the drain
   ITSELF produces `ApprovedAction(handlerWispClosed, gateOutcome=pass)` and the
   postDrain stop re-entry is a `drainTerminated` skip — gc's
   `terminal_reason==TerminalApproved` "drain should have approved" oracle.
2. **Hybrid gate through the real `ReconcilerRuntime`** (handler.go:318-327;
   hybrid.go:8-22). Hybrid was reducer-/gate-runner-only; the fill drives a
   hybrid loop (scoped agent verdict + condition gate) through the phase split,
   asserting phase-1 threads `GC_AGENT_VERDICT` into the gate subprocess env and
   phase-2 fires the terminal (PASS→approved) / iterate (FAIL-below-max) arms.
3. **Operator-stop from a HOLD state e2e** (manual.go:258;
   `TestStopHandler_FromWaitingManual_NoForceClose`, stop_test.go:204). The
   non-drain stop orchestration was reducer-only (G-STOP-4 / M15); the fill
   submits `operatorStop` through `runtime.submit` over loops pre-seeded at
   `waiting_manual` and `waiting_trigger`, asserting a plain `StoppedAction`
   terminal — no drain, no force-close, no synthetic iteration event.

## What this report demonstrates (DoD criterion 1)

The state machine (handler 9-step + operator + trigger) and recovery (reconcile.go
paths + idempotency) are **conformance-green against the transliterated gc suite**:
every must-priority gc test function is covered faithfully (per-component) and the
representative gc lifecycle branches are additionally driven end-to-end through the
real `ReconcilerRuntime` (reduce→gate→actuate→recovery). The only gc tests not
covered are the create/retry surface (M3) and live-store-I/O error arms (the Track
G actuation seam, ADR-0000 A25/A27), each justified above.
