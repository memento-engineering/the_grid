## 0.2.0-rc.5

- Breaking: none new in this candidate — it continues the 0.2.0 candidate
  line so that main and pub.dev agree again (rc.4 shipped before #237/#256).
- Workspace endpoint resolution is injectable: `BeadsWorkspace.discover(endpointResolver:)`
  takes an `EndpointResolver`; `ProxiedServerEndpointResolver` is the default
  and the gc-era endpoint fossils are gone (#237).
- `bd_compatibility.yaml` records the owned bd fork's plan-local parent
  cycle-check patch with a ref-specific fixture capture (#256).
- Tests pin loud SQL snapshot failures (a persistent SQL failure propagates
  instead of silently degrading to the CLI read path, #233) and the
  job-level bd-compatibility CI gate (#230).

## 0.2.0-rc.4

- Breaking: guarded conditional updates ride a NEGOTIATED capability (#205).
  The probe is tri-state and fail-closed (an indeterminate `bd` keeps the
  guards); a conditional mismatch surfaces as `BdGuardMismatch` instead of a
  generic failure, and there is no unguarded retry after a mismatch. The
  pre-negotiation conditional parameters on update are gone. Migration:
  depend on the negotiated path and catch `BdGuardMismatch` where CAS
  conflicts were previously inferred from generic errors.
- Coherence note: this is the floor `grid_runtime 0.2.0-rc.4` requires — the
  rc.3 pair was published incoherently (the runtime archive referenced
  guarded-write symbols no published beads_dart carried).

## 0.2.0-rc.3

- Guarded-write capability negotiation (`BdGuardMismatch`) and the `notes:`
  parameter on the update path. Consumed by grid_runtime's `StationBeadWriter`.

  NOTE: the previous version was published and the package then kept accruing
  source without a bump, so the hosted archive and the in-repo sources at that
  version differed. Local builds passed on path overrides while hosted
  resolves got stale code. This release re-syncs them.

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
