---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a24-ready-work-sql-port-conditional-blocks-has-no-failure-ke
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A24"
---
## A24 (2026-06-13) — Ready-work SQL port: `conditional-blocks` has NO failure-keyword semantics in `bd ready` (corrects ADR-0003 D5)

**Decision:** Track F (built, `grid_controller/lib/src/ready/`, +26 offline tests, hermetic differential green) ports `bd ready`'s predicate to SQL over the pool. **Correction to ADR-0003 D5 + the port spec:** D5 (and `ready-work-predicate.md`) describe "conditional-blocks' **failure-keyword semantics**" in the blocking predicate — but `bd ready` applies **none**. `beads/internal/storage/issueops/blocked.go:29` treats `conditional-blocks` in the *same disjunction* as `blocks`/`waits-for` (`type IN ('blocks','waits-for','conditional-blocks')`) with **no `close_reason` branch**, and `IsFailureClose` (types.go:926) has **zero non-test call sites** — the failure-keyword logic exists in beads but is not consulted by ready-work. The SQL port therefore matches D's three edge types identically; `kFailureCloseKeywords`/`isFailureClose` are ported as documented-inert data, not predicate inputs. Other pins: `ReadyWorkFilter` models only the **oracle-honored** knobs (status default `open`; ephemeral; sort policy) and omits `LabelsAny`/`MolType`/`WispType` (the plain-path-vs-`--json`-path divergence, traps #9/#10, is resolved by porting the `--json` oracle path); molecules excluded (A14); a **`runReadTransaction`** seam on `DoltQueryService` issues `START TRANSACTION READ ONLY` and hands the body a SELECT-only runner (the whole predicate — deferred-parent scan, descendant CTE, wisp projection — runs in one read txn); literals inlined via an escaper mirroring `mysql_client`. **Differential harness (D5 gate) is three-half:** (1) a hermetic `bd init` oracle witness per scenario clause (runs wherever `bd` is on PATH); (2) a hermetic `dolt sql-server` + server-mode `bd` harness proving SQL-port == `bd ready` on seeded divergent fixtures (skips cleanly without `dolt`/`bd`); (3) a live read-only differential over the real `tg` graph, self-skipping without `GC_DOLT_PASSWORD` and guarding on the `@@tg_working` probe — **never** seeding the gc-managed `tg` server (partition rule). Nuance: `bd update --defer <future>` flips `status` to `deferred`, so a future-deferred bead is excluded by the `status=open` clause regardless of `--include-deferred`; only a *past* defer keeps `status=open`.
**Why:** D5 mandates a differentially-tested SQL port; building it against `ready_work.go`/`blocked.go` revealed the conditional-blocks prose was aspirational (the keyword logic is dormant in bd 1.0.5). Verified directly in beads source before relying on it. The hermetic-server half makes DoD criterion 2 provable offline without the live city.
**Affects (if promoted):** ADR-0003 D5 + `docs/M2-BUILD-ORDER.md` Track F + `ready-work-predicate.md` §10 (drop the conditional-blocks failure-keyword claim; record the three-half harness). Code: `grid_controller` `src/ready/` + `DoltQueryService.runReadTransaction`.
**Status:** **promoted → ADR-0003 Decision 5 (Nico, 2026-06-14)** — conditional-blocks failure-keyword claim dropped.

