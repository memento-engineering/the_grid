## 0.2.0-rc.2

- The sync FLOOR (tg-zd4v): `GridRuntimeFactory.build` adds a
  `PollingTickerSource` on the SQL read path too (`syncFloorInterval`,
  default 45s) — the working-set probe is edge-triggered, so a store nobody
  writes to never re-captured and served a frozen frontier.
- `GridControllerRuntime` gains `onDirtySourceClosed` — a closed dirty-signal
  source is reported once instead of silencing sync forever.

## 0.2.0-rc.1

- Breaking: `BdCliService.exportAll` and `exportArgs` are REMOVED. `bd export` is
  refused in proxied-server mode, so every read that shelled it degraded silently
  there instead of failing. Migration: use `query(expr, includeClosed: …)` for a
  filtered read, `listScope(type:, status:)` for one scope, or the new
  `BeadProbeReader` seam for lifecycle probes.
- Breaking: `query` gains `includeClosed`, which appends `--all`. An all-status
  read is `query('status=open OR status=in_progress OR status=blocked OR
  status=deferred OR status=closed', includeClosed: true)`.
- Added: `BeadProbeReader` with `SqlBeadProbeReader` and `CliBeadProbeReader`
  implementations (`beadById`, `openBeads`, `openSuperseding`).
- Changed: `CliSnapshotReader` composes a snapshot from one broad query plus one
  batched dependency read instead of `bd export --all`. `SqlSnapshotReader` no
  longer falls back to the CLI reader — a persistent SQL failure is loud
  (transients are still absorbed by the pool's reconnect retry).
- Fixes the read path behind the 2026-08-04 station outage: unreapable molecules
  and an always-empty gate-dedup probe.

## 0.1.1

- Family coherence release from current mainline: probe-death recovery (`WorkingSetProbeSource` failure surfacing + reconnect-by-rebuild, the_grid#135) and current CLI service surface.

## 0.1.0

- Initial release: pure-Dart, framework-free beads client — bd CLI + Dolt SQL services, snapshot repository, structural diff, typed graph events.
