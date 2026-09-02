---
status: accepted
date: 2026-06-28
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a42-land-pr-wired-into-the-reentrant-completion-path-behind
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A42"
---
## A42 (2026-06-28) — land→PR wired into the reentrant completion path behind an explicit `--land` opt-in (tg-c7l)

**Decision (AI; `grid_cli` + `grid_engine`):** the **land policy itself is unchanged** — ADR-0006 D3 (ratified): on a positive terminal, **commit → push `grid/<bead>` → open a PR (`gh pr create`) → record the PR → NEVER auto-merge**. This amendment only **wires** it and records the two AI choices D3 did not name: the opt-in mechanism and the result-record key.
**Re-targeted to the LIVE path (the bead's framing was M3-era):** the bead names `StationGitService.land()` and `DispatchInteractor._finishAndReap` as the un-wired completion path. Since the M4-P1 finish-line cleanup, **that M3 dispatch path is DORMANT** (`grid run` routes through `runGridTree`/`composeRunTree`); the live completion path is the reentrant engine's **`LandCapability`** — the positive-terminal step of the `code` formula — which already implements commit→push→PR over the per-substation `SourceControl` (ADR-0008 D5) but **no-ops whenever `canLand` is false**. `composeRunTree` was hard-wiring `canLand=false` by always leaving `EffectContext.gitOps`/`prOpener` null. So "wire land()" = **flip `canLand` on an explicit opt-in**, not call the dormant M3 method.
**What was built (offline-green; `melos analyze` clean; grid_engine 153 / grid_cli 30, full workspace green):**
- **`grid run --land`** (default **OFF**, `negatable:false`): the explicit opt-in. When set on a `--no-dry-run` run it lifts real `GitOps(SystemGitRunner())` + `GhPrOpener(gh)` into the `EffectContext`, so `GitSourceControl.canLand` is true and the `land` step pushes + opens the PR. Unset ⇒ ops stay null ⇒ land no-ops (the early-arm **commit-only** posture, A37/A38, is the unchanged default — a human still lands).
- **Fail-closed `--land` ⊥ `--dry-run`:** land is inherently a live GitHub write, so `--land` with `--dry-run` is **refused (exit 64)**, matching the existing live-arm gate style (`--root`/`--state-workspace`/`--bead`). A dry run therefore *never* arms land.
- **The PR url is now actually RECORDED** (D3's "record the PR on the lifecycle bead" — previously the `LandCapability` returned `Ok({pr_url})` but `_writeOutcome` dropped the payload). Added a new, **additive, namespaced `grid.result.{nodePath}.{key}`** metadata family on the_grid's OWN session bead (`ResultKeys`/`nodeResultMetadata`), written through the chokepoint **disjoint from `grid.cursor.*`** so the cursor projection never misreads it. **No `NodeCursor`/freezed/codec churn**; write-only (no engine reader yet — it is the audit record). The four derailment invariants hold (one chokepoint, own session bead, off-build, A37-pristine source).
- The agent working-agreement prompt is **unchanged** ("COMMIT, do NOT push, do NOT open a PR") — correct under `--land` too: the AGENT only commits; the separate `land` step pushes/PRs. `LandCapability.commitAll` is a harmless belt-and-suspenders (a clean tree's `git commit` non-zero is dropped by the `Future<void>` seam), so push runs the agent's commits.
**Affects:** `grid_cli` (`run_command.dart` `--land` flag; `run_tree_command.dart` `runGridTree(land:)` + the gate + the conditional `EffectContext` land ops + banner); `grid_engine` (`capability_host._writeOutcome` records the `Ok` payload; `session_bead.dart` `ResultKeys`/`nodeResultMetadata`; `code_capabilities.dart` doc). **Not changed:** ADR-0006 D3 (policy intact), the dormant M3 `DispatchInteractor`/`StationGitService.land()` (left as-is for its eventual retirement scope). **Still the human gate:** the first LIVE `grid run --no-dry-run --land` (no live arm run here — nothing pushed, no PR opened).
**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into ADR-0006 D3 (one-line "the opt-in is `--land`; the PR is recorded as `grid.result.*`") or dispose at will.

