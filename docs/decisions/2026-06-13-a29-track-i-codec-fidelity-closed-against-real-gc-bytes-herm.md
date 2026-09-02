---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a29-track-i-codec-fidelity-closed-against-real-gc-bytes-herm
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A29"
---
## A29 (2026-06-13) — Track I codec-fidelity closed against REAL gc bytes (hermetic capture); live-shadow half stays M3

**Decision:** Track I conflates two goals with different blockers — **(a) codec fidelity** (does the 31-key `convergence.*` codec decode real gc bytes?) and **(b) live shadow acceptance** (diff against live gc traffic?). Only (b) needs live traffic. **(a) is now CLOSED with zero live-city risk.** Captured **real gc-produced convergence metadata across 6 states** (active / waiting_manual / terminated-approved / condition-gate-pass with the full 28-key `gate_outcome` set / no_convergence-at-max / waiting_trigger) by driving gc's **actual writer** (`internal/convergence` `CreateHandler`/`HandleWispClosed`/gate eval) through `cmd/gc`'s own test seam (`setupConvergenceRuntime` → `handleConvergenceRequest` + `convergenceTick`) against a `MemStore` + fake provider — **no supervisor, no agents, no live city** (`gc start` is machine-wide and would entangle the live factory, so it was deliberately avoided; gascity's dolt CGO dep compiles only with `CGO_*FLAGS → $(brew --prefix icu4c@78)`). Then bd-export round-tripped. Pinned (captured-never-authored) at `fixtures/upstream/2026-06-11-bd-1.0.5/convergence/` (6 captures + `bd-export-roundtrip.jsonl` + `MANIFEST.md`; gascity source `4e1e6f66d`/gc 1.1.1, bd 1.0.5). The throwaway capture harness was removed from gascity after use. **Result: the codec is TOTAL + CLEAN against reality** — all 6 decode with zero `failures`, byte-for-byte `encode(decode(m))==m` for every key, **no lib change needed** (the fixtures *confirm* Track A: `gate_truncated:""`→false [[A17]]; the wisp is a persistent `molecule` carrying `idempotency_key=converge:gc-1:iter:1` [[A15]]; bd preserves every value as a string end-to-end so the codec's string path — not `coerceWireValue` — is the convergence happy path). A reusable **multi-tick shadow replay harness** (test-support; advances to the pre-transition tick before emitting each derived `BeadClosed`, since `ShadowRuntime` reduces against `_source.current`) drives `ShadowRuntime` over the fixtures with AGREE + DIVERGE goldens — validating the divergence **mechanism** offline. **It surfaced a genuine, correct divergence:** the captured manual loop closes its wisp → the_grid predicts `waiting_manual`, but gc operator-approved at the next tick → `DivergenceReport(diverged: true, predicted: waiting_manual, observed: operatorApprove)` — exactly the ADR-0003 D6 coexistence signal shadow exists to catch, now pinned as a golden. Detection-timing fact pinned: `observedGcCommand` keys off a `BeadUpdated` of the convergence **root**; gc's terminal metadata write and the root-close are separate watcher diffs, so a faithful replay models them as distinct ticks (else the `BeadClosed` masks detection).
**Why:** Track I was "blocked on an actual convergence running," but that only gates (b). A focused research fan-out found the hermetic capture path (gc's own test seam) and the decoupling; executing it validates the codec against reality today. **(b) live shadow** remains genuinely pending — it needs gc running ≥1 convergence on a the_grid-owned disjoint rig (gc writes, the_grid reads read-only), which is **net-new M3 dogfood work** (author a convergence formula+gate, bind the `the_grid` rig, creds) and touches live shared state → Nico's go-ahead + ADR-0006 (M4b topology). M2 DoD criterion 4 already classes the live half as gated/non-blocking.
**Affects (if promoted):** `docs/M2-BUILD-ORDER.md` Track I + DoD criterion 4 (codec-fidelity half MET vs reality; live half = M3 dogfood). New pinned fixture (grid-porting version-pin record). Code: `packages/grid_reconciler/test/{fixtures,convergence,runtime}/` (codec-fidelity test + shadow replay harness/goldens; +26 tests, no lib change). **[Edited 2026-07-20 — tg-8gv.11(g), public-flip redaction directed by Nico: an out-of-band side-finding describing a specific third-party (gascity) process-argv credential-exposure weakness was removed here ahead of the public flip — it named a live external system's security posture, not a the_grid decision, and is not appropriate for a public repo.]**
**Status:** **promoted → docs/M2-BUILD-ORDER Track I + DoD criterion 4 (Nico, 2026-06-14)** — codec-fidelity half met vs reality; live-shadow half = M3.

