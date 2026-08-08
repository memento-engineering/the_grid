---
name: grid-porting
description: >
  Keeps the_grid aligned with bd, beads, and gascity upstream through an explicit version-policy
  record. Use when capturing upstream JSON/JSONL fixtures for a ref, detecting schema or protocol
  drift, or re-aligning the controller after upstream moves. Owns the version-policy record, fixture
  re-capture procedure, drift-diff commands, and ADR-0000 decision-recording checklist. Not for
  controller Dart code or mutation of live beads; upstream access is read-only.
---

# Grid Porting

the_grid consumes the bd CLI JSON envelope, the beads Dolt schema, and the gascity pack protocol.
This skill detects movement in those upstream surfaces and records deliberate responses.

## The Version Policy

D-BD1 (Nico, 2026-08-08) forbids a repository-wide bd pin. The drift rail tests
`gastownhall/beads@main`; the release rail tests the latest non-prerelease
published tag and the floor declared in `packages/beads_dart/bd_compatibility.yaml`.
CI uses fresh throwaway stores. Production-store migration follows the release
rail only. The checked-in `day_one_wait_through` records the one-time fleet
exception and is not a reusable migration mechanism.

Fixture capture is selected by an explicit `--ref <main-or-tag>` and resolved
40-character SHA. Main uses the drift rail; a version tag uses the release rail.
Captures are wholesale into a new dated directory, include ref and SHA provenance,
and are never hand-edited. The executable capture implementation and first bd-main
bytes belong to tg-rnd8.

Three invariants govern porting:

1. Fixtures are the verbatim output of the executable resolved from the requested ref under
   `BD_JSON_ENVELOPE=1`. They are captured, never authored.
2. Envelope, store-shape, pack, and SQL-vs-CLI probes detect drift before release.
3. Capture and diff probes have read-only access to live upstream workspaces. CI compatibility runs
   use only newly created throwaway stores.

## Fixture Re-Capture

Read `references/fixtures.md` before capture. A capture takes an explicit `--ref <main-or-tag>` and an
independently resolved 40-character SHA. Capture every fixture into a new dated directory with a
README recording both values, the executable provenance, exact commands, sources, and findings. Keep
all earlier directories. Never edit or partially top up a fixture directory; repeat the complete
capture when any byte is wrong or when a new projection needs coverage.

## Schema / Protocol Diffing

Read `references/drift-diff.md` for the probe commands.

1. `BdEnvelope.parse` requires envelope `schema_version == 1` and raises
   `BdSchemaDriftException` on mismatch.
2. Probe `information_schema` for required Dolt tables and columns. Migration versions are diagnostic;
   unknown shapes disable SQL reads and fall back loudly to `BdCliService`.
3. Compare pack and `city.toml` shapes with the schemas and examples from the selected gascity ref.
4. Run the SQL-vs-CLI snapshot equivalence canary. A difference means the SQL schema or CLI projection
   moved and requires investigation before release.

## Re-Alignment When Upstream Moves

Use `references/realignment.md` as the full checklist. Select the rail and explicit ref, resolve its
SHA independently, run the shape and compatibility probes, and re-capture fixtures wholesale when the
captured protocol changes. Record consequential shape or model decisions as ADR-0000 amendments before
changing Track A models. Do not silently rewrite ratified ADRs to follow upstream behavior.

### Drift triage

| Symptom | First move |
|---|---|
| Envelope schema mismatch | Stop and record the changed contract in ADR-0000 |
| SQL reads disabled | Compare the selected ref's required store shape and retain CLI fallback |
| SQL-vs-CLI equivalence red | Inspect the structural field diff and record any model change |
| Drift rail red | Use the filed upstream SHA to reproduce against `main` |
| Release rail red | Keep the feature gated or degrade it against the published tag/floor |
| pack or `city.toml` parse failure | Diff the selected gascity ref and record shape changes |
