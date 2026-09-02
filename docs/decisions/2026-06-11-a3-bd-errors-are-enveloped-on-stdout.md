---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a3-bd-errors-are-enveloped-on-stdout
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A3"
---
## A3 (2026-06-11) — bd errors are enveloped on STDOUT

**Decision:** `BdException` parsing must treat **stdout** as the primary error channel when exit ≠ 0: observed shape is `{"data": {"error": "<message>"}, "schema_version": 1}` on stdout with **empty stderr**, exit 1 (`bd dep list <unknown-id> --json`, bd 1.0.5, envelope mode). Parse stdout first, fall back to stderr, then raw text.
**Why:** ADR-0001's error-decision assumed stderr JSON (per `cmd/bd/output.go` reading); live behavior under `BD_JSON_ENVELOPE=1` differs. Fixture: `fixtures/upstream/2026-06-11-bd-1.0.5/tg-error-stdout.json`.
**Affects (if promoted):** ADR-0001 Decision 4 wording; `BdCliService` error hierarchy.
**Status:** promoted → ADR-0001 Decision 4 (2026-06-11).

