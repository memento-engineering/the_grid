# SCRATCH — public-readiness (the pass surface)

**Status: survey COMPLETE (2026-07-10); REFRESH COMPLETE (2026-07-19, post-molecule-era,
five lenses re-run + spot-verified); bead graph under epic `tg-8gv` — awaiting Nico's
bless.** Opened on Nico's directive: flip the_grid out of private (packages NOT published
yet) once (1) every SCRATCH doc is graduated into real documentation or deleted, (2)
READMEs/docs reflect reality, (3) dead code is deleted, (4) a dead-code/duplicate-code pass
has run and been cleaned up, (5) a debt skill exists (**created 2026-07-10:
`~/.claude/skills/debt`**).

Evidence: the 2026-07-10 5-lens read-only survey, re-run in full on 2026-07-19 against
HEAD `0cef37a` (the molecule era: PRs #60–#73, tg-2mb/#73, plus the seven docs landed
2026-07-19). Load-bearing claims spot-verified in-session both times. This doc is the
worklist + decisions ledger; **it deletes itself at the flip (tg-8gv.12).**

**Refresh verdict in one line: no new blocker; nothing from 07-10 got worse-in-kind — but
almost nothing on the worklist has been executed, entry-point drift deepened with the
molecule landing, and two new decisions (D-P7, and the §3 canonical-stamp fork) now gate
graduation work.**

---

## 1. The BLOCKER ledger

**2026-07-10:** real-gc fixture bytes (PII + tokens) in tree and history → resolved via the
re-capture lane (`tg-8gv.1` executed; D-P1 accepted history-as-is). Working tree holds zero
real-gc bytes; no live credentials tree or history.

**2026-07-19 refresh: NO new blocker.** All 72 files added since 07-10 are code/tests/docs;
new fixtures (`fixtures/upstream/2026-07-10-bd-1.0.5/`) are synthetic and self-documented;
secrets spot-probes all classify as test fakes / env-var names; no personal emails
(`operator@example.com` placeholders only).

## 2. Decisions only Nico can make

- **D-P1 · history strategy — RESOLVED: flip with history intact** (2026-07-10). Unchanged.
- **D-P2 · license — RESOLVED: MIT — and now EXECUTED + COMMITTED** (`da9cbf7`: root
  `LICENSE` + `repository:` in all 7 pubspecs; verified in HEAD 2026-07-19). The 07-10
  "uncommitted, for review" caveat is obsolete. Residue: no `homepage:` field (optional —
  pub.dev accepts `repository:`); NOTE-level.
- **D-P3 · tracked `.beads/` — RESOLVED: keep** (2026-07-10). Refresh input for the flip
  gate: `interactions.jsonl` is now 52 entries and its reason-strings name private siblings
  and their PR numbers (power_station#13, space_station#6, the_grid#36–#46, houston, tgdog,
  "Nico's ruling" narrative). No credentials. Scrub-vs-accept ruling rides `tg-8gv.12` (3).
- **D-P4 · archive convention** — moot given D-P1 (history survives;
  delete-and-rely-on-history works). Unchanged.
- **D-P5 · private-sibling references** (`tg-8gv.12` (5)): counts roughly DOUBLED with the
  molecule-era docs — genesis ×480 (120 files), lenny ×210, power_station ×128 (was 75),
  space_station ×107 (was 62), gascity ×86, houston ×16. Still the same ruling: README
  "internal siblings" note vs scrub. The note lane gets cheaper as counts grow.
- **D-P6 · branches — ANSWERED 07-10, still UNEXECUTED (2026-07-19):** 129 local+remote
  branches; ~60 stale merged `grid/tg-*` heads on origin; GitHub `deleteBranchOnMerge`
  still **false**; worktrees grew 9 → **29**. The interim auto-delete enablement never
  happened. One-time prune rides `tg-8gv.12` (2).
- **D-P7 · ADR-number assignment (NEW, 2026-07-19).** ADR-0013 was consumed by
  *state-holding-value-types* (2026-07-12), but `ADR-0000:466` still routes the
  resident-station graduation (`tg-8gv.4`) to "ADR-0013", and
  `SCRATCH-lifecycle-hooks.md:5` claims "next free is 0014" for its own graduation — the
  two now contend for 0014. Nico assigns both numbers; `tg-8gv.4` and the lifecycle-hooks
  epic are blocked-in-spirit until then (decision bead filed under tg-8gv).
- **In-flight, not a pass decision:** the signal-vs-derivation routing fork (RouteVerdict
  live vs `SCRATCH-declarative-routing`'s derivation model) is an open Nico ratification;
  until ruled, the three docs designing RouteVerdict's deletion need "the signal model is
  what runs today" stamps (catalogued in `SCRATCH-async-step-lifecycle.md` §5.3; no bead
  by design).

## 3. SCRATCH dispositions (the graduate-or-delete table)

**2026-07-19 re-verification: all 15 prior verdicts still stand, with three text
updates:** (a) memento-composition + third-party-harnesses are no longer "untracked!" —
committed 2026-07-19 (`0cef37a`); their target ADR-0008 D1/D10 amendments remain unwritten.
(b) **vnext-prd is UNBLOCKED**: ADR-0012 now exists (Proposed; Decision 1 ratified) and
names vnext §8 as source-of-record — caveat: §8's OTel/observable-source half stays
*reserved, unpromoted* in ADR-0012, so archiving is an informed Nico sign-off, not
automatic. (c) resident-station's graduation target renumbers per **D-P7**.

| Doc | Verdict | Why | Bead |
|---|---|---|---|
| resident-station | **GRADUATE → write the residency ADR (number per D-P7)** | RATIFIED 2026-07-02; only §6 promoted | tg-8gv.4 |
| station-config-model | **GRADUATE §1–6** → ADR-0008 D1 amendment or `docs/CONFIG-MODEL.md` | ratified v3, header stale; `grid_sdk/README.md:36` links it | tg-8gv.5 |
| grid-alignment | **GRADUATE** → ADR-0011 amendment + power_station ADR line | RULED design promoted nowhere; cited by live engine code | tg-8gv.6 |
| multi-root-federation | **GRADUATE the D-M half**, then delete | D-M1..M7 unbuilt + only here | tg-8gv.6 |
| orchestration-determinism | **GRADUATE §5 + PROC rules** → ops doc (still unwritten) | GLOSSARY cites both as ratified; canonical nowhere | tg-8gv.7 |
| memento-composition | **GRADUATE** → ADR-0008 D1 amendment (now committed) | forks resolved 2026-07-10 | tg-8gv.8 |
| third-party-harnesses | **active surface until ratified**, then ADR-0008 D10 amendments (now committed) | decided 07-02, awaiting ratification | tg-8gv.8 |
| allocation-tree | **DELETE** (file 2 genesis follow-ups first) | self-declared GRADUATED; ADR-0009 canonical | tg-8gv.8 |
| dart-runner-and-cli-sdk | **DELETE** (re-point 4 refs incl. 2 grid_cli code comments) | superseded; never-ratified | tg-8gv.8 |
| agent-scope | **ARCHIVE** (per D-P4) | fully promoted; ADR-0008 "detail of record" ×6 | tg-8gv.8 |
| asset-management | **ARCHIVE** after verifying cascade detail in ADR-0011 | ADR-0011 source-of-record | tg-8gv.8 |
| vnext-prd | **ARCHIVE — unblocked 2026-07-19** (Nico signs off the reserved-§8 caveat) | ADR-0012 names §8 source-of-record | tg-8gv.8 |
| docs-debt-sweep | fold worklist state into the ops doc; close (blocked on tg-8gv.7's doc) | W0–W9 executed | tg-8gv.8 |
| pub-capability-and-repo-split | keep as design note | unratified future-step design | tg-8gv.8 |
| public-readiness (this doc) | deletes itself at the flip | — | tg-8gv.12 |

**NEW surfaces (2026-07-19) — none existed at the 07-10 survey; none are graduate/delete
candidates yet:**

| Doc | Verdict | Why | Bead |
|---|---|---|---|
| beads-all-the-way-down | **ACTIVE-SURFACE**; needs canonical-fork stamp | backs the built tg-pm6 epic; designs RouteVerdict deletion (in-flight ruling) | tg-pm6 → tg-eli |
| declarative-routing | **ACTIVE-SURFACE — awaiting Nico ratification**; needs canonical-fork stamp | the routing epic's live design | (ratification) |
| DESIGN-tg-pm6 | **KEEP — canonical build ref**; needs A52-a2 + "inert" corrections (tg-6i8) | cited by live lib code ×10+ | tg-pm6 |
| diagnostics-projection | **ACTIVE-SURFACE** (ratified 07-18, unarmed); graduates → ADR-0012 amendment | epic tg-0ds deferred; "inert/flatCursor" claim stale (tg-6i8) | tg-0ds |
| lifecycle-hooks | **ACTIVE-SURFACE — awaiting ratification**; ADR number per D-P7 | decision-complete 07-18 | (unfiled epic) |
| cockpit | **source-of-record behind ADR-0012 D1**; stamp §5 superseded by diagnostics-projection §6 | ratified 07-11 | tg-wisp-5xa |
| async-step-lifecycle | **ACTIVE-SURFACE** (the 07-19 audit); §6 graduates → ADR-0013 amendment on ratification | resolves tg-uad; §5 drives tg-6i8 | tg-uad, tg-j6u, tg-090, tg-6i8 |

## 4. Doc-drift digest (→ tg-8gv.9, tg-8gv.10)

**2026-07-19: every 07-10 claim re-verified STILL TRUE except the pubspec `repository:`
fields (fixed, `da9cbf7`); several worse.** Still standing: root README frozen at "M1 in
progress" with a `grid_controller` package table and Riverpod-as-current; grid_cli README
spends ~63/87 lines on the deleted `grid run` while registered `gate`/`rework` go
undocumented; grid_runtime README ×10 pre-rename symbols + deleted `grid_reconciler`;
CLAUDE.md tail (Packages list / `exploration_contract` path-dep / A30-as-fact); PDR banner;
GLOSSARY tgdog-as-live; no README for beads_dart/grid_engine/grid_exploration/grid_devtools.

**New (molecule-era) drift:**
- `GLOSSARY.md:608,611` Flow F1 still hands the reader the retired `--land` flag —
  `grid_sdk/test/land_seam_retired_test.dart` exists specifically to forbid it.
- `grid_sdk/README.md:40-51` "Track A (skeleton)… no composition types yet" — now denies
  the entire shipped `RawAssetGrid`/`Station`/`runGrid`/`StationWork` surface (badly worse:
  it's the package a station author is told to depend on).
- `grid_engine/pubspec.yaml:2` description still speaks WorkPhase/EffectSeed (both deleted).
- `genesis_tree` pin drift now 3-way: `^0.1.3` (grid_cli, grid_engine) vs `^0.1.5` (grid_sdk).
- Entry-point layer is CLEAN of flatCursor/StepOutcome.Gate/Rewind claims — that drift is
  confined to SCRATCH/DESIGN docs and owned by **tg-6i8**.

**First-time-reader trip ranking (worst first):** root README (misrepresents the whole
system) → grid_cli README (headline command doesn't exist) → grid_sdk README (tells authors
the SDK is empty) → no front door on beads_dart/grid_engine → GLOSSARY/PDR internal
contradictions (tgdog, `--land`).

## 5. Dead + duplicate code digest (→ tg-8gv.11)

**2026-07-19 re-verification.** Still present, unchanged: WorkPhase
(`circuit_resolver.dart:7`), runGridTree (`substation_config.dart:45`),
StableInheritedSeed (`station_kernel.dart:149`) fossils; the `engine_fakes.dart` one-line
shim; the 4 tool scripts + empty `grid_sdk/tool/`; both raw `Process.run('bd')` spawns
(`demo_command.dart:32`, `substation_init.dart:26`); StationControl/StationAttach/
station_lock unwired (owned by OPEN epic tg-3s8 — not dead).

**Strike from the ledger (resolved/moot):** the byte-identical `fixtures.dart` pair (one
half deleted with the gc-fidelity layer, `bd13c50`); CapabilityContext ×5 / EffectSeed ×1
as *lib* fossils (now test-docstring lineage only); ADR-0009 Track G smells — **dissolved**
(`Expando` zero, live `_capCtx` zero, `CancelToken` is now the intended typed
`StepArgs.cancel`); "circuit_migration.dart frozen shapes" was a mis-homed premise (that
file is power_station's, not the_grid's).

**Add to the ledger (new since 07-10):**
- `grid_reconciler` lineage-comment fossils ×5 (`ready_work_source.dart:6`,
  `bead_ownership.dart:4`, `subprocess_provider.dart:14`, `git_runner.dart:46`,
  `beads_dart.dart:84`).
- runGridTree fossil leaked into generated code (`substation_config.freezed.dart` ×3 —
  fix source + regen clears four sites).
- `AllocationGated` lineage comment (`allocation.dart:246`).
- **Unwired-but-owned, new:** `ReloadCommand`/`StationReload` — barrel-exported, never
  registered in `bin/grid.dart` → tg-3s8, beside StationControl/Attach/Lock.
- **Flat-path retirement cluster → tg-eli (now UNBLOCKED — both deps closed):** engine-level
  `flatCursor` default + session_scope fallback, the NodeCursor pgid/pid/token flat-persist
  half (`capability_host.dart:463`), and the self-declared-dead `_persistRewind` cascade
  (`capability_host.dart:713-755`). Do NOT delete ahead of tg-eli.
- `liveFrontier()` convenience wrapper: built-and-parked, zero production callers
  (session_scope uses `effectiveCursor`+`eligibleSteps` directly) — ruling: delete or keep
  for future molecule consumers.
- **Duplication guards wanted (both dependency-arc-forced, prose-only today):**
  (1) `StationBeadWriter`'s hand-retyped `grid.step.*`/`grid.circuit.*` literals
  (`station_bead_writer.dart:155-164`) vs `MoleculeStepKeys`/`MoleculeCircuitKeys` — no
  parity test exists; (2) grid_devtools' `ext.exploration.*` pins
  (`grid_exploration_client.dart:22,25`) — the 07-10 ask, still unguarded. A
  `RecordingBdRunner` ×2 parity note rides the same guard work.
- The spawner/ProcessAllocation mirror (provisioning + SessionAlreadyExists blocks
  duplicated verbatim) is the **tg-uad divergence site** — drift note attached to tg-uad;
  optional shared-provisioning-helper extraction.

## 6. Related existing beads (don't duplicate)

tg-cxw (GridController* renames — grid_controller_* files are LIVE pending this, not
fossils), tg-3vq (doc-status stamps), tg-d4k, tg-2ds, tg-wiz, tg-qkc, tg-3s8
(resident-station epic — owns ALL the unwired control surface incl. Reload), **tg-eli**
(flat retirement — now unblocked, owns the flat cluster), tg-pm6 (molecule epic), tg-0ds
(diagnostics), tg-wisp-5xa (cockpit build), and the 2026-07-19 async-audit set: tg-uad
(P1 fix), tg-j6u (handoff-window test), tg-090 (SessionAlreadyExists hang), tg-6i8
(async-doc re-stamps).

## 7. The graph

`tg-8gv` (epic) → .1 fixtures ✅ · .2 history ✅ · .3 license ✅ (committed `da9cbf7`) ·
.4 residency ADR (number per **D-P7**) · .5 config-model · .6 grid-alignment+multi-root ·
.7 ops doc · .8 SCRATCH endgame (waits on .4–.7; commit-half of the untracked surfaces done
2026-07-19 via `0cef37a`) · .9 README reality (+ molecule-era additions) · .10 package
READMEs · .11 dead/dup sweep (ledger refreshed 2026-07-19) · .12 flip checklist (waits on
all; branch/worktree prune + scanner install + interactions ruling + D-P5) · **.13 (NEW)
decision: D-P7 ADR-number assignment**. All born deferred; Nico's bless flips open.
