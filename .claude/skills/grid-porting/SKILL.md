---
name: grid-porting
description: >
  Keeps the_grid aligned to its pinned bd / beads / gascity upstream. Use when bumping the bd version
  pin, re-capturing upstream JSON/JSONL fixtures, detecting schema or protocol drift (envelope
  schema_version, the Dolt migration version, pack-protocol / city.toml shapes), or re-aligning the
  controller after upstream moves. Owns the version-pin record, the fixture re-capture procedure, the
  drift-diff commands, and the re-alignment checklist (incl. recording decisions as ADR-0000 amendments).
  Not for: writing controller Dart code, or any mutation of live beads (read-only against upstream).
---

# Grid Porting

the_grid is a downstream consumer of three upstream surfaces — the **bd CLI** (JSON envelope), the
**beads Dolt schema** (migration version), and later **gc's pack-protocol / city.toml**. None of these
are owned here; all of them move. This skill is the procedure for staying pinned to a known-good
upstream, detecting when upstream has drifted past the pin, and re-aligning deliberately (doc before
code, ADR-0000 register).

Three invariants this skill defends:

1. **One recorded pin.** Exactly one upstream version is current at a time, recorded in `CLAUDE.md`.
2. **Fixtures are captured, never authored.** Every fixture is the verbatim output of a pinned `bd`
   invocation under `BD_JSON_ENVELOPE=1`. Hand-editing a fixture is forbidden — it silently breaks the
   one guarantee fixtures give (that the parser was tested against real upstream bytes).
3. **Drift is detected, not discovered.** Three diff probes (envelope schema_version, Dolt migration
   version, pack/city.toml shape) catch upstream movement before it reaches users. The SQL-vs-CLI
   equivalence test is the in-CI canary.

> **Read-only against live upstream.** Capturing fixtures and running diff probes are reads. This skill
> never mutates beads. gc's reconciler assumes a single writer per bead (ADR-0003 Decision 6); any
> capture against the live city HQ or `tg` is `SELECT`/`bd …`-read only.

## The Pinned Upstream

The current pin (as of this writing):

| Surface | Pin | Recorded in |
|---|---|---|
| **bd CLI** | `1.0.5` (commit `f9fe4ef2a`, `main@f9fe4ef2a6d3`) | `CLAUDE.md` → "Environment facts" → *Pinned upstream* |
| **beads schema** | not pinned — feature-detected per store | `DoltSchemaShape` in `beads_dart` probes `information_schema` at connect; the required tables/columns are the pin, the migration version is diagnostic only |
| **envelope** | `schema_version == 1` | `kBdSchemaVersion` in `lib/src/codecs/envelope.dart` |
| **fixtures** | `fixtures/upstream/2026-06-11-bd-1.0.5/` | dated dir name carries date + bd version |

Upstream source checkouts on disk (from `CLAUDE.md` "Environment facts" / "Pinned upstream"):

| Repo | Path | Used for |
|---|---|---|
| gascity (gc) | `~/development/gastownhall/gascity` | pack-protocol, `city.toml`, schemas (`schemas/pack`), reconciler behaviour |
| beads (bd) | `~/development/gastownhall/beads` | bd source, Dolt migrations (`internal/storage/schema/migrations/`) |
| lenny | `~/development/engineering.memento/lenny` | `exploration_contract` path dep (M0 prereq) |
| predictable-flutter | `~/development/predictable-flutter` | architecture skill |

### Reading the current pin

```bash
# The recorded pin (source of truth):
grep -n 'Pinned upstream' CLAUDE.md   # run from the_grid repo root

# The bd binary actually on PATH — must match the recorded commit:
bd version            # → bd version 1.0.5 (f9fe4ef2a: main@f9fe4ef2a6d3)

# The beads checkout commit — must match the bd binary:
git -C ~/development/gastownhall/beads rev-parse --short HEAD   # → f9fe4ef2a

# The dated fixture dir encodes date + version:
ls fixtures/upstream/   # run from the_grid repo root
```

If `bd version`, the beads checkout commit, and the recorded pin disagree, **stop** — you are not on the
pin. Reconcile before capturing fixtures or running drift probes (a fixture captured off-pin is worse
than no fixture).

## Fixture Re-Capture

Read **`references/fixtures.md`** before capturing. It documents the exact command behind every existing
fixture, the capture environment, and the wholesale-into-a-new-dated-dir rule. The one-line rules:

- Fixtures live at `fixtures/upstream/<date>-bd-<version>/`, captured under `BD_JSON_ENVELOPE=1`.
- A version bump means a **new dated dir** with **all** fixtures re-captured — never an in-place edit,
  never a partial top-up of the old dir. The old dir stays as the historical record of the prior pin.
- Each dir carries a `README.md` table (file → what → exact capture command) and the capture-time
  findings. The README is part of the fixture set, written at capture time.
- Never open a fixture in an editor to "fix" a value. If a fixture looks wrong, the capture was wrong —
  re-capture it.

## Schema / Protocol Diffing

Read **`references/drift-diff.md`** for the concrete probe commands. The three drift surfaces:

1. **Envelope `schema_version`** — pinned at `1`. `BdEnvelope.parse` asserts it; a mismatch throws
   `BdSchemaDriftException` at runtime. This is the cheapest probe (one `bd` call) and the loudest
   failure.
2. **Dolt migration version** — the controller's `DoltQueryService` carries a targeted migration version
   const. The live store reports its own via `SELECT COALESCE(MAX(version), 0) FROM schema_migrations`.
   Compare that against the highest migration in the pinned beads checkout
   (`internal/storage/schema/migrations/`, currently `0050`). beads itself raises `SchemaSkewError` when
   the store's `MAX(version)` exceeds the binary's `LatestVersion()`; the_grid mirrors that guard by
   falling back to CLI reads (ADR-0001 Decision 4 "Schema-drift guard").
3. **pack-protocol / city.toml** — later milestones (M3 runtime) read gc's pack and city shapes. The
   canonical shapes live in `~/development/gastownhall/gascity/schemas/pack` and the example
   `city.toml`s under `examples/*/`. Snapshot-diff these against the pinned checkout.

The **SQL-vs-CLI snapshot equivalence test** (tagged, ADR-0001 Decision 7) is the in-CI drift canary: if
the pooled-SQL snapshot and the `bd export --include-infra` snapshot ever disagree, either the schema
moved under the SQL reader or bd's projection moved under the CLI reader. Either way it trips before a
release.

## Re-Alignment When Upstream Moves

When `bd version` / the beads checkout has advanced past the pin, re-align in this order (full checklist
in **`references/realignment.md`**):

1. **Confirm the move is intentional.** Pin bumps are a decision, not a side effect of `git pull`.
   Confirm with Nico; do not silently bump.
2. **Bump the pin in `CLAUDE.md`** ("Environment facts" → *Pinned upstream*: new version + commit) and
   in any const that names the bd/migration version.
3. **Re-capture fixtures wholesale** into a new `fixtures/upstream/<new-date>-bd-<new-version>/` dir
   (procedure: `references/fixtures.md`). Write the dir's `README.md` at capture time.
4. **Update the targeted migration version** const in `DoltQueryService` to the new
   `internal/storage/schema/migrations/` high-water mark.
5. **Run the test suite.** The codec fixtures re-pin the parser; the **SQL-vs-CLI equivalence test** is
   the canary — a red here means the schema or projection actually changed shape, not just a version
   number.
6. **Record the decision as an ADR-0000 amendment** (per `CLAUDE.md` process rules / ADR-0000 register):
   what moved, what shape changed, what the_grid did about it. AI-made re-alignment calls stay in
   ADR-0000 until Nico promotes or rejects them. **Never** edit a ratified ADR (0001+) to match new
   upstream behaviour, and never silently re-shape a Track A model to match drift.

### Drift triage table

| Symptom | Probe | First move |
|---|---|---|
| `BdSchemaDriftException` at runtime | envelope `schema_version` ≠ 1 | hard stop — envelope contract broke; ADR-0000 before any code |
| SQL reads disabled, fell back to CLI, "loud log" | migration `MAX(version)` > targeted const | bump targeted const after confirming schema delta is read-safe |
| SQL-vs-CLI equivalence test red | structural snapshot diff | inspect the diffed fields; a real shape change ⇒ re-align Track A via ADR-0000 |
| `bd version` ahead of recorded pin | `references/realignment.md` step 1 | confirm intent, then full re-alignment |
| pack/`city.toml` parse fails (M3) | `references/drift-diff.md` §pack | diff pinned `schemas/pack`; ADR-0000 for shape change |
