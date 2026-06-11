# Upstream fixtures — captured 2026-06-11

**bd:** 1.0.5 (f9fe4ef2a: main@f9fe4ef2a6d3) · **envelope:** `BD_JSON_ENVELOPE=1` everywhere · **sources:** the_grid workspace (db `tg`, empty) and city HQ (`~/gascity`).

| File | What | Capture |
|---|---|---|
| `tg-list-all-empty.json`, `tg-ready-empty.json` | empty-workspace envelopes | `bd list --json --all --limit 0` / `bd ready --json` in the_grid |
| `tg-statuses.json`, `tg-types.json` | status + type defs incl. the 13 `types.custom` | `bd statuses --json` / `bd types --json` |
| `tg-error-stdout.json` | error shape: enveloped on **stdout**, stderr empty, exit 1 (ADR-0000 A3) | `bd dep list tg-nonexistent --json` |
| `hq-session-sample.json`, `hq-message-sample.json`, `hq-molecule-sample.json` | per-domain list samples | `bd list --json --all --type <t> --limit 3` in HQ |
| `hq-ready-sample.json` | populated ready envelope | `bd ready --json --limit 5` in HQ |
| `hq-export-sample.jsonl` | raw export JSONL, first 25 records | `bd export --include-infra \| head -n 25` in HQ |

Findings recorded at capture time: HQ store contains **no** agent/rig/role/convoy/gate beads (34,588 task / 692 session / 390 chore / 1 molecule / 1 step / 1 bug) → ADR-0000 A2; `bd list` does not surface infra types → ADR-0000 A5.

Re-capture procedure: porting skill (Track I). Do not hand-edit.
