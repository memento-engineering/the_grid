/// M2 work-convergence reconciler for the_grid.
///
/// Ports gc's convergence state machine (ADR-0003) into Dart: a pure
/// `reduce(state, event, snapshot) → (state', actions)` reducer fed by
/// grid_controller's `GraphEvent` stream, with actuation batched through bd.
/// Layering follows predictable-flutter (see docs/adr/ADR-0001..0003).
///
/// Scope is **work convergence only** (ADR-0003 Decision 1); topology and
/// session reconciliation are M3/M4.
library;

// Track A — convergence domain + metadata codec (the contract Tracks B–H
// bind to). Wire literals are byte-faithful to
// gascity/internal/convergence/metadata.go + handler.go; see each type's
// doc comment for file:line citations.
export 'src/convergence/convergence_metadata.dart';
export 'src/convergence/convergence_state.dart';
export 'src/convergence/field_reading.dart';
export 'src/convergence/gate_config.dart';
export 'src/convergence/gate_mode.dart';
export 'src/convergence/gate_outcome.dart';
export 'src/convergence/gate_result.dart';
export 'src/convergence/gate_timeout_action.dart';
export 'src/convergence/go_duration.dart';
export 'src/convergence/go_scalars.dart';
export 'src/convergence/idempotency_key.dart';
export 'src/convergence/reconciler_action.dart';
export 'src/convergence/reducer_event.dart';
export 'src/convergence/verdict.dart';

// Track A — projections over the GraphSnapshot (reuses grid_controller's
// ProjectionResult boundary) and their Riverpod selectors (ADR-0002 D2).
export 'src/projections/convergence.dart';
export 'src/projections/wisp.dart';
export 'src/providers/convergence_providers.dart';

// Track B (the pure reducer) and Track C–G surfaces land here as they're
// built per docs/M2-BUILD-ORDER.md.
