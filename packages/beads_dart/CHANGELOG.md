## 0.2.0-rc.10

- Added: `DoltQueryService.queryTimeout` (10 s) is applied to the Dolt SQL connection and its queries through `mysql_client`'s connect timeout, so a state store that never answers no longer hangs a mint; distinct from `BdCliService.pourTimeout`, which bounds only the atomic `bd create --graph` process (tg-akc8, #329).

## 0.2.0-rc.9

- Fixed: `ProcessBdRunner` decodes a child's pipes with `Utf8Decoder(allowMalformed: true)`. Its deadline SIGKILLs a wedged `bd`; a pipe cut between the bytes of one multibyte character made the strict decoder throw `Unfinished UTF-8 octet sequence` from its close as the pipe's done event landed — before `process.exitCode` resolved, so the done-future errored with no listener and the error was UNCAUGHT in the zone. The resident isolate died on it ~90 s into every lunar boot on 2026-09-05 (epoch 39), right after the boot burst's 15 s bd timeouts. A torn tail is U+FFFD now and the call fails as it already did, with `BdTimeoutException` (tg-jbji, #326).

## 0.2.0-rc.8

- The SQL ready port and the CLI snapshot reader carry a ready-only fallback merge, so a bead the store reports ready is never silently absent from a joined snapshot (tg-vdt0, #311).

## 0.2.0-rc.7

- Molecule pours (`bd create --graph`) run on a dedicated 60-second deadline instead of the 15-second single-row default; the exception is named, tested, and bounded, and every other bd call keeps the 15-second deadline (tg-336w, #280).
- `DoltQueryService.close()` releases the state-store proxy sockets so a resident can exit after its shutdown fixpoint (tg-46q1, #285).
- The publish gate no longer embargoes on the upstream bd day-one window; we ship our rc against their rc (#275).

## 0.2.0-rc.6

- Added intake-safe create and list options: `create` takes `defer`,
  `externalRef` and `setMetadata`, and `listScope` reads one scope by `type`,
  `externalRef`, or both, with `includeClosed`. Metadata rides an unconditional
  follow-up `update` per key, because bd has no `create --set-metadata` on any
  supported version; the create argv still carries the external reference, so a
  caller's dedupe read finds the bead even if the metadata write fails.
- bd 1.3.0-rc.1 rehearsal — fixture set, hermetic guard, day-one window
  v1.3.0, drift audit receipts. No store, binary, or fleet component moved:
  the release rail's first real gate waits on the published v1.3.0 tag.
- New fixture set `fixtures/upstream/2026-09-02-bd-1.3.0-rc.1/` (ref
  `v1.3.0-rc.1`, SHA `9c6a69ec12350959ec8c495c74eeb02902d629b6`); every delta
  versus `2026-08-08-bd-main` is pinned by name in
  `test/tool/fixture_drift_test.dart`, and a removed or renamed `Bead`-decoded
  wire key now fails that suite loudly.
- Fix: `--set-metadata` values written by bd 1.3 arrive as typed JSON scalars
  (`attempt=3` → `3`) while pre-1.3 values stay strings, so one store carries
  MIXED shapes. `metadataEntryEquals`/`metadataScalarText` normalise both, and
  `CliBeadProbeReader.openBeads` uses them. bd's own `--metadata-field` filter
  and the SQL leg already agreed (`JSON_UNQUOTE` renders a scalar as its text).
- Fix: `BdCliService.deleteArgs` pins `--cascade` beside `--force`. bd 1.3
  stops cascading by default and `--force` alone orphans dependents; a delete
  through this service is a subtree delete on every supported bd, and 1.0.5
  accepts the flag.
- Feat: exit 14 (`MIGRATION-FREEZE` marker present, write refused) decodes to
  `BdMigrationFrozen`, carrying the marker path bd named. A frozen store reads
  as frozen, never as a crash.
- Test: `test/integration/sql_cli_equivalence_test.dart` and
  `cross_workspace_probe_test.dart` skip when the `bd` on PATH is not the
  store's `.beads/.local_version` writer. `tool/bd_compatibility/run.sh` keeps
  its two-argument form and now completes through the corpus-replay step on a
  foreign binary.
- Receipt (d): `bd dep cycles --json` changes shape at 1.3. beads_dart never
  calls it (`grep -rn "cycles" lib` is empty) — no action.
- Receipt (e): the 1.3 `--brief` / `--brief-deps` projections are NOT adopted
  here; the light-snapshot memory model is tg-185's.
- Receipt (f): proxied `bd update --ephemeral` half-wisps written by pre-1.3
  builds are NOT repaired by 1.3. A future repair sweep would be witnessed in
  `test/integration/wisp_snapshot_test.dart`.
- Receipt: upstream's ready-work exclusion set at rc.1
  (`internal/storage/sqlbuild/ready.go:17-27`) is identical to the hand port in
  `lib/src/ready/ready_work_query.dart` — pinned as a comment, no code change.
- Receipt: the rc `delete` envelope's `data.deleted` is a bare string without
  `--cascade` and a list (plus `deleted_count`) with it. `BdCliService.delete`
  discards the envelope, so only the argv moved.
- Follow-up scope: `grid_runtime`'s `StationBeadWriter` writes numeric-looking
  `--set-metadata` values (pgid/pid); its readers require a separate audit.

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
