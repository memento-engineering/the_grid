# M6 unpark — federation reconciliation scoping (2026-07-01)

**Status:** SCOPING (read-only assessment; doc-before-code). Written on `main` after ADR-0009
(the Allocation Tree) landed (`080cd9c`). M6 federation was parked on `m6-federation` **specifically
to build the Allocation Tree first** — because the burn-follower was a broken daemon
`ServiceCapability`, and ADR-0009 gives it a home (a daemon/lease `Allocation`). This scopes the
unpark. **No new decision** — it executes ADR-0011 (accepted) + ADR-0009's deferred **Track E (the
lease family)**.

## The divergence (measured)

- `m6-federation` and `main` share ancestor `c76089d`, then split: **m6 = 10 commits** (ADR-0011 +
  `grid_federation` A–G + `butane_grid_assets` burn + the compute asset + the compute-reaper fix);
  **main = 14 commits** (the whole ADR-0009 stack + the StationServices cleanup + the naming pass).

## Reconciliation assessment — the git merge is CLEAN; the work is SEMANTIC

- **`git merge-tree main m6-federation` reports ZERO conflicts.** The only file both branches touched
  is `docs/adr/ADR-0008` — and the two forward-pointer stamps (main's Allocation stamp, m6's
  Asset-umbrella stamp) are independent additions that **auto-merge** (both kept). `grid_federation`
  + `butane_grid_assets` are NEW packages main never touched; m6's `grid_assets` changes are in
  `compute/` while main's are in `code/` — no overlap. **So there is no merge-conflict hell.**
- **`grid_federation` is standalone** — it does NOT import the changed engine (no
  `grid_engine`/`EffectContext`/`Allocation` coupling). Tracks A–E (lease lifecycle / membership /
  presence / capability model / git-over-LAN) replay clean.
- **The SDK is additive**, so the burn/compute `ServiceCapability` impls still COMPILE against the
  new engine (`createAllocation` has defaults; `Capability`/`Formula`/`ServiceCapability`/`StepKind`
  unchanged). The `EffectResolver` references in butane/compute are **doc comments only** (cosmetic —
  freshen to `SessionResolver`).
- **BUT two things are still broken after a clean merge:**
  1. **The burn-follower is behaviorally broken** (the bug that parked M6): `BurnFollowerCapability
     extends ServiceCapability`, matches a peer, **leases its slot, and holds it via an
     `Expando<_FollowerHold>` keyed by ctx** (`burn_capabilities.dart:170`), as a `StepKind.daemon`.
     A daemon `ServiceCapability` reaches `complete` → is reaped before the host drives it. This is
     the *exact* smell ADR-0009 D1 named ("the `Expando<_FollowerHold>` becomes plain Allocation
     instance fields"). It must be **rebuilt as a daemon/lease `Allocation`**, not merged as-is.
  2. **`composeRunTree` is hardcoded to the `code` asset** (`FormulaResolver(_codeFormulaFor)` +
     `buildCodeRegistry()`), so it can't wire the **burn** asset. The burn is the *second* asset —
     exactly the trigger for the deferred `composeRunTree` domain/asset-parameterization (the Q3
     finding + ADR-0008 D1).

## The unpark build order (offline; per-commit; green-on-a-branch, never red on main)

- **U1 — reconcile on a branch.** `git checkout -b m6-unpark main; git merge m6-federation` (clean).
  Freshen the stale `EffectResolver`→`SessionResolver` doc comments in butane/compute. Establish what
  compiles vs. what the burn wiring needs. (Do NOT land on main until U5 is green — main stays green.)
- **U2 — the `LeaseAllocation` family (ADR-0009 Track E, deferred).** Implement `LeaseAllocation`:
  adopt-or-reacquire (freshness = ask the owner "grant X still valid ∧ mine?"), `detach` = keep the
  grant, `dispose` = release. Over `grid_federation`'s lease client. Offline (fake bus/owner).
- **U3 — rebuild the burn-follower + compute-lease as lease Allocations.** `BurnFollowerCapability`
  mints a daemon-held `LeaseAllocation` (the `Expando<_FollowerHold>` → Allocation instance fields);
  the daemon-reap bug **dissolves** (held for the mounted lifetime, never written to `complete`).
  Reconcile `kBurnFormula`'s daemon step with the model. Same treatment for `grid_assets`
  `LeaseCapability` if it holds a daemon lease.
- **U4 — `composeRunTree` asset-parameterization (ADR-0008 D1 — now has its 2nd consumer).** Lift
  `resolver` + `registry` + `services` to inputs (default = the `code` asset), so the burn asset
  composes without editing the composer. This is the "more domain-driven" change deferred in the
  naming/cleanup thread — the burn is the concrete second asset that earns it.
- **U5 — offline green + adversarial review.** The burn end-to-end offline (fan-out → await-all
  barrier → daemon lease held → close, AND the failure path: escalate + release the leaked lease);
  the federation invariants at depth; read-only `Explore` refute pass; then **land `m6-unpark` on
  main**.
- **HUMAN GATE — the live cross-machine burn (Studio↔`linux-dashboard`).** Real lease → dispatch →
  the follower daemon adopt/detach with the **co-wired `liveness` + `adoptProof`** (from a real
  `ProcessGroupController`) — Nico present. Never workflow-built.

## What holds / what does not change

- **ADR-0011 (Federation + Asset Management) still holds** — the burn-follower-as-daemon-`Allocation`
  was the *anticipated* reconciliation (ADR-0009 Consequences names it explicitly). No ADR-0011
  change; the **burn IMPL** changes (U3) + `composeRunTree` generalizes (U4).
- **ADR-0009 Track E (lease family) is the U2/U3 core** — this is the deferral coming due, now with a
  real consumer to validate against (not speculative substrate).
- Two threads previously deferred converge here as the actual work: **ADR-0009 Track E
  (`LeaseAllocation`)** + **ADR-0008 D1 (`composeRunTree` asset-parameterization)**.

## Safety rails (carried)

Offline unpark (fakes: fake bus/owner/liveness, temp repos; no live `claude`/`git`/`bd`/network);
coexistence (`tg` read-only, sessions → `tgdog`, never `.beads/hooks/`; no broad process-kill —
scope to own pgid); the codec boundary untouched; the live cross-machine burn is the human gate.
