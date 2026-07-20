# Operations — the failure ladder & the standing disciplines

**Status: durable operations doc** (opened 2026-07-19, public-readiness pass tg-8gv.7).
This graduates the **ratified** operational content out of
`SCRATCH-orchestration-determinism.md` — the failure-discrimination ladder (§1, which
`GLOSSARY.md` cites as ratified) and the enduring PROC disciplines distilled from its
incident catalog (§2). The SCRATCH remains the incident **history**: the per-incident
forensics (I-1's loader cwd walk, I-14's mis-diagnosis and correction, the one-time
cleanups) stay there; every rule here keeps its `I-n` provenance so the trail back is
one hop. Where a rule has since been coded, the current enforcement point is named —
verified against source at time of writing.

---

## 1. The failure-discrimination ladder (ratified)

A gating **F** must never mean three different things. The ladder discriminates the
failure classes at the source, so the committee gate stays trustworthy enough that a
human is needed only for genuine code disputes:

1. **A validation plan that cannot run in the worktree is an ARMING REFUSAL, never a
   gate** (I-3, I-12). An environment/authoring defect — a `cd` into a directory the
   worktree doesn't have, an absolute path, prose executed as `sh` (rc=127) — is
   refused before any spawn, loud, naming the bead and the offending clause. It never
   reaches the committee dressed as a code verdict.
   *Enforcement today:* the tg-a76 arming preflight implemented this in the old
   `grid_cli` boot path; that path (and the preflight with it) was deleted in the
   runGrid migration (tg-d5f, #43). Its re-home is queued as delegate/type validation
   (`GRID-SDK-BUILD-ORDER.md`, tg-a76/tg-5wb) — until it lands, the §2.1 authoring
   discipline is the load-bearing enforcement.
2. **A critic with no parseable verdict is a TRANSPORT ERROR, not a judgment** (I-2,
   I-13). The committee's verdict transport is a three-channel chain — canonical file →
   captured result envelope → fail-closed default F — and every grade carries its
   `transport` provenance (`file`/`envelope`/`fail-closed-default`, durable on
   `grid.result.<nodePath>.transport`), so a fail-closed default is visibly not a
   judgment. The critic prompt interpolates the **absolute** canonical verdict path
   (cwd-invariant; the I-13 stray-write class), with a round-fresh stray-file belt and
   a `Grade:`-heading envelope fallback behind it (grid_assets `committee.dart`,
   tg-291/tg-r66).
3. **Only a plan that RAN AND FAILED is a true gating F.** This is the only class that
   should reach a human ruling — and the only one where "fix it and rework" is the
   right verb.

A **false gate** is a rung-1 or rung-2 artifact gating a green round. The ruling path
for one is `grid gate resolve --grade <lane>=<A-E> --rationale "<why>"` (§2.3), never
an edit to the work.

---

## 2. Standing disciplines

### 2.1 Authoring work beads

- **`validation_plan` is an executable contract, worktree-relative only** (I-3, I-12).
  The gating lane executes the field as `sh` **inside the bead's worktree**: never `cd`
  into a named repo dir (the runner is already rooted there), never reference an
  absolute path outside the worktree, never file prose in the field. A plan defect
  costs real money — I-12's prose-planned beads burned two rework rounds (~$16) on
  work whose other three lanes were straight-A.
- **Dep-gated beads are created deferred → deps wired → undeferred, always** (I-8).
  Against a live station, ready = armed: a `bd create` is live the moment it commits,
  and a blocker-less create mounts within seconds — before the dep-add lands. The
  deferred-create discipline closes both the half-authored-work race (I-8) and the
  unblessed-work race (the original intake rule). A positive terminal is the only
  unmount (A40), so a wrongly-mounted session survives its own cause — prevention is
  the whole game.

### 2.2 Cross-repo renames

- **Before a cross-cutting rename lands, grep every consumer of the renamed symbols
  across the sibling checkouts** (I-4). For each consumer: migrate it in-wave, or
  decouple it at the composition root — in the **same landing**. The grep is
  deterministic; the migrate-vs-decouple call is where ownership knowledge enters
  (I-4's `butane` was externally owned, so: decouple). The break class this closes
  surfaces only at the next cold boot, never in the rename's own suite.

### 2.3 Gates and rework

- **Never bare-resolve a gate born from a persisted lane F** (I-14). The route re-reads
  the **persisted** lane grades on the session bead, not the fresh verdict files — so a
  plain close of a still-F gate re-arms the node and re-gates seconds later, a
  guaranteed no-op loop. The ruling flow: correct the lane grade first
  (`grid gate resolve <id> --grade <lane>=<A-E> --rationale "<why>"` writes the
  corrected grade + `transport=operator-ruling` through the chokepoint, then closes).
  This is now code-enforced: `runGateResolve` **refuses LOUD, zero writes** on a plain
  resolve while any feeding lane still grades F, naming the lanes and their transport
  provenance (`grid_cli/gate_command.dart`, tg-i08).
- **A re-gating node refreshes its existing OPEN gate — it never mints a duplicate**
  (I-14 mint-dedup). `StationBeadWriter` bumps `regate_count`/`regated_at` on the
  existing gate; `grid gate ls` shows the reset age plus a `re-gated Nx` marker, so a
  churning gate is visible on one stable id.
- **Rework is a verb, not a re-key ritual** (I-5, I-6). `grid rework <bead>` retires
  the terminated round through the chokepoint, clears stale specify-authored fields,
  appends the operator's finding to the work bead's notes under a ROUND N header, and
  enforces the ~3-round cap — refusing LOUD beyond it (a human decides). It refuses on
  a live (open, non-gated) session; an open-but-**gated** session with nothing running
  is the one safe retire (`SessionScope`'s gate-resolve transition re-arms in place, no
  runner restart — the I-5 wedge, closed).
- **Treat `gate ls` as the ultimatum surface, and keep it honest** (I-15). Pre-dedup
  terminal closes leaked their gate beads (14 found open against long-closed sessions);
  mint-dedup caps per-node growth, but a sweep of open gates at session terminal-close
  is still owed (tg-ycu, deferred) — until it lands, stale open gates are swept by
  hand, and an old open gate against a closed session is a leak, not a signal.

### 2.4 Teardown and process liveness

- **The down path ends with an orphan sweep** (I-9). Unmount = kill, but the kill chain
  is fire-and-forget — a spawn in flight during teardown can outlive it (I-9's agent
  survived a clean `down`). This is now engine code: `RestartReconciler.sweepOrphans`
  (grid_engine) reconciles the station against zero-expected from two independent
  evidence halves — the transport's `listRunning` under the session prefix, and the
  restart-fence pgids persisted on the station's own non-terminal session beads — with
  quiet-pass settling, scoped kills only (coexistence), and a **required** loud
  `onOrphan` reporter. `runGrid` wires it (`work.sweepOrphans`) and
  `GridHandle.teardown()` runs it after the tree unmounts.
- **An orphan report is an invariant violation, not noise.** A clean teardown logs
  nothing; every reap carries a concrete failure story (a leaked agent burning tokens
  against a worktree nobody owns). Investigate the window that produced it.
- **Don't arm a watch/monitor until the boot banner confirms the runner minted** (I-7).
  A compile-failed boot never mints, and a monitor armed on faith polls a ghost. An
  operator-harness pattern, not grid behavior — kept because it recurs.

---

## 3. Where inference stays

Three things deliberately do **not** reduce to a guard (SCRATCH §3): **rework scope**
(reading a critic's rationale and writing a fix note bounded to exactly the finding),
**infra recovery** (the rare cross-system diagnosis — launchd, substrate, store
serving), and the **keep/kill committee analysis** (whether a lane earns its spawn
cost). The ladder's purpose is to spend human judgment only there.

---

## 4. Worklist state (the docs-debt sweep, W0–W9)

The companion `docs/SCRATCH-docs-debt-sweep.md` (retired to git history — tg-8gv.8) executed
its worklist in full (2026-07-05):
`GLOSSARY.md` was authored and corrected per the rulings log (W0), the emptied package
stubs deleted (W1), supersession stamps applied to ADR-0008 (Formula→Circuit + the
`grid_sdk` naming) and ADR-0002 (package topology) with vnext-prd §5 banner'd (W2, W3,
W6), the `rig` prose residue swept from grid_engine doc-comments (W4), `DEBUGGING.md`
created and the core docs de-leonarded (W5), tg-cxw widened to cover the
`GridControllerPlugin` rename (W7), the config-model proposal drafted as
`SCRATCH-station-config-model.md` (W8, since ratified v3 and largely executed by the
runGrid rebuild), and the standing rule recorded that the glossary updates at each
ratification (W9).
