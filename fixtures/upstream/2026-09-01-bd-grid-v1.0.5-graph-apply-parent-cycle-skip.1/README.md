# Upstream fixtures — 2026-09-01T18:24:30.756650Z

**bd ref:** `grid-v1.0.5-graph-apply-parent-cycle-skip.1` · **resolved SHA:** `94cb40e85426bcb8afcba4fabf59fc952d47febe` · **executable:** `/tmp/tg-igv2-capture.b4poaY/bd` · **environment:** `BD_JSON_ENVELOPE=1`, `BD_NON_INTERACTIVE=1` (forced by `ProcessBdRunner`).

The `tg-*` files come from the empty the_grid capture workspace. The `fx-*` files come from the seeded synthetic workspace. Captured output is never hand-edited; repeat the complete grid-porting capture into a new dated directory.

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

- ParentKey graph-apply dependencies skip redundant SQL cycle checks; ParentID dependencies remain checked.
- Envelope schema_version remains 1, no migration is added, and no JSON model changes.
