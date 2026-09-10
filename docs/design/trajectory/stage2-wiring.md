# Stage 2 wiring — pour, successors, and the quiesced G2 cut

This document is the implementation source of truth for Stage 2. It extends the
trajectory system already in the tree; it does not define a parallel record,
projection, append, or epoch mechanism.

**Baseline.** `MoleculePoured` and `StepSuperseded` are authored in
`packages/grid_trajectory/lib/src/codec/records/step_records.dart` (lines 84 and
240). The P2 read fold already consumes `StepSuperseded` as
`StepCursorSupersede` in
`packages/grid_trajectory/lib/src/fold/step_cursor_delta.dart` (lines 154–161).
`MoleculePoured` is deliberately not a P2 cursor delta: the null arm at lines
162–169 records that molecule edges belong in `proj_step_edges`. Both record
types are registered in
`packages/grid_trajectory/lib/src/codec/codec_registry.dart`, but no production
site constructs either one. The same registry maps
`authority.epoch.advanced` to the existing `AuthorityEpochTransition` at line
47, which is the Stage 2 stamp vehicle.

This bead is documentation-only. It appends no trajectory record, changes no
writer or fold, retires no bead type, and does not cross a stage boundary.

## 1. Entry gate: G1 cut prerequisite

Stage 2 is gated on the completed G1 cut.

No G2 implementation chunk mounts, and no G2 `shadow` or `cut` posture is
enabled, while G1 remains in shadow. The prerequisite certificate is a
`TrajectoryDiscipline.cut` resolution with `dualRead: primary` on both axes and
`mode: required`, followed by three clean G1 boots whose legacy fallback count
and unexplained divergence count are both zero. An absent or internally
inconsistent certificate is a named boot refusal, not a warning or an implicit
demotion.

This ordering follows `trajectory-schema.md` §9 and the accepted decisions
`the_grid#wave-2-flip-scope-soak-and-kill-date` and
`the_grid#wave-2-entry-criteria-rulings`. The wave-2 material in
`cut-wiring.md` is historical rationale only: its design-incomplete appendix is not authority,
while those two later accepted entries are. The schema orders
the coherent groups G1 and then G2. The G2 cut removes the step and molecule
bead carriers that G1 shadow still treats as live authority, and the
projection-only falsifier cannot be claimed while G1 still permits legacy
fallback. Allowing the windows to overlap would therefore erase G1's oracle
while still claiming that oracle can decide G1 truth.

## 2. Construction and lifecycle

Stage 2 adds one G2 posture value at configuration assembly. It resolves to
absent/off, `shadow`, or `cut`; this is one posture, not independent writer and
reader toggles. Every non-off value validates the G1 certificate from §1 before
constructing a G2 runtime. Missing, shadow, non-primary, non-required, or
uncertified G1 state refuses boot by the name `G2G1PrerequisiteRefused` and
reports the mismatched field.

The postures have these lifecycle meanings:

* **Off:** no G2 writer, comparator, or cut behavior is mounted.
* **Shadow:** legacy step/molecule creation remains authoritative. After the
  legacy call returns, the authority appends the matching G2 record through the
  existing trajectory recorder, lets the existing post-ACK mirror apply it,
  and compares legacy and projected graph truth. Shadow never retires or reaps
  a graph bead type.
* **Cut:** reachable only after the G2 comparator records three clean rounds
  with zero unexplained mismatches and zero projection fallback. G2 records and
  projections become authoritative, all new step and molecule bead creation is
  disabled, and only the first-boot reap plus the bounded fallback in §§5–6
  remains.

The runtime mounts and stops with the existing trajectory harness. It uses the
existing recorder, sole appender, mirror, fold metadata, and
`TrajectoryAdmissionHalt`; configuration supplies values while those
implementations remain injected services. No posture is read from ambient
state after assembly has resolved and validated it.

### `molecule.poured` contract

The envelope correlations are `session_id` and `round`. The payload is formed
once from the selected molecule and has this exact contract:

* `formula` is the selected circuit/formula identity.
* `graph.nodes` is the lexically sorted list of executable step paths.
* `graph.edges` is the lexically sorted list of `{from_path,to_path,kind}`
  objects, containing only `blocks` and `validates` edges. Lexical comparison
  uses the tuple `(from_path, to_path, kind)`.
* `node_count` is the number of executable nodes.
* `graph_digest` is lowercase SHA-256 over the UTF-8 bytes of canonical JSON:
  object keys are recursively sorted and the encoding has no insignificant
  whitespace.

Parent/child structure is reconstructed from paths and formula metadata; it is
not encoded as an extra edge kind. The same canonical graph value feeds the
legacy `GraphApplyPlan` adapter in shadow and the `MoleculePoured` record in
both non-off postures, so the two sides cannot drift through separate
derivations. The authored `pour:<session_id>:<round>` idempotency key is the
retry key and the crash-gap healing key.

### `step.superseded` contract

`session_id`, `round`, and `step_path` identify the existing logical step.
`old_step_round` is `currentDepth`; `new_step_round` is exactly
`currentDepth + 1`; `cause` is `validation-failed`; and `budget_remaining` is
`max(0, kMaxReworkRounds - (spentRounds + 1))`. The record retains the authored
`supersede:<session_id>:<round>:<step_path>:<old_step_round>` idempotency key
and the constructor invariant that the new round exceeds the old round.

## 3. Derivation layer: record map

Stage 2 extends the existing observer-written derivation layer. The authority
and session sites observe completed legacy mutations in shadow; they do not ask
an agent-authored disc to assert a lifecycle fact. Envelope ownership continues
to use the service-derived `substation` value.

| Record | Observation site | Trigger | Payload source | Idempotency | Fold target | Shadow oracle |
|---|---|---|---|---|---|---|
| `molecule.poured` | `StationAdmissionAuthority.pourMolecule` in `packages/grid_engine/lib/src/kernel/station_admission_authority.dart` | After `_writer.createMolecule` returns, for both a fresh create and an idempotent empty result, so retry heals a crash between the legacy write and append | The one canonical molecule graph described in §2, derived from the selected formula/circuit and executable `GraphApplyPlan` | `pour:<session_id>:<round>` | `proj_step_edges` | Legacy step/molecule bead graph and the `GraphApplyPlan` applied from the same canonical graph |
| `step.superseded` | `SessionScope._mintStepSuccessor` in `packages/grid_engine/lib/src/circuit/session_scope.dart` | After `ctx.writer.createStepSuccessor` returns, for both a fresh create and an idempotent existing-successor result | `sessionId`, current session `round`, `nodePath`, `currentDepth`, `spentRounds`, and `kMaxReworkRounds` under the §2 formula | `supersede:<session_id>:<round>:<step_path>:<old_step_round>` | Existing `StepCursorSupersede` chain update in `proj_step_cursor` | Legacy successor bead at the same path, with its supersedes relationship and depth |

The earlier intake path
`packages/grid_engine/lib/src/kernel/session_scope.dart` names the same planned
observation seam; in this checkout `SessionScope` lives under `src/circuit`.
There is one observation site, `SessionScope._mintStepSuccessor`, not two.

G2-1 adds the missing `MoleculePoured` edge delta through the same
incremental-SQL and in-memory-replay delta architecture already used by P1 and
P2. The record-to-delta function is shared by live append and replay, and the
two appliers implement the same delta semantics. Molecule edges do not route
through `StepCursorDelta`, and Stage 2 does not create a second fold framework.

The Stage 2 engine projection rule is:

* Frontier and status consumers read P2 plus `proj_step_edges`.
* An absent P2 row remains the existing pending/not-yet-materialized case; it
  is not proof of completion, supersession, or a missing graph.
* Step result, cooldown, and restart fields continue to come from
  `StepTransition` until G4.
* Lease breadcrumbs are read from the existing attempt-lease projections
  before graph bead types retire.

The schema §9 falsifier checkpoint is satisfied only when the frontier/status
suite rows 3/5/6/14/15/16 run through those projection reads with a guard that
detects any legacy graph call.

## 4. Append discipline

Shadow ordering is legacy mutation first, append second, and the existing
post-ACK mirror third. A legacy success followed by append failure is a named
shadow divergence. It is never silently repaired from reconstructed or guessed
data. A retry re-enters the legacy operation and uses the deterministic record
idempotency key after the legacy call returns, including when
`createMolecule` returns its deduplicated empty shape or successor creation
returns the existing successor. This closes the legacy-write/record-append
crash gap without duplicating a trajectory fact.

Cut ordering is intent record append and ACK first, projection/mirror
confirmation second, and only then any newly enabled engine action. No legacy
graph create occurs. In particular, a poured molecule is not admitted to drive
until its edge projection is confirmed, and supersession cannot release the
predecessor until the chain update is confirmed.

Every Stage 2 append uses the existing sole trajectory appender and its
fencing-token and counter-CAS discipline. The existing appender owns record
identity, per-epoch sequence allocation, durable append, incremental fold, ACK,
and post-ACK mirror sequencing. Stage 2 introduces no direct SQL write,
independent queue, second recorder, or alternate recovery log.

## 5. Failure posture

In shadow, an append, fold, or comparison failure is non-fatal to the legacy
run, but it emits the existing typed trajectory flare, disqualifies that round
from the three-clean-round G2 certificate, and increments the relevant named
failure or mismatch counter. The comparator never converts an unexplained
mismatch into a fallback success.

In cut, append refusal, post-ACK mirror failure, a stale projection, checksum
mismatch, or fold failure trips the existing `TrajectoryAdmissionHalt` and
prevents drive. It never falls back to a deleted graph bead carrier. A molecule
is not driveable before its `molecule.poured` ACK and edge-projection
confirmation. A predecessor is not released as superseded before its
`step.superseded` ACK and P2 chain confirmation.

A failed one-shot reap leaves the residue visible and prevents the driver from
starting. The next boot repeats the scan and retries the idempotent delete;
neither the receipt nor a partially completed scan may assert zero residue.
Rollback means booting the previous epoch's code. Trajectory rows and
projections remain additive: rollback does not delete records, rewrite an
epoch stamp, or reverse a fold.

## 6. First-boot runbook

1. Verify the completed G1 certificate and the G2 shadow certificate. Stop on
   a missing receipt, nonzero fallback, or unexplained divergence.
2. Stop the station and take the paired backup required by the trajectory
   operational contract.
3. Before any Stage 2 epoch claim, read the outgoing legacy discipline and
   require zero open sessions. A nonzero count causes a loud exit-64-style
   refusal, appends no Stage 2 stamp, and starts no driver.
4. At a blocked cut, choose exactly one of the schema's two drain vehicles:
   boot the previous G1-cut epoch code until its sessions terminate, or use the
   standing harvest-review/close-session playbook. Re-run the zero-open check.
   Stage 2 never crosses the boundary over an open session.
5. Claim the new epoch and append the existing
   `authority.epoch.advanced` / `AuthorityEpochTransition` with observed
   provenance and `provenance_basis: stage2:g2-cut`. The Stage 2 basis is a
   stamp on the existing epoch record, not a new record type.
6. Before starting the driver, scan closed sessions for legacy-poured residual
   step/molecule beads and run `reapMolecule` once per residue using its
   existing idempotent deletion semantics. Re-scan to zero. A failure refuses
   operational boot and leaves an auditable retry on the next boot.
7. Record the cut receipt, start the driver only after the zero-residue check,
   and monitor projection lag, append refusal, comparison, and fallback
   counters.
8. On rollback, boot the previous epoch's code. Do not delete trajectory
   history or rewrite the Stage 2 stamp.

The read-only drain arm is fixed before the cut. After G2 writers retire, only
`reapMolecule` over legacy-poured residue survives. It may perform terminal deletes only:
it permits no new molecule mint, step mint, successor mint, or
admission. It is bounded to one round cycle measured from its activation
receipt. At the next round boundary it must report zero residue or refuse
extension.

On the normal path, G2-8 deletes `reapMolecule` after every station reports its
first-boot zero-residue receipt. If the fallback is activated, the arm is
deleted at Stage 3 entry. It cannot bypass the zero-open-session gate and is
distinct from the pre-cut choice to boot previous code or harvest open
sessions.

## 7. What Stage 2 does not do

Stage 2 does not append or enable `AdmissionGrantIssued`,
`AdmissionGrantConsumed`, `AdmissionGrantClosed` (grant close),
`AdmissionRefused`, `AdmissionRestored`, or `AdmissionDriveApproved`. It does
not retire mount-attempt beads; remove `_mountedIds`,
`_mountAttemptsScheduled`, `_mountAttemptWrites`, or any other admission
reservation/latch state; activate authority eligibility re-evaluation or
admission-family `TrajectoryTick` queries; slim `SessionHeadView` or
`proj_session_head`; or alter Stage 3 grant fencing. Those are Stage 3
surfaces, and this design explicitly fences Stage 3.

It also leaves gate records, G4 verification/effect writers, generic non-graph
bead types, the G1 cut design, and operator hard-delete policy untouched.

## 8. Build-size calibration and dependency-ordered decomposition

These estimates are calibrated against
`docs/design/trajectory/stage0-measurements.md` and the landed Stage 0/Stage 1
file sizes. They count production plus tests and are planning bounds, not
acceptance thresholds.

| Chunk | Repository | Depends on | Contents | Production LOC | Test LOC |
|---|---|---|---|---:|---:|
| G2-1 | the_grid | completed G1 cut | G2 config/codec helpers, canonical molecule graph, `MoleculePoured` edge delta for incremental and replay folds | 360 | 360 |
| G2-S | space_station | G2-1 config seam | runner posture parsing, named G1-prerequisite refusal, cut receipts and status rendering | 90 | 90 |
| G2-2 | the_grid | G2-1 | shadow emission at `pourMolecule` and `_mintStepSuccessor` through the existing recorder and post-ACK mirror | 300 | 280 |
| G2-3 | the_grid | G2-2 | G2 shadow comparator, mismatch taxonomy, fallback counters and three-round certificate | 330 | 300 |
| G2-4 | the_grid | G2-1, G2-2 | P2/edge projection graph read model, frontier reconstruction, lease-source migration and missing-row posture | 600 | 520 |
| G2-5 | the_grid + space_station | G2-3, G2-4 | schema rows 3/5/6/14/15/16 from projections only, runner probes and a legacy-call guard | 450 | 500 |
| G2-6 | the_grid | G2-S, G2-5, three clean rounds | quiesced boot gate, Stage 2 epoch basis, cut-mode record authority and step/molecule writer retirement; cut remains unarmed until G2-7 | 520 | 480 |
| G2-7 | the_grid | G2-6 | first-post-cut residue scan, one-shot idempotent legacy reap, read-only one-round drain arm and driver-start gate | 260 | 300 |
| G2-8 | the_grid | G2-7 plus fleet zero-residue receipts | delete `reapMolecule` on the normal path after fleet zero-residue receipts; if the bounded fallback was activated, make its deletion a hard Stage 3 entry prerequisite; remove shadow fallback and run repository hygiene | 220 | 260 |
| **Total** |  |  |  | **3,130** | **3,090** |

The dependency graph is `completed G1 cut → G2-1 → G2-2 → G2-3`;
`G2-1 → G2-S`; `G2-1 + G2-2 → G2-4`; `G2-3 + G2-4 → G2-5`;
`G2-S + G2-5 + three clean rounds → G2-6 → G2-7 → G2-8`.

G2-6 is cut-capable but cannot be enabled until G2-7 makes the required
first-boot reap atomic with driver admission. G2-8 completes the normal Stage
2 path. Only an explicitly activated bounded fallback defers its drain-arm
deletion to the Stage 3 entry gate, without implementing any Stage 3 admission
surface.
