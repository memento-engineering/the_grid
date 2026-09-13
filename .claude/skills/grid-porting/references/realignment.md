# Re-Alignment Reference

The full checklist for moving the_grid's pin forward when upstream (bd / beads / gc) has advanced. A pin
bump is a **decision** (doc before code, ADR-0000 register) — not a side effect of `git pull` in an
upstream checkout.

## Preconditions

- A drift probe (`references/drift-diff.md`) has reported a difference, **or** a deliberate upstream
  bump is planned.
- The move is **confirmed with Nico.** AI does not silently bump the pin. If the bump itself is the
  AI's recommendation, that recommendation is an ADR-0000 amendment Nico ratifies before you proceed.

## Checklist

### 1. Pin the new version everywhere it's recorded

```bash
# The authoritative record (run from the_grid repo root):
grep -n 'Pinned upstream' CLAUDE.md
```

Edit `CLAUDE.md` "Environment facts" → *Pinned upstream* to the new `bd X.Y.Z (commit)`. Update any
const that names the bd version. Confirm the beads checkout is at the matching commit:

```bash
bd version
git -C ~/development/gastownhall/beads rev-parse --short HEAD   # must match the bd binary
```

### 2. Re-capture fixtures wholesale into a new dated dir

Procedure: `references/fixtures.md`. New `fixtures/upstream/<new-date>-bd-<new-version>/`, every fixture
re-captured under `BD_JSON_ENVELOPE=1`, on the new pin. Write that dir's `README.md` at capture time
(version, sources, capture-command table, capture-time findings). Leave the old dir untouched as the
historical record.

Do **not**:
- edit the old dir in place,
- copy old fixtures forward and tweak them,
- drop a single new file into the old dir.

### 3. Update the targeted migration version

```bash
ls ~/development/gastownhall/beads/internal/storage/schema/migrations/*.up.sql \
  | sed -E 's@.*/([0-9]+)_.*@\1@' | sort -n | tail -1      # new high-water mark
```

Set the `DoltQueryService` targeted-migration const to that number. Before doing so, inspect the
migrations added since the old const (`references/drift-diff.md` §2) and confirm none of them re-shape a
table the snapshot `SELECT`s read in a way the hand-written queries can't handle. If they do, the SQL
reader needs updating too — and that's a code change gated by the doc step (§5).

### 4. Run the test suite

```bash
# From the package; the integrator/CI runs the full suite:
#   cd packages/grid_controller && dart test
```

What each signal means:

- **Codec fixture tests** re-pin the parser to the new fixtures. Red here ⇒ the envelope/JSON shape
  changed; reconcile the models (record it in the decision register, never a silent Track A edit).
- **SQL-vs-CLI equivalence test** (the drift canary, ADR-0001 Decision 7) ⇒ if red, the schema moved
  under the SQL reader or bd's projection moved under the CLI reader. This is the test that catches a
  structural change a version-number bump alone would hide. Do not green it by loosening the assertion —
  fix the reader or escalate the shape change.
- **No-SQL-writes / no-`.beads/hooks/`-touch test** (PDR §6.6) must stay green regardless. If a
  re-alignment tempts you to write SQL or touch hooks, stop — that's an invariant, not a tradeoff.

### 5. Record the decision in the register

Per `CLAUDE.md` process rules and the decision register (`docs/decisions/` — see the `decide`
skill for the write path; the old ADR-0000 pending-amendment convention is retired, superseded
by the decisions repository's own specification):

- Author an entry capturing **what moved** (versions/commits), **what shape changed** (envelope /
  migrations / pack), and **what the_grid did** (const bumps, model reconciliation, reader changes).
- Entries are recorded `accepted` on write — an autonomous re-alignment call is still recorded
  honestly in `decision-makers`, and a call needing Nico's ratification stays open as a question
  until he rules, rather than being logged as a done deal.
- **Never** edit a ratified ADR entry to match new upstream behaviour, and **never** silently
  re-shape a Track A model (`packages/grid_controller/lib/src/models/`) to absorb drift. Track A
  is LOCKED; a forced change to it is exactly the kind of decision the register exists to surface.

## Severity ladder

| What moved | Blast radius | Gate |
|---|---|---|
| bd patch, envelope `schema_version` unchanged, no new migrations | fixtures re-pin only | re-capture + run suite; ADR-0000 note |
| new migrations, snapshot tables unaffected | bump targeted const | confirm read-safety; ADR-0000 amendment |
| new migrations re-shape a read table | SQL reader change | code change, fully gated by §5 before written |
| envelope `schema_version` changed | codec foundation | **hard stop**; ADR-0000 + Nico before any code |
| pack / `city.toml` shape changed (M3+) | runtime parser | ADR-0000 amendment; affects `grid_runtime` only |

When in doubt about whether a change is "just a version number" or a real shape change, the answer is the
**SQL-vs-CLI equivalence test** plus the codec fixture tests. If both are green on the new pin, the move
was a re-pin; if either is red, it was a re-shape and needs the doc step before any code lands.
