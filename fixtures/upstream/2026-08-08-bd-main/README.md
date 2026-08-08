# Upstream fixtures — 2026-08-08T21:37:42.073913Z

**bd ref:** `main` · **resolved SHA:** `869020c2213db2bfd9e1ba0aa54c7e60d52e5f2c` · **executable:** `/tmp/tg-rnd8-capture.Wx3gMk/bd-main` · **environment:** `BD_JSON_ENVELOPE=1`, `BD_NON_INTERACTIVE=1` (forced by `ProcessBdRunner`).

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
| `fx-show-sample.json` | `bd show fx-show --json` |
| `fx-export-sample.jsonl` | `bd export --include-infra` |

## Findings

Drift from the 1.0.5 set is asserted in `packages/beads_dart/test/tool/fixture_drift_test.dart`: `show --json` adds `revision`, and truncated envelope output adds `pagination`; envelope schema version remains 1.
