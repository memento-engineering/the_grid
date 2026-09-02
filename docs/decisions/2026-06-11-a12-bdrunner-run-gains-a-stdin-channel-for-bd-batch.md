---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a12-bdrunner-run-gains-a-stdin-channel-for-bd-batch
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A12"
---
## A12 (2026-06-11) — `BdRunner.run` gains a `stdin` channel for `bd batch`

**Decision:** Extend the `BdRunner` seam with an optional `{String? stdin}` parameter; `ProcessBdRunner` writes it to the child's stdin and closes the stream (EOF). `BdCliService.batch(lines)` pipes its newline-joined script this way.
**Why:** upstream `bd batch` reads its line-oriented script from **stdin** (`cmd/bd/batch.go`), but the first-cut runner interface was argv-only, so `batch()` was a no-op that would commit an empty transaction (caught by the Wave-1 adversarial verifier). A stdin channel keeps batching a single atomic spawn / one `DOLT_COMMIT` (ADR-0001 Decision 4) with no temp-file lifecycle. Minor internal-interface refinement, recorded for completeness.
**Affects (if promoted):** none in the ratified docs (implementation detail of ADR-0001 D4's batch requirement). Code: `services/bd_runner.dart`, `services/bd_cli_service.dart`.
**Status:** pending.

