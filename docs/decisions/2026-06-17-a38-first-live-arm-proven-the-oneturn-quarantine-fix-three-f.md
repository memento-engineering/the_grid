---
status: accepted
date: 2026-06-17
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a38-first-live-arm-proven-the-oneturn-quarantine-fix-three-f
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A38"
---
## A38 (2026-06-17) — first live arm PROVEN; the `oneTurn`-quarantine fix + three failure-path hardenings an adversarial review caught

**Decision (AI, pending Nico):** the genesis arm ran live and **the_grid autonomously built both genesis features** — agents it spawned committed `feat(tree): MultiChildSeed/MultiChildBranch …` (genesis-7r9) and `feat(tree)!: first-class Key value-type …` (genesis-q8h) into throwaway worktrees off `genesis-grid`, session lifecycle tracked in the `tgdog` state store, **genesis never written to**, local-first (no push/PR), and the A37 robustness fix held (no controller crash). Four real bugs surfaced and are fixed (offline-green, 147+ tests, `melos analyze` clean):
- **`oneTurn` completion misread as a crash (fixed, A38-1).** The subprocess provider spawns **detached** (for whole-tree kill), so `Process.exitCode` is unreadable and every exit arrives as `Died('process vanished')` — and the actuator crash-loops/**quarantines** a *successful* one-shot agent. Fix: `SubprocessProvider._emitExit` now emits `Exited(0)` for a `oneTurn` session that vanishes (completion-by-intent; work success is judged by the commit), `Died` only for `longLived`. `Lifecycle` is the right axis — orthogonal to the provider (subprocess/tmux) and the backend (anthropic/swift-infer/…); the subprocess detached-mode is merely *why the symptom shows*.
- **Live side-car without `--state-workspace` would write `type=session` into the read workspace (fixed, A38-2).** The A37 "genesis pristine" invariant was enforced only by genesis's own schema rejecting the type. `runGrid` now **fail-closes a live run that omits `--state-workspace`** (exit 64) — the_grid enforces its own partition.
- **Orphan worktree on post-provision failure (fixed, A38-3).** A `spawnSession` reject (the arm2 `invalid issue type` case) left the just-minted worktree/branch behind → the bead could *never* re-dispatch. `_dispatch` now wraps the post-provision steps in a conservative unwind: close any orphan session bead, reap the (clean) worktree, drop the records, then rethrow (caught + reported, never re-crashed).
- **Stuck dispatch record on `_provider.start` failure (fixed, A38-3).** Same unwind drops `_dispatched`/`_bySession` so the idempotency guard no longer wedges every retry.
**Surfaced by:** a 3-dimension adversarial-review workflow (ownership/coexistence, oneTurn lifecycle, dispatch correctness), each finding independently verified — earned its cost. **Affects:** `subprocess_provider.dart`, `run_command.dart` (`runGrid` guard), `dispatch_interactor.dart` (`_dispatch` unwind). **Known follow-ups (not blocking):** the leonard-debugs-the_grid half is wired (`ext.exploration.*` host + a live VM URI each run) but **unexercised** this session; running an agent on a non-Anthropic backend (swift-infer) needs a coding-harness/provider shim (claude CLI is Anthropic-wire-only) — **parked by Nico**; `listBeadWorktrees` (restart-rebind sweep) still has no caller (orphan recovery across a controller restart).
**Status:** **AI decisions, pending Nico** — the live-arm proof + the four fixes are recorded here per the ADR-0000 rule; promote/dispose at will.

