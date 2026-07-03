import 'package:beads_dart/beads_dart.dart';

import '../convergence/convergence_metadata.dart';
import '../convergence/convergence_state.dart';
import '../convergence/reducer_event.dart';
import '../projections/convergence.dart';

/// Adapts a beads_dart [GraphEvent] into the convergence [ReducerEvent]
/// it implies, resolved against the current set of convergence loops.
///
/// **The one live channel that maps cleanly is wisp closure.** A
/// `GraphEvent.beadClosed` whose closed bead is a loop's `active_wisp` (the
/// wisp that just finished its iteration) is gc's `HandleWispClosed` entry
/// (handler.go:161) — it becomes a [ReducerEvent.wispClosed] for that loop's
/// root. This is the reactive replacement for gc's per-tick closure polling
/// (ADR-0003 Decision 2): gc detects closure by re-listing each tick; the grid
/// observes the `BeadClosed` diff event (ADR-0001 Decision 5 +
/// `@@<db>_working` waking the controller, ADR-0000 A21).
///
/// **Operator and trigger events do NOT come from the diff stream.** Operator
/// commands travel out-of-band (gc's controller socket — operator-trigger.md §1)
/// and, once the_grid owns a loop, the_grid's command surface mints
/// [ReducerEvent.operatorApprove]/`operatorIterate`/`operatorStop` directly
/// (the runtime's `submit`). A trigger pass is the result of the runtime's own
/// trigger evaluation over `waiting_trigger` loops (trigger.go:52-101 cadence),
/// minted as [ReducerEvent.triggerPassed]. Detecting them from our OWN metadata
/// writes (the §1.6 detection signatures) is for SHADOW mode observing gc's
/// writes — see [GraphEventAdapter.observedGcCommand]. The live owning runtime
/// never round-trips its own writes back through detection.
class GraphEventAdapter {
  const GraphEventAdapter();

  /// Maps [event] to a [ReducerEvent] for one of [convergences], or null when
  /// the event concerns no convergence loop (the overwhelmingly common case —
  /// most graph churn is ordinary work beads).
  ///
  /// Only `BeadClosed` is mapped here: the closed bead must be the resolved
  /// `active_wisp` of exactly one loop. A closure of a non-active wisp (a
  /// speculative/burned/already-processed child) yields null — the reducer's
  /// monotonic dedup would skip it anyway, and re-firing it wastes a cycle.
  ReducerEventFor? adapt(GraphEvent event, Iterable<Convergence> convergences) {
    if (event is! BeadClosed) return null;
    final closedId = event.after.id;
    for (final convergence in convergences) {
      final active = convergence.metadata.activeWisp;
      if (active == null || active != closedId) continue;
      // Only loops in a state where a wisp closure is meaningful (active /
      // waiting_*). A terminated loop's events are guarded by the reducer's
      // step-1 terminal guard, but skipping here avoids a no-op cycle.
      if (convergence.isClosed) continue;
      return ReducerEventFor(
        convergence: convergence,
        event: ReducerEvent.wispClosed(
          convergenceBeadId: convergence.id,
          wispId: closedId,
        ),
      );
    }
    return null;
  }

  /// SHADOW-mode detection (operator-trigger.md §1.6): infers the convergence
  /// command gc performed from the metadata effects of a `BeadUpdated` on a
  /// convergence root — a strictly READ-only inference for the divergence
  /// report. Never used by the writing runtime (it would round-trip our own
  /// writes). Returns the detected command label, or null.
  ///
  /// The signatures are gc's terminal/iterate write-sets: a fresh
  /// `terminal_reason=approved`/`stopped` with an `operator:` actor, or a
  /// `waiting_manual → active` state flip. These are heuristics for the
  /// divergence diagnostic, not authoritative — shadow mode reports what gc
  /// *appears* to have done against what the_grid *would* have done.
  ObservedGcCommand? observedGcCommand(GraphEvent event) {
    if (event is! BeadUpdated) return null;
    if (event.after.issueType != IssueType.convergence) return null;
    final before = ConvergenceMetadata.decode(event.before.metadata);
    final after = ConvergenceMetadata.decode(event.after.metadata);

    final beforeReason = before.terminalReason?.wire;
    final afterReason = after.terminalReason?.wire;
    final afterActor = after.terminalActor ?? '';
    if (beforeReason != afterReason && afterReason != null) {
      final isOperator = afterActor.startsWith('operator:');
      if (afterReason == 'approved') {
        return ObservedGcCommand(
          beadId: event.after.id,
          command: isOperator
              ? GcCommandKind.operatorApprove
              : GcCommandKind.handlerApproved,
          actor: afterActor,
        );
      }
      if (afterReason == 'stopped') {
        return ObservedGcCommand(
          beadId: event.after.id,
          command: GcCommandKind.operatorStop,
          actor: afterActor,
        );
      }
      if (afterReason == 'no_convergence') {
        return ObservedGcCommand(
          beadId: event.after.id,
          command: GcCommandKind.handlerNoConvergence,
          actor: afterActor,
        );
      }
    }

    final beforeState = before.state.stateOrNull;
    final afterState = after.state.stateOrNull;
    if (beforeState == ConvergenceState.waitingManual &&
        afterState == ConvergenceState.active) {
      return ObservedGcCommand(
        beadId: event.after.id,
        command: GcCommandKind.operatorIterate,
        actor: afterActor,
      );
    }
    if (beforeState == ConvergenceState.waitingTrigger &&
        afterState == ConvergenceState.active) {
      return ObservedGcCommand(
        beadId: event.after.id,
        command: GcCommandKind.triggerAdvance,
        actor: afterActor,
      );
    }
    return null;
  }
}

/// A [ReducerEvent] resolved against the [Convergence] it concerns — the
/// adapter's output, ready for the runtime to reduce.
class ReducerEventFor {
  const ReducerEventFor({required this.convergence, required this.event});

  final Convergence convergence;
  final ReducerEvent event;
}

/// The convergence command shadow mode infers gc performed (read-only
/// diagnostic).
enum GcCommandKind {
  operatorApprove,
  operatorIterate,
  operatorStop,
  triggerAdvance,
  handlerApproved,
  handlerNoConvergence,
}

/// A shadow-detected gc command (operator-trigger.md §1.6 signature match).
class ObservedGcCommand {
  const ObservedGcCommand({
    required this.beadId,
    required this.command,
    required this.actor,
  });

  final String beadId;
  final GcCommandKind command;
  final String actor;

  @override
  String toString() => 'ObservedGcCommand($beadId, ${command.name}, "$actor")';
}
