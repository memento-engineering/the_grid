# Upstream fixtures — assembled 2026-07-10

**bd:** 1.0.5 (f9fe4ef2a: main@f9fe4ef2a6d3) · **envelope:** `BD_JSON_ENVELOPE=1` everywhere.

This set replaces `2026-06-11-bd-1.0.5/` at the same pin (public-readiness pass, tg-8gv.1):
the predecessor's `hq-*` files were raw exports from a live production store and carried
operator data. The `fx-*` files here are captured from a **seeded scratch store** (prefix
`fx`, identity `operator`, `types.custom` matching this repo's roster) — real bd 1.0.5
output bytes, synthetic content. The `tg-*` files are carried forward from the 2026-06-11
capture **unchanged** (same pin, originally captured in this workspace's then-empty store).

| File | What | Capture |
|---|---|---|
| `tg-list-all-empty.json` | empty-workspace list envelope | `bd list --json --all --limit 0` *(2026-06-11)* |
| `tg-statuses.json`, `tg-types.json` | status + type defs incl. the 13 `types.custom` | `bd statuses --json` / `bd types --json` *(2026-06-11)* |
| `tg-error-stdout.json` | error shape: enveloped on **stdout**, stderr empty, exit 1 (ADR-0000 A3) | `bd dep list tg-nonexistent --json` *(2026-06-11)* |
| `fx-session-sample.json`, `fx-message-sample.json`, `fx-molecule-sample.json` | per-domain list samples (closed session w/ metadata; ephemeral message w/ labels+assignee; molecule) | `bd list --json --all --type <t> --limit 3` |
| `fx-ready-sample.json` | populated ready envelope (5 records) | `bd ready --json --limit 5` |
| `fx-export-sample.jsonl` | raw export JSONL, first 25 records; record `fx-eu5` carries 3 comments | `bd export --include-infra \| head -n 25` |

Seeding recipe (reproducible): one P0 bug + 3 comments (`fx-eu5`), one closed session with
`metadata.agent_name` (`fx-hbc`), one ephemeral message with a `thread:` label, one molecule,
an epic with two children (one dep edge), a deferred task, closed/chore/decision variety,
and 8+ open ready tasks.

Re-capture procedure: porting skill (Track I). Do not hand-edit.
