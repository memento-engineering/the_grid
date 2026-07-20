# ADR-0009 — The Allocation Tree (build order)

**Status:** READY TO BUILD (offline) — **ADR-0009 Accepted 2026-07-01.** Source of decisions:
**`docs/adr/ADR-0009-the-allocation-tree.md`** + the design surface
**`docs/SCRATCH-allocation-tree.md`** (retired to git history — tg-8gv.8). This refactors the effect layer of the reentrant engine
(ADR-0007/0008) into the_grid's **third tree** — nodes = `Allocation`s — dissolving the
`Expando` / `_capCtx ??=` / `CancelToken` smears and adding **adopt / detach / reattach**.

## Safety rails (carried — non-negotiable)

- **OFFLINE-first.** Every track builds with fakes: a fake `ProcessGroupController`, a fake
  spawner, an injected clock, temp repos. **No live `claude`, no real process spawn in tests.**
  **The first LIVE arm — real adopt/detach across a real controller restart — is the HUMAN GATE**
  (Nico present).
- **Coexistence (ADR-0006 / A37):** `tg` read-only, sessions → `tgdog`; **no broad process-kill**
  (scope kills to the_grid's own pgid); the codec boundary + gc rigs untouched; never
  `.beads/hooks/`.
- **Invariants hold AT DEPTH** (they are the whole point of this refactor, not a footnote): the
  effect layer (`Allocation`) is **never handed a writer/notifier** — it reports, the **Host**
  persists off-build through the one chokepoint (inv 2); no pipeline subscription (inv 1);
  convergence never mounts; A37 pristine source.

## Tracks (dependency-ordered)

| Track | Scope | ADR refs | Depends on |
|---|---|---|---|
| **A — the `Allocation` SDK** (pure, `grid_engine`) | The `Allocation` abstraction + `JobAllocation` convenience + the state machine (`starting → live → [ready] → dying → gone`, `adopting`) + the **report sink** + the **address** type. `Capability.createAllocation(ctx)` factory (sync mint). **Zero I/O.** | D1/D4/D6 | — |
| **B — `CapabilityHost` thin-driver refactor** (`grid_engine`) | Rewrite `CapabilityHostState` to the D5 contract: compute address; **kick** `startOrAdopt` on mount (guarded once); on `didChangeDependencies`/`didUpdateWidget` → `canUpdate` → `update` **or** re-key/replace; on unmount → **`dispose` (kill)** *or* **`detach` (leave)** per type/scenario; give the Allocation a **report sink** + cancel token; **persist reports off-build** (the existing chokepoint). **DELETE** the `Expando`, `_capCtx ??=` freeze, `CancelToken` juggling → `Allocation` instance fields. | D3/D5 | A |
| **C — the process family (`ProcessAllocation`)** (`grid_engine`/`grid_runtime`; migrate `grid_assets` effects) | Over the existing `SubprocessProvider` + `terminateGroup`/pgid reaper + the pgid/pid/token fence. **Daemon:** adopt-or-respawn (freshness = pgid alive ∧ token echoed over its endpoint) + **`detach`** (leave running + persist handle). **One-shot:** respawn-or-skip (reuse today's behavior). Migrate `agent`/`verify` (`grid_assets`) onto `ProcessAllocation`. | D4/D6 | A, B |
| **D — adopt + detach in `RestartReconciler`** (`grid_engine`) | Generalize respawn-or-skip → **respawn-or-adopt** + **reattach-a-detached-survivor** on one path; the freshness barrier (**no-adopt-on-faith**); the **orphan sweep** catches un-re-adopted detached effects (generalize the `listBeadWorktrees` sweep). | D2/D4 | A, C |
| **E — the lease family (`LeaseAllocation`)** | **DEFERRED to the M6 unpark** — depends on `grid_federation` (parked on `m6-federation`). When unparked: the burn-follower becomes a daemon-holding `LeaseAllocation` (adopt-or-reacquire; freshness = owner "grant X still valid + mine?"). **This is where the M4-P1 daemon-reap bug dissolves.** | D4 | A, B + grid_federation |
| **F — invariants + acceptance** (mutation-tested, AT DEPTH) | The four derailment invariants still hold (no writer in the effect layer; off-build persist; no pipeline sub; A37); **no-adopt-on-faith** (an adopt path with no freshness assertion FAILS); the **sandbox-dissolved reads** (depend-on-context → `update` fires — non-vacuous); `JobAllocation` respawn-or-skip; daemon **adopt / detach / reattach**. Each with a sanity control. | all | A–D |
| **G — delete dead paths + structural fences** | Once B/C land: remove the `Expando`/`_capCtx`/`CancelToken`-juggling remnants; keep/add structural fences (**effect layer has no writer**; **`dispose` is not overloaded** — `dispose` ≠ `detach`). | D3/D5 | B, C |

## Definition of done

1. **`Allocation` SDK** (A): abstraction + `JobAllocation` + state machine + report sink; pure, tested.
2. **Thin-driver Host** (B/G): `CapabilityHost` on the D5 contract; the `Expando` / `_capCtx ??=` / `CancelToken` juggling **deleted**; invariants hold at depth.
3. **Process family** (C): daemon adopt-or-respawn + detach; one-shot respawn-or-skip; existing effects migrated.
4. **Reconciler** (D): respawn-or-adopt + reattach-detached + orphan sweep; freshness barrier.
5. **Invariants** (F): mutation-tested, non-vacuous, at depth.
6. **`melos analyze` clean + the full offline suite green** across all packages.
7. **LIVE arm** (real adopt/detach across a controller restart) — **human gate, Nico present.**

## How to build (the ultracode workflow plan)

- **Central authorship of A + B** — load-bearing: the SDK core + the **invariant-critical Host**.
  These are the derailment surface; author them directly, review read-only.
- Then a **workflow fans out C / D / F** (implement → read-only-`Explore` adversarial verify →
  fold — the M4-P1 / Circuit pattern), **G** as the cleanup wave. Per-track commits; reviewers are
  **read-only `Explore`**; prefer **flat schemas / plain-text** returns (the Circuit's
  nested-schema lesson). Honor the order **A → B → C → D → F**, **G** after B/C.
- **Track H (the live arm) is never workflow-built** — it's the human gate.

## Deferred (explicit — not this pass)

- **E (lease family / the burn)** — the M6 unpark (needs `grid_federation`); the burn-follower is
  its first client.
- **The genesis FR** (non-registering `getInheritedSeedOfExactType`) — optional; the primary read
  is the existing registering `dependOn` (react via update/replace) + `StableInheritedSeed` for
  constant config.
- **Documenting the third-tree pattern in `genesis_tree`** (four pieces + typesetting/perception).
- **The genesis home for restoration** (post-prototype; ADR-0008 D6).
- **The live arm** (real adopt/detach across a controller restart).
