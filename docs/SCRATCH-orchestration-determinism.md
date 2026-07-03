# SCRATCH — converting operator inference to deterministic behavior

**Status: operator log + correction proposals (2026-07-02).** Written after a day of running the
code circuit live (11 beads landed by grid agents). Nico's ask: *document what's going wrong and
recommend how to correct it deterministically — or where deterministic behavior could be coded
instead of inferred.* The thesis: **almost every manual steering call today maps to a bead that
makes it deterministic, and most are already filed or landed.** What's left after that is the real
Fable-worthy residue (§3).

## 1. The incident catalog

Each row: what happened → root cause → the deterministic correction (**CODE** = buildable guard,
**PROC** = a deterministic operator rule) → status → the inference it eliminates.

### I-1 — Committee down after the repo split (loader cwd walk)
- **What:** all 3 LLM critic lanes instant-failed, 3 retries, breaker-exhausted; zero CLI session
  traces. Silent since the split.
- **Root:** `PackagedAssetLoader._discoverRoot` resolves `extension/` by walking UP from cwd. The
  post-split runner runs with `cwd = space_station`, which can never reach power_station's rubrics
  → `loadRubric` throws inside `CriticCapability.spawn` → supervised `Failed`, no process spawned.
- **Correction (CODE):** resolve via package config (`Isolate.resolvePackageUriSync`), cwd-independent.
- **Status: LANDED** (tg-0j0, power_station #2). Bridge stopgap retired.
- **Inference eliminated:** the forensic "why did all three critics fail with no traces" pass.

### I-2 — False gate: critic verdict written to stdout, not the critique file
- **What:** a Sonnet critic concluded `Verdict: A` in its result text but never wrote
  `.grid/critique/<rubric>.json`; the fail-closed missing-file rule graded **F**, tripping the
  spread gate. A *false* gate — the judgment was A.
- **Root:** the verdict transport had a single channel (the file); an instruction-following miss
  drops the whole verdict. FT-2 already captures the result envelope — the redundancy existed, unused.
- **Correction (CODE):** `CriticCapability.result()` falls back to the captured envelope; strict
  `^[A-F]$` validation; last-match scan (a concluding verdict beats an echoed template). Fail-closed
  preserved (no parseable verdict anywhere ⇒ F).
- **Status: LANDED** (tg-291, power_station #3, hardened over 3 rounds).
- **Inference eliminated:** the operator "transcribe the critic's real verdict onto the lane + close
  the gate" ruling. This class of gate no longer reaches a human.

### I-3 — Malformed validation plan (gating F on good work)
- **What:** tg-ucz's `validation_plan` was `cd power_station && melos run analyze && melos run test`
  — authored from the umbrella-dir view. The gating lane runs *inside the worktree*, which has no
  `power_station/` subdir → `rc=1` → gating **F** regardless of the work's quality.
- **Root:** nothing checks that a `validation_plan` is actually runnable in the worktree before the
  bead is armed. A plan defect is indistinguishable from a code defect at the gate.
- **Correction (CODE — TO FILE):** an **arming preflight** that lints `validation_plan`: reject (or
  loudly warn) a plan that `cd`s outside the worktree, references a path absent in the worktree, or
  is empty. Cheap, deterministic, runs at `validateArming`.
- **Correction (PROC):** validation plans are **worktree-relative only** — never `cd` into a named
  repo dir (the runner is already rooted there). Fold into the bead-authoring rule.
- **Status: TO FILE** (§4). Today handled by operator diagnosis + a plan rewrite + a rework round.
- **Inference eliminated:** "diagnose why code-validation F'd on obviously-correct work."

### I-4 — A cross-repo rename broke fresh compiles (butane)
- **What:** after the Circuit rename landed (the_grid #10 / power_station #4), every fresh worktree
  boot failed to compile — space_station composed `BurnRunCommand` from **gc-owned, unmigrated**
  `butane_grid_assets`, still on `Formula`.
- **Root:** a rename wave migrated the repos it owns but left an *external, unowned* consumer
  dangling. The break surfaced only at the next cold boot, not in the rename's own suite.
- **Correction (PROC + partial CODE):** before a cross-cutting rename, **grep every consumer of the
  renamed symbols across sibling checkouts**; for each, migrate it in-wave OR decouple it in the
  composition root, in the same landing. The grep is deterministic; the migrate-vs-decouple call is
  where ownership knowledge (butane is gc-owned, untouchable) enters — that part stays inference.
- **Status: LANDED** (decouple, space_station `fef00fb`); rule recorded here.
- **Inference:** knowing butane is gc-owned and deprioritized, so decouple (not migrate).

### I-5 — Resident rework doesn't re-mint after a GATED round
- **What:** after tg-ucz's round-1 gate, re-keying the closed session did **not** re-mint round 2 on
  the live runner; a runner restart was required.
- **Root:** a **positive** terminal (advance→land→close) unmounts the work branch (A40), so a re-key
  cleanly re-mints on a resident runner (proven: RS-4, tg-291). A **gate** parks the `SessionScope`
  branch mounted+latched; an external close doesn't re-fire it.
- **Correction (CODE):** the `grid rework` verb (tg-x1j) makes this deterministic — v1: refuse while
  a live session is OPEN and require a runner restart (matches today's working mechanic); v2: for a
  gated round, drive the designed gate-resolve re-arm.
- **Status: FILED** (tg-x1j, with the finding recorded).
- **Inference eliminated:** "why isn't round 2 minting" + the manual `work_bead=<bead>#rN` re-key.

### I-6 — Manual re-key is the rework mechanic
- **What:** each rework round, the operator hand-sets `work_bead=<bead>#r<N>` to force a fresh mint.
- **Correction (CODE):** `grid rework <bead>` (tg-x1j) — re-key through the chokepoint, append the
  finding, report the round, cap at ~3.
- **Status: FILED** (tg-x1j).

### I-7 — Operator-tooling friction (not grid code)
- Stale-session monitor pick (two sessions share a `work_bead` across rework rounds → the watcher
  grabbed the closed one): **fixed** — the watch script prefers the open/newest session.
- Duplicate monitors after a failed boot (a compile-fail `space run` never mints, but the paired
  monitor keeps polling): **PROC** — don't arm the monitor until the runner banner confirms boot.
- These are my harness patterns, not grid behavior; noted for completeness.

### I-8 — Create-then-dep race: a blocker-less create mounts before its deps land (2026-07-03)
- **What:** filing the tg-1di mirror bead against a LIVE resident station: `bd create` (open) and
  the `bd batch` dep-add landed as two commits ~seconds apart; the station's watcher saw the
  blocker-less create first → tg-1di momentarily READY → mounted + spawned. The dep landed right
  after, but A40 (positive-terminal-only unmount) correctly keeps an in-flight session alive — so
  a wrong mount survived its own cause. Compounded: the bead was foreign-rooted
  (`grid.root: space_station`) on a pre-multi-root binary, so its agent got a the_grid worktree.
- **Root:** bead authoring raced the reactive frontier. Ready = armed (D-R4) means the store is
  the trigger surface — a create is LIVE the moment it commits, not when the author finishes.
- **Correction (PROC, effective immediately):** dep-gated beads are **created deferred → deps
  wired → undeferred**, always — the same discipline as the intake rule, now for a second reason
  (the first: unblessed work; this: half-authored work). A create with `--deps` in one atomic
  call would also close it (CODE candidate: verify plain `--deps <id>` semantics — the
  `blocks:<id>` form is inverted).
- **Inference eliminated:** the diagnose-why-did-that-mount pass + orphan cleanup.

### I-9 — An in-flight spawn survived a graceful `space down` (2026-07-03)
- **What:** the same wrong-mount agent (tg-1di, pid 49010 / pgid 49009) was STILL RUNNING after
  `space down` completed and the lock released — teardown missed it. Found via the ps sweep during
  cleanup; killed scoped by pgid.
- **Root (suspected):** the mount/spawn was in flight while the teardown unmounted the tree — the
  dispose-kill pass ran before the allocation registered its process, leaving the child
  unparented. The A38 conservative-unwind covered the post-provision-failure path; this is the
  teardown-vs-spawn window.
- **Correction (CODE — FILED deferred):** the down path ends with an orphan sweep — after unmount
  completes, reconcile `listRunning(<session prefix>)` (or the restart-fence pgids from the state
  store) against zero-expected and terminate stragglers LOUD. Same liveness family as tg-9fl's
  fences.
- **Inference eliminated:** the post-down ps forensics.

## 2. The synthesis — what makes orchestration deterministic

The manual steering today was **overwhelmingly the cost of the missing resident station + rework
verb + plan preflight.** Land those and the loop collapses:

- **Resident station (RS-5b + RS-6)** removes the entire per-arm *boot → monitor → SIGINT-kill →
  re-key* cycle. One process reacts to ready beads; I stop hand-firing each arm and hand-killing each
  runner. (It also dissolves I-5/I-7: no per-arm runner to latch or restart.)
- **`grid rework` (tg-x1j)** makes rework a verb, not an operator re-key ritual (I-5, I-6).
- **Arming plan-preflight (§4, to file)** closes the last inference-heavy gate cause (I-3).
- **Already landed:** loader resolution (I-1) and verdict transport (I-2) — the two committee faults
  that produced false failures — are gone.

Net: after RS-5b/6 + tg-x1j + the preflight, the routine loop is *fire-and-forget over a ready
frontier*, and the false-signal classes that needed human rulings are coded out.

## 3. The residual — where inference genuinely stays

Three things do **not** reduce to a guard, and are the honest Fable-worthy residue:

1. **Rework SCOPE.** Reading a critic's C/F rationale and writing a fix note bounded to *exactly*
   the finding (so the agent fixes one thing, not the world). This is real review judgment; the most
   we can code is routing (a spec-adherence C → auto-revise vs advance — a keep/kill decision, §
   below), not the content of the note.
2. **Infra recovery.** The power-loss / misrooted-dolt-substrate diagnosis. Rare, but it needed
   reasoning across launchd, gc's supervisor, and bd's auto-server behavior. RS-6's launchd recipe +
   a substrate-health preflight (candidate bead) shrink it but won't erase it.
3. **The keep/kill committee analysis.** Per-lane flip analysis, cost tradeoffs, whether a lane earns
   its ~$1.5 spawn. Analytical, one-shot, high-leverage — the archetypal Fable turn.

## 4. Beads this surfaces (to file, deferred until blessed)

- **OP-1 — arming validation-plan preflight (CODE, I-3).** `validateArming` lints `validation_plan`:
  reject a plan that `cd`s outside the worktree / references an absent path / is empty; LOUD refusal
  naming the offending clause. + the worktree-relative-plans authoring rule. `grid_cli`, offline.
- **OP-2 — substrate-health preflight (CODE, §3.2, smaller).** At `space run` boot, verify the state
  store actually reads (the `tg`-not-found class) before arming; on failure, a diagnostic naming the
  expected dolt root vs. the served one — turns the power-loss recovery into a named error, not a
  forensic hunt.
- (Existing, already filed: **tg-x1j** rework verb; **RS-5b/RS-6** resident station.)

## 5. One structural recommendation

The pattern under all of this: **the code circuit's failure signals are currently
under-discriminated** — a gating F means equally "the code is broken," "the plan can't run," or "the
critic fumbled the file." Every one of today's operator rulings was me *disambiguating a failure the
system reported as identical*. The highest-leverage deterministic move is to make the engine
distinguish these at the source: a plan that won't execute is an **arming refusal** (never a gate), a
critic that produces no parseable verdict is a **transport error** (retry, not F), and only a plan
that runs and fails is a true gating F. I-1/I-2 already did this for two classes; OP-1 does it for the
third. Push that principle and the gate becomes trustworthy enough to need a human only for genuine
code disputes — which is exactly the line where inference should live.
