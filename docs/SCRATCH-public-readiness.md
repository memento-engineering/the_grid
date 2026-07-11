# SCRATCH — public-readiness (the pass surface)

**Status: survey COMPLETE (2026-07-10); bead graph FILED DEFERRED under epic `tg-8gv` —
awaiting Nico's bless.** Opened on Nico's directive: flip the_grid out of private (packages NOT
published yet) once (1) every SCRATCH doc is graduated into real documentation or deleted,
(2) READMEs/docs reflect reality, (3) dead code is deleted, (4) a dead-code/duplicate-code pass
has run and been cleaned up, (5) a debt skill exists as a result of this action (**created
2026-07-10: `~/.claude/skills/debt`** — encodes this pass's procedure).

Evidence: a 5-lens read-only survey (two SCRATCH-disposition sweeps, a doc-drift audit, a
dead+duplicate-code hunt with full import-reachability BFS, a secrets/hygiene scan of tree AND
git history), load-bearing claims spot-verified in-session. This doc is the worklist + decisions
ledger for the pass; **it deletes itself at the flip (tg-8gv.12).**

---

## 1. The one BLOCKER

`fixtures/upstream/2026-06-11-bd-1.0.5/` `hq-*` samples + `convergence/bd-export-roundtrip.jsonl`
are **real bd exports from the live gc**: personal email + real name, **22 `instance_token`
values + session UUIDs**, `/Users/nico` paths, private-rig topology, internal doc links. Verified
clean: `convergence/*.json`, `tg-*.json`, `fixtures/exploration/*`. Because the files are tracked,
the data is **also in git history** — sanitizing the working tree alone is not enough.
→ `tg-8gv.1` (re-capture sanitized) + `tg-8gv.2` (history strategy).

**RESHAPED (2026-07-10, Nico's "ditch the gc-porting fixtures?" question):** the gc-fidelity
layer is already dead — `convergence/` has ZERO consumers (its tests died with grid_reconciler;
`ConvergenceFields` gone), and `grid_engine/lib/src/projections/{agent_session,message,molecule}`
are barrel-exported but imported by nothing (gc domain nouns, M1/M2 era).

**EXECUTED on main (Nico "you do it on main", 2026-07-10):** deleted `convergence/` + the
grid_engine projections (lib + tests + barrel exports) + the engine's fixture loader + orphan
`tg-ready-empty.json`; new fixture set **`fixtures/upstream/2026-07-10-bd-1.0.5/`** at the same
pin — clean `tg-*` files carried forward byte-unchanged, the 4 hq files replaced by `fx-*`
captures from a seeded scratch store (prefix `fx`, identity `operator`; real bd 1.0.5 bytes,
synthetic content; seeding recipe in the set's README). bead_test/bd_cli_service_test re-pinned
(the fx export also carries 3 dependency edges — the export dep-parser now has fixture
coverage the hq sample never gave it). The working tree holds zero real-gc bytes.

No live credentials exist anywhere (tree or history) — every token/password/sk-ant hit is a test
fake or an env-var *name*. `.beads/.env` is properly untracked.

## 2. Decisions only Nico can make (the pass cannot finish without them)

- **D-P1 · history strategy — RESOLVED: flip with history intact (Nico, 2026-07-10).** Nico:
  name/email are already public (gh handle, git commits everywhere); the rest of the hq bytes
  (22 loopback session tokens drained 2026-06-11, one dolt-topology ops narrative,
  `/Users/nico` paths) are inert. He picked the re-capture lane (tree fully clean; history
  keeps the old bytes) over any rewrite. No filter-repo, no fresh start.
- **D-P2 · license — RESOLVED: MIT (Nico, 2026-07-10).** Executed same day: root `LICENSE` +
  `repository:` field in all 7 package pubspecs (working tree, uncommitted, for review).
- **D-P3 · tracked `.beads/` — RESOLVED: keep (2026-07-10).** Checked upstream: the
  beads-managed `.beads/.gitignore` deliberately does NOT ignore `interactions.jsonl` /
  `config.yaml` / `metadata.json` ("Config files … are tracked by git by default") — the
  tracked set is upstream's intent, not an accident. Zero work.
- **D-P4 · archive convention** (gates `tg-8gv.8`): in-tree `docs/archive/` vs delete-and-rely-on-
  history. Coupled to D-P1 — **moot if D-P1 resolves flip-as-is** (history survives, so
  delete-and-rely-on-history works).
- **D-P5 · private-sibling references** (`tg-8gv.12`): docs mention power_station (×75),
  space_station (×62), gascity, lenny, houston — README "internal siblings" note vs scrub.
- **D-P6 · branches — ANSWERED (2026-07-10):** two families — hand-made milestone/docs branches
  (2026-06-12→07-08) and `grid/tg-*` per-bead branches (2026-06-28→07-10), the_grid's own
  provisioning. **Land has no reap step:** 9 stale `.grid/worktrees/` worktrees + local branches
  and ~20 origin `grid/tg-*` heads persist for already-squash-merged beads (recorded on
  **tg-hlz**; interim: GitHub "Automatically delete head branches"). One-time prune rides
  tg-8gv.12.

## 3. SCRATCH dispositions (the graduate-or-delete table)

| Doc | Verdict | Why | Bead |
|---|---|---|---|
| resident-station | **GRADUATE → write ADR-0013** | RATIFIED 2026-07-02; only §6 promoted; D-R/D-C/D-A1 recorded nowhere else | tg-8gv.4 |
| station-config-model | **GRADUATE §1–6** → ADR-0008 D1 amendment or `docs/CONFIG-MODEL.md` | ratified v3 but header stale; `grid_sdk/README.md:36` links it | tg-8gv.5 |
| grid-alignment | **GRADUATE** → ADR-0011 amendment + power_station ADR line | RULED MQTT-bus/claim-flow design promoted nowhere; cited by live engine code | tg-8gv.6 |
| multi-root-federation | **GRADUATE the D-M half**, then delete | D-M1..M7 (tg-7gm) unbuilt + only here; D-F/D-Z already in ADR-0000 | tg-8gv.6 |
| orchestration-determinism | **GRADUATE §5 + PROC rules** → ops doc | GLOSSARY cites both as `ratified`; canonical nowhere | tg-8gv.7 |
| memento-composition (untracked!) | **GRADUATE** → ADR-0008 D1 amendment | forks resolved 2026-07-10; not in git at all | tg-8gv.8 |
| third-party-harnesses (untracked!) | **active surface until ratified**, then ADR-0008 D10 amendments | decided 07-02, awaiting ratification; not in git | tg-8gv.8 |
| allocation-tree | **DELETE** (file 2 genesis follow-ups first) | self-declared GRADUATED; ADR-0009 canonical | tg-8gv.8 |
| dart-runner-and-cli-sdk | **DELETE** (re-point 4 refs incl. 2 grid_cli code comments) | core shapes superseded; ADR-0008:69 marks them never-ratified | tg-8gv.8 |
| agent-scope | **ARCHIVE** (per D-P4) | fully promoted, but ADR-0008 calls it "detail of record" ×6 | tg-8gv.8 |
| asset-management | **ARCHIVE** after verifying capability-cascade detail is in ADR-0011 | ADR-0011 names it source-of-record | tg-8gv.8 |
| vnext-prd | **ARCHIVE — blocked** | §8 observability has NO home until ADR-0012 is written | tg-8gv.8 |
| docs-debt-sweep | fold worklist state into the ops doc; close | its W0–W9 all executed | tg-8gv.8 |
| pub-capability-and-repo-split | keep as design note (rename out of SCRATCH or graduate at the repo split) | unratified design for a future step | tg-8gv.8 |
| public-readiness (this doc) | deletes itself at the flip | — | tg-8gv.12 |

**Ratified-but-unpromoted content at risk if deleted early:** resident-station's entire
residency/control-plane/arbitration design; grid-alignment's bus + claim flow;
multi-root's D-M design; orchestration-determinism's failure ladder; vnext-prd §8.

## 4. Doc-drift digest (→ tg-8gv.9, tg-8gv.10)

Drift is concentrated in the human entry points; GLOSSARY (except tgdog), DEBUGGING,
SUBSTATION-INIT, and the workspace pubspec are current.

- **Root README**: frozen at "M1 in progress"; package table lists `grid_controller`, omits
  beads_dart/grid_engine/grid_sdk/grid_runtime; Riverpod presented as current; ADR list stops at 0004.
- **grid_cli/README**: ~65/88 lines document the deleted `grid run` (+ dead symbols
  `GridConvergenceSource`/`BdActuator`/`GateEvaluator`/`OwnsRigs`, `--rig`, tgdog); `gate`/`rework`
  undocumented.
- **grid_runtime/README**: pre-rename (`GridBeadWriter`/`GridGitService`/`OwnsRigs`), cites deleted
  `grid_reconciler`, stale "TmuxProvider CUT" note.
- **grid_sdk/README**: status block says Track-A skeleton; B/C/D/J0 landed.
- **CLAUDE.md tail**: "Packages (ADR-0002)" list, `exploration_contract` path-dep claim, and the
  A30 environment-fact are all superseded.
- **PDR.md**: needs a dated supersession banner (grid_controller/grid_reconciler/Riverpod/rig).
- **GLOSSARY.md**: presents tgdog as live — contradicts SUBSTATION-INIT §4.
- **No README at all**: beads_dart (most-depended-on!), grid_engine, grid_exploration, grid_devtools.
- **Pubspecs**: no `repository`/`homepage` anywhere; 2 stale descriptions (grid_exploration
  "plugin", grid_engine WorkPhase framing); genesis_tree pin drift `^0.1.3` vs `^0.1.5`.

## 5. Dead + duplicate code digest (→ tg-8gv.11)

The tree is unusually clean: **zero orphan lib files** (151/151 reachable by import BFS), zero
TODO/FIXME/@Deprecated, no unregistered CLI commands, no unread flags. Residue to execute:

- **NOT dead — do not delete**: `StationControl`/`StationAttach`/`station_lock` (grid_cli) are
  built-but-unwired resident-station surface, owned by open epic **tg-3s8** (and ADR-0013, tg-8gv.4).
- Comment fossils naming deleted types ×~8 sites (`WorkPhase`, `runGridTree`,
  `StableInheritedSeed`, `CapabilityContext`, `EffectSeed`).
- One redundant one-line re-export shim: `grid_engine/test/support/engine_fakes.dart`.
- Rulings needed: 4 dev tool scripts (prune or keep); 2 raw `Process.run('bd')` spawns off the
  BdRunner chokepoint (`demo_command.dart:32`, `substation_init.dart:26`).
- Duplication map: byte-identical `test/support/fixtures.dart` ×2 (beads_dart, grid_engine);
  `RecordingBdRunner` ×2 (dependency-direction-forced); grid_devtools hand-pins
  `ext.exploration.*` strings (deliberate per ADR-0002 D3 — add a cross-pinning conformance
  guard). bd-envelope codec and process-spawn helpers verified NOT duplicated.
- `GridHandshake.plugins` field name + `GridControllerPlugin`/`GridControllerRuntime` symbol
  renames ride the existing **tg-cxw** (already widened by the 07-05 sweep).
- Trim the gascity argv-token side-finding prose (CLAUDE.md:14, ADR-0000:213, ADR-0006:166) —
  it publishes a weakness narrative about the private gc.

## 6. Related existing beads (don't duplicate)

tg-cxw (GridController* renames), tg-3vq (doc-status stamps), tg-d4k (SUBSTATION-INIT types.custom),
tg-2ds (retired-partition fixture purge), tg-wiz (test layout mirror), tg-qkc (thin-Command
extraction), tg-3s8 (resident-station epic — owns the "unwired" control surface).

## 7. The graph

`tg-8gv` (epic) → .1 fixtures → .2 history (decision) · .3 license (decision) ·
.4 ADR-0013 · .5 config-model · .6 grid-alignment+multi-root · .7 ops doc ·
.8 SCRATCH endgame (waits on .4–.7) · .9 README reality · .10 package READMEs ·
.11 dead/dup sweep · .12 flip checklist (waits on all). All born deferred; Nico's bless flips open.
