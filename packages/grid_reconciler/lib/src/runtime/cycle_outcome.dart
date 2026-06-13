import '../actuator/actuator.dart';
import '../convergence/reconciler_action.dart';
import '../convergence/reducer_event.dart';
import '../reducer/reduce_result.dart';

/// Why a single reduce→gate→actuate cycle ended — the structured trace the
/// runtime records per processed event (for diagnostics, tests, and the
/// deferred-error contract).
enum CycleStatus {
  /// The reduce produced a transition and the actuator committed it.
  actuated,

  /// Phase 1 of a fresh gate evaluation: the runtime ran the gate and
  /// re-entered the reducer (phase 2) — this trace covers phase 1; phase 2 has
  /// its own [CycleOutcome].
  gateEvaluated,

  /// The reduce was a no-op (a `skipped` — dedup, terminal guard, idempotent
  /// operator no-op). No mutation.
  skipped,

  /// A real store / probe / actuation failure mid-transition (ADR-0000 A25):
  /// `no_action` + error + NO further mutation for the bead this cycle. The
  /// next cycle retries idempotently.
  failed,

  /// The cycle ended by re-enqueuing a deferred event (the operator-stop drain,
  /// ADR-0000 A19): the drain pipeline ran and [CycleOutcome.requeued] carries
  /// the re-entry.
  requeued,
}

/// The structured outcome of one cycle — gc's `(HandlerResult, error)` analog,
/// surfaced as data so the runtime can log it, requeue from it, and tests can
/// assert against it.
class CycleOutcome {
  const CycleOutcome({
    required this.convergenceBeadId,
    required this.status,
    this.result,
    this.actuation,
    this.error,
    this.requeued,
  });

  /// A clean no-op cycle (no convergence concerned, or the bead vanished).
  const CycleOutcome.noop(String beadId)
    : convergenceBeadId = beadId,
      status = CycleStatus.skipped,
      result = null,
      actuation = null,
      error = null,
      requeued = null;

  final String convergenceBeadId;
  final CycleStatus status;

  /// The reduce result this cycle executed (null for a vanished bead).
  final ReduceResult? result;

  /// The actuation result, when the cycle actuated.
  final ActuationResult? actuation;

  /// The failure, when [status] is [CycleStatus.failed].
  final Object? error;

  /// The event re-enqueued behind a drain (when [status] is
  /// [CycleStatus.requeued]).
  final ReducerEvent? requeued;

  /// The primary action of the reduce — gc's `HandlerResult` analog.
  ReconcilerAction? get primary => result?.primary;

  bool get isFailure => status == CycleStatus.failed;

  @override
  String toString() =>
      'CycleOutcome($convergenceBeadId, ${status.name}'
      '${error != null ? ', error=$error' : ''})';
}
