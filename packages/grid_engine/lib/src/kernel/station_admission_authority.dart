import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../bridge/trust_guard.dart';
import '../domain/joined_snapshot.dart';
import '../domain/linked_sessions.dart';
import '../domain/mount_attempt.dart';
import '../domain/mount_eligibility.dart';
import '../domain/rework.dart';
import '../domain/session_bead.dart';
import '../domain/session_disposition.dart';
import '../domain/session_projection.dart';
import '../domain/substation_config.dart';
import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/circuit.dart';

/// A work bead and the session projection that must ride with its mount.
final class StationAdmissionCandidate {
  const StationAdmissionCandidate({required this.bead, required this.session});

  /// The structurally participating work bead being evaluated.
  final Bead bead;

  /// The joined live, terminal, voided, or retired-round projection, if any.
  final SessionProjection? session;
}

/// One candidate whose station and substation capacity has been reserved.
final class StationAdmissionReservation {
  const StationAdmissionReservation({
    required this.candidate,
    required this.substationId,
    required this.mountAttempt,
    required this.sessionId,
    required this.adopted,
  });

  /// The candidate whose capacity is synchronously held.
  final StationAdmissionCandidate candidate;

  /// The substation scope that owns this reservation.
  final String substationId;

  /// The durable mount-attempt ordinal, only for a newly recorded mount.
  final int? mountAttempt;

  /// The adopted or newly created session id, once one exists.
  final String? sessionId;

  /// Whether [sessionId] was adopted from the supplied snapshot.
  final bool adopted;
}

/// A fail-closed admission answer carrying its named clause and explanation.
final class StationAdmissionRefusal {
  const StationAdmissionRefusal({
    required this.candidate,
    required this.clause,
    required this.detail,
  });

  /// The candidate that failed closed.
  final StationAdmissionCandidate candidate;

  /// The stable refusal category.
  final String clause;

  /// The human-readable refusal explanation.
  final String detail;
}

/// The immutable result of one synchronous admission request.
final class StationAdmissionBatch {
  StationAdmissionBatch({
    required List<StationAdmissionReservation> admitted,
    required List<StationAdmissionCandidate> waiting,
    required List<StationAdmissionRefusal> refused,
  }) : admitted = List<StationAdmissionReservation>.unmodifiable(admitted),
       waiting = List<StationAdmissionCandidate>.unmodifiable(waiting),
       refused = List<StationAdmissionRefusal>.unmodifiable(refused);

  /// Reservations that may mount now.
  final List<StationAdmissionReservation> admitted;

  /// Candidates held behind capacity or an in-flight mount-attempt write.
  final List<StationAdmissionCandidate> waiting;

  /// Candidates rejected by a fail-closed clause.
  final List<StationAdmissionRefusal> refused;
}

/// Signals that a freshly-created session was durably voided after its pour
/// timed out. The caller records its existing Stage-1 observations and waits
/// for the authority's invalidation instead of parking the retired session.
final class StationMintVoided implements Exception {
  const StationMintVoided({
    required this.workBeadId,
    required this.retiredSessionId,
  });

  /// The work bead whose timed-out attempt was retired.
  final String workBeadId;

  /// The session id that was durably voided and closed.
  final String retiredSessionId;

  @override
  String toString() =>
      'StationMintVoided($workBeadId, retiredSessionId: $retiredSessionId)';
}

typedef _ScopeKey = ({String stateSubstation, String substationId});

enum _MountAttemptWriteState { writing, recorded }

final class _UnsnapshottedReservation {
  _UnsnapshottedReservation({
    required this.scopeKey,
    required this.mountAttempt,
    required this.writeState,
  });

  final _ScopeKey scopeKey;
  final int? mountAttempt;
  _MountAttemptWriteState writeState;
  String? sessionId;
  bool minting = false;
}

/// All mutable admission state for one station/substation scope.
///
/// These names deliberately remain the incumbent bead-backed latches. Stage 3
/// replaces their medium; this in-process cut only moves their ownership. The
/// retained void transition still writes `grid.voided_reason`.
final class _AdmissionScopeState {
  final Set<String> _mountedIds = <String>{};
  final Set<String> _mountAttemptsScheduled = <String>{};
  final Map<String, String> _mountEligibilityRefusals = <String, String>{};
  final Set<({String beadId, String clause})> _mountEligibilityRechecks =
      <({String beadId, String clause})>{};
  Timer? _mountEligibilityRecheckTimer;
  final Set<String> _trustRefusedReported = <String>{};
  final Set<String> _surplusRetiresScheduled = <String>{};
  final Set<String> _surplusAliveReported = <String>{};
  final Set<String> _sessionAmbiguityReported = <String>{};
  final Set<String> _gateSweepsScheduled = <String>{};
  String? _capacityWaitingSignature;
}

/// The single station-owned answer to “may this attempt start now?”.
///
/// The authority owns synchronous station/substation reservations and all
/// durable attempt transitions. It receives immutable values, never a tree
/// context, and composes the existing mount-eligibility and trust policies.
final class StationAdmissionAuthority {
  /// Creates the one in-process admission owner for a station.
  StationAdmissionAuthority({
    required StationBeadWriter writer,
    required String stateSubstation,
    required int maxConcurrentWork,
    AllocationLiveness? liveness,
  }) : _writer = writer,
       _stateSubstation = stateSubstation,
       _maxConcurrentWork = maxConcurrentWork,
       _liveness = liveness ?? neverLive;

  final StationBeadWriter _writer;
  final String _stateSubstation;
  final int _maxConcurrentWork;
  final AllocationLiveness _liveness;

  final Map<_ScopeKey, _AdmissionScopeState> _scopes =
      <_ScopeKey, _AdmissionScopeState>{};
  final Map<String, _UnsnapshottedReservation> _reservations =
      <String, _UnsnapshottedReservation>{};
  final Map<String, _ScopeKey> _lastScopeByBead = <String, _ScopeKey>{};
  final Map<String, _ScopeKey> _scopeBySessionId = <String, _ScopeKey>{};
  final Map<Object, void Function()> _listeners = <Object, void Function()>{};
  final Map<String, Timer> _retryTimers = <String, Timer>{};
  final Map<String, Future<void>> _mountAttemptWrites =
      <String, Future<void>>{};
  final Set<String> _retryBlocked = <String>{};
  bool _disposed = false;

  /// Adds a station-lifetime invalidation callback and returns an idempotent
  /// remover. No mutable authority state is exposed through this hook.
  void Function() addInvalidationListener(void Function() listener) {
    if (_disposed) return () {};
    final token = Object();
    _listeners[token] = listener;
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      _listeners.remove(token);
    };
  }

  /// Answers one substation's pending candidates synchronously.
  StationAdmissionBatch admitPending(
    JoinedSnapshot snapshot,
    SubstationConfig config,
    ServiceBundle services,
    Iterable<StationAdmissionCandidate> candidates,
  ) {
    final supplied = candidates.toList(growable: false);
    if (_disposed) {
      return StationAdmissionBatch(
        admitted: const [],
        waiting: const [],
        refused: [
          for (final candidate in supplied)
            StationAdmissionRefusal(
              candidate: candidate,
              clause: 'disposed',
              detail: 'the station admission authority is disposed',
            ),
        ],
      );
    }

    final scopeKey = (
      stateSubstation: _stateSubstation,
      substationId: config.substationId,
    );
    final scope = _scopes.putIfAbsent(scopeKey, _AdmissionScopeState.new);
    final suppliedIds = {for (final candidate in supplied) candidate.bead.id};

    // Structural unmount is a release. This is scoped, so another WorkList's
    // request can never release a reservation it does not own.
    for (final beadId in scope._mountedIds.difference(suppliedIds).toList()) {
      _release(beadId, onlyScope: scopeKey);
    }
    for (final candidate in supplied) {
      if (candidate.session?.isTerminal == true) {
        final reservation = _reservations[candidate.bead.id];
        final terminalId = candidate.session?.sessionId;
        if (reservation == null || reservation.sessionId == terminalId) {
          _release(candidate.bead.id, onlyScope: scopeKey);
        }
      }
    }
    // Existing durable work consumes this substation's cap regardless of its
    // position in the pending priority order below.
    for (final candidate in supplied) {
      if (candidate.session case final session? when !session.isTerminal) {
        scope._mountedIds.add(candidate.bead.id);
      }
    }

    final durableRows = <String, SessionProjection>{};
    for (final entry in snapshot.sessionsByWorkBead.entries) {
      final row = entry.value;
      final id = row.sessionId;
      durableRows[id != null && id.isNotEmpty ? id : 'work:${entry.key}'] = row;
    }
    for (final entry in snapshot.surplusSessionsByWorkBead.entries) {
      for (var index = 0; index < entry.value.length; index++) {
        final row = entry.value[index];
        final id = row.sessionId;
        durableRows[id != null && id.isNotEmpty
                ? id
                : 'work:${entry.key}:surplus:$index'] =
            row;
      }
    }
    final durableLiveIds = {
      for (final entry in durableRows.entries)
        if (!entry.value.isTerminal) entry.key,
    };

    // A reservation represented by its now-terminal durable row has settled.
    for (final entry in _reservations.entries.toList()) {
      final sessionId = entry.value.sessionId;
      if (sessionId != null && durableRows[sessionId]?.isTerminal == true) {
        _release(entry.key);
      }
    }

    final ordered = supplied.toList()
      ..sort((a, b) {
        final byPriority = a.bead.priority.compareTo(b.bead.priority);
        return byPriority != 0 ? byPriority : a.bead.id.compareTo(b.bead.id);
      });
    final admitted = <StationAdmissionReservation>[];
    final waiting = <StationAdmissionCandidate>[];
    final capacityWaiting = <StationAdmissionCandidate>[];
    final refused = <StationAdmissionRefusal>[];

    for (final candidate in ordered) {
      final bead = candidate.bead;
      _lastScopeByBead[bead.id] = scopeKey;
      final projectedSessionId = candidate.session?.sessionId;
      if (projectedSessionId != null && projectedSessionId.isNotEmpty) {
        _scopeBySessionId[projectedSessionId] = scopeKey;
      }
      final eligibility = _evaluateEligibility(
        snapshot,
        config,
        services,
        bead,
      );
      switch (eligibility) {
        case MountRefused(:final clause):
          _release(bead.id, onlyScope: scopeKey);
          _noteEligibilityRefusal(scope, services, bead.id, clause);
          refused.add(
            StationAdmissionRefusal(
              candidate: candidate,
              clause: _clauseName(clause),
              detail: clause,
            ),
          );
          continue;
        case MountEligible():
          _noteEligibilityRestored(scope, services, bead.id);
      }

      final trustRefusal = _trustRefusal(snapshot, services, bead);
      if (trustRefusal != null) {
        _release(bead.id, onlyScope: scopeKey);
        _reportTrustRefused(scope, services, bead, trustRefusal);
        refused.add(
          StationAdmissionRefusal(
            candidate: candidate,
            clause: 'trust',
            detail: trustRefusal,
          ),
        );
        continue;
      }

      if (_retryBlocked.contains(bead.id)) {
        waiting.add(candidate);
        continue;
      }

      final linked = snapshot.linkedSessions(bead.id);
      final verdict = linkedSessionVerdictOf(linked);
      if (bead.isClosed) {
        final disposition = sessionDispositionOf(verdict.winner);
        if (disposition is! LiveSession) {
          _release(bead.id, onlyScope: scopeKey);
        }
        final clause = switch (disposition) {
          LiveSession() => 'work-terminal',
          HeldSession() => 'held',
          DoneSession() => 'done',
          NoSession() || VoidedSession() => 'work-terminal',
        };
        refused.add(
          StationAdmissionRefusal(
            candidate: candidate,
            clause: clause,
            detail: 'the work bead is terminal',
          ),
        );
        continue;
      }
      switch (verdict) {
        case AdoptLinkedSession(:final session, :final rivals):
          if (rivals.isNotEmpty) {
            _reportDuplicateLive(scope, services, bead.id, session, rivals);
            _release(bead.id, onlyScope: scopeKey);
            refused.add(
              StationAdmissionRefusal(
                candidate: candidate,
                clause: 'duplicate-live',
                detail: 'more than one live durable session links this bead',
              ),
            );
            continue;
          }
          final sessionId = session.sessionId;
          if (sessionId == null || sessionId.isEmpty) {
            // A hand-built/offline projection can represent a live round
            // without its bead id. It remains mounted and capacity-counted,
            // but is not called an adoption (public adoptions always carry an
            // id) and can never enter session-creation I/O.
            scope._mountedIds.add(bead.id);
            admitted.add(
              StationAdmissionReservation(
                candidate: StationAdmissionCandidate(
                  bead: bead,
                  session: session,
                ),
                substationId: config.substationId,
                mountAttempt: null,
                sessionId: null,
                adopted: false,
              ),
            );
            continue;
          }
          scope._mountedIds.add(bead.id);
          admitted.add(
            StationAdmissionReservation(
              candidate: StationAdmissionCandidate(
                bead: bead,
                session: session,
              ),
              substationId: config.substationId,
              mountAttempt: null,
              sessionId: sessionId,
              adopted: true,
            ),
          );
          continue;
        case BlockedLinkedSession(:final session):
          _release(bead.id, onlyScope: scopeKey);
          final disposition = sessionDispositionOf(session);
          final name = disposition is HeldSession ? 'held' : 'done';
          refused.add(
            StationAdmissionRefusal(
              candidate: candidate,
              clause: name,
              detail: 'the linked session is a blocking terminal ($name)',
            ),
          );
          continue;
        case RemintLinkedSession(:final session, :final surplus):
          final winnerAlive = staleFences(session).where(_liveness).toList();
          if (winnerAlive.isNotEmpty) {
            _reportVoidRefused(scope, services, bead.id, session, winnerAlive);
            _release(bead.id, onlyScope: scopeKey);
            refused.add(
              StationAdmissionRefusal(
                candidate: candidate,
                clause: 'live-fence',
                detail: 'a voided linked session still has a live process',
              ),
            );
            continue;
          }
          final aliveSurplus = surplus
              .where((row) => staleFences(row).any(_liveness))
              .toList();
          if (aliveSurplus.isNotEmpty) {
            _reportSurplusAlive(scope, services, bead.id, aliveSurplus);
            _release(bead.id, onlyScope: scopeKey);
            refused.add(
              StationAdmissionRefusal(
                candidate: candidate,
                clause: 'live-fence',
                detail: 'a surplus terminal session still has a live process',
              ),
            );
            continue;
          }
          if (surplus.isNotEmpty) {
            unawaited(
              retireSurplusSessions(
                workBeadId: bead.id,
                keptSessionId: session.sessionId ?? '',
                surplus: surplus,
                services: services,
              ),
            );
          }
        case NoLinkedSession():
          break;
      }

      var reservation = _reservations[bead.id];
      if (reservation != null && reservation.scopeKey != scopeKey) {
        waiting.add(candidate);
        capacityWaiting.add(candidate);
        continue;
      }
      if (reservation != null) {
        scope._mountedIds.add(bead.id);
        if (reservation.writeState == _MountAttemptWriteState.writing) {
          waiting.add(candidate);
        } else {
          admitted.add(_reservationValue(candidate, reservation));
        }
        continue;
      }

      // A mounted branch can need a fresh session reservation across the
      // close/re-key gap without spending another durable mount attempt.
      final retiredRound =
          candidate.session != null &&
          reworkRoundOf(bead.id, candidate.session!.workBeadId) != null;
      final alreadyMounted =
          scope._mountedIds.contains(bead.id) || retiredRound;
      if (!_hasCapacity(
        scope,
        config,
        durableLiveIds,
        candidateAlreadyCounted: alreadyMounted,
      )) {
        waiting.add(candidate);
        capacityWaiting.add(candidate);
        continue;
      }
      if (alreadyMounted) {
        reservation = _UnsnapshottedReservation(
          scopeKey: scopeKey,
          mountAttempt: null,
          writeState: _MountAttemptWriteState.recorded,
        );
        _reservations[bead.id] = reservation;
        admitted.add(_reservationValue(candidate, reservation));
        continue;
      }

      final attempt =
          (snapshot.mountAttemptsByWorkBead[bead.id]?.count ?? 0) + 1;
      reservation = _UnsnapshottedReservation(
        scopeKey: scopeKey,
        mountAttempt: attempt,
        writeState: _MountAttemptWriteState.writing,
      );
      _reservations[bead.id] = reservation;
      scope._mountedIds.add(bead.id);
      waiting.add(candidate);
      _scheduleMountAttempt(scope, services, bead.id, attempt, reservation);
    }

    final capacityWaitingSignature = capacityWaiting
        .map((entry) => entry.bead.id)
        .join(',');
    if (capacityWaiting.isNotEmpty &&
        scope._capacityWaitingSignature != capacityWaitingSignature) {
      _flare(services, 'work.throttled', {
        'count': '${capacityWaiting.length}',
        'beadIds': capacityWaitingSignature,
      });
    }
    scope._capacityWaitingSignature = capacityWaiting.isEmpty
        ? null
        : capacityWaitingSignature;
    return StationAdmissionBatch(
      admitted: admitted,
      waiting: waiting,
      refused: refused,
    );
  }

  MountEligibilityDecision _evaluateEligibility(
    JoinedSnapshot snapshot,
    SubstationConfig config,
    ServiceBundle services,
    Bead bead,
  ) {
    final predicate = composeMountEligibility([
      dispatchableWorkClause(resident: config.resident),
      driveListClause(config.driveList),
      crossLinkExclusionClause(
        snapshot.frontierExclusionsByBeadId,
        snapshot.sessionsByWorkBead,
      ),
      mountAttemptClause(snapshot.mountAttemptsByWorkBead),
    ], services.mountEligibility);
    try {
      return predicate(bead);
    } on Object catch (error) {
      return MountEligibilityDecision.refused(
        clause:
            'mount eligibility evaluation failed: ${truncateReason('$error')}',
      );
    }
  }

  String? _trustRefusal(
    JoinedSnapshot snapshot,
    ServiceBundle services,
    Bead bead,
  ) {
    if (services.trust == null) return null;
    final reasons = <String>[];
    final accepted = applyTrustGuard(
      candidates: {bead.id},
      beadsById: snapshot.graph.beadsById,
      floor: services.trustFloor,
      trustConfigured: true,
      onUnresolved: reasons.add,
    );
    return accepted.contains(bead.id) ? null : reasons.single;
  }

  bool _hasCapacity(
    _AdmissionScopeState scope,
    SubstationConfig config,
    Set<String> durableLiveIds, {
    required bool candidateAlreadyCounted,
  }) {
    final unsnapshotted = _reservations.values.where((reservation) {
      final sessionId = reservation.sessionId;
      return sessionId == null || !durableLiveIds.contains(sessionId);
    }).length;
    final stationUsed = durableLiveIds.length + unsnapshotted;
    if (!candidateAlreadyCounted && stationUsed >= _maxConcurrentWork) {
      return false;
    }
    final substationCap = config.maxConcurrentWork ?? _maxConcurrentWork;
    if (!candidateAlreadyCounted && scope._mountedIds.length >= substationCap) {
      return false;
    }
    return true;
  }

  StationAdmissionReservation _reservationValue(
    StationAdmissionCandidate candidate,
    _UnsnapshottedReservation reservation,
  ) => StationAdmissionReservation(
    candidate: candidate,
    substationId: reservation.scopeKey.substationId,
    mountAttempt: reservation.mountAttempt,
    sessionId: reservation.sessionId,
    adopted: false,
  );

  void _scheduleMountAttempt(
    _AdmissionScopeState scope,
    ServiceBundle services,
    String workBeadId,
    int attempt,
    _UnsnapshottedReservation reservation,
  ) {
    final latch = '$workBeadId:$attempt';
    final Future<void> write;
    if (scope._mountAttemptsScheduled.add(latch)) {
      final completer = Completer<void>();
      write = completer.future;
      _mountAttemptWrites[latch] = write;
      scheduleMicrotask(() async {
        try {
          await _writer.recordMountAttempt(
            substation: _stateSubstation,
            workBeadId: workBeadId,
            attempt: attempt,
            note: 'mount attempt $attempt of $kMaxMountAttempts',
          );
          completer.complete();
        } on Object catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      });
    } else {
      write = _mountAttemptWrites[latch] ?? Future<void>.value();
    }
    scheduleMicrotask(() async {
      try {
        await write;
        if (_disposed || !identical(_reservations[workBeadId], reservation)) {
          return;
        }
        reservation.writeState = _MountAttemptWriteState.recorded;
        _notifyListeners();
      } on Object catch (error) {
        if (!identical(_reservations[workBeadId], reservation)) return;
        _release(workBeadId);
        scope._mountAttemptsScheduled.remove(latch);
        _flare(services, 'work.mountAttemptRecordFailed', {
          'beadId': workBeadId,
          'attempt': '$attempt',
          'reason': truncateReason('$error'),
        });
        _scheduleRetryInvalidation(workBeadId);
      }
    });
  }

  /// Retires a voided dead key after verifying its recorded process fences.
  Future<void> retireVoidedSession({
    required String workBeadId,
    required SessionProjection deadSession,
    required String reason,
  }) async {
    if (staleFences(deadSession).any(_liveness)) {
      throw StateError('void retirement refused: a process fence is live');
    }
    final deadId = deadSession.sessionId ?? '';
    if (deadId.isEmpty) return;
    await _writer.update(
      deadId,
      metadata: voidRetireMetadata(
        workBeadId: workBeadId,
        deadSessionId: deadId,
        reason: reason,
      ),
    );
    _releaseSession(workBeadId, deadId);
    _notifyListeners();
  }

  /// Creates and binds the session for an already-recorded reservation.
  Future<({String? sessionId, StationAdmissionRefusal? refusal})>
  createSessionAttempt(
    JoinedSnapshot snapshot,
    StationAdmissionCandidate candidate, {
    required String title,
    required Map<String, String> metadata,
  }) async {
    final live = <String, SessionProjection>{};
    final linked = snapshot.linkedSessions(candidate.bead.id);
    for (var index = 0; index < linked.length; index += 1) {
      final row = linked[index];
      final id = row.sessionId;
      if (!row.isTerminal) {
        live[id != null && id.isNotEmpty ? id : 'anonymous:$index'] = row;
      }
    }
    if (live.length > 1) {
      return (
        sessionId: null,
        refusal: StationAdmissionRefusal(
          candidate: candidate,
          clause: 'duplicate-live',
          detail: 'more than one live durable session links this bead',
        ),
      );
    }
    if (live.isNotEmpty) {
      return (
        sessionId: null,
        refusal: StationAdmissionRefusal(
          candidate: candidate,
          clause: 'live-attempt',
          detail: 'a live durable attempt already links this bead',
        ),
      );
    }
    final reservation = _reservations[candidate.bead.id];
    if (reservation == null ||
        reservation.writeState != _MountAttemptWriteState.recorded ||
        reservation.sessionId != null ||
        reservation.minting) {
      return (
        sessionId: null,
        refusal: StationAdmissionRefusal(
          candidate: candidate,
          clause: 'missing-reservation',
          detail: 'no recorded, unconsumed admission reservation exists',
        ),
      );
    }
    reservation.minting = true;
    try {
      final id = await _writer.createSession(
        substation: _stateSubstation,
        title: title,
        workBeadId: candidate.bead.id,
        metadata: metadata,
      );
      reservation.sessionId = id;
      _scopeBySessionId[id] = reservation.scopeKey;
      _notifyListeners();
      return (sessionId: id, refusal: null);
    } finally {
      reservation.minting = false;
    }
  }

  /// Pours a fresh or orphaned molecule, durably voiding only a raw Dart
  /// timeout that belongs to this bead's freshly-created reservation.
  Future<Map<String, String>> pourMolecule(
    GraphApplyPlan plan, {
    required String workBeadId,
    required String sessionId,
    required Iterable<String> rootCrumbs,
  }) async {
    try {
      final result = await _writer.createMolecule(
        plan,
        substation: _stateSubstation,
        sessionId: sessionId,
        rootCrumbs: rootCrumbs,
      );
      _notifyListeners();
      return result;
    } on TimeoutException {
      final reservation = _reservations[workBeadId];
      if (reservation?.sessionId != sessionId) rethrow;
      try {
        await _writer.reapMolecule(sessionId: sessionId);
      } on Object {
        // Best effort: durable void + close remains the release fence.
      }
      await _writer.update(
        sessionId,
        metadata: voidRetireMetadata(
          workBeadId: workBeadId,
          deadSessionId: sessionId,
          reason: 'mint-timeout',
        ),
      );
      await _writer.close(sessionId, reason: 'mint-timeout');
      _release(workBeadId);
      _scheduleRetryInvalidation(workBeadId);
      throw StationMintVoided(
        workBeadId: workBeadId,
        retiredSessionId: sessionId,
      );
    }
  }

  /// Writes the completion marker when [outcomeMarked] is false; on the true
  /// call, optionally reaps, closes, and releases the attempt.
  Future<void> completeSession({
    required String workBeadId,
    required String sessionId,
    required bool outcomeMarked,
    required bool reapMolecule,
    required ServiceBundle services,
  }) async {
    if (!outcomeMarked) {
      await _writer.update(sessionId, metadata: sessionCompleteMetadata());
      _notifyListeners();
      return;
    }
    if (reapMolecule) {
      await _bestEffortReap(sessionId, 'positive-terminal', services);
    }
    await _writer.close(sessionId);
    _releaseSession(workBeadId, sessionId);
    _notifyListeners();
  }

  /// Closes a reworked round and its open gates, releasing only after close.
  Future<void> closeRetiredReworkSession({
    required String workBeadId,
    required String sessionId,
    required bool reapMolecule,
    required ServiceBundle services,
  }) async {
    if (reapMolecule) {
      await _bestEffortReap(sessionId, 'reworked', services);
    }
    await _writer.closeSessionAndOpenGatesForTerminal(
      sessionId: sessionId,
      closeReason: 'reworked',
      trigger: GateCloseCause.supersededRound,
    );
    _releaseSession(workBeadId, sessionId);
    _notifyListeners();
  }

  /// Settles a live session whose work bead went terminal, including its gate
  /// sweep, and releases only after the whole writer transition succeeds.
  Future<void> settleWorkTerminalSession({
    required Bead terminalWorkBead,
    required String sessionId,
    required ServiceBundle services,
  }) async {
    final scope = _scopeForBead(terminalWorkBead.id);
    final latch = '$sessionId:${GateCloseCause.workBeadClosed.wireValue}';
    if (scope != null && !scope._gateSweepsScheduled.add(latch)) return;
    try {
      await _writer.closeOpenGatesForTerminal(
        sessionId: sessionId,
        trigger: GateCloseCause.workBeadClosed,
        disposition: GateSweepSessionDisposition.live,
        terminalWorkBead: terminalWorkBead,
      );
      _releaseSession(terminalWorkBead.id, sessionId);
      _notifyListeners();
    } on Object {
      rethrow;
    }
  }

  /// Marks a suspicious rework decline and deliberately keeps it counted.
  Future<void> markReworkDeclined({
    required String workBeadId,
    required String sessionId,
    required String reason,
  }) async {
    await _writer.update(
      sessionId,
      metadata: {
        SessionBeadKeys.reworkDeclined: 'true',
        SessionBeadKeys.reworkDeclinedReason: reason,
      },
    );
    _notifyListeners();
  }

  /// Marks a breaker escalation, optionally reaps, closes, then releases.
  Future<void> escalateAndCloseSession({
    required String workBeadId,
    required String sessionId,
    required String reason,
    required bool reapMolecule,
    required ServiceBundle services,
  }) async {
    await _writer.update(
      sessionId,
      metadata: {
        SessionBeadKeys.escalation: 'breaker-exhausted',
        if (reason.isNotEmpty) SessionBeadKeys.escalationReason: reason,
      },
    );
    if (reapMolecule) {
      await _bestEffortReap(sessionId, 'breaker-exhausted', services);
    }
    await _writer.close(sessionId, reason: 'breaker-exhausted');
    _releaseSession(workBeadId, sessionId);
    _notifyListeners();
  }

  /// Closes gates for an already-terminal session without making admission.
  Future<void> closeTerminalGates({
    required String sessionId,
    required GateCloseCause cause,
    required GateSweepSessionDisposition disposition,
    required ServiceBundle services,
  }) async {
    final scope = _scopeForSession(sessionId);
    final latch = '$sessionId:${cause.wireValue}';
    if (scope != null && !scope._gateSweepsScheduled.add(latch)) return;
    await _writer.closeOpenGatesForTerminal(
      sessionId: sessionId,
      trigger: cause,
      disposition: disposition,
    );
    _notifyListeners();
  }

  /// Demotes terminal-only surplus linked rows through the incumbent void-key
  /// shape. A live rival is refused and never rewritten.
  Future<void> retireSurplusSessions({
    required String workBeadId,
    required String keptSessionId,
    required List<SessionProjection> surplus,
    required ServiceBundle services,
  }) async {
    final ordered = orderLinkedSessions(surplus);
    final verdict = linkedSessionVerdictOf(ordered);
    if (verdict is AdoptLinkedSession) return;
    final scope = _scopeForBead(workBeadId);
    for (final row in ordered) {
      final deadId = row.sessionId ?? '';
      if (deadId.isEmpty || !row.isTerminal) continue;
      if (staleFences(row).any(_liveness)) {
        if (scope != null) {
          _reportSurplusAlive(scope, services, workBeadId, [row]);
        }
        continue;
      }
      if (scope != null && !scope._surplusRetiresScheduled.add(deadId)) {
        continue;
      }
      final reason =
          'surplus linked session: "$workBeadId" keeps "$keptSessionId"; '
          'this closed row was demoted so the join stays single-valued';
      try {
        await _writer.update(
          deadId,
          metadata: voidRetireMetadata(
            workBeadId: workBeadId,
            deadSessionId: deadId,
            reason: reason,
          ),
        );
        _flare(services, 'work.sessionSurplusRetired', {
          'beadId': workBeadId,
          'sessionId': deadId,
          'workBeadKey': voidKeyFor(workBeadId, deadId),
          'keptSessionId': keptSessionId,
        });
        _notifyListeners();
      } on Object catch (error) {
        _flare(services, 'work.sessionSurplusRetireFailed', {
          'beadId': workBeadId,
          'sessionId': deadId,
          'reason': truncateReason('$error'),
        });
      }
    }
  }

  Future<void> _bestEffortReap(
    String sessionId,
    String closeReason,
    ServiceBundle services,
  ) async {
    try {
      await _writer.reapMolecule(sessionId: sessionId);
    } on Object catch (error) {
      _flare(services, 'session.moleculeReapFailed', {
        'sessionId': sessionId,
        'closeReason': closeReason,
        'reason': truncateReason('$error'),
      });
    }
  }

  void _noteEligibilityRefusal(
    _AdmissionScopeState scope,
    ServiceBundle services,
    String beadId,
    String clause,
  ) {
    final former = scope._mountEligibilityRefusals[beadId];
    scope._mountEligibilityRefusals[beadId] = clause;
    if (scope._mountEligibilityRechecks.add((beadId: beadId, clause: clause))) {
      scope._mountEligibilityRecheckTimer ??= Timer(Duration.zero, () {
        scope._mountEligibilityRecheckTimer = null;
        _notifyListeners();
      });
    }
    if (former != clause) {
      _flare(services, 'work.mountEligibilityRefused', {
        'beadId': beadId,
        'clause': clause,
      });
    }
  }

  void _noteEligibilityRestored(
    _AdmissionScopeState scope,
    ServiceBundle services,
    String beadId,
  ) {
    scope._mountEligibilityRechecks.removeWhere(
      (entry) => entry.beadId == beadId,
    );
    final former = scope._mountEligibilityRefusals.remove(beadId);
    if (former != null) {
      _flare(services, 'work.mountEligibilityRestored', {
        'beadId': beadId,
        'clause': former,
      });
    }
  }

  void _reportTrustRefused(
    _AdmissionScopeState scope,
    ServiceBundle services,
    Bead bead,
    String reason,
  ) {
    if (!scope._trustRefusedReported.add(bead.id)) return;
    final scheme = bead.metadata[OriginTrustKeys.scheme];
    final actor = bead.metadata[OriginTrustKeys.actor];
    final origin =
        scheme is String &&
            scheme.isNotEmpty &&
            actor is String &&
            actor.isNotEmpty
        ? '$scheme:$actor'
        : 'malformed';
    _flare(services, 'work.trustRefused', {
      'beadId': bead.id,
      'origin': origin,
      'floor': services.trustFloor.level.name,
      'reason': reason,
    });
  }

  void _reportDuplicateLive(
    _AdmissionScopeState scope,
    ServiceBundle services,
    String beadId,
    SessionProjection winner,
    List<SessionProjection> rivals,
  ) {
    if (!scope._sessionAmbiguityReported.add(beadId)) return;
    _flare(services, 'work.duplicateLiveRefused', {
      'beadId': beadId,
      'sessionId': winner.sessionId ?? '',
      'rivalSessionIds': rivals.map((row) => row.sessionId ?? '').join(','),
    });
  }

  void _reportSurplusAlive(
    _AdmissionScopeState scope,
    ServiceBundle services,
    String beadId,
    List<SessionProjection> alive,
  ) {
    if (!scope._surplusAliveReported.add(beadId)) return;
    _flare(services, 'work.sessionSurplusAlive', {
      'beadId': beadId,
      'sessionIds': alive.map((row) => row.sessionId ?? '').join(','),
    });
  }

  void _reportVoidRefused(
    _AdmissionScopeState scope,
    ServiceBundle services,
    String beadId,
    SessionProjection session,
    List<AdoptFence> alive,
  ) {
    if (!scope._surplusAliveReported.add(beadId)) return;
    _flare(services, 'session.voidRefused', {
      'workBeadId': beadId,
      'deadSessionId': session.sessionId ?? '',
      'pgids': alive.map((fence) => '${fence.pgid}').join(','),
      'reason': 'a voided session still records a live process fence',
    });
  }

  _AdmissionScopeState? _scopeForBead(String beadId) {
    final key = _lastScopeByBead[beadId];
    return key == null ? null : _scopes[key];
  }

  _AdmissionScopeState? _scopeForSession(String sessionId) {
    final key = _scopeBySessionId[sessionId];
    return key == null ? null : _scopes[key];
  }

  void _release(String workBeadId, {_ScopeKey? onlyScope}) {
    final reservation = _reservations[workBeadId];
    if (onlyScope != null &&
        reservation != null &&
        reservation.scopeKey != onlyScope) {
      return;
    }
    if (reservation != null) _reservations.remove(workBeadId);
    if (onlyScope != null) {
      _scopes[onlyScope]?._mountedIds.remove(workBeadId);
    } else {
      for (final scope in _scopes.values) {
        scope._mountedIds.remove(workBeadId);
      }
    }
  }

  void _releaseSession(String workBeadId, String sessionId) {
    final reservation = _reservations[workBeadId];
    // A reworked/voided predecessor can close while a reservation for the next
    // round is already held. Never release that successor reservation.
    if (reservation != null && reservation.sessionId != sessionId) return;
    _release(workBeadId);
  }

  void _scheduleRetryInvalidation(String workBeadId) {
    if (_disposed || _retryTimers.containsKey(workBeadId)) return;
    _retryBlocked.add(workBeadId);
    _retryTimers[workBeadId] = Timer(Backoff.standard.delayFor(1), () {
      _retryTimers.remove(workBeadId);
      _retryBlocked.remove(workBeadId);
      _notifyListeners();
    });
  }

  void _notifyListeners() {
    if (_disposed) return;
    for (final listener in _listeners.values.toList(growable: false)) {
      try {
        listener();
      } on Object {
        // Integration listeners cannot turn a completed durable transition
        // back into a failed one.
      }
    }
  }

  static String _clauseName(String detail) {
    final colon = detail.indexOf(':');
    return colon < 0 ? detail : detail.substring(0, colon);
  }

  static void _flare(
    ServiceBundle services,
    String name,
    Map<String, String> data,
  ) {
    try {
      services.transport?.flare(name, data);
    } on Object {
      // Observability never breaks admission or a durable transition.
    }
  }

  /// Cancels timers/listeners and makes future requests fail closed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final scope in _scopes.values) {
      scope._mountEligibilityRecheckTimer?.cancel();
      scope._mountEligibilityRecheckTimer = null;
    }
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryBlocked.clear();
    _mountAttemptWrites.clear();
    _lastScopeByBead.clear();
    _scopeBySessionId.clear();
    _listeners.clear();
  }
}
