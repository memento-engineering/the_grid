# Upstream fixtures — 2026-09-03T05:42:54Z

**bd ref:** `grid-head-a45199a-dep-cycle-indexed-recursion.1` · **resolved SHA:** `f82590301c2a2167360f2fb376c56407c4ebc630` · **executable:** `/Users/nico/development/engineering.memento/the_grid/.grid/worktrees/the_grid/tg-4gaz/.grid/tg-4gaz-capture.bIbI9f/bd` · **environment:** `BD_JSON_ENVELOPE=1`, `BD_NON_INTERACTIVE=1`.

The `tg-*` files come from an empty synthetic the_grid capture workspace; the `fx-*` files come from a seeded synthetic workspace. Captured output is never hand-edited; repeat the complete grid-porting capture into a new dated directory.

| File | Exact `bd` argv |
|---|---|
| `tg-list-all-empty.json` | `bd list --json --all --limit 0` |
| `tg-statuses.json` | `bd statuses --json` |
| `tg-types.json` | `bd types --json` |
| `tg-error-stdout.json` | `bd dep list tg-nonexistent --json` |
| `fx-session-sample.json` | `bd list --json --all --type session --limit 3` |
| `fx-message-sample.json` | `bd list --json --all --type message --limit 3` |
| `fx-molecule-sample.json` | `bd list --json --all --type molecule --limit 3` |
| `fx-ready-sample.json` | `bd ready --json --limit 5` |
| `fx-show-sample.json` | `bd show fx-message --json` |
| `fx-export-sample.jsonl` | `bd export --include-infra` |

## Findings

- The cycle and ancestry CTEs walk each dependency table with its own recursive member joined directly on `issue_id`.
- `applyGraph` declares both dependency inserts cycle-validated; its whole-graph preflights and final transaction-local `CycleThroughEdges` walk remain the cycle authority.
- The patch is based on `a45199a546f959044426b98716975c70b7c77a16`, the fleet binary's own commit.
- Envelope `schema_version` remains 1, with no migration or JSON model changes.
