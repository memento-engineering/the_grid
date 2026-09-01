# Stage-1 wiring — the dual-write shadow window for G1 (attempt lifecycle + step.transition)

**Scope.** This document designs the Stage-1 *wiring*: how the fenced service, the sole
appender, and the tick get constructed and threaded into the live engine; the derivation
layer that turns every G1 legacy write into an observer-written trajectory append; the
failure posture; and the first-boot runbook. It designs the **shadow window** — legacy
writes stay, appends add (schema §9's coexistence rule: G1 cuts as a dual-write shadow
window first). The **cut** — quiesced epoch boundary, legacy-writer retirement,
teardown-replay deletion, the dual-read drain, the worktree-outstanding barrier, and the
release train — is a separate, operator-ratified change and is **not designed here**
(§5 below fences it off explicitly). Where schema §9 says "teardown replay deletes here"
under Stage 1, it means Stage 1's *second half*: this document covers only the shadow
window; every deletion and every behavioral change belongs to the cut.

**Headline property: Stage 1 changes NOTHING about what mounts.** Every record is an
append shadowing a legacy write that still fires; no eligibility clause, no admission
behavior, no reap, no re-key is added, removed, or conditioned. (r2: the
worktree-outstanding barrier, which was the one exception, moved to the cut package —
§2.4.)

**Cross-reference convention (r2).** `schema §N` means `trajectory-schema.md` section N.
A bare `§N` means a section of THIS document. Every reference below is marked one way or
the other.

Authorities: `trajectory-schema.md` schema §5 (append discipline) and schema §9 (Stage-1
scope, the coexistence rule as amended by audit round 2, plus the r2 amendment noted in
§2.4 below); `transition-inventory.md` (the emitter map, spot-verified against the
current tree — corrected line numbers below are from the live tree, 2026-08-31);
`stage0-measurements.md` (M1 first-boot provisioning window, M2 gc cadence, M3 latency —
read narrowly, see §2.5, M4 reconnect + the commit-throw hazard, M6 head re-stamp
specification); the landed Stage-0 package `packages/grid_trajectory/`.

Binding constraints, restated because every section below leans on them:

- **Observer-written.** Records derive where the *engine* observes or effects the
  transition — the `StationBeadWriter` chokepoint's outcome-bearing callers and the
  runtime event stream — never self-reported by agent processes.
- **Strictly additive dual-write.** No legacy write is removed or reordered. An append
  failure NEVER fails the legacy path: it flares and counts. The shadow window measures
  divergence; it must not create it.
- **Non-blocking as well as non-fatal.** No engine hot path ever awaits an append. Every
  derivation *enqueues* to the harness's single writer (§2.5); the only synchronous
  trajectory awaits in the whole system are at boot (belt verify, epoch claim) and at
  clean-down (the fixpoint drain).
- **Sole appender.** Every append goes through the ONE `TrajectoryAppender` owned by the
  fenced service. The derivation layer holds a handle to the harness's queue, never a
  second appender, never a second connection that writes.
- **Extraction boundary.** Engine code hands the queue *constructed records*
  (`grid_trajectory`'s sealed types). Concrete record construction lives in an
  engine-side derivation layer; `grid_trajectory` stays mechanics-only
  (`test/architecture/extraction_boundary_test.dart` enforces it).
- **Leaf package.** `grid_trajectory` keeps zero `grid_*` deps. New deps flow TOWARD it:
  `grid_runtime → grid_trajectory` and `grid_sdk → grid_trajectory` are the two new
  edges; nothing flows back.
- **Recoverable identity only.** The recorder holds NO identity that is not recoverable
  from the `grid.lease.*` breadcrumbs plus the log itself (§2.1). Its in-memory maps are
  caches, rebuilt at boot; losing them loses nothing durable.

---

## 1 Construction — the fenced service in the assembly

### 1.1 Where it is built — and in which repo

`assembleStationWork` (`grid_sdk/lib/src/work/work_assembly.dart:300`) — the one place
that already builds the state store's `StationBeadWriter` (`work_assembly.dart:484-489`)
and knows everything the service needs: the grid home, the state store's dolt server
listener (via `grid_trajectory`'s `resolveDoltServerListener(gridHome)` —
`grid_trajectory/lib/src/connect/server_config.dart:54`, over `.grid/.beads/dolt/`,
never bd's proxy), the station name (the state partition, `work_assembly.dart:403`), the
substation prefix set (the `allowSet`, `:470-473` — the seat-derivation input), and the
flare transport.

**Scope honesty (r2, blocker 3):** `assembleStationWork` has **no production caller in
the_grid**. Its only non-test caller org-wide is
`space_station/packages/space_station_assets/lib/src/up_command.dart:491`. Stage 1 is
therefore a **two-repo change**: the harness, recorder, and hooks land in the_grid; the
`TrajectoryConfig` threading, the `--trajectory`/`--no-trajectory` flag, the banner
lines, and the `/status` block land in **space_station** (`up_command.dart` and its flag
surface). With the barrier moved to the cut (§2.4), **power_station is out of scope**:
the one chain that touched it (`worktree.provisioned` via
`power_station/.../code_capabilities.dart`) is re-sited into the_grid's
`StationGitService` itself (§2.3), which computes `preexisting` locally
(`grid_runtime/lib/src/git/station_git_service.dart:335-336`).

**Operating posture for the window:** the shadow window runs on the operator machine's
dev overrides — the gitignored `pubspec_overrides.yaml` co-editing linkage, which is its
designed purpose — so the_grid's branch and space_station's branch move together with
**no publish wave inside the window**. The release train (grid package tags →
`space_station_assets` 0.2.1 (from the current 0.2.0) → lunar bump) is a **cut
deliverable**, listed in §5/§6.

New value object, built beside the writer:

```
final trajectory = await TrajectoryHarness.build(
  config: trajectoryConfig,            // §1.3
  gridHome: stateStore.root,
  station: stateSubstation,            // 'tranquility' on the reference deployment
  seatPrefixes: allowSet,              // input to ownedPrefixOf — §2.2 seat row
  onFlare: transport?.flare,
);
```

`TrajectoryHarness` is a small grid_sdk class owning exactly five things: the
`TrajectoryDb` connection (as the `trajectory` SQL user), the ONE `TrajectoryAppender`,
the **append queue and its single writer loop** (§2.5), the `TrajectoryTick`, and the
**`StationTrajectoryRecorder`** (the derivation layer, §2). It is threaded into
`StationWorkRuntime._` as a field and handed out through `wiring` to the consumers that
need it: the runtime-event subscriber (harness-internal, over `provider.events`), and
`SessionScope`/`CapabilityHost`/`StationGitService` via the existing wiring values (one
new ambient value: `TrajectoryRecorderScope`, null-object when disabled).

The recorder is **injected as an optional collaborator** everywhere. Disabled or
degraded, it is a counting no-op; no call site ever branches on "is the trajectory up".

### 1.2 Lifecycle — start after stores, stop before them

Boot order, inside `StationWorkRuntime.start()` (`work_assembly.dart:177-206`), with one
contract on the caller: **`up` holds the station lock before calling `start()`** — it
already does, in the actual caller:
`space_station_assets/lib/src/up_command.dart` acquires the lock at `:440`, calls
`assembleStationWork` at `:491`, and calls `start()` at `:519` — so the epoch claim's
mutual-exclusion precondition (schema §5 "the caller HOLDS the station lock") is met by
ordering, not by new machinery.

1. `_sourcesStart()` — controllers up (the dolt server must be reachable; it is bd's
   server and bd's proxy has already started it).
2. **Trajectory up:** connect as `trajectory` user → **`verifyBeltAtBoot()` FIRST** →
   `claimEpoch(pid, pgid, cause:'boot')` → `tick.start()` (boot pass + 30 s interval).

   **Verify-before-claim (r2, minor 17):** a corrupt log must not advance the fence. The
   Stage-0 API permits this order: `verifyBeltAtBoot()`
   (`grid_trajectory/lib/src/append/trajectory_appender.dart:231-260`) is a pure
   station-scoped `SELECT seq, boot_epoch, epoch_seq … ORDER BY seq` that consults no
   claimed-epoch state — `_bootEpoch` is untouched and `_requireEpoch` is not on the
   path — and on a violation `_haltNow` latches the appender halted before any
   `traj_epoch` INSERT or fence UPSERT has happened. A halted verify means: no claim, no
   fence advance, flare `trajectory.halted`, and the station **continues booting
   legacy-only** (§3). Only a clean scan proceeds to `claimEpoch` (INSERT `traj_epoch`
   MAX+1, fence-cell UPSERT seeds/advances — schema §5).
3. Freshness barrier, restart reconcile, teardown replay, driver start — all untouched.
   (The teardown replay STAYS through the whole shadow window; it deletes at the cut.)

Shutdown order, inside `StationWorkRuntime.shutdown()` (`work_assembly.dart:232-237`),
before `_sourcesShutdown()` — with a **hard ordering guarantee (r2, major 9): trajectory
shutdown NEVER blocks sources shutdown.** Every new statement is individually guarded in
the settle style the surrounding teardown already uses (space_station up_command's
`settle('lock release', …)` pattern); a throw is caught, counted, and flared as the
Stage-0 non-fatal signal class — M4 says so in as many words for the forced commit:
"`doltCommitIfDue()` still throws — that path has no outcome to carry, and guard 5 pins
it" (`stage0-measurements.md:446-447`).

1. *(guarded)* **Drain the queue:** `tick.runToFixpoint()` — schema §5's clean-down
   primitive — which by §2.5's contract also drains the append queue to empty before the
   fixpoint returns. A fixpoint not reached (bd unreachable, fenced out, pass cap) is
   reported via the outstanding count in the harness's final status flare; the successor
   boot's tick inherits the remainder.
2. **No `authority.epoch.closed` record at Stage 1.** That record is family 2
   (admission); under the coexistence rule as amended, only attempt/step-family records
   append at Stage 1 — the epoch *tables* (`traj_epoch`, `traj_fence`) are Stage-0
   mechanics written by the claim path, but the `.advanced`/`.closed` *records* arrive
   at Stage 3 with their family. The Stage-1 clean-down receipt is the fixpoint
   telemetry plus the boundary dolt commit.
3. *(guarded, try/caught)* Force a boundary `doltCommitIfDue()` (flush the cadence). A
   throw here is the cadence-failure signal: caught, counted, flared — never
   propagated. Then `tick.dispose()`, close the trajectory connection (both guarded).
4. Then `_sourcesShutdown()` — unconditionally reached; the trajectory always stops
   before the stores it reads, and never prevents them stopping.

The harness also owns the **gc cadence** (M2): `CALL DOLT_GC()` on `trajectory` every
5 minutes (config), ~120 ms each, reclaiming ~98% — caps the working set near 900 MB at
full storm. Online, no quiesced window, never touches bd's proxy (M2 implication 3).

### 1.3 Config surface — arm without the trajectory

`assembleStationWork` gains one parameter, `TrajectoryConfig` (the parameter is a
the_grid edit; the flag surface and banner that feed it are space_station edits — §1.1):

- `mode: disabled | auto | required` (default **auto**).
  - `disabled` — no connection, no claim, recorder is a silent no-op. A station can
    always arm without the trajectory.
  - `auto` — enabled iff the provisioning artifact exists
    (`.grid/trajectory/trajectory.secret`, the `trajectorySecretPath` convention). An
    unprovisioned home boots legacy-only with a one-line notice, not a warning storm.
  - `required` — a failed connect/claim still NEVER blocks the boot (constraint: the
    trajectory being down degrades to legacy-only), but the degradation is a loud,
    repeated warning and `/status` shows `trajectory: DEGRADED` (§3).
- `tickInterval` (30 s), `gcInterval` (5 min), `commitCadence` (Stage-0 defaults),
  `queueBound` (§2.5, default 4096).

Runners surface it as `--trajectory` / `--no-trajectory` on `up` (declared in
`space_station_assets`' up command; lunar inherits through the delegate as usual).
Dry-run (`dryRun: true`) forces `disabled`: a dry arm must not claim an epoch or write
anything — same physics as the recording no-op bd.

### 1.4 The epoch claim at boot

One claim per boot, `cause:'boot'`, under the held station lock, **after** a clean belt
verify (§1.2). 1213 → re-read MAX and retry (up to 3) per the Stage-0 claim path;
refused → degrade to legacy-only (§3), never a boot failure. The claim seeds
`traj_fence` on a fresh home (cert-round UPSERT rule) and after any restore (M6: a
snapshot-restored stale fence cell is corrected by exactly this claim). The claimed
epoch is the envelope `boot_epoch` for every append this process makes, and
`authority_id` = `<station>/<epoch>`.

---

## 2 The derivation layer — `StationTrajectoryRecorder`

One class, engine-side (`grid_runtime/lib/src/trajectory/station_trajectory_recorder.dart`),
constructed by the harness. It is the ONLY code that names concrete record classes for
Stage-1 types. It exposes intent-named methods (`sessionMinted(...)`,
`processExited(...)`, `stepTransition(...)`) that build the sealed record + envelope
correlation and **enqueue** to the harness's single writer (§2.5) — always **after** the
legacy write, always non-fatally, never awaited on an engine path.

### 2.1 Identity threading — attempt_id gets a durable carrier (r2, blocker 2)

The instance token is durable for a reason: it is persisted as a step-bead breadcrumb
and read back. attempt_id rides **the same carrier** — the `grid.lease.*` breadcrumb
namespace, the lease vendor's single-writer namespace
(`grid_engine/lib/src/molecule/process_lease_vendor.dart:24`: "`grid.lease.*` has
exactly one writer").

- **The breadcrumb key.** `LeaseKeys` (`molecule_schema.dart:126-131`) gains
  `attemptId = 'grid.lease.attempt_id'` beside `pgid`/`pid`/`token`. All three
  breadcrumb shapes extend in place: `leaseBreadcrumb` (the acquire payload,
  `process_lease_vendor.dart:309-313`) writes it; `kClearedLeaseKeys` (`:321-325`)
  clears it; `leaseBreadcrumbOf` (`:334+`) parses it **tolerantly** — an absent
  attempt_id key means a pre-Stage-1 breadcrumb and the parse still succeeds (adoption
  never regresses). The single-writer invariant is untouched: acquire/spawn writes,
  release and the boot sweep clear (`:566-710`, `:669`), nothing else touches the
  namespace.
- **Fresh spawn mints.** A spawn mints a new ULID attempt_id, threads it on the
  `ProcessHandle` beside the token, and `_persistBreadcrumb`
  (`process_lease_vendor.dart:806`, `:820-841`) persists it with the same retry loop —
  including the load-bearing synchronous check-then-enqueue gate at `:825-830`, which
  is not altered (§2.5 notes the enqueue placement).
- **Adoption CONTINUES the attempt.** When `proveFreshness` holds and the allocation
  goes `adopting → ready` with no spawn (`grid_engine/lib/src/sdk/allocation.dart:593-626`),
  the adopt path reads the breadcrumb's attempt_id **back** — the same parsed breadcrumb
  that already feeds the `AdoptFence` (`capability_host.dart:340-344` via
  `leaseBreadcrumbOf`) — and the recorder uses it as-is. **No fresh mint on adopt.**
  Schema §3's one-attempt-one-incarnation therefore becomes *true* on adopt: the process
  incarnation persists, and its attempt persists with it. `attempt.adopt.proved` keys
  `adopt:<attempt_id>` against an attempt whose `.started` genuinely appended (in a
  prior boot's epoch).
- **Bounce.** The restart reconciler recovers attempt_id **from the breadcrumb** where
  present, so `attempt.terminal(settled)` for a prior boot's session (caller
  `restart_reconciler.dart:813`) joins the real P1 attempt row and its idem key
  (`terminal:<attempt_id>`, schema §5) dedupes correctly. Sessions predating Stage 1 —
  no attempt_id key in the breadcrumb, or no breadcrumb at all — settle with a
  reconciler-minted attempt_id, `provenance='inferred'`, and a payload marker
  (`attempt_id_basis:'reconciler-minted'`); they are outside the shadow's comparable set
  anyway.
- **Env export.** The child still sees `GRID_ATTEMPT_ID`: it is added to the
  **`AllocationContext` env block** at `capability_host.dart:327-333` (r2 correction,
  minor 13: this map belongs to `AllocationContext`, not `StepArgs` — `StepArgs` has no
  env, `capability_host.dart:209-217`), and reaches the process via `_buildChildEnv`
  (`subprocess_provider.dart:218-231`): allowlist base → freshly minted
  `IncarnationEnv` → `config.env` layered **last**, which is why the host's value wins.
  `GRID_INSTANCE_TOKEN` is NOT removed — its retirement is a cut change.
- **Observation join.** `RuntimeEvent.sessionStarted` (`subprocess_provider.dart:286`)
  gains an `attemptId` field read from `config.env['GRID_ATTEMPT_ID']` at spawn —
  additive, defaulted, non-breaking *in-repo*; the public-API surface change
  (`grid_runtime.dart:60`) ships in the cut's release train, consumed via dev overrides
  during the window (§1.1). Exit events join by session name; the recorder's
  name→attempt map is a **cache** rebuilt from breadcrumbs at boot.
- **Session-scoped records** (mint, terminal, round-retired) use the session-scoped
  attempt row shape: `step_path=''`, `step_round=0` (schema §3, one shape, no special
  case). The recorder mints the session-scope attempt_id at session mint and recovers it
  after a bounce from the log (the last session-scoped attempt row for the session) —
  never from memory alone.
- **incarnation** = the supervised `restartCount` — which is *persisted* on the step
  bead (`capability_host.dart:523-532` reads the current persisted value) and drives the
  ValueKey re-key (`circuit_scope.dart:160-165`); recoverable, not recorder-held.
- **Recoverability rule (binding):** every identity above — attempt_id, name→attempt,
  predecessor chain, round counter, incarnation — is recoverable from the `grid.lease.*`
  breadcrumbs plus the log (last-row queries) plus persisted step-bead state. The
  recorder's maps are warm caches of that, nothing more.

### 2.2 Correlation sources (envelope columns)

| Column | Stage-1 source |
|---|---|
| `session_id` | derivation-site argument / `GRID_SESSION_ID` |
| `work_bead_id` | the ORIGINAL immutable id. The recorder strips `#rN`/`#void-` when deriving from legacy strings; the record never carries a mutated key |
| `round` | recorder-held per-session counter, seeded by parsing the `#rN` shape at first sight (and re-seedable from the log after a bounce), bumped only by the round-retired observation (§2.3) |
| `step_path` | nodePath at the observation site |
| `step_round` | supersedes-chain depth plus the count of CLOSED `type=gate` beads attributed to the same structural step incarnation. `StationJoinBridge` derives the durable count from every watched state snapshot and keys it with `closedGateCountKey(nodePath, structuralIncarnation)`. A timed gate belongs to the newest step incarnation present when the gate was created; an untimed gate is accepted only when the path has one possible incarnation, and ambiguous untimed history fails closed. `SessionScope` consumes that watched joined value, combines the active incarnation's count with `supersedesDepthByPath`, and threads the result through the unchanged `CircuitScope`/`StepMount.circuitRound` surface. A gate-cleared rearm records the successor round and the resumed host observes that same round |
| `incarnation` | persisted restartCount (§2.1) |
| `attempt_id` | §2.1 — breadcrumb-carried |
| `mount_attempt_id` | recorder-minted ULID spanning ONE `SessionScope` mint sequence (the in-memory `_maxMintAttempts` = 5 budget, `session_scope.dart:156`) — **plus (r2, major 8) the payload carries the legacy mount-attempt bead's `grid.attempt.count`** (`mount_attempt.dart:49`, merged in place per `:70-80`, durable cap `kMaxMountAttempts` = 3 at `:69`) **as `legacy_attempt_count`, the shadow-comparable ordinal.** The ULID keys the record; the ordinal is what `traj shadow-diff` joins against the legacy bead |
| `grant_id` | **Stage-1 placeholder** (design call): `ck_grant_link` requires `grant_id` on `attempt.session.started`, but no grants exist before Stage 3. The recorder mints a fresh ULID per mount as a pre-grant id, payload-marked `grant_basis:'pre-stage3'`. At Stage 3 the real `admission.grant.issued` takes over the same slot |
| `seat` | derived by the recorder via `BeadOwnershipPredicate.ownedPrefixOf(id, knownPrefixes)` (`grid_runtime/lib/src/lifecycle/bead_ownership.dart:69` — static, TWO arguments, longest-prefix match over the allowSet, **nullable**). r2 (minor 12): on a null return (no known prefix owns the id) the recorder stamps the literal `seat='unowned'` with a payload marker — deterministic, never CHECK-refused, so `ck_seat`'s presence rule cannot turn an unowned id into a permanent clean-round blocker. Note the allowSet carries both identity axes (name and prefix, `work_assembly.dart:470-473`); longest-match is deterministic but the resolved seat may be either axis |
| `worktree`/`branch`/`commit_sha` | captured **inside `StationGitService.provisionWorktree`** (§2.3): `preexisting` is computed locally at `station_git_service.dart:335-336`, and the base sha is one `git rev-parse HEAD` at the same instant — the_grid-only, no power_station edit |
| `occurred_at` | the observation instant; `provenance` defaults `observed`, `inferred` only where stated (exit inference, reconciler settlement, reconciler-minted attempt ids, and the `step-complete-implies-running` reconstruction whose complete observation proves its running predecessor) |

### 2.3 The record map — every Stage-1 type, its observation site, its trigger

All triggers are: **the same code path as the legacy write, immediately after it,
enqueued, non-fatal.** "After" means after the legacy call returns (success OR failure —
at Stage 1 the recorder appends only on legacy success, so the shadow never leads the
incumbent; the known non-atomic crash class this creates is the schema-§9 allow-list's
named class).

| record_type | Observation site (live tree, 2026-08-31) | Trigger + notes |
|---|---|---|
| `attempt.session.started` | `station_bead_writer.dart:295-327` (`createSession`; sole caller `session_scope.dart:634-639`) | after the birth stamping merge; rig/model from the same metadata; pre-grant `grant_id` (§2.2) |
| `attempt.process.started` | `subprocess_provider.dart:286` (SessionStarted emit) via the harness's runtime-event subscription | pid/pgid/beadId from the event; `attempt_id` from the event's new field (breadcrumb-backed, §2.1); `predecessor_attempt_id` from the log's last attempt row per (session, step_path) — not from memory alone |
| `attempt.process.exited` | `subprocess_provider.dart:450+` (`_emitExit`) | r2 (major 7): `_emitExit` emits exactly TWO shapes — `RuntimeEvent.exited` (read code, or the `oneTurn` vanish with `inferred: true`) and `RuntimeEvent.died` (watchdog kill / longLived vanish). **`RuntimeEvent.respawned` has ZERO production emitters org-wide** (union member at `runtime_event.dart:67-70`; constructed only in tests) — nothing in this design keys on it. `inferred=true` ⇒ envelope `provenance='inferred'` |
| *incarnation succession* | the supervised-restart path, not an event: `_persistFailure` bumps the persisted `restartCount` (`capability_host.dart:429`, `:523-532`) and the ValueKey re-key (`circuit_scope.dart:160-165`) mounts the successor, whose spawn mints attempt_id at incarnation+1 (§2.1); the lease vendor's spawn-under-existing-breadcrumb transition supplies the same succession signal when a fresh spawn overwrites a prior attempt's breadcrumb — the outgoing breadcrumb's attempt_id is the successor's `predecessor_attempt_id` | (r2, major 7 — replaces everything previously keyed on `Respawned`) |
| `attempt.terminal` (succeeded) | `session_scope.dart:904-970` (`_completeAndClose`) | r2 (major 6): derived at the **outcome-bearing caller**, uniformly with the other three terminal rows. The bare writer `close(String id, {String? reason})` (`station_bead_writer.dart:1226`) is the shared close for EVERY disposition, carries no outcome, and is **not a derivation site**. outcome=succeeded; one record, NO tail — the tail members stay legacy at Stage 1 and additionally become tick obligations (§2.4) |
| `attempt.terminal` (escalated) | `session_scope.dart:1341+` (`_escalateAndClose`) | outcome=escalated, reason from grid.escalation_reason |
| `attempt.terminal` (lost / void) | `session_scope.dart:578-585` (voidRetireMetadata write) | outcome=lost + intact keys — the record carries the ORIGINAL work_bead_id while legacy still writes `#void-` |
| `attempt.terminal` (settled) | `station_bead_writer.dart:439-477` (`settleSessionForTerminalWork`); its two callers: `restart_reconciler.dart:813` and the gate-sweep settle at `station_bead_writer.dart:392` (scheduled from `work_list.dart`'s workBeadClosed sweep, `:355-372`) | outcome=settled, work_terminal_reason; reconciler-originated ⇒ `provenance='inferred'`, attempt_id per §2.1's bounce rule |
| `attempt.round.retired` | `station_command_handler.dart:320-323` (rework re-key) + `session_scope.dart:211-225` (retired-round close, writer `:331-343`) | one record per retire (merges the old round-closed); cause=rework/void; bumps the recorder's round counter |
| `attempt.rework_declined` | `session_scope.dart:1321-1339` (`_declineRework`) | after the HELD merge |
| `attempt.mint.outcome` | `session_scope.dart:817/:827` via `_flareMint :840`, `:786` (stage), and the refusal evaluations at `:475/:510` | r2 (minor 14): the refusal derivation is **per-evaluation at the recorder** — the recorder call sits ABOVE the `_mintBlockedReported` latch (`session_scope.dart:473-474`, `:508-509`); the latch keeps throttling the *flare* only. Every refused evaluation appends; undercounting resolved. Keyed work_bead_id + mount_attempt_id (§2.2) |
| `attempt.lease.acquired/.released/.swept` | `process_lease_vendor.dart:806/:820` (acquire persist), release (`:860-875`), boot sweep (`:566-710`) | after each breadcrumb write/sweep; the breadcrumb now CARRIES attempt_id (§2.1) — the record reads it, never invents it |
| `attempt.adopt.proved` | `process_lease_vendor.dart:747+` (breadcrumb read) / `sdk/allocation.dart:593-626` (adopt decision); fence `capability_host.dart:340-344` | adopted-vs-respawned durable at last; attempt_id = the breadcrumb's, continued (§2.1) |
| `attempt.liveness.lost/.regained` + `traj_pulse` beats | net-new (inventory: NO EMITTER EXISTS — confirmed, and `RuntimeEvent.activityChanged` is ALSO emitter-less in production). r2 (major 11): the observation surface is **(a)** a worktree `.grid` mtime scan on the tick — the signal the standing operational finding says tells the truth about dead sessions — and **(b)** the provider's activity poll surface `RuntimeProvider.lastActivity(name)` (`runtime_provider.dart:66`; impl `subprocess_provider.dart:433`, refreshed per transcript line at `:589`). The wedge monitor (`wedge_monitor.dart:88-123`) reads bead state, not liveness, and is NOT a surface here. Beats UPSERT `traj_pulse` on the tick cadence, `observed_via='worktree-mtime'` or `'provider-activity'` | detector rides the tick (§2.4); may emit `lost` ONLY for a beat observed within the current epoch — the empty-pulse ⇒ `unknown` rule verbatim. The scanner walks every live worktree's `.grid` per tick; its I/O cost is budgeted and measured in W7 (§6) |
| `attempt.note` | `work_assembly.dart:522-532` registry sink | Stage 1 arms ONLY the tick's `channel='obligation-stuck'` notes (schema §5's N-failure rule); the Q5 content-split for agent journaling is deferred. **AMENDED by cut-wiring wave 1, chunk C2 (§0.4):** a SECOND channel is armed — `channel='dual-read-round-summary'`, one note at every session terminal plus one boot-final note at the clean-down fixpoint, carrying the boot's dual-read counters. The vehicle was chosen because it EXISTS (`AttemptNote` requires a `sessionId` and mints `note:<session>:<ordinal>`), and it is what makes bounces stop resetting the wave-1 gate evidence. A stated extension, not a slip |
| `worktree.provisioned` | **`station_git_service.dart:309-358` (`provisionWorktree`) itself** — r2 (blocker 3): the observation moves INTO the service, where `preexisting` (`:335-336`) and the branch are locally in hand; one added `git rev-parse HEAD` captures the base sha at the same instant. No power_station edit; `adopted_existing` need not ride the return type — the recorder hook is inside the method | after the worktree add/adopt returns; `ck_provision` gets sha+branch |
| `worktree.reaped/.held` | `session_scope.dart:934/:939/:949` (reap outcomes; today flare-only) | after the reap attempt; payload gains path + branch (the flares omit them today — the record does not) |
| `step.transition` (running/ready/complete/failed) | `capability_host.dart` persist sites via `_firePersist` (`:366` started, `:369` ready, `:373` complete, `:384` failure; failure_class splits store_unavailable vs work per the tg-7ux conflation) | after each step-bead mutation returns; result keys on complete ride the payload |
| `step.transition` (gated) | `capability_host.dart:90-130` (step half at `:116`) + derived twin `session_scope.dart:1004-1030` | state=gated; the GATE BEAD mint stays wholly legacy — `gate.opened/.closed` records are NOT in G1 and do not append at Stage 1 |
| `step.transition` (rearm) | `session_scope.dart:1222-1274` (`_rearm`, single-key write `:1260-1263`) | cause='gate_cleared', **step_round bumped** — this is the record that kills the I-14 stale-join loop at the cut; during the window it shadows the bump |
| `step.transition` (gate-close re-arm resume) | the incremented round re-keys the existing host, and the complete persist site carries the fresh host `attempt_id`; `StationTrajectoryRecorder.stepComplete` enqueues an idempotent running predecessor only when no running row was observed for that same session/path/round/incarnation correlation | the inferred running and observed complete carry one fresh host `attempt_id` and the same successor `step_round` as the rearm row. Completion proves rather than directly witnesses its predecessor, so the running row carries `provenance='inferred'` and `provenance_basis='step-complete-implies-running'`; the complete row remains `provenance='observed'` with no basis |

**Not in this table, deliberately:** `molecule.poured`, `step.superseded` (G2, Stage 2),
all admission/grant/authority records (G3) — **including the worktree-outstanding
refusal** (§2.4) — all verification/effect records (G4), `gate.*` records (arrive with
P4's writers).

`CapabilityHost` routing, `requireProcessLeaseVendor`, `StepMount`, and
`CircuitScope` are unchanged. Gate-resume coverage is observation-only: it adds
no route-specific execution branch and weakens no guard.

**Known, counted gaps.** When a teardown deregisters a session while the spawner is
suspended, the provider kills the process and returns with no `sessionStarted` and no
supervision armed (`subprocess_provider.dart:268-279` — the comment says so verbatim).
A real process incarnation ran and died with zero events, hence zero records. No attempt
row means no obligation, so the tick will not notice; this remains
`stop_races_spawn`. Ordinary append loss after a successful legacy write remains
`non_atomic_crash`.

Post-fix gate-cured rounds must yield **zero shadow-diff rows for the cured node**: the
rearm successor and its resumed running/complete writes now share one incremented
`step_round`, and the resumed writes share one fresh `attempt_id`. Only banked streams
with the structural predecessor-after-successor signature — successor pending with no
attempt, its linked predecessor updated later to a ran state — earn
`uninstrumented_resume`. That historical name does not reclassify ordinary state lag or
ordinary missing process identity.

### 2.4 The tick at Stage 1 — attempt/step families only; nothing that mounts changes

The tick's query list (`kStage0ObligationQueries` → a Stage-1 set built in the harness)
arms per schema §9's amendment: attempt/step-family obligations ONLY, and **during the
dual-write window an obligation must never fight a live legacy writer.**

*Armed in the shadow window (record-only or legacy-idle repairs):*

1. **Unknown-terminal settlement** — `attempt.terminal(outcome=unknown)` rows without a
   settling successor: probe the process table/worktree, append the settling terminal
   (`resolves_record_id`, `provenance='inferred'`). No legacy counterpart exists;
   nothing to fight.
2. **worktree.reaped backfill** — P6 shows a provisioned worktree whose session's P1 row
   is terminal AND the path is gone from disk (the legacy reap already ran) but no
   `.reaped` record landed (the non-atomic crash class): append the record,
   `provenance='inferred'`. Record-only; the filesystem action stays legacy-owned.
3. **Liveness detector** — pulse-threshold transitions (§2.3), current-epoch-beats-only.
4. **Stuck-obligation accounting** — schema §5's N=5 rule:
   `attempt.note(channel='obligation-stuck')` + flare.

*Moved to the CUT package entirely (r2, blocker 1):* the **worktree-outstanding
admission barrier** — its eligibility clause, its P6-snapshot machinery (the ambient
published snapshot, its refresh off the tick, its staleness rule), and its refusal
record — plus the head re-stamp obligation (the M6c repair) and the live worktree reap
under a terminal session.

**Rationale, stated for the record:** under strict dual-write the legacy inline reap
keeps running, so the stale-adopt window the barrier exists to close only OPENS when the
inline reap retires — which happens at the cut, not before. Arming the barrier inside
the shadow window would spend real machinery (a second read path into the trajectory db
from a synchronous, bead-only `MountEligibilityPredicate` —
`mount_eligibility.dart:14-15`, composed at `work_list.dart:260-262`, evaluated at
`:305` — plus a snapshot-staleness posture) to guard a window that is not yet open, and
it would be the ONE place Stage 1 changed what mounts. It is instead a cut-package
deliverable, built and budgeted there. **Consequence, restated as the headline: Stage 1
changes NOTHING about what mounts.**

> **Schema §9 amendment (r2 — to land as a doc edit with the build):** the cert-round
> staging "the barrier LOGIC arms at Stage 1 as an eligibility clause in the legacy
> mount-gate path reading P6" (`trajectory-schema.md:1349-1353`, also `:1004`,
> `:1856-1858`) is **superseded**: the barrier logic AND its refusal record arm together
> at the cut, alongside the inline-reap retirement that opens the window they close. The
> shadow window arms no admission behavior of any family.

The tick's fold reads require the Stage-1 folds: **P2 (`proj_step_cursor`) and P6
(process identity/worktree) incremental deltas** join P1 in the appender's synchronous
step 5, built exactly like `sessionHeadDeltaFor` (one pure delta function, two
appliers).

### 2.5 Append discipline — enqueued, bounded, drained (r2, major 4)

The design decision "non-fatal" left "non-blocking" open. Closed as follows:

- **Enqueue, never await.** Every derivation site hands its constructed record to the
  harness's append queue and returns. No engine hot path — none of `_persistStarted/
  _persistReady/_persistComplete/_persistFailure` (`capability_host.dart:366-384`), none
  of `_completeAndClose`/`_rearm`/`_declineRework`/`_escalateAndClose`, not
  `_persistBreadcrumb` or `release` — ever awaits an append. In `_persistBreadcrumb`
  specifically, the enqueue sits after `writer.update` returns and before the method's
  own return, OUTSIDE the synchronous check-then-enqueue gate
  (`process_lease_vendor.dart:825-830`), which is not perturbed.
- **One writer, FIFO per session.** The harness runs a single writer loop over the
  queue — the sole code that touches the `TrajectoryAppender`. The queue preserves
  per-session FIFO order (global FIFO in practice; per-session is the stated guarantee,
  since cross-session order is not load-bearing). The tick's obligation appends ride the
  same loop between queued entries, so the tick can never park an engine transition —
  the engine never waits on the loop at all.
- **Bounds + overflow.** The queue is bounded (`queueBound`, default 4096 entries). On
  overflow the incoming append is **dropped and counted** (`dropped` counter) with a
  rate-limited flare `trajectory.queueOverflow` — the same disqualification physics as
  any drop: a round with any dropped append cannot count as a clean round (§3).
- **Drain points.** The ONLY synchronous awaits are at boot (belt verify, epoch claim —
  §1.2) and at clean-down: `runToFixpoint()` on `down` first drains the queue to empty,
  then runs obligation passes to fixpoint. **Crash-loss is allowed and counted**: queue
  entries lost to a crash are exactly the §9 non-atomic class — the successor boot's
  shadow-diff sees legacy rows without records, attributes them, and the round is
  disqualified from the clean-round criterion. The window's integrity comes from
  counting, not from durability of the queue.
- **Accounting stays honest un-awaited.** Outcome accounting (`Appended`/`dropped`/
  latches, §3) happens in the writer loop, which is the only appender caller — the
  counters gate the cut criterion and never race the engine.
- **Refusal-record volume vs. the disqualification rule (build amendment,
  2026-08-31 — the r2-minor-14 interaction, stated honestly).** The
  per-evaluation mint-refusal record (§2.3's `attempt.mint.outcome` row) fires
  from a site that runs on EVERY joined-snapshot publish, so a
  persistently-refused bead under a publish storm would append the noisiest,
  least informative record type without bound — racing the very `queueBound`
  whose overflow disqualifies the round from the §3 clean-round criterion (a
  self-inflicted path to a permanently unreachable cut). The build therefore
  dedupes refusal records **per bead per 30 s window** (the tick's own
  granularity): an identical-reason refusal inside the window is not
  re-appended; a reason CHANGE records immediately; every fresh mint decision
  opens a fresh window. Consequence for the shadow-diff: refusal counts in the
  log are a floor at tick granularity, not a per-evaluation census — refusal
  *pressure* stays measurable (first refusal, every reason transition, every
  window boundary) while the disqualification counter can no longer be
  overflowed by the refusal class itself. The undercount r2 minor 14 was
  written against was the FLARE latch (one line per whole mint sequence,
  reason changes invisible); the window keeps both properties that fix wanted
  without the queue-overflow interaction.

**Latency claims (r2, major 5).** The previous draft extrapolated M3's headroom to the
P2/P6 fold shapes. Withdrawn: M3 is a *statement-count proxy* over P1-shaped rows
(`stage0-measurements.md:322-326`) and its own implication 1 says it proves "nothing
about P2–P8's actual row shapes" (`:356-364`); 62.3 appends/s is single-writer
*throughput*, not per-call latency headroom — and with §2.5 no engine call pays append
latency at all, so the number that matters is queue drain rate vs. production rate.
**W6's acceptance criterion (§6): measure the real P2+P6 fold shapes in the build's
integration suite — sustained drain rate above the observed storm production rate, and
p99 writer-loop transaction time — before the shadow window arms.** The M3 harness
re-measures again before the cut.

---

## 3 Failure posture — the trajectory can degrade; work cannot

The writer loop wraps every append; the sealed outcome decides:

| Outcome | Behavior | Operator surface |
|---|---|---|
| `Appended` / `AppendDeduped` | count | `/status trajectory: LIVE` counters |
| `AppendFencedOut` | recorder latches **quiet** (mirrors the appender's inert latch), stops deriving, flares `trajectory.fencedOut` ONCE | `trajectory: FENCED-OUT (epoch N, live M)` — a successor holds authority; this process should be going down anyway |
| `AppendCorruptionHalt` | recorder latches **halted**; every later derivation short-circuits to a count; flare `trajectory.halted` with the reason; the log is presumed damaged until a human looks (schema §5's alarm class) | `trajectory: HALTED — <reason>`; loud on every status read; legacy path entirely unaffected |
| `AppendInternalError` (server hiccup, dead socket) | count `dropped`, rate-limited flare `trajectory.appendDropped` (30 s bucket, the standing reporter convention); the writer loop keeps draining subsequent appends and drives the guarded reconnect eagerly on the next append (M4: the failure is a typed ~20 ms outcome, no hang; `ReconnectResumed` re-seeds, `ReconnectInert` latches quiet). **Reconnect re-resolves the listener first** (§4) | `trajectory: DEGRADED (dropped: N)` |
| queue overflow | count `dropped`, flare `trajectory.queueOverflow` (§2.5) | same counter, same disqualification |
| `AppendGrantRefused` | cannot occur at Stage 1 (no grant-scoped appends); counted as dropped if it ever does | — |

**Trajectory DOWN entirely** (db absent, connect refused, belt-verify halt or claim
refused at boot): the harness records `TrajectoryMode.degraded` (or `halted`) with the
cause, the station boots and runs **legacy-only**, `up`'s banner prints one warning line
(`trajectory: DOWN (<cause>) — running legacy-only; shadow window not counting`), and
`/status` carries the same. Work is never blocked; no mount, no step, no close ever
waits on the trajectory.

**Divergence accounting is the point of the window:** every `dropped`/`quiet`/`halted`
count is exported into the `/status` trajectory block and consumed by
`traj shadow-diff` — **a round with any dropped append cannot count as a clean round**
(the mismatch it would produce is real, not noise). The legacy write's own failure path
is untouched: a failed legacy write with no append (the recorder appends only after
legacy success) is the named allow-list class, adjudicated once per schema §9.

**The state writer's null-sink hole stays open through the window (r2, major 10).** The
state `StationBeadWriter` is built with no `onFlare` (`work_assembly.dart:484-489`)
while every work-store writer has one (`:496-502`); closing it would switch on a real
volume of previously-evaporating flares (`session.minted :325`, `gate.autoClosed :430`,
`session.workTerminal :467`, `gate.opened :641/:667`, `gate.autoCloseFailed :695`,
`rework.specPreserved :1144`) — changing the incumbent's operator surface inside the
exact window whose job is attributing divergence. **Deferred to the cut**, as its own
bead with its own before/after. The recorder does not need it: verified against every
row of §2.3, each derivation site is a direct code hook (SessionScope methods,
CapabilityHost persist sites, the lease vendor, StationGitService, the runtime event
stream, the command handler) — **no Stage-1 record derives from a writer flare.**

---

## 4 First-boot runbook

Provisioning happens **against the RUNNING state-store server over SQL** — with one
prerequisite whose absence forces the M1 offline window. The runbook NEVER touches bd's
proxy pid/lock files ad hoc; the one destructive step follows the inlined procedure in
Appendix A (which is the standing dolt-server-kill playbook, landed here as a citable
artifact).

**Step 0 — pre-flight snapshot.** `cp -Rc` the `.grid/.beads` dir (M1: 18 GB in <90 ms,
copy-on-write). Standard first step of any risky operation against the real store.

**Step 1 — the bootstrap credential check.** bd's child server has exactly ONE user,
`root@localhost`, which cannot authenticate over the 127.0.0.1 TCP address any client
dials and has no socket (M1). Probe: attempt a server-level connect with the `gridboot`
bootstrap credential. **The gridboot secret has a stated home (r2, minor 15):
`.grid/trajectory/gridboot.secret`, mode 0600, beside `trajectory.secret`** — created at
step 1b, read by the probe and by any later re-run of `traj provision`; it is the
credential with `GRANT ALL ON *.*` and never leaves that directory.
- **Present** (any Stage-0-provisioned home): go to step 2.
- **Absent** — the ONE offline window (the M1 first-boot provisioning finding):
  1. station down (`down`, verify the lock released);
  2. stop bd's proxy and child server per **Appendix A** (explicit steps below);
  3. offline seed, from inside `.grid/.beads/dolt/`, with `--doltcfg-dir` discipline
     (the T1 trap):
     `dolt --doltcfg-dir .doltcfg sql -q "CREATE USER IF NOT EXISTS 'gridboot'@'%' IDENTIFIED BY '<secret>'; GRANT ALL ON *.* TO 'gridboot'@'%';"`
     with `<secret>` freshly generated and written to
     `.grid/trajectory/gridboot.secret` (0600) in the same step;
  4. restart the store per Appendix A step 4. One window, ever, per home.

**Step 2 — live provisioning over SQL** (idempotent, re-runnable, shipped as
`traj provision` on the runner):
1. `CREATE DATABASE IF NOT EXISTS trajectory` beside the ledger database (M1: invisible
   to bd, sweep unchanged on the 18 GB live copy).
2. `applyTrajectorySchema` — `dolt_ignore` registration FIRST, then the schema's §4 DDL
   verbatim (schema §4, not this document's §4).
3. `provisionTrajectoryUser` — creates `trajectory`@'%', grants `trajectory.*` ONLY,
   secret at `.grid/trajectory/trajectory.secret` (0600, never under `.beads/`; the
   asserted boundary: this credential is refused by the ledger database).
4. Verify: connect as `trajectory`, `SELECT COUNT(*) FROM trajectory` (0), guard queries
   green.

**Step 3 — epoch-1 claim.** Nothing to do by hand: the first `up --trajectory` runs
belt-verify over the empty log (clean), then claims (lock → `claimEpoch` → epoch 1,
fence cell seeded by the claim's UPSERT → tick boot pass). A restore at any later date
leaves a stale fence cell; the next boot's claim corrects it (M6 implication 2) — no
manual repair exists or is needed.

**Step 4 — the arm sequence.**
```
dart run lunar:lunar up --grid-home "$(pwd)" --trajectory      # observe-only first, as ever
# banner shows: trajectory: LIVE epoch=1 …
```

**Reclamation on a scoped-grant home (tg-3o6b):** `DOLT_GC` needs SERVER-level privilege
and step 2.3 grants the service `trajectory.*` ONLY — the boundary wins, so on these
homes gc is **operator-run**: the harness disables its cadence after one
`trajectory.gcDisabled` flare and the operator runs `traj gc` (the gridboot credential)
when growth warrants it. The service grant is never widened to make the cadence work.

**Reconnect rule (r2, minor 15):** the harness resolves the listener at build via
`resolveDoltServerListener` — and **re-resolves it on every reconnect attempt**. bd
rewrites the child server's port on its own terms (M1b had to rewrite port 63412 to
defang the copy); a reconnect loop pinned to the boot-time port would re-dial a dead
listener forever and sit silently DEGRADED after any bd-initiated restart.

**One grid per machine — restated for the trajectory (r2, minor 15):** two stations over
the same org claim epochs in two *separate* trajectory databases (one per grid home)
while contending for the same bd stores — the fence provides **no** mutual exclusion
between them. The standing one-grid-per-machine rule is the only guard; the trajectory
does not relax it, it sharpens it.

**The shadow-window operating loop:**
1. Rounds run normally — legacy is the incumbent oracle; appends shadow it.
2. **Per round**, the operator (and the stage checklist) runs `traj shadow-diff` — the
   typed mismatch report keyed `(session, field, legacy_value, fold_value, seq)`, now
   also carrying that round's dropped-append count (queue overflow included), the tick's
   refusal telemetry, and the named-gap counts (non-atomic crash class,
   stop-races-spawn — §2.3).
3. On any unexplained mismatch: the cut is blocked, the mismatch flares, **the fold is
   presumed wrong** (the legacy path is the incumbent during its own replacement); the
   known classes go to the named allow-list, adjudicated once.
4. **Cut criterion:** zero unexplained mismatches over **3 consecutive rounds**, each
   with zero dropped appends, on record.
5. **Evidence to the operator for the cut ratification:** the 3 shadow-diff reports; the
   `/status` trajectory counters over the window (appends/dedupes/drops per round); a
   `traj show` sample of one full session lifecycle; the allow-list with its
   adjudications; and the unshadowable-facts statement (schema §9: attempt_id, digests,
   incarnation identity have no legacy counterpart — the window certifies the SHARED
   facts only; `legacy_attempt_count` (§2.2) exists precisely to keep the mint ordinal
   in the shared set). The cut itself is the separate ratified change (§5).

### Appendix A — store stop/start (the standing dolt-server-kill playbook, inlined)

Referenced by step 1b. This is the standing operational playbook, landed here so the
runbook's one destructive step has a citable artifact:

1. **Stop bd's proxy first**, then SIGTERM the dolt child server (never SIGKILL first —
   give it its shutdown commit).
2. **Clear bd's proxy pid/lock files** after the server is down — skipping this leaves
   the store dark/zombie to bd.
3. Any `dolt gc` runs **inside `dolt/<database>/`**, never from `.beads/`.
4. **Restart:** boot bd / the station's normal path; if bd will not respawn the server,
   start it manually — `dolt sql-server --config config.yaml` from inside `.beads/dolt/`.

---

## 5 What Stage 1 does NOT do

- **Nothing about what mounts changes.** No eligibility clause is added — the
  worktree-outstanding barrier, its P6-snapshot machinery, and its refusal record are
  ALL cut-package deliverables (§2.4, incl. the schema-§9 amendment note).
- **No legacy write is deleted, reordered, or conditioned.** Every bd write in the
  retirement list keeps firing exactly as today, including `#rN`/`#void-` re-keys, the
  step-bead churn, the mount-attempt bead, and the four-step terminal tail.
- **No teardown-replay removal.** `replayTeardownTail` runs at every boot through the
  whole window. It deletes at the CUT (falsifier clause 2's first checkpoint) — schema
  §9's "deletes here" refers to Stage 1's cut half, not this shadow half.
- **No admission records** — no grants, no refusals-as-records, no
  `authority.epoch.advanced/.closed` records, no eligibility re-evaluation on the tick.
- **No session-bead slimming, no head-summary handover.** The session bead's writers are
  untouched; P1 is shadow-populated and read by nothing in the engine (reads stay
  legacy; the dual-read + fallback counter is cut machinery).
- **No gate records, no pour/supersede records** (G2), **no verification/effect
  records** (G4), no digest capture beyond the worktree base sha.
- **No GRID_INSTANCE_TOKEN removal** — dual-export only.
- **No publish, no version bumps.** The window runs on dev overrides (§1.1). The
  **release train is a cut deliverable**: grid package tags (the `grid_runtime` minor
  for the public `RuntimeEvent` field, the `grid_sdk` minor for `assembleStationWork`'s
  parameter, `grid_trajectory` as landed) → `space_station_assets` 0.2.1 → lunar's
  version bump. **Ordering constraint (build amendment, 2026-08-31):**
  `grid_runtime` and `grid_sdk` now carry `grid_trajectory: ^0.1.0` — the SAME
  hosted-caret-under-`resolution: workspace` form every other in-repo edge
  uses (`grid_sdk → grid_engine ^0.3.0-rc.7`, `grid_cli → grid_trajectory
  ^0.1.0` pre-dating this window) — so the cut's tag wave must cut
  `grid_trajectory-v0.1.0` FIRST, before the `grid_runtime`/`grid_sdk` tags
  that constrain on it. Inside the window the dev overrides carry it, as they
  carry everything else.
- **No operator-surface change on the incumbent.** The state writer's `onFlare` hole
  stays open through the window (§3); closing it is a cut-adjacent bead.
- **The cut is a separate, operator-ratified change**: quiesced boundary, drain
  procedure, legacy deletion, dual-read arming, the barrier + P6 snapshot, the tick's
  bd-writing repairs (head re-stamp, live reap), the release train, token retirement —
  all of it rides the ratification gate with the §4 evidence pack.

---

## 6 Build-size estimate per chunk

Each chunk is one bead-sized cut, dependency-ordered; LOC are production + test,
calibrated against Stage 0's landed sizes (appender 810, tick 318, fold ~700). **Two
repos:** W1–W8 land in the_grid; WS lands in space_station. During the window
space_station consumes the_grid's branch via the operator machine's
`pubspec_overrides.yaml` — no publish wave inside the window; cross-repo ordering is
only "WS after W1's API exists on the branch".

| # | Repo | Chunk | Contents | Est. LOC (prod + test) |
|---|---|---|---|---|
| W1 | the_grid | Harness + config + lifecycle | `TrajectoryHarness`, `TrajectoryConfig`, append queue + writer loop (§2.5), assembly threading, verify-before-claim boot order, guarded shutdown drain (§1.2), gc cadence | 450 + 350 |
| W2 | the_grid | Attempt identity | `LeaseKeys.attemptId` + breadcrumb shapes, `ProcessHandle` threading, mint/adopt-continue/reconciler-recover rules (§2.1), `AllocationContext` env export, `RuntimeEvent.sessionStarted.attemptId` | 200 + 200 |
| WS | space_station | Runner surface | `TrajectoryConfig` threading at `up_command.dart:491`, `--trajectory`/`--no-trajectory`, banner + `/status` block | 120 + 100 |
| W3 | the_grid | Recorder core + attempt family | `StationTrajectoryRecorder`, failure posture + latches, ~11 attempt/worktree builders, seat/round/pre-grant derivation, `legacy_attempt_count` read | 700 + 500 |
| W4 | the_grid | Call-site hooks | outcome-bearing terminal callers (`_completeAndClose`/`_escalateAndClose`/void/settle callers), session_scope (decline/mint-per-evaluation/rearm), command handler (round-retired), lease vendor, `provisionWorktree` in-service capture + base sha | 320 + 260 |
| W5 | the_grid | step.transition family | capability_host persist-site hooks, gated half, rearm step_round bump, failure_class split, restart-succession derivation | 260 + 210 |
| W6 | the_grid | P2 + P6 folds | `stepCursorDeltaFor` + `processIdentityDeltaFor`, incremental SQL + replay appliers, appender step-5 registration. **Acceptance criterion: the integration suite measures the REAL P2+P6 fold shapes — sustained drain rate above observed storm production rate, p99 writer-loop transaction time — before the window arms (§2.5)** | 550 + 500 |
| W7 | the_grid | Tick Stage-1 obligations | shadow-posture query set (settlement, reaped-backfill, stuck accounting), liveness detector + the **worktree `.grid` mtime scanner and `lastActivity` poll** (explicitly in-budget, I/O cost measured against N concurrent worktrees), pulse UPSERT path | 400 + 320 |
| W8 | the_grid | Shadow-diff extension + runbook | step-fact comparison lanes, `legacy_attempt_count` join, dropped/overflow gating of clean rounds, named-gap classification (stop-races-spawn), `traj provision` verb, runbook doc + Appendix A, schema-§9 amendment edit, CI guard additions | 300 + 270 |

Total ≈ **3,300 prod + 2,710 test LOC** across 9 chunks. Ordering: W1–W2 unblock the
rest *on the branch* (no publish — WS consumes via overrides); W3–W5 parallelize; W6
gates W7 (and its measurement gates the window arming); W8 closes the window's tooling.
Explicitly NOT here (cut package): barrier + P6 snapshot + staleness posture, head
re-stamp obligation, live reap obligation, dual-read, teardown-replay deletion, token
retirement, `onFlare` hole closure, release train.

---

## Review log

- **r1 design** — agent, Fable seat: initial Stage-1 dual-write wiring design.
- **r1 review** — agent, Opus seat: adversarial review against the live tree,
  verdict **fix-then-build**, 18 findings (3 blocker / 8 major / 7 minor)
  (`stage1-design-review.json`).
- **r2 (this revision)** — adjudications by the operator seat; **all 18 findings
  accepted**, with blocker 1 resolved by *staging* (the worktree-outstanding barrier and
  its P6-snapshot machinery moved wholly to the cut package, plus a schema-§9 amendment
  note) rather than by building snapshot machinery inside the window. Every corrected
  citation in this revision was re-verified against the live tree (2026-08-31).
