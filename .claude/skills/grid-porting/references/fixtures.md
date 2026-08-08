# Fixtures Reference

Upstream fixtures are the verbatim bytes of `bd` invocations under `BD_JSON_ENVELOPE=1`, using the
executable resolved from a caller-supplied `--ref <main-or-tag>`. They bind the codec parser to real
upstream output. They are **captured, never authored** — hand-editing one
defeats the only guarantee it gives.

## Layout

```
fixtures/upstream/
└── <date>-bd-<version>/          ← e.g. 2026-06-11-bd-1.0.5/
    ├── README.md                 ← file→what→capture-command table + capture-time findings
    ├── tg-list-all-empty.json    ← empty-workspace envelopes (the_grid db `tg`)
    ├── tg-ready-empty.json
    ├── tg-statuses.json          ← built-in status defs
    ├── tg-types.json             ← built-in + custom type defs
    ├── tg-error-stdout.json      ← error shape: enveloped on stdout, stderr empty, exit≠0
    ├── hq-session-sample.json    ← per-domain list samples from city HQ (~/gascity)
    ├── hq-message-sample.json
    ├── hq-molecule-sample.json
    ├── hq-ready-sample.json      ← populated ready envelope
    └── hq-export-sample.jsonl    ← raw `bd export --include-infra` JSONL, first N records
```

The dated directory identifies the capture session. Every new ref capture gets a new directory; all
prior directories remain as historical records.

## Capture environment

- **`BD_JSON_ENVELOPE=1` on every invocation.** This is what makes errors arrive enveloped on stdout
  and every success carry `schema_version`. A fixture captured without it is the wrong shape.
- **On the requested ref and SHA.** Callers supply `--ref <main-or-tag>` and its independently resolved
  40-character SHA. The beads checkout and every command's executable must resolve from that ref at
  that SHA before capture.
- **Two sources.** `tg-*` fixtures come from the_grid's own (empty) workspace, db `tg`. `hq-*` fixtures
  come from city HQ (`~/gascity`), which has populated, real-shaped data.
- **No hand-edits, ever.** Not to redact, not to "fix", not to prettify. If a value looks wrong, the
  capture was wrong — re-capture.

## Exact capture commands

These produced the historical `2026-06-11-bd-1.0.5/` set. They are the command template for a complete
capture into a new dated directory. All commands use the executable resolved from the requested ref
and run with `BD_JSON_ENVELOPE=1` exported.

In **the_grid** workspace (db `tg`, empty):

```bash
export BD_JSON_ENVELOPE=1

bd list --json --all --limit 0          > tg-list-all-empty.json   # empty data:[] envelope
bd ready --json                         > tg-ready-empty.json       # empty ready envelope
bd statuses --json                      > tg-statuses.json          # built-in status defs
bd types --json                         > tg-types.json             # built-in + custom type defs

# Error shape: enveloped on STDOUT, stderr empty, exit 1 (ADR-0001 Decision 4 / ADR-0000 A3).
# Redirect stdout only — the envelope is on stdout; do NOT 2>&1.
bd dep list tg-nonexistent --json       > tg-error-stdout.json      # exit 1; {"data":{"error":…},"schema_version":1}
```

In **city HQ** (`cd ~/gascity` first — capture path is read-only):

```bash
export BD_JSON_ENVELOPE=1

# Per-domain LIST samples — small `--limit`, one type each.
bd list --json --all --type session  --limit 3 > hq-session-sample.json
bd list --json --all --type message  --limit 3 > hq-message-sample.json
bd list --json --all --type molecule --limit 3 > hq-molecule-sample.json

# Populated ready envelope.
bd ready --json --limit 5                       > hq-ready-sample.json

# Raw export JSONL — one record per line; keep the first N for the fixture.
# `--include-infra` pulls agent/rig/role/message infra beads that `bd list` never surfaces
# (ADR-0001 Decision 4). The snapshot composition + domain sampling on the CLI path use export, not list.
bd export --include-infra | head -n 25          > hq-export-sample.jsonl
```

> **Why infra samples come from `export`, not `list`:** `bd list` does not surface infra-typed beads
> (agent/rig/role) regardless of `--all`. The capture-time finding recorded in the `2026-06-11`
> README is that HQ held no agent/rig/role/convoy/gate beads at all — re-confirm this on every capture,
> because it drives which domain projections have live coverage.

## README.md per dir

Each dated dir's `README.md` is part of the fixture set and is written at capture time. It must carry:

- The supplied ref, independently resolved 40-character SHA, executable provenance, and the note that
  `BD_JSON_ENVELOPE=1` was set everywhere.
- The source(s): the_grid db `tg` (empty) and city HQ (`~/gascity`).
- A table: **file → what it is → exact capture command** (the commands above).
- **Capture-time findings** — anything observed at capture that informs the models or an ADR (e.g. the
  HQ infra-bead census, "`bd list` doesn't surface infra types"). These are the breadcrumbs that
  justify ADR-0000 amendments; record them while you have the live store in front of you.
- A pointer back to this skill as the re-capture procedure and the "do not hand-edit" rule.

## When to re-capture

- A **new ref or resolved SHA** changes captured output → full capture into a new dated directory (see
  `references/realignment.md`).
- The **envelope `schema_version` changes** → the codec contract moved; re-capture is mandatory and a
  hard ADR-0000 gate (the parser's `kBdSchemaVersion` assertion will be failing).
- A **new domain projection** needs a fixture it lacks → still a full re-capture into a fresh dir at the
  explicitly selected ref, not a one-off file dropped into an existing directory. Keep each directory
  internally consistent: every file has the same ref, resolved SHA, executable, and capture session.
