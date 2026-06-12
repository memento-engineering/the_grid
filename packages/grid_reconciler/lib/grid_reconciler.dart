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

// Track A (convergence domain + metadata codec), Track B (the pure reducer),
// Track C–G surfaces land here as they're built per docs/M2-BUILD-ORDER.md.
