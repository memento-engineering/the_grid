/// Reactive beads controller SDK for the_grid.
///
/// Layering follows predictable-flutter: Services (stateless I/O) →
/// Repositories (own one source, emit state) → Interactors/Selectors/
/// Transformers → consumers. See docs/adr/ADR-0001 and ADR-0002.
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
// repository/interactor/transformer, dirty-signal sources, and the Riverpod
// provider surface.
export 'src/interactors/graph_sync_interactor.dart'
    show GraphSyncStats, GraphSyncInteractor;
export 'src/providers/grid_providers.dart';
export 'src/reactivity/beads_repository.dart';
export 'src/reactivity/dirty_signal.dart';
export 'src/reactivity/grid_controller_runtime.dart';
export 'src/reactivity/grid_runtime_factory.dart';
export 'src/reactivity/snapshot_reader.dart';
export 'src/reactivity/snapshot_readers.dart';
export 'src/transformers/graph_events_transformer.dart';

// Reactive domain projections (Track E; ADR-0002 Decision 2): the M1 proving
// trio — sessions, messages, molecules/steps — as freezed value types plus
// pure selectors over graphSnapshotProvider.
export 'src/projections/agent_session.dart';
export 'src/projections/message.dart';
export 'src/projections/molecule.dart';
export 'src/projections/projection_error.dart';
export 'src/projections/projection_providers.dart';
export 'src/projections/step.dart';
