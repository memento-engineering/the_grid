/// The restorable circuit cursor (ADR-0008 D4 / M4-P1 §3, D-3).
///
/// The in-memory shape of a reentrant circuit's progress — a per-node
/// [StepState] position plus the per-node respawn fence (D-4) and the
/// supervised-restart bookkeeping (D-5). Persisted as FLAT, merge-safe
/// `grid.cursor.{nodePath}.*` keys on the_grid's OWN session bead (Track B does
/// the codec) — never the foreign work bead (A37). This file is the pure
/// value-type; the metadata codec lives in `session_bead.dart`.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'circuit.dart';

part 'cursor.freezed.dart';
part 'cursor.g.dart';

/// One inflated node's cursor entry, keyed by its `nodePath` in a
/// [CircuitCursor].
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

    /// How many times this node has been RE-KEYED BY A ROUTING REWIND
    /// (the `Rewind` verdict — tg-o90). Bumped monotonically per node on every
    /// rewind wave that names it, and part of the node's reconcile key
    /// (`CircuitScope`), so a rewound node that is still MOUNTED (a daemon) is
    /// torn down and re-run rather than silently left alive under a stale
    /// incarnation.
    ///
    /// DISTINCT from [restartCount] (a supervised CRASH restart, D-5): a rework
    /// round never spends the restart budget and a crash never spends a rework
    /// round. It is also the BOUNDED-ROUNDS counter — the host refuses a rewind
    /// from a node that has reached `kMaxReworkRounds`, and a `route` reads its
    /// own count back through the ambient `SiblingView` to escalate first.
    @Default(0) int rewindCount,

    /// How many times this node was REAPED ON ADOPTION — a prior station
    /// generation left it at [StepState.running] and its recorded process was
    /// found DEAD at boot, so the reaper re-mounted it.
    ///
    /// CAPTURE-ONLY, and deliberately a THIRD incarnation axis — disjoint from
    /// BOTH [restartCount] (a LIVE-supervised crash, D-5) and [rewindCount] (a
    /// routing rework round, A47). A47's rule is the law here: "Two axes, not
    /// one: a rework round never spends the supervised-restart budget, and a
    /// crash never spends a rework round." A STATION DEATH is a third cause, so
    /// it gets a third counter — **a station death is not a step failure:** the
    /// `maxRestarts` breaker is for a process that died while the station was
    /// ALIVE to supervise it, so charging a bounce to it would make the
    /// operator's recovery lever destructive (the third bounce that caught a
    /// long step mid-run would trip the breaker and close a session whose step
    /// never failed).
    ///
    /// UNLIKE the other two axes it is **NOT part of the reconcile key**
    /// (`CircuitScope`'s `ValueKey('$path#$restartCount.$rewindCount')` — A47):
    /// a re-key exists to TEAR DOWN a still-mounted effect, and the reap runs at
    /// boot BEFORE the kernel mounts anything, so there is no live incarnation
    /// to displace and nothing to re-key. Nothing in the frontier reads it and
    /// no breaker trips on it — so a bounce stays FREE. Its ONLY job is to make
    /// a crash-LOOPING station visible ("this step has died with the station 4
    /// times") instead of silently invisible.
    @Default(0) int reapCount,

    /// The earliest time a failed node may re-key (backoff — D-5); null when not
    /// cooling down.
    DateTime? cooldownUntil,

    /// The durable log byte-offset for the deferred adopt-a-live-process seam
    /// (§11); null until restoration ships.
    int? logOffset,

    /// Capture-only FLOW TELEMETRY (FT-1, tg-pez) — the wall-clock instant this
    /// incarnation began driving its effect (the host's kick), ISO-8601 UTC on
    /// the wire; null until the node has started. Never gates orchestration.
    DateTime? startedAt,

    /// Capture-only flow telemetry — the wall-clock instant of this incarnation's
    /// terminal transition (complete/failed/ready/gated); null until terminal.
    DateTime? finishedAt,

    /// Capture-only flow telemetry — `finishedAt - startedAt` in milliseconds,
    /// derived at the terminal write; null when the start was never measured
    /// (fail-safe omission).
    int? durationMs,

    /// Capture-only flow telemetry — the truncated diagnostic reason persisted
    /// alongside a `failed` terminal (the `AllocationFailed.reason`); null when
    /// the failure carried no diagnostic.
    String? failureReason,
  }) = _NodeCursor;

  const NodeCursor._();

  factory NodeCursor.fromJson(Map<String, dynamic> json) =>
      _$NodeCursorFromJson(json);

  /// True when [state] is a POSITIVE TERMINAL ([StepState.ready] or
  /// [StepState.complete]) — the two states that satisfy a `dependsOn`.
  bool get isPositiveTerminal =>
      state == StepState.ready || state == StepState.complete;
}

/// A circuit's cursor: every inflated node's [NodeCursor] keyed by its full
/// `nodePath` (e.g. `tg-7r9/harnessPeripheral/build`).
///
/// A missing key reads as a default `pending` [NodeCursor] (a node that has
/// never run). The empty cursor is the freshly-minted session's starting point.
typedef CircuitCursor = Map<String, NodeCursor>;
