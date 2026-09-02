---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a20-the-graphsnapshot-is-the-complete-graph-issues-wisps-ide
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A20"
---
## A20 (2026-06-13) — the GraphSnapshot is the complete graph (`issues` ∪ `wisps`), identical on both capture paths; this also closes a latent M1 divergence

**Decision:** both M1 capture paths now compose the **complete** graph — all beads regardless of ephemerality, infra type, template, or gate-typing; filtering is the consumer's job (projections/selectors). SQL path: the snapshot SELECTs UNION the `wisps`/`wisp_dependencies`/`wisp_labels` tables into the `issues`/`dependencies`/`labels` reads (issues∪wisps merged by column **name** in Dart, not a positional SQL `UNION`, because `is_blocked` reached the two tables via different migration tracks so ordinals can diverge and a `SELECT *` union would scramble values). CLI path: `bd export --all` replaces `--include-infra` (`--all` lifts the default infra/template/ephemeral exclusions — export.go). **Latent M1 bug closed:** beads migration **0035** moved all infra beads (agent/rig/role/message) into the `wisps` table and DELETEd them from `issues`, so the *old* SQL path (`SELECT … FROM issues` only) silently missed infra on any post-0035 database while the CLI path (`--include-infra`) saw them — the two M1 read paths could disagree on a real workspace. They now read the identical `issues ∪ wisps` set. Residual nuance (minor, documented): the CLI inline-dependency hydration filters edges by source `issue_id` while the SQL path reads the edge tables unconditionally, so they diverge only on an orphan edge whose source bead is absent (mid-burn / cross-query skew) — "identical" holds for any well-formed graph.
**Why:** [[A15]]'s poured wisps (and, more importantly, post-0035 infra) were invisible to the snapshot on both paths — a critical gap that would have gutted `closedWispCount`/`findByIdempotencyKey`/wisp-closure detection. Found by an adversarial verifier, independently confirmed against beads storage source, fixed with a round-trip integration fixture (`wisp_snapshot_test`) and an SQL-vs-CLI equivalence canary. (With the [[A15]] correction to pour *persistent*, the_grid's own iterations land in `issues`; the wisp union remains required for infra + any genuinely ephemeral beads + path equivalence.)
**Affects (if promoted):** ADR-0001 (snapshot inclusion semantics: complete graph, consumer-side filtering). Code (shipped M1): `grid_controller` `dolt_query_service.dart`, `bd_cli_service.dart`, `snapshot_reader(s).dart`, `issue_type.dart` + tests + `test/integration/wisp_snapshot_test.dart`.
**Status:** **promoted → ADR-0001 Decision 4 (Nico, 2026-06-14)** — complete-graph snapshot (issues∪wisps), `export --all`, consumer-side filtering; closed the post-0035 infra divergence.

