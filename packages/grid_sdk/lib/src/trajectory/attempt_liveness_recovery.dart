import 'package:beads_dart/beads_dart.dart' show GraphSnapshot;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// The off-tree cut adapter that retires an active session after its current
/// attempt durably loses liveness.
///
/// The adapter is inert until [activate]. Station assembly activates it only
/// after the first authored tree flush, leaving restart reconciliation and the
/// preserved-cursor resume path first opportunity to restore the round. Every
/// invocation re-reads the state snapshot; no reactive value or service is
/// cached from the tree.
final class StationAttemptLivenessRecovery {
  /// Creates a recovery adapter over the station's shared authority, recorder,
  /// fresh state snapshot, and emit-only transport bundle.
  StationAttemptLivenessRecovery({
    required StationServices Function() services,
    required GraphSnapshot Function() snapshot,
    required StationTrajectoryRecorder recorder,
    required ServiceBundle transportServices,
  }) : _services = services,
       _snapshot = snapshot,
       _recorder = recorder,
       _transportServices = transportServices;

  final StationServices Function() _services;
  final GraphSnapshot Function() _snapshot;
  final StationTrajectoryRecorder _recorder;
  final ServiceBundle _transportServices;
  final Map<String, int> _roundBySession = <String, int>{};

  bool _active = false;

  /// Arms recovery after station startup has given the existing restart and
  /// tree-resume machinery its first authored flush. Idempotent.
  void activate() => _active = true;

  /// Retires one still-matching lost attempt through the shared station
  /// authority and records its terminal and round-retirement testimony.
  ///
  /// Missing, malformed, mismatched, or closed non-void state is a harmless
  /// no-op because the durable loss no longer names the current live session
  /// relationship. A cut acknowledgement failure remains loud and retryable.
  Future<void> handle({
    required String attemptId,
    required String sessionId,
    required String workBeadId,
  }) async {
    if (!_active) return;

    final session = _snapshot().bead(sessionId);
    if (session == null || session.issueType != GridIssueTypes.session) return;
    final rawWorkKey = session.metadata[SessionBeadKeys.workBead];
    if (rawWorkKey is! String) return;

    final parsed = StationTrajectoryRecorder.parseLegacyWorkKey(rawWorkKey);
    if (parsed.workBeadId != workBeadId) return;
    final original = rawWorkKey == workBeadId;
    final parsedRound = parsed.round;
    final rework =
        parsedRound != null &&
        rawWorkKey == reworkKeyFor(workBeadId, parsedRound);
    final voided = rawWorkKey == voidKeyFor(workBeadId, sessionId);
    if (!original && !rework && !voided) return;
    if (session.isClosed && !voided) return;

    final exposedRound = original ? 0 : (rework ? parsedRound : null);
    final oldRound = _roundBySession.putIfAbsent(
      sessionId,
      () => exposedRound ?? 0,
    );
    _recorder.seedSessionAttempt(sessionId, attemptId);
    if (exposedRound != null) {
      _recorder.seedRound(sessionId, oldRound);
    }

    final services = _services();
    final halt = services.trajectoryAdmissionHalt;
    if (halt == null) {
      throw StateError('liveness-loss recovery requires the cut trajectory');
    }

    if (!session.isClosed) {
      await services.admission.retireLostSession(
        workBeadId: workBeadId,
        sessionId: sessionId,
        attemptId: attemptId,
        services: _transportServices,
      );
    }

    final result = await _recorder.sessionVoided(
      sessionId: sessionId,
      workBeadId: workBeadId,
      reason: 'attempt-liveness-lost',
    );
    await halt.handleTerminalResult(result, recordClass: 'attempt.terminal');
    switch (result) {
      case Acked():
        break;
      case Dropped():
        throw StateError('liveness-loss terminal testimony was dropped');
      case Suppressed():
        throw StateError('liveness-loss terminal testimony was suppressed');
    }

    _recorder.roundRetired(
      sessionId: sessionId,
      cause: RoundRetireCause.voided,
      oldRound: oldRound,
    );
    _roundBySession.remove(sessionId);
    try {
      _transportServices.transport?.flare('attempt.liveness.lost', {
        'workBeadId': workBeadId,
        'sessionId': sessionId,
        'attemptId': attemptId,
      });
    } on Object {
      // Observability cannot undo durable retirement.
    }
  }
}
