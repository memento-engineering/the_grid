/// The restorable formula cursor (ADR-0008 D4 / M4-P1 §3, D-3).
///
/// The in-memory shape of a reentrant formula's progress — a per-node
/// [StepState] position plus the per-node respawn fence (D-4) and the
/// supervised-restart bookkeeping (D-5). Persisted as FLAT, merge-safe
/// `grid.cursor.{nodePath}.*` keys on the_grid's OWN session bead (Track B does
/// the codec) — never the foreign work bead (A37). This file is the pure
/// value-type; the metadata codec lives in `session_bead.dart`.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'formula.dart';

part 'cursor.freezed.dart';
part 'cursor.g.dart';

/// One inflated node's cursor entry, keyed by its `nodePath` in a
/// [FormulaCursor].
///
/// Flat per key so two concurrent leaf hosts writing DISJOINT keys never lose a
/// write through bd's client-side metadata merge (the D-1 serialization gate
/// closes the same-key race; flatness closes the disjoint-key one). Doubles as
/// the restoration bucket — [logOffset] is the deferred adopt seam (§11).
@freezed
abstract class NodeCursor with _$NodeCursor {
  /// Creates a cursor entry in [state], optionally carrying the spawned process
  /// identity ([pgid]/[pid]/[token]), the supervised-restart bookkeeping
  /// ([restartCount]/[cooldownUntil]), and the restoration [logOffset].
  const factory NodeCursor({
    /// The node's lifecycle state.
    @Default(StepState.pending) StepState state,

    /// The spawned process-group id (the per-node respawn-or-skip kill target —
    /// D-4); null until `SessionStarted`, or when pgid resolution failed.
    int? pgid,

    /// The spawned leader pid (diagnostics + the liveness fence for the guarded
    /// terminate); null until `SessionStarted`.
    int? pid,

    /// The engine-minted `GRID_INSTANCE_TOKEN` freshness fence (per node — D-4);
    /// null until `SessionStarted`.
    String? token,

    /// How many times this node has been supervised-restarted (gates the breaker
    /// predicate — D-5).
    @Default(0) int restartCount,

    /// The earliest time a failed node may re-key (backoff — D-5); null when not
    /// cooling down.
    DateTime? cooldownUntil,

    /// The durable log byte-offset for the deferred adopt-a-live-process seam
    /// (§11); null until restoration ships.
    int? logOffset,
  }) = _NodeCursor;

  const NodeCursor._();

  factory NodeCursor.fromJson(Map<String, dynamic> json) =>
      _$NodeCursorFromJson(json);

  /// True when [state] is a POSITIVE TERMINAL ([StepState.ready] or
  /// [StepState.complete]) — the two states that satisfy a `dependsOn`.
  bool get isPositiveTerminal =>
      state == StepState.ready || state == StepState.complete;
}

/// A formula's cursor: every inflated node's [NodeCursor] keyed by its full
/// `nodePath` (e.g. `tg-7r9/harnessPeripheral/build`).
///
/// A missing key reads as a default `pending` [NodeCursor] (a node that has
/// never run). The empty cursor is the freshly-minted session's starting point.
typedef FormulaCursor = Map<String, NodeCursor>;
