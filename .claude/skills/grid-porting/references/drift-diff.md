# Drift Diff Reference

Concrete commands to detect upstream drift across the three surfaces the_grid consumes. All probes are
reads. Run them on the pin (SKILL.md → "Reading the current pin") so a difference means *upstream
moved*, not *you're off-pin*.

## 1. Envelope `schema_version`

Pinned at `1`. `BdEnvelope.parse` asserts `schema_version == kBdSchemaVersion` and throws
`BdSchemaDriftException` on mismatch — so at runtime this drift is loud and self-reporting. To probe it
ahead of a release:

```bash
export BD_JSON_ENVELOPE=1

# Any bd JSON call carries the version at top level. Read it directly:
bd statuses --json | jq '.schema_version'      # → 1

# Cross-check the const the parser pins against:
grep -n 'kBdSchemaVersion' \
  /Users/nico/development/engineering.memento/the_grid/packages/grid_controller/lib/src/codecs/envelope.dart
```

If `bd`'s `schema_version` ≠ `kBdSchemaVersion`, the envelope contract changed. This is a **hard stop**:
the codec layer is the foundation, and bumping the const without understanding the shape change is how
you ship a silent mis-parse. ADR-0000 amendment before any code (`references/realignment.md`).

## 2. Dolt migration version

the_grid's `DoltQueryService` carries a **targeted migration version** const — the schema version its
hand-written `SELECT`s were written against. Three numbers must agree:

```bash
# (a) The live store's applied migration high-water mark.
#     This is exactly the query beads itself uses (internal/storage/schema/schema.go).
#     SELECT-only — safe against the live `tg` server. Use the controller's pooled reader,
#     or a one-off mysql client with the discovered creds (host 127.0.0.1, port 34947, db tg).
#     SELECT COALESCE(MAX(version), 0) FROM schema_migrations;

# (b) The highest migration shipped by the PINNED beads checkout.
ls ~/development/com.gastownhall/beads/internal/storage/schema/migrations/*.up.sql \
  | sed -E 's@.*/([0-9]+)_.*@\1@' | sort -n | tail -1      # → 0050

# (c) The const the_grid targets.
grep -rn 'targetedMigration\|migrationVersion\|schemaVersion' \
  /Users/nico/development/engineering.memento/the_grid/packages/grid_controller/lib/src/
```

Interpretation:

- **(a) == (b) == (c)** → aligned.
- **(a) > (c)** → the live store has migrated past what the SQL reader was written for. beads' own guard
  (`SchemaSkewError` when store `MAX(version)` > binary `LatestVersion()`) is the upstream analogue;
  the_grid mirrors it by the ADR-0001 Decision 4 schema-drift guard — **disable SQL reads, fall back to
  `BdCliService`, log loudly**. Then inspect whether the new migrations touch tables the snapshot reads,
  and bump (c) only after confirming the deltas are read-safe.
- **(b) > (c)** → the pinned beads moved (e.g. after a version bump) but the targeted const wasn't
  updated. Update (c) as part of re-alignment.

To see *what* changed between two migration high-water marks (e.g. an old pin's `NNNN` and the new
`0050`):

```bash
# List the migrations added since the old targeted version:
ls ~/development/com.gastownhall/beads/internal/storage/schema/migrations/ \
  | awk -F_ '$1+0 > 47 {print}'        # migrations after 0047, adjust the bound

# Diff the actual DDL of a specific new migration:
git -C ~/development/com.gastownhall/beads log --oneline -- internal/storage/schema/migrations/
cat ~/development/com.gastownhall/beads/internal/storage/schema/migrations/0050_*.up.sql
```

The **SQL-vs-CLI equivalence test** (tagged, ADR-0001 Decision 7) is the in-CI version of this probe:
it composes one snapshot via pooled SQL and one via `bd export --include-infra` and asserts they match.
A red there means the schema moved under the SQL reader (or bd's projection moved under the CLI reader) —
it catches structural drift that a version-number compare alone would miss.

## 3. pack-protocol / city.toml

Relevant from M3 (`grid_runtime`) onward. gc's pack and city shapes are the canonical source:

```bash
# Canonical pack schema(s) in the pinned gascity checkout:
ls ~/development/com.gastownhall/gascity/schemas/pack

# Example city.toml shapes (the structural reference for parsing):
find ~/development/com.gastownhall/gascity/examples -name city.toml

# Diff a shape against the pin after a gc bump (git-level — the checkout IS the pin):
git -C ~/development/com.gastownhall/gascity log --oneline -- schemas/pack
git -C ~/development/com.gastownhall/gascity diff <old-pin>..<new-pin> -- schemas/pack examples/*/city.toml
```

A change in `schemas/pack` or the `city.toml` shape that the_grid parses is drift: treat it like any
other — confirm intent, re-align, and record an ADR-0000 amendment describing the shape change and the
controller's response. Until M3 consumes these, this probe is informational only.

## Quick all-surfaces check

```bash
export BD_JSON_ENVELOPE=1
echo "pin (recorded):"; grep 'Pinned upstream' /Users/nico/development/engineering.memento/the_grid/CLAUDE.md
echo "bd binary:";      bd version
echo "beads checkout:"; git -C ~/development/com.gastownhall/beads rev-parse --short HEAD
echo "envelope:";       bd statuses --json | jq '.schema_version'
echo "migrations max:"; ls ~/development/com.gastownhall/beads/internal/storage/schema/migrations/*.up.sql | sed -E 's@.*/([0-9]+)_.*@\1@' | sort -n | tail -1
```

All five should line up with each other and with the dated fixture dir. Any disagreement is the signal
to open `references/realignment.md`.
