# Conformance inventory — the "other" convergence tests

**Scope.** ADR-0003 Decision 7 names six test files as the executable spec for Track H
(`handler_test.go`, `reconcile_test.go`, `manual_test.go`, `trigger_test.go`, `gate_test.go`,
`hybrid_test.go`) — those are specified elsewhere. This document inventories **every remaining
`*_test.go`** in `gascity/internal/convergence/` and classifies each test (and each table row /
sub-case) for the Dart port. Source of truth (read-only, pinned on disk):
`/Users/nico/development/com.gastownhall/gascity/internal/convergence/`.

Directory census (all 21 test files): the named six, plus the **15 files inventoried here**:

| File | Test fns | Verdict at a glance |
|---|---|---|
| `metadata_test.go` | 6 | must — Track A codec |
| `create_test.go` | 10 | must — creation contract the reconciler consumes |
| `events_test.go` | 8 | must — event payload JSON contract (shadow-mode diffing) |
| `evaluate_test.go` | 8 | must — evaluate-step resolution + prompt validation |
| `formula_test.go` | 15 | must — formula/var validation |
| `template_test.go` | 8 | must — artifact path layout + `var.*` extraction |
| `capture_test.go` | 1 (9 rows) | must — output truncation (Track D) |
| `condition_test.go` | 19 | mostly must — gate env/exec/containment (Track D) |
| `artifact_test.go` | 8 | mostly must — artifact dir layout + containment |
| `stop_test.go` | 10 | must — operator-stop transition (complements `manual_test.go`) |
| `retry_test.go` | 9 | must — retry-as-new-loop (invariant 6 corollary) |
| `depfilter_test.go` | 6 | should — pure, but **dead code at pinned HEAD** (see note) |
| `acl_test.go` | 4 | 1 should / 3 skip — token ACL is gc-runtime enforcement |
| `token_test.go` | 5 | skip — gc controller-token file lifecycle |
| `testenv_import_test.go` | 0 | skip — generated blank import of gc's testenv |

Priority rubric: **must** = pure domain behavior (or M2-DoD gate-contract behavior) the Dart
suite keeps · **should** = valuable but runtime/platform-coupled or currently unreferenced
upstream · **skip** = gc-runtime-specific (reason given, one line).

ADR-0003 invariants referenced below by number: 1 monotonic dedup · 2 write ordering
(`last_processed_wisp` LAST; `gate_outcome_wisp` last in gate persistence) · 3 idempotency keys ·
4 iteration derived from closed children · 5 speculative pour · 6 terminal irreversibility ·
7 single writer. "D3" = the gate execution contract (ADR-0003 Decision 3). Transition-table rows
quoted from ADR-0003 §Decision 2.

---

## Shared fixture: what the Dart fake store/emitter must support

The non-runtime tests below all run against `fakeStore` + `fakeEmitter` defined in
`handler_test.go:18–305` (shared by the whole package — the Dart conformance suite needs ONE
fake pair for create/retry/stop AND the named-six suites):

- `fakeStore` (handler_test.go:24–42) holds `beads map[id]→{info, metadata, children}` and
  implements the full `Store` interface (handler.go:69–114): `GetBead`, `GetMetadata` (returns a
  **copy**, handler_test.go:93–98), `SetMetadata`, `CloseBead`, `DeleteBead`, `Children`,
  `PourWisp`, `PourSpeculativeWisp`, `ActivateWisp`, `FindByIdempotencyKey`,
  `CountActiveConvergenceLoops`, `CreateConvergenceBead`.
- **Injectable failure hooks** (handler_test.go:29–33): `PourWispFunc`,
  `PourSpeculativeWispFunc`, `FindByIdempotencyKeyFunc`, `ActivateWispFunc`, `GetBeadFunc` —
  the Dart fake needs settable closures for the same five seams.
- **`WriteLog []string`** (handler_test.go:38–39, appended at every `SetMetadata`,
  handler_test.go:109): records the *key* of every metadata write **in order** — this is how
  write-ordering (invariant 2) assertions work. Non-negotiable for the Dart fake.
- `addBead(id, status, parentID, idempotencyKey, meta)` (handler_test.go:48–71) registers
  parent→child links; `CreatedAt = now-10m`, `ClosedAt = now`.
- Pour is **idempotent**: `pourWisp` returns the existing bead ID when a bead with the same
  `IdempotencyKey` exists (handler_test.go:187–192) — invariant 3; otherwise mints
  `wisp-<counter>` with status `in_progress`. `CreateConvergenceBead` mints `conv-<counter>`
  with status `in_progress` (handler_test.go:253–267).
- `CloseBead(id, reason)` sets status `closed` and stamps metadata key `close_reason`
  (handler_test.go:113–129).
- Missing beads error by wrapping a sentinel (`beads.ErrNotFound`, handler_test.go:81) —
  recovery code distinguishes not-found from transient store failure (handler.go:70–72); the
  Dart fake needs a typed `BeadNotFound` error.
- `fakeEmitter` (handler_test.go:279–305): records `{Type, EventID, BeadID, Payload, Recovery}`
  per `Emit`; helper `findEvent(type)` returns the first match.

Key literals used everywhere:

- `IdempotencyKey(beadID, n)` = `converge:{beadID}:iter:{n}` (handler.go:19–21).
  `ParseIterationFromKey` uses the **last** index of `:iter:` and rejects negatives
  (handler.go:26–39).
- `HandlerAction` values (handler.go:120–128): `iterate`, `approved`, `no_convergence`,
  `waiting_manual`, `waiting_trigger`, `stopped`, `skipped`.
- Close reasons (handler.go:46–55) — all **≥ 20 chars** because bd's
  `validation.on-close=error` validator rejects shorter `close_reason` (handler.go:41–45):
  `CloseReasonCreateRollback` = `convergence: bead-create rollback after error`,
  `CloseReasonRetryRollback` = `convergence: retry-create rollback after error`,
  `CloseReasonManualApprove` = `convergence: iteration closed by manual approve`,
  `CloseReasonManualSupersede` = `convergence: active wisp superseded during manual stop`,
  `CloseReasonManualStop` = `convergence: iteration closed by manual stop`,
  `CloseReasonReconcileDone` = `convergence reconcile: terminated-state bead closed`,
  `CloseReasonHandlerCleanup` = `convergence: terminated state observed; closing root`,
  `CloseReasonHandlerRoot` = `convergence: workflow handler closing root after terminate`.

---

## 1. `metadata_test.go` — Track A codec (ALL MUST)

Source under test: `metadata.go`. Key/value domains the codec must encode:

| Domain | Values (exact literals) | Source |
|---|---|---|
| `convergence.state` | `creating`, `active`, `waiting_manual`, `waiting_trigger`, `terminated` | metadata.go:50–56 |
| `convergence.trigger` | `""` (none), `event` | metadata.go:60–63 |
| `convergence.gate_mode` | `manual`, `condition`, `hybrid` | metadata.go:66–70 |
| `convergence.gate_timeout_action` | `iterate`, `retry`, `manual`, `terminate` | metadata.go:73–78 |
| `convergence.terminal_reason` | `approved`, `no_convergence`, `stopped`, `partial_creation` | metadata.go:81–86 |
| `convergence.gate_outcome` | `pass`, `fail`, `timeout`, `error` | metadata.go:89–94 |
| `convergence.waiting_reason` | `manual`, `hybrid_no_condition`, `timeout`, `sling_failure` | metadata.go:97–102 |
| verdicts (normalized) | `approve`, `approve-with-risks`, `block` | metadata.go:105–109 |

Full field-constant list (metadata.go:12–44) — note this is **31 keys**, not the 16 in
M2-BUILD-ORDER Track A; the extra 15: `gate_retry_count`, `terminal_reason`, `terminal_actor`,
`waiting_reason`, `retry_source`, `city_path`, `rig`, `evaluate_prompt`, `gate_stdout`,
`gate_stderr`, `gate_duration_ms`, `gate_truncated`, `pending_next_wisp`, `trigger`,
`trigger_condition`. Plus the prefix `var.` (metadata.go:47).

| Test | Scenario | Exact assertions | Inv. | Fixture | Priority |
|---|---|---|---|---|---|
| `TestNormalizeVerdict` (metadata_test.go:8–54, **24 rows**) | Given a raw agent verdict string, when normalized, then map to canonical verdict | Canonical pass-through: `approve`, `approve-with-risks`, `block`. Past tense: `approved`→`approve`, `blocked`→`block`, `approve-with-risk`/`approved-with-risks`/`approved-with-risk`→`approve-with-risks`. Case-insensitive (`APPROVE`, `Approved`, `BLOCK`, `Blocked`, `Approve-With-Risks`, `APPROVED-WITH-RISKS`). Whitespace trimmed (`"  approve  "`, `"\tapproved\n"`, `" block "`). **Empty/whitespace-only → `block`. Unknown (`maybe`, `yes`, `reject`, `123`) → `block`** (fail-closed) | D3 (agent-verdict channel read, not reinterpreted) | none (pure) | **must** |
| `TestEncodeDecodeInt` (56–80, 5 rows) | Round-trip int↔string | `0`→`"0"`, `1`→`"1"`, `-1`→`"-1"`, `42`→`"42"`, `999999`→`"999999"`; decode returns `(n, true)` | 1, 4 (iteration arithmetic) | none | **must** |
| `TestDecodeIntEdgeCases` (82–100) | Invalid decode inputs | `""`→`(0,false)`, `"abc"`→`(0,false)`, `"3.14"`→`(0,false)` | 1, 4 | none | **must** |
| `TestEncodeDecodeDuration` (102–120, 5 rows) | Round-trip Go durations | `0`, `1s`, `5m`, `2h30m`, `100ms` all round-trip exactly | D3 (gate_timeout) | none | **must** (see trap #1) |
| `TestDecodeDurationEdgeCases` (122–134) | Invalid duration decode | `""`→`(0,false)`, `"not-a-duration"`→`(0,false)` | D3 | none | **must** |
| `TestMetadataPresent` (136–177) | Absent vs empty-string distinction | key with value → `("active", true)`; key with `""` → `("", true)`; absent key → `("", false)`; nil map → `("", false)` | 2 (the handler branches on present-vs-empty markers, e.g. `gate_outcome_wisp`) | none | **must** |

---

## 2. `create_test.go` — creation contract (9 must / 1 should)

Source: `create.go:45–186` (`CreateHandler`). The reconciler consumes beads in the states this
handler produces; the recovery rows `""→adopt/pour` and `creating→terminate` are defined
against this write sequence.

**⚠ ordering (create happy path, create.go:98–168):** `state=creating` FIRST after
`CreateConvergenceBead` → 12 fixed metadata writes in declaration order
(`formula, target, max_iterations, gate_mode, gate_condition, gate_timeout,
gate_timeout_action, city_path, rig, evaluate_prompt, trigger, trigger_condition`,
create.go:103–116) → `var.*` writes (**Go map iteration = random order — do not assert var
order**, create.go:124–128) → `state=active` (create.go:152) → **pour** (after `active`!) →
`active_wisp` → `iteration=1` LAST. A crash between `active` and pour leaves an active loop
with no wisp — that is exactly what the recovery path `active→recover/replay/pour` repairs.

**⚠ ordering (trigger path, create.go:133–149):** `iteration=0` → `state=waiting_trigger` →
emit `convergence.created` → return with **no pour, empty FirstWispID**.

**Rollback contract** (`closeBead`, create.go:91–95): on any failure after bead creation, write
`state=terminated` then `CloseBead(beadID, CloseReasonCreateRollback)`, errors ignored, original
cause returned.

| Test | Scenario | Exact assertions | Inv./row | Fixture | Priority |
|---|---|---|---|---|---|
| `TestCreateHandler_Basic` (create_test.go:12–103) | Valid params → root bead + first wisp + event | Result has non-empty `BeadID`/`FirstWispID`. Root metadata: `convergence.formula`=`test-formula`, `convergence.target`=`test-agent`, `convergence.state`=`active`, `convergence.max_iterations`=`"5"`, `convergence.gate_mode`=`manual`, `convergence.active_wisp`=FirstWispID, `convergence.iteration`=`"1"`, `var.doc_path`=`/docs/readme.md`, `convergence.city_path`=`/home/test/city`. Wisp's idempotency key == `converge:{beadID}:iter:1`. Exactly **1** emitted event, type `convergence.created`, payload `formula`=`test-formula`, `first_wisp_id`=FirstWispID | 3 | fakeStore + fakeEmitter | **must** |
| `TestCreateHandler_Validation` (105–147, **3 rows**) | Missing field → error, nothing created | Error contains `formula is required` / `target is required` / `max_iterations must be positive` (create.go:46–54) | — | fakeStore | **must** |
| `TestCreateHandler_PartialCreateCleanup` (149–186) | `PourWispFunc` fails → rollback | Error contains `pouring first wisp`; some bead exists with status `closed` AND `convergence.state`=`terminated` | recovery row `creating→terminate` (this is the producer side) | fakeStore with `PourWispFunc` returning error | **must** |
| `TestCreateHandler_InvalidGateConfig` (188–213) | `GateMode: "invalid-mode"` → error **before any bead exists** | error non-nil; `len(store.beads) == 0` (gate config validated via `ParseGateConfig` before `CreateConvergenceBead`, create.go:60–67) | — | fakeStore | **must** |
| `TestCreateHandler_StateCreatingBeforeActive` (215–257) | Write-ordering of the two `convergence.state` writes | In `WriteLog`, the first `convergence.state` index (creating) < second (active) | **2** | fakeStore `WriteLog` | **must** |
| `TestCreateHandler_DefaultGateMode` (259–283) | Empty `GateMode` defaults | `convergence.gate_mode` == `manual` (create.go:55–57) | — | fakeStore | **must** |
| `TestCreateHandler_PersistsRig` (285–321) | `Rig: "gascity-prod"` persisted + in payload | metadata `convergence.rig`=`gascity-prod`; 1 event; payload `rig`=`gascity-prod` | D6 (rig is the coexistence partition marker) | fakeStore + emitter | **must** |
| `TestCreateHandler_TriggerDefersFirstWisp` (323–378) | `Trigger: "event"` + condition → no pour | `FirstWispID == ""`; metadata: `state`=`waiting_trigger`, `iteration`=`"0"`, `trigger`=`event`, `trigger_condition`=`/scripts/check-chunk-complete`, `active_wisp`=`""`; **0 children**; `convergence.created` payload `first_wisp_id`=`""` | row `creating/entry → waitingTrigger` | fakeStore + emitter | **must** |
| `TestCreateHandler_TriggerRequiresCondition` (380–401) | `Trigger: "event"` without condition | error contains `requires a trigger condition` (trigger.go:35: `parsing trigger config: trigger mode "event" requires a trigger condition path`); `len(store.beads) == 0` | — | fakeStore | **must** |
| `TestCreateHandler_EmptyRigForCityScope` (403–425) | Empty Rig = city/HQ scope | `meta["convergence.rig"] == ""` | D6 | fakeStore | should (trivial; empty-write vs absent is indistinguishable in the Go map fake) |

---

## 3. `events_test.go` — event payload JSON contract (ALL MUST)

Source: `events.go`. Needed for the fake-emitter assertions in every handler suite AND for
shadow-mode diffing against gc's actual event stream. Event types (events.go:11–20):
`convergence.created|iteration|terminated|waiting_manual|manual_approve|manual_iterate|manual_stop|trigger_advance`.
Event-ID formats (events.go:38–81): `converge:{bead}:created`,
`converge:{bead}:iter:{N}:iteration`, `converge:{bead}:iter:{N}:waiting_manual`,
`converge:{bead}:terminated`, `converge:{bead}:manual_approve`,
`converge:{bead}:iter:{N}:manual_iterate`, `converge:{bead}:manual_stop`,
`converge:{bead}:iter:{N}:trigger_advance` (deliberately distinct from the iteration ID —
events.go:74–81).

**⚠ JSON shape:** pointer fields *without* `omitempty` serialize as **explicit `null`**:
`retry_source` (CreatedPayload), `gate_outcome`, `gate_result`, `waiting_reason`,
`next_wisp_id`, `iteration_tokens`, `cumulative_tokens` (IterationPayload), `exit_code`
(GateResultPayload), `wisp_id`/`next_wisp_id` (ManualActionPayload). Only `rig` carries
`omitempty` (absent when empty). The Dart codec must keep nulls present.

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestMarshalPayload_CreatedPayload` (events_test.go:9–35) | Round-trip CreatedPayload incl. `RetrySource` pointer | decoded `formula`==input; `retry_source` round-trips as `"gc-conv-old"` | **must** |
| `TestMarshalPayload_IterationPayload_NullFields` (37–70) | Manual-mode iteration payload | raw JSON has key `gate_outcome` with literal value `null`; key `gate_result` with literal `null` (present, not omitted) | **must** |
| `TestMarshalPayload_TerminatedPayload` (72–98) | Terminated payload round-trip | `terminal_reason`==`approved`, `total_iterations`==3, `final_status`==`"closed"` | **must** |
| `TestMarshalPayload_WaitingManualPayload` (100–135) | Timeout-driven waiting_manual | `reason`==`timeout`; `gate_outcome` deref == `timeout`; nested `GateResultPayload{exit_code:1, stdout:"check failed", duration_ms:55000}` round-trips | **must** |
| `TestMarshalPayload_ManualActionPayload` (137–162) | Operator iterate payload | `actor`==`operator:alice`, `prior_state`==`waiting_manual`, `new_state`==`active`, `next_wisp_id` deref == `gc-w-10` | **must** |
| `TestGateResultPayload_NullExitCode` (164–184) | Timeout/killed gate | raw JSON `exit_code` is literal `null` | **must** |
| `TestDeliveryTiers` (186–197) | Tier constants | `TierCritical`==`"critical"`, `TierRecoverable`==`"recoverable"`, `TierBestEffort`==`"best_effort"` (events.go:26–35; tier→event mapping: critical = Iteration+Terminated, recoverable = Created+WaitingManual+ManualIterate, best_effort = ManualApprove+ManualStop) | **must** |
| `TestGateResultToPayload_WithDuration` (199–215) | GateResult→payload conversion | non-nil payload; `duration_ms`==2500 from `2500ms` duration; (events.go:195–206: returns **nil** when `Outcome == ""` — manual mode) | **must** |

---

## 4. `evaluate_test.go` — evaluate-step resolution (ALL MUST)

Source: `evaluate.go`. `EvaluateStepName` = `"evaluate"` (evaluate.go:14);
`DefaultEvaluatePromptPath` = `prompts/convergence/evaluate.md` (evaluate.go:18); required
substrings = `bd meta set` AND `convergence.agent_verdict` (evaluate.go:22–25).

**⚠** `ResolveEvaluateStep` canonicalizes `cityPath` via `EvalSymlinks` first (best-effort
fallback to `Clean` if it doesn't exist, evaluate.go:46–49), rejects escape via relative-path
check (`escapes city directory`), and — **stricter than condition paths** — rejects ANY symlink
in the resolved path (`evaluate prompt path contains symlinks`, evaluate.go:60–63).

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestResolveEvaluateStep_DefaultPath` (evaluate_test.go:9–23) | Formula without custom prompt | `step.Name`==`evaluate`; `step.PromptPath`==`{city}/prompts/convergence/evaluate.md` | **must** |
| `TestResolveEvaluateStep_CustomPath` (25–42) | `EvaluatePrompt: "custom/my-evaluate.md"` | PromptPath == `{city}/custom/my-evaluate.md` | **must** |
| `TestResolveEvaluateStep_PathTraversal` (44–56) | `"../../etc/passwd"` | error; message contains `escapes` | **must** (D3 containment) |
| `TestValidateEvaluatePrompt_Valid` (58–63) | Content with both substrings | nil error | **must** |
| `TestValidateEvaluatePrompt_MissingBdMetaSet` (65–74) | Has verdict key only | error mentions `bd meta set` | **must** |
| `TestValidateEvaluatePrompt_MissingAgentVerdict` (76–85) | Has `bd meta set` only | error mentions `convergence.agent_verdict` | **must** |
| `TestValidateEvaluatePrompt_MissingBoth` (87–100) | Neither substring | error mentions both | **must** |
| `TestValidateEvaluatePrompt_EmptyContent` (102–114) | Empty bytes | error mentions both | **must** |

---

## 5. `formula_test.go` — formula/var validation (ALL MUST)

Source: `formula.go`. Errors are **accumulated** and joined as
`convergence validation failed:\n  - {e1}\n  - {e2}` (formula.go:60) /
`required vars validation failed:\n  - …` (formula.go:82).

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestValidateForConvergence_ConvergenceFalse` (formula_test.go:9–22) | `Convergence: false` | error contains `convergence flag must be true` | **must** |
| `TestValidateForConvergence_ReservedStepName` (24–37) | Step named `evaluate` | error contains `reserved for controller injection` | **must** |
| `TestValidateForConvergence_Valid` (39–48) | convergence=true, no reserved steps, no cityPath | nil error (validation of the prompt is **skipped when cityPath==""** or readFile==nil, formula.go:42) | **must** |
| `TestValidateForConvergence_CustomEvaluatePromptValid` (50–68) | readFile returns content with both substrings at `/city/custom/evaluate.md` | nil error | **must** |
| `TestValidateForConvergence_CustomEvaluatePromptMissingSubstrings` (70–91) | Prompt missing both | error mentions `bd meta set` and `convergence.agent_verdict` | **must** |
| `TestValidateForConvergence_CustomEvaluatePromptInvalid` (93–112) | Only `bd meta set` present | error mentions `convergence.agent_verdict` | **must** |
| `TestValidateForConvergence_CustomEvaluatePromptReadError` (114–132) | readFile errors | error contains `reading evaluate prompt` | **must** |
| `TestValidateForConvergence_MultipleErrors` (134–151) | flag false AND reserved step | single error containing BOTH messages (accumulation, not short-circuit) | **must** |
| `TestValidateRequiredVars_AllPresent` (153–163) | required ⊆ vars (extra ok) | nil error | **must** |
| `TestValidateRequiredVars_Missing` (165–181) | 2 of 3 missing | error mentions `branch` AND `target` (both accumulated) | **must** |
| `TestValidateRequiredVars_EmptyMap` (183–192) | empty vars | error mentions `repo` | **must** |
| `TestValidateRequiredVars_NilMap` (194–200) | nil vars | error | **must** |
| `TestValidateRequiredVars_InvalidKeyNames` (202–215) | required contains `invalid.key` | error mentions `invalid.key` even though it IS present in vars (key-shape check precedes presence check, formula.go:69–76) | **must** |
| `TestValidateRequiredVars_NoRequired` (217–221) | nil required list | nil error | **must** |
| `TestValidateVarKey` (223–257, **19 rows**) | Identifier validity | true: `repo`, `branch_name`, `_private`, `x`, `abc123`, `A`, `camelCase`, `_`, `__double`, `a1b2c3`. false: `""`, `invalid.key`, `has space`, `with-hyphen`, `123start`, `a/b`, `a=b`, `hello world`, `" leading"` | **must** (see trap #3: Go `unicode.IsLetter` accepts non-ASCII letters) |

---

## 6. `template_test.go` — template context + artifact layout (ALL MUST)

Source: `template.go`. `ArtifactDirFor` = `{cityPath}/.gc/artifacts/{beadID}/iter-{N}`
(template.go:23–25). `ExtractVars` strips the `var.` prefix and **always returns a non-nil
map** (template.go:43–51).

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestArtifactDirFor` (template_test.go:8–47, 3 rows) | Path format | `(/home/user/city, abc123, 3)` → `/home/user/city/.gc/artifacts/abc123/iter-3`; same for iter-1 and iter-100 | **must** |
| `TestNewTemplateContext_WithVars` (49–88) | Build context from root metadata | `BeadID`/`WispID`/`Iteration` pass through; `ArtifactDir` == ArtifactDirFor(city, bead, iter); `Formula`==`deploy`; `RetrySource`==`""`; `Var` has exactly 2 entries `repo→my-repo`, `branch→main` (the `other.key` and `convergence.*` keys excluded) | **must** |
| `TestNewTemplateContext_WithoutVars` (90–100) | No `var.*` keys | `len(Var)==0` | **must** |
| `TestNewTemplateContext_WithRetrySource` (102–108) | retrySource param | `RetrySource`==`prev-bead-id` (nil metadata tolerated) | **must** |
| `TestExtractVars_MixedMetadata` (110–142) | Mixed keys | exactly 3 vars (`repo`, `branch`, `target`), prefix stripped, non-`var.` keys absent | **must** |
| `TestExtractVars_EmptyMap` (144–149) | `{}` | empty result | **must** |
| `TestExtractVars_NilMap` (151–159) | nil | **non-nil** empty map | **must** |
| `TestExtractVars_NoVarKeys` (161–170) | only `convergence.*` | empty result | **must** |

---

## 7. `capture_test.go` — output truncation (MUST)

Source: `capture.go`. `MaxOutputBytes = 4096` (capture.go:13). `TruncateOutput` backs off to a
UTF-8 rune boundary, scanning at most `utf8.UTFMax`(4)−1 bytes back (capture.go:47–69).

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestTruncateOutput` (capture_test.go:9–95, **9 rows**) | byte-slice truncation | under limit `("hello",10)`→`("hello",false)`; at limit `(5)`→no trunc; over limit `("hello world",5)`→`("hello",true)`; empty/nil → `("",false)`; `maxBytes=0` + empty → `("",false)`; `maxBytes=0` + data → `("",true)`; 4196 `x`s @4096 → exactly 4096 `x`s + true; `"hello 世界!"` @ maxBytes=8 (cuts inside 世) → truncated=true AND result is **valid UTF-8** (boundary backed off) | D3 (gate stdout/stderr capture) | **must** (see trap #7 — must operate on BYTES, not Dart UTF-16 strings) |

---

## 8. `condition_test.go` — gate env / path containment / subprocess (16 must / 2 should / 1 skip)

Source: `condition.go`. This is the Track D executable spec beyond `gate_test.go`.

### Env contract (`ConditionEnv.Environ`, condition.go:79–150)

Whitelist-built (never inherits the parent env wholesale). Always present:
`PATH={conditionPATH()}`, `HOME={CityPath || os.TempDir()}` (**HOME is the city path** —
sandbox from the operator's real home, condition.go:80–89), `TMPDIR={os.TempDir()}`,
`BEADS_DIR={StorePath||CityPath}/.beads`, `GC_BEAD_ID`, `GC_ITERATION`, `GC_WISP_ID`,
`GC_ITERATION_DURATION_MS`, `GC_CUMULATIVE_DURATION_MS`, `GC_MAX_ITERATIONS`, plus
`GC_CITY`/`GC_CITY_PATH`/`GC_CITY_RUNTIME_DIR={city}/.gc/runtime` (via citylayout,
condition.go:102). Optional — **omitted entirely when empty** (not set to `""`):
`GC_DOC_PATH`, `GC_AGENT_VERDICT`, `GC_AGENT_PROVIDER`, `GC_AGENT_MODEL`, `GC_WORK_DIR`,
`GC_STORE_PATH`, `GC_ARTIFACT_DIR`, `GC_MOLECULE_DIR` (condition.go:105–128). Pass-through
from the controller's env when non-empty (condition.go:132–147): `BEADS_DOLT_AUTO_START`,
`BEADS_DOLT_SERVER_HOST`, `BEADS_DOLT_SERVER_PORT`, `BEADS_DOLT_SERVER_USER`,
`BEADS_DOLT_PASSWORD`, `GC_DOLT`, `GC_DOLT_HOST`, `GC_DOLT_PORT`, `GC_DOLT_USER`,
`GC_DOLT_PASSWORD` (10 keys), plus `GC_INTEGRATION_REAL_BD` (gc-test shim).
`SafePATH` = `/usr/local/bin:/usr/bin:/bin` (condition.go:20); `conditionPATH()` prepends the
dirs of resolved `bd`, `gc`, `dolt`, `jq` binaries, deduped, then SafePATH entries
(condition.go:31–53).

### Exit-code → outcome mapping (`runOnceNoPreExecRetry`, condition.go:315–404)

| Condition | Outcome | ExitCode |
|---|---|---|
| exit 0 | `pass` | `0` |
| non-zero exit | `fail` | the code |
| per-script deadline exceeded | `timeout` | **nil** |
| **parent** context cancelled | `error` (checked BEFORE timeout — never misclassified, condition.go:350–358) | nil |
| pre-exec failure (not found, perm) | `error`, `Stderr = err.Error()` (NOT script output, condition.go:385–391) | nil |

Retry (condition.go:269–287): retry **only on `timeout`**, up to `retryBudget`;
`RetryCount` = number of retries actually performed. `cwd` precedence: `WorkDir` >
`StorePath` > `CityPath` (condition.go:320–326). ETXTBSY ("text file busy") pre-exec errors are
retried up to 5 times with 25ms delay (condition.go:22–25, 290–313). Output captured via
bounded buffers of `MaxOutputBytes + 4` then truncated to `MaxOutputBytes`
(condition.go:332–345).

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestConditionEnvEnviron` (condition_test.go:15–80) | Fully-populated env | All 17 key=value pairs per the table above, incl. `BEADS_DIR=/home/test/city/.beads`, `GC_ITERATION=3`, `GC_CITY_RUNTIME_DIR=/home/test/city/.gc/runtime`, `GC_AGENT_VERDICT=approve`; `HOME` and `TMPDIR` present | **must** |
| `TestConditionEnvEnvironOptionalEmpty` (82–116) | Optional fields empty | `GC_DOC_PATH`, `GC_AGENT_VERDICT`, `GC_AGENT_PROVIDER`, `GC_AGENT_MODEL`, `GC_MOLECULE_DIR`, `GC_ARTIFACT_DIR` all **absent** (not empty-valued); `GC_BEAD_ID`/`PATH` still present | **must** |
| `TestConditionEnvEnvironPreservesIntegrationRealBD` (118–141) | gc integration bd shim passthrough | — | **skip** — `GC_INTEGRATION_REAL_BD` exists only for gc's own integration-test bd shim |
| `TestConditionEnvEnvironUsesStorePathForBeadsDir` (143–169) | StorePath set | `BEADS_DIR={store}/.beads`, `GC_STORE_PATH=/rig`, `GC_CITY=/city` (rig-scoped store overrides BEADS_DIR but not GC_CITY) | **must** |
| `TestConditionEnvEnvironPreservesDoltConnection` (171–200) | Dolt env passthrough | `BEADS_DOLT_SERVER_PORT=33061`, `GC_DOLT_HOST=127.0.0.1`, `GC_DOLT_PASSWORD=secret` forwarded verbatim | **must** (the_grid's gates hit the same Dolt server) |
| `TestResolveConditionPath` (202–523, **13 subtests**) | envelope/base dual-root containment | abs path accepted; relative joined under base; **symlink allowed** if contained; `../outside.sh` rejected with error containing `traversal`; empty path → error; nonexistent → error; **#2320**: rel path escaping base but inside envelope (rig under city) resolves; escaping both → `traversal` error; **#2354 sibling layout**: rel path under base (rig sibling of city) resolves; escaping both → rejected; **symlink under base → target outside both** rejected with `symlink target outside containment`; empty base falls back to envelope. ⚠ two sibling-layout subtests are **verbatim duplicates** (lines 351/467 and 376/499 — Go auto-suffixes `#01`; dedupe in Dart) | **must** (D3 containment; pre- AND post-`EvalSymlinks` checks, condition.go:226–248; abs paths skip containment by design, condition.go:216–217) |
| `TestRunConditionPass` (525–552) | exit-0 script | `Outcome`==`pass`, `ExitCode` deref ==0, stdout contains `ok`, `Duration > 0` | **must** |
| `TestRunConditionFail` (554–578) | exit-1 script | `Outcome`==`fail`, `ExitCode` deref ==1, stderr contains `failing` | **must** |
| `TestRunConditionRetriesTextFileBusy` (580–613) | script held open for write, released after 50ms | final `pass`; stdout `ok` (ETXTBSY pre-exec retried ≤5× @25ms) | should — Unix-specific ETXTBSY semantics; verify Dart `Process.start` even surfaces it the same way |
| `TestRunConditionUsesWorkDir` (615–652) | `WorkDir` set | `pass`; `pwd` output contains workDir; `BEADS_DIR` printed == `{city}/.beads` (WorkDir changes cwd, NOT BEADS_DIR); `cat target.txt` works | **must** |
| `TestRunConditionUsesStorePathAsDefaultWorkDir` (654–686) | `StorePath` set, no WorkDir | cwd == storeDir; `BEADS_DIR=={store}/.beads` | **must** |
| `TestConditionPATHUsesResolvedToolDirs` (688–709) | fake `bd`/`gc` on PATH | `conditionPATH()` starts with the tool dir | should — depends on host `LookPath`; keep behavior, fixture differs |
| `TestRunConditionTimeout` (711–732) | sleep 60 @ 100ms timeout | `Outcome`==`timeout`; `ExitCode == nil` | **must** |
| `TestRunConditionTimeoutRetry` (734–755) | same, retryBudget=2 | `Outcome`==`timeout`; `RetryCount == 2` | **must** |
| `TestRunConditionNotFound` (757–769) | nonexistent script | `Outcome`==`error` | **must** |
| `TestRunConditionOutputCapture` (771–796) | stdout + stderr | stdout contains `stdout-data`, stderr contains `stderr-data`, `Truncated == false` | **must** |
| `TestRunConditionOutputTruncation` (798–825) | 5096-byte stdout | `pass`; `len(Stdout) <= 4096`; `Truncated == true` | **must** |
| `TestRunConditionParentContextCancelled` (827–854) | parent ctx pre-cancelled | `Outcome`==`error` (NOT `timeout`); `RetryCount == 0` (no retry against cancelled parent) | **must** |
| `TestRunConditionEnvVarsAvailable` (856–886) | script echoes env | stdout contains `BEAD=bead-env-test`, `ITER=7`, `PATH={conditionPATH()}` | **must** |

---

## 9. `artifact_test.go` — artifact dir creation/validation (6 must / 2 should)

Source: `artifact.go`. `EnsureArtifactDir` = `MkdirAll(ArtifactDirFor(...), 0o755)` wrapped as
`creating artifact directory: …` (artifact.go:14–20). `ValidateArtifactDir`
(artifact.go:28–69): canonicalize root via `Abs`+`EvalSymlinks`, then walk; symlinks must
resolve (multi-hop) inside the root; regular files + dirs allowed; everything else rejected as
`unsafe file type in artifact directory`.

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestEnsureArtifactDir_Creates` (artifact_test.go:13–35) | fresh dir via fake FS | returns `/city/.gc/artifacts/bead-1/iter-2`; exactly **1** FS call, method `MkdirAll`, with that path | **must** (fake FS: needs call recording `{Method, Path}`, pre-seeded `Dirs`, injectable `Errors[path]`) |
| `TestEnsureArtifactDir_AlreadyExists` (37–50) | dir pre-exists in fake | same path returned, no error | **must** |
| `TestEnsureArtifactDir_MkdirError` (52–64) | fake returns `ErrPermission` | error contains `creating artifact directory` | should (error-wrapping text) |
| `TestValidateArtifactDir_Clean` (66–86) | regular file + nested subdir/file | nil error | **must** |
| `TestValidateArtifactDir_EmptyDir` (88–93) | empty dir | nil error | **must** |
| `TestValidateArtifactDir_SymlinkOutside` (95–112) | symlink → other temp dir | error mentioning `symlink`/`outside` (exact: `symlink %q points outside artifact directory: resolves to %q`, artifact.go:56) | **must** (D3 containment) |
| `TestValidateArtifactDir_SymlinkInside` (114–130) | symlink → file in same dir | nil error | **must** |
| `TestValidateArtifactDir_FIFO` (132–147) | `mkfifo` in dir | error contains `unsafe file type` | should — needs `mkfifo`; Dart can shell out or skip on unsupported platforms (Go test skips when unavailable) |

---

## 10. `stop_test.go` — operator stop (ALL MUST)

Source: `manual.go:241–445` (`StopHandler`) — the transition-table row
**`any | operator stop | → terminated | stopped`**. This file complements `manual_test.go`
(covered elsewhere; `setupWaitingManualHandler` used by one test below lives there — the Dart
suite shares one fixture builder set).

Shared fixture `setupActiveHandler` (stop_test.go:15–50): root `root-1` `in_progress` with
`state=active, iteration="1", max_iterations="5", formula=test-formula, target=test-agent,
gate_mode=condition, gate_timeout="60s", gate_timeout_action=iterate, active_wisp=wisp-iter-2,
last_processed_wisp=wisp-iter-1`; child `wisp-iter-1` closed (key `converge:root-1:iter:1`);
child `wisp-iter-2` with parameterized status (key `converge:root-1:iter:2`).

**⚠ ordering (StopHandler, manual.go:230–240 doc + body):** drain closed active wisp through
`HandleWispClosed` first → force-close still-open wisp (`CloseReasonManualSupersede`) → derive
iteration from children (**after** force-close, so it counts it — invariant 4) → clear
`agent_verdict` + `agent_verdict_wisp` (write `""`) → `terminal_reason=stopped` →
`terminal_actor=operator:{user}` → `waiting_reason=""` → `state=terminated` → emit synthetic
`convergence.iteration` (force-closed wisp only) BEFORE CloseBead (TierCritical) → emit
`convergence.terminated` BEFORE CloseBead (TierCritical) → `CloseBead(CloseReasonManualStop)` →
emit `convergence.manual_stop` AFTER CloseBead (TierBestEffort) → **`last_processed_wisp`
written LAST** (invariant 2 commit point).

| Test | Scenario | Exact assertions | Inv./row | Priority |
|---|---|---|---|---|
| `TestStopHandler_DrainCompletedIteration` (stop_test.go:52–78) | active wisp closed + cached gate pass (`gate_outcome_wisp=wisp-iter-2`, `gate_outcome=pass`) → drain terminates via approve; stop becomes no-op | `result.Action`==`stopped`; root `state`==`terminated`; `terminal_reason`==**`approved`** (NOT stopped — the drain won) | rows `active/gate=pass→terminated/approved` + stop; inv. 2 (cached-outcome replay), 6 | **must** |
| `TestStopHandler_DrainThenStop` (80–110) | active wisp closed + cached gate **fail** → drain iterates, then stop proceeds | `Action`==`stopped`; `state`==`terminated`; `terminal_reason`==`stopped`; `convergence.terminated` event emitted | stop row after iterate | **must** |
| `TestStopHandler_ForceClose` (112–144) | active wisp still `in_progress` | wisp-iter-2 status becomes `closed`; root `terminated`/`stopped`; **`last_processed_wisp`==`wisp-iter-2`** (advanced to the force-closed wisp) | inv. 1, 2, 4 | **must** |
| `TestStopHandler_ForceClose_SyntheticEvent` (146–181) | force-close emits synthetic iteration event | `convergence.iteration` event exists; payload `action`==`stopped`, `wisp_id`==`wisp-iter-2`, `gate_outcome`==null, `gate_result`==null, `next_wisp_id`==null | event contract (TierCritical at-least-once) | **must** |
| `TestStopHandler_ClearsStaleVerdict` (183–202) | root has `agent_verdict=approve` + `agent_verdict_wisp` | both cleared to `""` after stop (prevents verdict leaking into a retry) | — | **must** |
| `TestStopHandler_FromWaitingManual_NoForceClose` (204–233) | stop from `waiting_manual` (no active wisp) | `Action`==`stopped`; `state`==`terminated`; **no** `convergence.iteration` event; `convergence.manual_stop` event present | stop row from waitingManual | **must** (fixture: `setupWaitingManualHandler` from manual_test.go) |
| `TestStopHandler_MissingActiveWisp_StopsGracefully` (235–263) | `active_wisp` points at a deleted bead, no replacement | no error; `terminated`/`stopped`; no synthetic iteration event; manual_stop emitted | recovery tolerance (ErrNotFound → recover-or-skip, manual.go:273–288) | **must** |
| `TestStopHandler_ActiveWispMissingBeforeForceClose_StopsGracefully` (265–305) | `GetBeadFunc` returns the wisp once (drain read) then `ErrNotFound` (force-close read) | no error; `state`==`terminated` | same — the ErrNotFound branch at force-close (manual.go:318–333) | **must** (needs call-counting `GetBeadFunc`) |
| `TestStopHandler_MissingActiveWisp_RecoversReplacementBeforeForceClose` (307–335) | stale `active_wisp` deleted; replacement child carries the SAME idempotency key `converge:root-1:iter:2` | replacement gets force-closed; `last_processed_wisp`==`wisp-replacement` | inv. 3 (key-based recovery via `recoverCurrentActiveWisp`, manual.go:447+) | **must** |
| `TestStopHandler_StoreErrorReadingActiveWisp_ReportsError` (337–351) | `GetBeadFunc` returns a non-NotFound error | error EXACTLY `reading active wisp "wisp-iter-2": store unavailable for wisp-iter-2` (transient store failure must NOT be swallowed as not-found) | — | **must** |

---

## 11. `retry_test.go` — retry-as-new-loop (ALL MUST)

Source: `retry.go:21–147` (`RetryHandler`). Retry is the **corollary of invariant 6**: a
terminated loop is never reopened — retry creates a brand-new root bead, copies config, sets
`convergence.retry_source`, and pours iteration 1 of the NEW loop.

Guards: source `state` must be `terminated` (retry.go:29–34); source `terminal_reason` must
NOT be `approved` (retry.go:37–42, error contains `cannot be retried`).
**⚠ ordering (retry.go:83–128):** `state=creating` → 12 metaWrites in order
(`formula, target, gate_mode, gate_condition, gate_timeout, gate_timeout_action,
max_iterations, city_path, rig, evaluate_prompt, retry_source, state=active` — note
**`state=active` is the last metaWrite and happens BEFORE the pour**, unlike create where it is
a separate write; also note **`trigger`/`trigger_condition` are NOT copied** — a retried
triggered loop becomes a plain wisp-close loop) → copy `var.*` (random order) → pour
(`converge:{newBead}:iter:1`) → `active_wisp` → `iteration=1` LAST. Rollback identical to
create but with `CloseReasonRetryRollback`.

Shared fixture `setupTerminatedHandler` (retry_test.go:14–53): closed root `source-1` with
full config metadata (incl. `gate_mode=condition`, `gate_condition=/path/to/gate.sh`,
`gate_timeout="30s"`, `gate_timeout_action=iterate`, `last_processed_wisp=wisp-iter-3`,
`var.doc_path`, `var.branch`) + closed child `wisp-iter-3` (key `converge:source-1:iter:3`).

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestRetryHandler_CarriesRigForward` (55–67) | source has `rig=gascity-prod` | new bead `convergence.rig`==`gascity-prod` (D6 partition marker survives retry) | **must** |
| `TestRetryHandler_Success` (69–103) | retry stopped loop, maxIterations=10 | `NewBeadID`/`FirstWispID` non-empty; `Iteration`==1; new bead: `state`==`active`, `formula`==`test-formula`, `active_wisp`==FirstWispID, `max_iterations`==`"10"` (the NEW value, not the source's 5), `iteration`==`"1"` | **must** |
| `TestRetryHandler_PartialCreateCleanup` (105–131) | `PourWispFunc` fails | error contains `pouring first wisp`; a non-source bead exists with status `closed` + `state`==`terminated` | **must** |
| `TestRetryHandler_InvalidGateConfig` (133–152) | source carries `gate_mode=invalid-mode` | error contains `invalid gate config` (full: `source bead %q has invalid gate config: …`, retry.go:64); NO new bead created (validation precedes creation) | **must** |
| `TestRetryHandler_SourceNotTerminated` (154–171) | source `state=active` | error mentions `terminated` | **must** |
| `TestRetryHandler_SourceApproved` (173–186) | `terminal_reason=approved` | error mentions `approved` and `cannot be retried` | **must** (inv. 6) |
| `TestRetryHandler_CopiesConfig` (188–239) | full config copy | new bead carries: formula, target, `gate_mode`==`condition`, `gate_condition`==`/path/to/gate.sh`, `gate_timeout`==`"30s"`, `gate_timeout_action`==`iterate`, `city_path`, `evaluate_prompt`==`check the code`, `max_iterations`==`"10"`; ALL `var.*` copied (`doc_path`, `branch`, `extra_var`) | **must** |
| `TestRetryHandler_SetsRetrySource` (241–253) | provenance | `convergence.retry_source`==`source-1` | **must** |
| `TestRetryHandler_EmitsCreatedEvent` (255–296) | event contract | one `convergence.created`; `BeadID`==NewBeadID; `EventID`==`converge:{newBead}:created`; payload: formula/target/`gate_mode`==`condition`/`max_iterations`==10/`first_wisp_id`==FirstWispID/`retry_source` deref ==`source-1` | **must** |

---

## 12. `depfilter_test.go` — dependency filter (ALL SHOULD)

Source: `depfilter.go:10–18` (`MatchesDependencyFilter`). **Classification note:** at the
pinned gascity HEAD this function has **zero non-test references** (verified by grep across the
repo) — it is dead code shipped with tests. Pure and trivial to port, but port it only when/if
the_grid adopts `depends_on_filter` semantics; until then keep the spec, defer the code.

| Test | Scenario | Exact assertions | Priority |
|---|---|---|---|
| `TestMatchesDependencyFilter_EmptyFilter` (depfilter_test.go:5–13) | nil or `{}` filter | always matches | should |
| `TestMatchesDependencyFilter_Match` (15–26) | `{terminal_reason: approved}` vs matching meta | true | should |
| `TestMatchesDependencyFilter_Mismatch` (28–39) | value differs (`stopped` vs `approved`) | false | should |
| `TestMatchesDependencyFilter_MissingKey` (41–51) | filter key absent from meta | false | should |
| `TestMatchesDependencyFilter_EmptyStringVsMissing` (53–73) | filter value `""` | does **NOT** match absent key; DOES match key present-and-empty (same absent-vs-empty discipline as `MetadataPresent`) | should |
| `TestMatchesDependencyFilter_MultipleKeys` (75–99) | multi-key AND semantics | all match → true; one mismatch → false | should |

---

## 13. `acl_test.go` — token ACL (1 should / 3 skip)

Source: `acl.go`. `ProtectedPrefix` = `convergence.` (acl.go:6); agent-writable exceptions:
`convergence.agent_verdict`, `convergence.agent_verdict_wisp` (acl.go:10–13); `var.*` always
protected (acl.go:19–21).

| Test | Scenario / classification |
|---|---|
| `TestRequiresToken` (acl_test.go:7–54, **27 rows**) | **should** — pure predicate defining which metadata keys are controller-protected: 19 named `convergence.*` fields → true; the two verdict keys → **false**; `var.doc_path`/`var.branch`/`var.` → true; `random_key`/`merge_strategy`/`""`/`title` → false. Enforcement is gc hook machinery, but the protected/agent-writable partition is domain knowledge the_grid needs the moment it writes convergence metadata into a token-guarded store (M3+). |
| `TestScrubTokenEnv` (56–83) | skip — scrubs `GC_CONTROLLER_TOKEN` from agent-session spawn env; session spawning is gc runtime / M3 `grid_runtime`. |
| `TestScrubTokenEnvNil` (85–90) | skip — nil-passthrough of the same runtime helper. |
| `TestScrubTokenEnvNoToken` (92–105) | skip — no-token copy semantics of the same runtime helper. |

---

## 14. `token_test.go` — controller token file (ALL SKIP)

Source: `token.go` (`.gc/controller.token`, env `GC_CONTROLLER_TOKEN`, atomic
temp-file+rename, mode `0600`).

| Test | Classification |
|---|---|
| `TestGenerateToken` (token_test.go:10–34) | skip — 32-byte crypto-random hex token generation for gc's controller identity; the_grid authenticates to bd as `--actor grid-controller`, not via gc's token file. |
| `TestWriteReadTokenRoundtrip` (36–55) | skip — gc-owned `.gc/` runtime file I/O. |
| `TestWriteTokenFileMode` (57–76) | skip — POSIX 0600 mode of gc's token file. |
| `TestRemoveTokenIdempotent` (78–108) | skip — gc token lifecycle. |
| `TestReadTokenMissingFile` (110–121) | skip — gc token lifecycle. |

---

## 15. `testenv_import_test.go` — SKIP

Generated blank import (`_ "internal/testenv"`) that wires gc's test environment side effects
into the package (testenv_import_test.go:1–5). No tests; nothing to port.

---

## Count summary

| | Files | Test functions | must | should | skip |
|---|---|---|---|---|---|
| Totals | 15 | **117** | **96** | **12** | **9** |

Per file: metadata 6/0/0 · create 9/1/0 · events 8/0/0 · evaluate 8/0/0 · formula 15/0/0 ·
template 8/0/0 · capture 1/0/0 · condition 16/2/1 · artifact 6/2/0 · stop 10/0/0 ·
retry 9/0/0 · depfilter 0/6/0 · acl 0/1/3 · token 0/0/5 · testenv_import 0/0/0.
(Sub-case expansion: ~205 individually-asserted cases once the table rows — 24 verdicts,
27 ACL keys, 19 var keys, 13 path subtests, 9 truncation rows, etc. — are counted.)

---

## Coverage gaps — behaviors no test pins; the Dart suite should ADD these

1. **Exact Go-duration string literals.** `TestEncodeDecodeDuration` only round-trips; it never
   pins `EncodeDuration(2h30m) == "2h30m0s"`, `"100ms"`, `"0s"`. The Dart codec must interop
   with gc-written metadata strings — add literal-pinning cases.
2. **Exact truncation boundary for multi-byte UTF-8.** The `"hello 世界!"` row asserts only
   `wantTrunc`; pin the exact result (`maxBytes=8` backs off to 6 bytes → `"hello "`).
3. **Create rollback on metadata-write failure.** Only the `PourWisp` failure path is tested
   (create_test.go:149); a `SetMetadata` failure mid-`metaWrites` (create.go:117–121) and the
   `close_reason` literal `CloseReasonCreateRollback` are never asserted.
4. **Default title** `"Convergence: " + formula` (create.go:81–83) — unasserted.
5. **RetryHandler quirks (upstream behavior to pin verbatim, candidates for an ADR-0000
   note):** (a) `maxIterations <= 0` is NOT validated (unlike create); (b) `trigger` /
   `trigger_condition` are NOT copied to the new bead (retry.go:88–101) — a retried triggered
   loop silently becomes wisp-close-driven. Neither is tested upstream.
6. **StopHandler idempotent no-op** (already `terminated`+`stopped` → `ActionStopped`, no
   error, manual.go:250–255) — documented, untested. Also untested: stop from
   `waiting_trigger` (allowed by the guard at manual.go:258) and the invalid-state error
   (e.g. `creating` → `cannot stop bead …`).
7. **StopHandler step-6 write order** (`terminal_reason` → `terminal_actor` →
   `waiting_reason=""` → `state=terminated`, then events, then close, then LPW LAST) — no
   `WriteLog` assertion exists; add one (invariant 2 is the whole point).
8. **EventID format functions** (events.go:38–81) have no direct unit tests in these files —
   in particular `EventIDTriggerAdvance` vs `EventIDIteration` non-collision (the documented
   reason for the distinct suffix, events.go:74–81). Add literal tests.
9. **`rig` omitempty omission** in event payloads is asserted only in `handler_test.go`
   (`TestWithEventRigPopulatesEveryRigPayload`, outside this inventory) — keep at least one
   omission/presence pair in the Dart events suite. Likewise `retry_source: null` when absent
   (only the populated case is tested).
10. **`ResolveConditionPath` absolute-path permissiveness**: absolute paths OUTSIDE
    envelope/base are accepted by design (condition.go:216–229, "callers vouch") — only the
    inside-roots happy case is tested. Pin the permissive case so a future "fix" doesn't break
    pack-installed gates. Also untested: `not a regular file` and `file is not executable`
    rejections (condition.go:255–260), and `conditionPATH` dir dedup.
11. **ConditionEnv values untested:** `HOME` *value* (== CityPath — the sandboxing contract),
    `TMPDIR` value, `GC_WORK_DIR` emission when WorkDir set, and 7 of the 10 Dolt/Beads
    passthrough keys.
12. **`MatchesDependencyFilter(nil, nonEmptyFilter)`** → false — untested.
13. **`ValidateArtifactDir`** with a broken (dangling) symlink — `EvalSymlinks` errors; the
    walk returns `resolving symlink …` — untested.
14. **`DecodeInt` whitespace/sign forms** (`" 1"`, `"+1"`) — unpinned and exactly where
    Go/Dart diverge (trap #2). **`ValidateVarKey` non-ASCII letters** (`"é"`) — unpinned
    (trap #3).
15. **`RequiresToken`** table omits 11 protected-by-prefix keys (`gate_stdout`, `gate_stderr`,
    `gate_duration_ms`, `gate_truncated`, `pending_next_wisp`, `trigger`, `trigger_condition`,
    `city_path`, `rig`, `evaluate_prompt`, `iteration` variants) — extend if ported.

---

## Porting traps

1. **Go duration codec.** `convergence.gate_timeout` etc. store Go `time.Duration` strings
   (`"30s"`, `"2h30m0s"`, `"100ms"`). Dart's `Duration.toString()` is `0:00:30.000000` and
   there is no built-in parser for Go syntax — write a Go-compatible
   `encodeDuration`/`decodeDuration` (units `h m s ms µs/us ns`, and note `EncodeDuration(0)`
   = `"0s"`). Round-tripping Dart-style strings would corrupt interop with gc-written beads.
2. **`strconv.Atoi` ≠ `int.parse`.** Go rejects surrounding whitespace; Dart's `int.parse`
   accepts leading/trailing whitespace. `DecodeInt(" 1")` must return `(0, false)` — do not
   delegate naively to `int.tryParse`.
3. **`unicode.IsLetter` in `ValidateVarKey`** accepts ANY Unicode letter (`é`, `世`). A
   `[A-Za-z_][A-Za-z0-9_]*` regex is stricter than gc and the ASCII-only test table will not
   catch the divergence. Either use Dart's unicode-aware letter classes or record a deliberate
   ASCII-only deviation as an ADR-0000 amendment.
4. **Verdict normalization is fail-closed.** Empty, whitespace-only, and ALL unknown strings
   → `block`. The past-tense map has exactly 5 entries including the singular
   `approve-with-risk`. Lowercase + trim FIRST, then map, then canonical check.
5. **Absent vs empty-string metadata is load-bearing** (`MetadataPresent`,
   `MatchesDependencyFilter`, the `gate_outcome_wisp` replay marker). gc "clears" keys by
   writing `""`, never deleting (StopHandler writes `agent_verdict=""`). In Dart, `map[key]`
   returning `null` conflates the two — use `containsKey`. On the bd side, the actuator's
   `--metadata key=` write must SET empty, not remove (verify against bd 1.0.5 during Track E).
6. **JSON null-vs-omitted.** Payload nullable fields serialize as explicit `null` (no
   `omitempty`) — `retry_source`, `gate_outcome`, `gate_result`, `exit_code`, `next_wisp_id`,
   `wisp_id`, `waiting_reason`, token fields — while `rig` alone is omitted-when-empty.
   `json_serializable` must use `includeIfNull: true` for the former and an omit strategy for
   `rig` only.
7. **`TruncateOutput` operates on BYTES.** maxBytes is a UTF-8 byte budget; the boundary
   backoff scans ≤3 bytes backwards from `maxBytes` looking for a rune start
   (capture.go:61–67). Dart `String` is UTF-16 — implement over `List<int>`/`Uint8List` and
   decode at the end; `maxBytes=0` with data returns `("", true)`, with empty data
   `("", false)`. The bounded buffers capture `MaxOutputBytes + 4` so overflow is detectable
   (condition.go:332–335); `Truncated` is the OR of both streams' truncation AND buffer
   overflow (condition.go:345).
8. **Gate outcome classification order** (condition.go:350–369): check PARENT context
   cancellation FIRST (→ `error`, no retry), then the per-script deadline (→ `timeout`,
   `ExitCode=nil`), then exit errors (→ `fail` with code), else `pass` with `ExitCode=0`.
   Pre-exec failures put `err.Error()` in `Stderr`, NOT script output. Retry ONLY on
   `timeout`; `RetryCount` counts performed retries (budget 2 ⇒ final count 2).
9. **⚠ create vs retry write-ordering asymmetry.** Create: `state=creating` → meta → vars →
   **`state=active` as a separate write** → pour → `active_wisp` → `iteration`. Retry:
   `state=creating` → meta with **`state=active` as the LAST metaWrite** → vars → pour →
   `active_wisp` → `iteration`. Both pour AFTER active. The
   `TestCreateHandler_StateCreatingBeforeActive` WriteLog assertion depends on exactly two
   `convergence.state` writes — adding or merging writes breaks conformance.
10. **Go map iteration is randomized** for `Vars`/`var.*` copies (create.go:124, retry.go:109)
    — the write order of var keys is unspecified. Dart maps are insertion-ordered: do NOT bake
    var-write order into WriteLog assertions, and do not rely on it in the actuator.
11. **Event emission straddles the close** (StopHandler): TierCritical events (synthetic
    iteration, terminated) BEFORE `CloseBead`, TierBestEffort (`manual_stop`) AFTER, and
    `last_processed_wisp` after everything. The synthetic iteration event reuses
    `EventIDIteration(bead, N)` — same ID space as real iteration events (dedup downstream is
    by event ID).
12. **`ResolveConditionPath` dual-root (envelope ∪ base) containment** with checks BOTH before
    and after `EvalSymlinks`, roots canonicalized first (macOS `/tmp` → `/private/tmp`);
    absolute condition paths bypass containment entirely (trusted-caller contract);
    `base==""` falls back to envelope; `envelope==""` is rejected. Symlinked scripts are
    ALLOWED if the target stays inside a root — whereas `ResolveEvaluateStep` rejects ANY
    symlink (evaluate.go:60–63). Do not unify the two policies.
13. **Duplicated Go subtests.** `TestResolveConditionPath` contains two pairs of verbatim
    duplicate subtest names (condition_test.go:351/467 and 376/499 — Go silently suffixes
    `#01`). Port each case once; `package:test` would otherwise carry confusing duplicates.
14. **Close reasons are ≥20 chars by contract** (bd `validation.on-close=error` rejects
    shorter). Any Dart-side close MUST use the exact `CloseReason*` literals — shortening one
    makes bd reject the close at actuation time even though every fake-store test passes.
15. **`beads.ErrNotFound` sentinel matters.** Stop/recovery paths branch on
    not-found-vs-transient store errors (manual.go:275, 320). The Dart store seam needs a
    typed not-found error, and the fake's injectable `GetBeadFunc` must be able to return
    both kinds (see `TestStopHandler_StoreErrorReadingActiveWisp_ReportsError`, which pins the
    exact wrapped message).
16. **`ExtractVars` returns a non-nil map for nil input** and `NewTemplateContext` tolerates
    nil metadata — null-safety shortcuts (`meta!`) will diverge.
