---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a18-the-convergence-metadata-schema-is-31-keys-not-the-16-th
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A18"
---
## A18 (2026-06-13) — the convergence metadata schema is 31 keys, not the 16 the build order lists

**Decision:** `metadata.go:12-44` defines **31** `convergence.*` keys; `docs/M2-BUILD-ORDER.md` Track A (and by reference ADR-0003) lists 16. The 15 omitted, all typed in the Track-A codec and several invariant-load-bearing: `gate_retry_count`, `terminal_reason`, `terminal_actor`, `waiting_reason`, `retry_source`, `city_path`, `rig`, `evaluate_prompt`, `gate_stdout`, `gate_stderr`, `gate_duration_ms`, `gate_truncated`, `pending_next_wisp`, `trigger`, `trigger_condition`. Notably **`pending_next_wisp`** — the speculative-pour recovery marker (handler.go:268, `validPendingNextWisp` 935-945) — is among the omitted even though **ADR-0003 invariant 5 references it by name**; `gate_outcome_wisp`'s replay companions (`gate_retry_count`/`gate_stdout`/`gate_stderr`/`gate_duration_ms`/`gate_truncated`) and the recovery-dispatch inputs (`terminal_reason`/`terminal_actor`/`waiting_reason`) are likewise required. Also pinned (none named by any track text, all consumed by the handler): the `var.` metadata prefix (`VarPrefix`, metadata.go:47) carrying pour vars + `evaluate_prompt`; `NormalizeVerdict` (metadata.go:121-138, with its five past-tense mappings + unknown→block); and the eight canonical `CloseReasons` (handler.go:47-55).
**Why:** the build order's "16 keys" was an undercount taken from a partial reading; building the codec against the full `metadata.go` surfaced the true set. Getting this wrong would drop replay/recovery state on the floor.
**Affects (if promoted):** `docs/M2-BUILD-ORDER.md` Track A (correct "16" → "31"); ADR-0003 (note the full key set; invariant 5's `pending_next_wisp` is real and now typed). Code: already complete in `convergence_metadata.dart`.
**Status:** **promoted → docs/M2-BUILD-ORDER Track A + ADR-0003 Decision 2 (Nico, 2026-06-14)** — 31-key schema recorded.

