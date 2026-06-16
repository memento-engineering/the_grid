# Exploration-attach conformance fixture — `extensions` wire shape

Pinned capture of the_grid's exploration host (`grid_exploration`) wire output
in the **`extensions`** key shape that leonard ≥0.1.0 reads, locking the
`plugins`→`extensions` rename (ADR-0000 **A33**; M3-BUILD-ORDER Track 6).

Mirrors the M2 codec-fidelity fixture discipline: version-pinned, never
hand-edited — re-capture only via the tool below.

## Contract version

- **leonard read contract:** `leonard_agent` ≥ 0.1.0 (the rebrand that renamed
  the serialized map `plugins`→`extensions`). Reader, **no `plugins` fallback**:
  - handshake: `leonard_agent/lib/src/vm_service_client.dart` reads
    `json['extensions']` only.
  - observation: `leonard_agent/lib/src/observation/models.dart`
    (`Observation.fromJson`) reads `j['extensions']` only.
- **prefix / methods / protocol version:** unchanged — `ext.exploration.*`,
  `core.handshake` / `core.get_stable_observation` / `<ns>.<tool>`,
  protocol version `'1'`.

## Files (the_grid host output)

- `handshake.json` — `ext.exploration.core.handshake` result. Manifest under
  the `extensions` array: `[{namespace: grid, tools: [requery, snapshot,
  ready, events, stats]}]`. No legacy `plugins` / `pluginCount`.
- `observation.json` — `ext.exploration.core.get_stable_observation` result.
  Grid state under `value.extensions.grid` (the bare-fragment shape leonard's
  `ExtensionFragment.fromJson` peels): `beadCount`, `readyCount`, `readyBeads`.
- `grid-ready.json` — `ext.exploration.grid.ready` tool result (`{ok, value:
  {count, beads}}`).

## Capture provenance

- **Source:** in-memory fake controller snapshot (NO bd / Dolt) — 3 beads
  (`tg-1` molecule, `tg-2`/`tg-3` tasks), ready set `{tg-2, tg-3}`,
  `capturedAt = 2026-06-15T12:00:00Z`.
- **Volatile fields:** `stability.lastRefreshMs` and `…grid.stats.lastRefreshMs`
  carry wall-clock latency and are NOT load-bearing; the replay test
  (`test/conformance_fixture_test.dart`) normalizes them before comparing, so
  the pin catches key/shape drift but tolerates timing jitter.

## Re-capture (never hand-edit)

From `packages/grid_exploration/`:

```sh
dart run tool/capture_conformance_fixture.dart \
  ../../fixtures/exploration/2026-06-15-leonard-extensions
```
