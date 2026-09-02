---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a28-track-h-conformance-green-against-gc-s-convergence-suite
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A28"
---
## A28 (2026-06-13) — Track H: conformance-green against gc's convergence suite; DoD criterion 1 met

**Decision:** Track H (built, `test/conformance/` + `doc/port/conformance-report.md`) closes M2's DoD criterion 1 ("state machine + recovery conformance-green against the transliterated gc suite", ADR-0003 D7). It audited **all 21 gc `*_test.go` files (165 test functions)** against the *actual* Go source (not the Wave-1 inventory summaries) and found **every must-priority case already covered faithfully** by the per-component suites — reducer (`test/reducer/`, handler+operator+trigger), recovery (`test/recovery/`), gates (`test/gates/`), domain literals (`test/convergence/`) — each asserting gc's exact values with `file:line` citations; **zero must-cases missing or weaker-than-gc at the unit layer, and zero real conformance bugs (no `lib/` change needed)**. H added the non-redundant remainder: **5 end-to-end lifecycle conformance tests through the real `ReconcilerRuntime`** (the layer the unit tests can't provide) — gate-fail→iterate→iter==max→`no_convergence`; wisp-close manual short-circuit→`waiting_manual`→operator approve; →operator iterate (hold consumed+resolved in one runtime); trigger-gated wisp-close→`waiting_trigger`→`triggerPassed`→active (the T6→T10 chain); gate timeout→action `retry` (4 gate spawns = budget exhaustion → fall-through iterate). The coverage report maps every gc test function → Dart test → status (faithful / filled-here / e2e / n-a) with must/should/skip tallies — the DoD-criterion-1 artifact. **n-a classes (documented, not silently skipped):** the **create/retry surface** (`create_test.go`/`retry_test.go` — mint a new root, out of `reduce()` scope per A22 item 4 / A19 item (a); lands with the M3 create surface); the **live-store-I/O error arms** (`*_StoreError*`, `IterateHandler_PourWispFailure` — a transient GetBead/PourWisp failure is unreproducible at the pure reducer/recovery layer, it is the Track-G actuation seam's contract per A25/A27, covered there); and **gate-execution internals** (`condition_test.go` env/path/capture — Track D's own suite, not the state machine).
**Why:** D7 makes gc's tests the executable spec; criterion 1 needs them demonstrably green. The audit confirmed the per-track transliterations (built from the inventories) were already faithful, so H's marginal value was the integrated e2e layer + the auditable report — not re-transliteration. Two adversarial lenses (fidelity/completeness + e2e/regression); round 1's 3 gaps were filled, round 2 clean.
**Affects (if promoted):** confirms ADR-0003 D7 / `docs/M2-BUILD-ORDER.md` DoD criterion 1 (met). Code: `packages/grid_reconciler/test/conformance/` + `doc/port/conformance-report.md`.
**Status:** **promoted → confirms ADR-0003 Decision 7 / DoD criterion 1 (Nico, 2026-06-14)**.

