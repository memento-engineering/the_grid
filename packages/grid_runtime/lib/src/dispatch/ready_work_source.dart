import 'dart:async';

import 'package:grid_controller/grid_controller.dart';

/// The dispatch read seam over grid_controller's reactive surface — the
/// second-consumer analog of grid_reconciler's `ConvergenceSource` (M3
/// Track 5; ADR-0006 Decision 1). The [DispatchInteractor] attaches as a
/// **SECOND consumer** of the same observable surface M2 uses; it does **not**
/// go through reduce→gate→actuate.
///
/// The live implementation ([GridReadyWorkSource]) reads grid_controller's
/// `GridControllerRuntime` — its `GraphEvent` stream and its `readyBeads`
/// projection. Tests inject a [FakeReadyWorkSource] driving a synthetic event
/// stream + a programmable ready set. The seam keeps the dispatcher free of
/// Riverpod and of grid_controller's repository wiring (exactly how
/// `ConvergenceSource` keeps the reconciler free of them).
///
/// **Why a `Bead` lookup, not just the entered-id set.** A
/// `GraphEvent.readySetChanged` carries only the entered/exited **ids**
/// (`Set<String>`), so the dispatcher must resolve each entered id to its full
/// [Bead] (the ownership axis reads the id PREFIX and `metadata.rig`). This
/// seam exposes that lookup ([bead]) plus the current [readyBeads] list so the
/// dispatcher can both react to events and reconcile the current ready set on
/// start.
abstract interface class ReadyWorkSource {
  /// The live typed change events (grid_controller's `GraphEvent` stream); the
  /// dispatcher filters for `readySetChanged`.
  Stream<GraphEvent> get events;

  /// The current ready-work set — `bd ready`'s authoritative output projected
  /// by grid_controller (`readyBeads`). Plain work [Bead]s, no
  /// `convergence.rig` key (so `OwnsRigs` is uncallable on them; A32).
  List<Bead> get readyBeads;

  /// The full [Bead] for [id] in the current snapshot, or null if absent — the
  /// resolve a `readySetChanged.entered` id needs (the event carries only ids).
  Bead? bead(String id);
}

/// The live [ReadyWorkSource] over a grid_controller [GridControllerRuntime].
class GridReadyWorkSource implements ReadyWorkSource {
  GridReadyWorkSource(this._runtime);

  final GridControllerRuntime _runtime;

  @override
  Stream<GraphEvent> get events => _runtime.events;

  @override
  List<Bead> get readyBeads => _runtime.readyBeads;

  @override
  Bead? bead(String id) => _runtime.bead(id);
}
