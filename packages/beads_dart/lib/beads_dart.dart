/// beads_dart — a pure-Dart beads client.
///
/// The M1 kernel of the_grid, wearing its ecosystem name (D-A6): `Bead`/
/// `GraphSnapshot` models, the envelope codec, the `bd` CLI wrapper, workspace
/// discovery (server/embedded), the Dolt SQL read path + `@@<db>_working`
/// probe, watchers, and structural diff. It knows beads facts only — the_grid's
/// own opinions layered on top (ownership predicates, driveability narrowing,
/// session-bead semantics) live in `grid_engine`, not here.
///
/// Layering follows predictable-flutter: Services (stateless I/O) →
/// Repositories (own one source, emit state) → Interactors/Selectors/
/// Transformers → consumers. See docs/adr/ADR-0001 and ADR-0002.
///
/// Framework-free at the package boundary (D-A7): Futures for acts, Streams
/// for observations, a synchronous `current` where a seed value is needed. No
/// riverpod, no StateNotifier — implementers build notifiers/providers on top.
///
/// ## Version-compat contract
///
/// Pinned against **bd 1.0.5** (`f9fe4ef2a`). The wire contract is bd's
/// enveloped `--json` output (`{schema_version, data}`); every decode path
/// asserts `schema_version == 1` (see [BdSchemaDriftException] in
/// `src/errors/bd_exception.dart`) and the SQL read path treats a drift as a
/// hard signal to fall back to the bd CLI rather than trust a stale row
/// shape. That assertion — fail loud on an unexpected `schema_version`,
/// never silently coerce — is the documented guard against upstream bd
/// releases drifting the wire format out from under this client. Re-pinning
/// to a newer bd release goes through the grid-porting skill's re-capture +
/// drift-diff procedure, never a silent bump of the assumed shape.
library;

// Models (value types — plain names per ADR-0001 Decision 2).
export 'src/models/bead.dart';
export 'src/models/bead_comment.dart';
export 'src/models/bead_dependency.dart';
export 'src/models/bead_status.dart';
export 'src/models/dependency_type.dart';
export 'src/models/graph_apply_plan.dart';
export 'src/models/graph_snapshot.dart';
export 'src/models/issue_type.dart';

// Codecs.
export 'src/codecs/envelope.dart';

// Ready-work SQL port + differential harness (Track F; ADR-0003 Decision 5).
// The ready-work predicate ported from beads ready_work.go over the pooled,
// SELECT-only Dolt connection, plus the differential gate that diffs it against
// the `bd ready --json` oracle.
export 'src/ready/ready_work_differential.dart';
export 'src/ready/ready_work_filter.dart';
export 'src/ready/ready_work_query.dart';

// Services (stateless I/O): workspace discovery, bd CLI, Dolt SQL reads.
export 'src/services/bd_cli_service.dart';
export 'src/services/bd_runner.dart';
export 'src/services/beads_workspace.dart';
export 'src/services/dolt_endpoint.dart';
export 'src/services/dolt_query_service.dart';
export 'src/services/dolt_row_mapper.dart';

// Errors.
export 'src/errors/bd_exception.dart';

// Diff + typed events.
export 'src/diff/diff_snapshots.dart';
export 'src/diff/graph_event.dart';

// Reactivity core (Track D): the controller runtime + its seams, the
// repository/interactor/transformer, and the dirty-signal sources. Streams
// for observations, Futures for acts, a synchronous `current` for the seed
// value — no framework deps at the package boundary (D-A7).
export 'src/interactors/graph_sync_interactor.dart'
    show GraphSyncStats, GraphSyncInteractor;
export 'src/reactivity/beads_repository.dart';
export 'src/reactivity/dirty_signal.dart';
export 'src/reactivity/grid_controller_runtime.dart';
export 'src/reactivity/grid_runtime_factory.dart';
export 'src/reactivity/snapshot_reader.dart';
export 'src/reactivity/snapshot_readers.dart';
export 'src/transformers/graph_events_transformer.dart';

// Reactive domain projection primitives (Track E; ADR-0002 Decision 2): the
// typed decode-failure result plus the [Step] value type — shared by
// grid_reconciler's Wisp projection, so they stay in the pure beads client.
// The grid-opinionated projections (sessions, messages, molecules — AL-1b)
// moved to grid_engine; see grid_engine's barrel.
export 'src/projections/projection_error.dart';
export 'src/projections/step.dart';
