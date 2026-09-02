# Upstream fixtures — 2026-09-02T17:51:38.488170Z

**bd ref:** `1.3.0-rc.1` · **resolved SHA:** `9c6a69ec12350959ec8c495c74eeb02902d629b6` · **executable:** `/tmp/tg-1liv-capture.lid7lH/bd` · **environment:** `BD_JSON_ENVELOPE=1`, `BD_NON_INTERACTIVE=1` (forced by `ProcessBdRunner`).

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

- Release tag v1.3.0-rc.1 (prerelease, published 2026-08-31); the directory drops the leading v to match the 2026-07-10-bd-1.0.5 precedent.
- Added issue key: close_reason ("Closed") is emitted on a closed bead (fx-session-sample.json, fx-export-sample.jsonl); the 2026-08-08-bd-main set carried closed_at only.
- revision widens from a JSON number (2026-08-08-bd-main) to a JSON string at rc.1; beads_dart decodes no revision field, so this is a fixture-level pin only.
- owner is ABSENT from every rc capture because HOME is pinned to a throwaway root, so no git identity reaches the bytes. This is a capture-environment fact, not upstream drift, and is exempted BY NAME in fixture_drift_test.dart.
- --set-metadata re-types numeric/boolean/null-looking values into JSON scalars: attempt=3 lands as 3, flag=true as true, nothing=null as JSON null. bd HEAD-a45199a stores all four as strings, so a store written by both binaries carries MIXED shapes for one key.
- bd show <missing> --json adds a hint field beside error (observed on the rc binary; the capture set has no show-not-found command, so this delta is recorded here rather than in the bytes).
- bd create --json timestamps carry sub-second RFC3339Nano precision (2026-09-02T17:26:18.432109Z); list/show/ready/export re-serialise at second precision. The capture set has no create command, so this delta is recorded here.
- labels rides the rc create/update envelopes (observed on this hermetic embedded store). The capture set has no create/update command, and labels on proxied create/update envelopes is out of scope for a rehearsal that moves no store (D-BD1) — recorded here, not in the bytes.
- bd delete --force alone no longer cascades: the rc leaves the child behind and returns data.deleted as a STRING, while --cascade --force returns a LIST plus deleted_count. beads_dart discards the delete envelope, so only the argv changes (see CHANGELOG).
- bd dep list <missing> --json error text changed from "not found: issue tg-nonexistent" to "resolving tg-nonexistent: no issue found matching \"tg-nonexistent\""; the envelope keys are unchanged.
- Envelope schema_version remains 1 in all nine JSON captures.
