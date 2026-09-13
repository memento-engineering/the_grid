import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../bridge/trust_guard.dart';
import '../diagnostics/state_store_deadline.dart';
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
import 'trajectory_scope.dart';

/// A read-only station admission snapshot for operator status surfaces.
///
/// Only bead identities, refusal clauses, and reservation/refusal timing cross
/// this boundary. Candidate bodies and mutable authority state remain private.
final class StationAdmissionStatus {
  /// Creates an immutable snapshot of the station admission budget.
  StationAdmissionStatus({
    required this.maxAgents,
    required List<({String bead, String? sessionId, DateTime since})>
    reservations,
    required List<({String bead, String clause, DateTime since})> refusals,
    List<({String bead, String substation, DateTime since})>
        zeroAdmissionWaiters =
        const [],
  }) : reservations = List.unmodifiable(reservations),
       refusals = List.unmodifiable(refusals),
       zeroAdmissionWaiters = List.unmodifiable(zeroAdmissionWaiters);

  /// The station-wide concurrency ceiling.
  final int maxAgents;

  /// Every authority-owned reservation, including pre-session reservations.
  final List<({String bead, String? sessionId, DateTime since})> reservations;

  /// Every currently active mount-eligibility refusal across all scopes.
  final List<({String bead, String clause, DateTime since})> refusals;

  /// Pending work in every scope whose latest admission pass admitted zero.
  final List<({String bead, String substation, DateTime since})>
  zeroAdmissionWaiters;
}

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
    required this.reservationToken,
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

  /// Opaque in-process capability for releasing an unconsumed reservation.
  ///
  /// The authority compares this value by identity. Adopted, anonymous-live,
  /// and offline reservations carry null because they own no releasable
  /// unsnapshotted grant.
  final Object? reservationToken;
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

  /// Candidates held behind capacity, retry backoff, or another scope's
  /// reservation.
  final List<StationAdmissionCandidate> waiting;

  /// Candidates rejected by a fail-closed clause.
  final List<StationAdmissionRefusal> refused;
}

/// Signals that a freshly-created session was durably voided after its pour
/// reached the state-store mint deadline. The caller records its existing
/// Stage-1 observations and waits for the authority's invalidation instead of
/// parking the retired session.
final class StationMintVoided implements Exception {
  const StationMintVoided({
    required this.workBeadId,
    required this.retiredSessionId,
    required this.cause,
  });

  /// The work bead whose timed-out attempt was retired.
  final String workBeadId;

  /// The session id that was durably voided and closed.
  final String retiredSessionId;

  /// The raw Dart or classified bd pour timeout that triggered compensation.
  final Object cause;

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
    required this.reservationToken,
    required this.since,
    required this.reclaimedSessionId,
  });

  final _ScopeKey scopeKey;
  final int? mountAttempt;
  final Object reservationToken;
  final DateTime since;
  _MountAttemptWriteState writeState;
  String? sessionId;
  String? reclaimedSessionId;
  bool minting = false;
}

/// All mutable admission state for one station/substation scope.
///
/// Stage 3 exclusively owns retirement into trajectory projections and
/// obligation queries: bead-backed mount attempts, structural mounted
/// membership, and admission latches all keep their incumbent media here.
/// This is not that switch; every bead write and flare remains. This correction
/// removes only in-memory report/scheduling suppression for current snapshot
/// facts, so the existing operations run level-triggered on each pass.
/// The retained void transition still writes `grid.voided_reason`.
final class _AdmissionScopeState {
  // Structural branch membership is not represented by JoinedSnapshot.
  final Set<String> _mountedIds = <String>{};
  // Refusal timing and restoration history are not snapshot facts.
  final Map<String, ({String clause, DateTime since})>
  _mountEligibilityRefusals = <String, ({String clause, DateTime since})>{};
  // This timer is the live bounded recheck operation, not a snapshot fact.
  Timer? _mountEligibilityRecheckTimer;
  // First-observed zero-admission timing is not carried by JoinedSnapshot.
  final Map<String, DateTime> _zeroAdmissionSinceByBead = <String, DateTime>{};
  // Started rival-cleanup microtasks are unavailable from JoinedSnapshot.
  final Set<String> _rivalCleanupsInFlight = <String>{};
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
    required RuntimeProvider provider,
    required String stateSubstation,
    required int maxConcurrentWork,
    AllocationLiveness? liveness,
    TrajectoryAdmissionHalt? trajectoryAdmissionHalt,
    DateTime Function()? clock,
  }) : _writer = writer,
       _provider = provider,
       _stateSubstation = stateSubstation,
       _maxConcurrentWork = maxConcurrentWork,
       _liveness = liveness ?? neverLive,
       _clock = clock ?? DateTime.now,
       _trajectoryAdmissionHalt = trajectoryAdmissionHalt {
    _removeTrajectoryAdmissionHaltListener = trajectoryAdmissionHalt
        ?.addListener(_notifyListeners);
  }

  final StationBeadWriter _writer;
  final RuntimeProvider _provider;
  final String _stateSubstation;
  final int _maxConcurrentWork;
  final AllocationLiveness _liveness;
  final DateTime Function() _clock;
  final TrajectoryAdmissionHalt? _trajectoryAdmissionHalt;
  void Function()? _removeTrajectoryAdmissionHaltListener;

  // Per-substation branch and status state is unavailable to one-scope calls.
  final Map<_ScopeKey, _AdmissionScopeState> _scopes =
      <_ScopeKey, _AdmissionScopeState>{};
  // Grants held before their durable session rows appear are not snapshot facts.
  final Map<String, _UnsnapshottedReservation> _reservations =
      <String, _UnsnapshottedReservation>{};
  // Bare bead ids on async entry points cannot derive their substation scope.
  final Map<String, _ScopeKey> _lastScopeByBead = <String, _ScopeKey>{};
  // Registered station consumers are process-local, not snapshot facts.
  final Map<Object, void Function()> _listeners = <Object, void Function()>{};
  // Live backoff operations are process-local, not snapshot facts.
  final Map<String, Timer> _retryTimers = <String, Timer>{};
  // Writes not yet represented by JoinedSnapshot require one shared future.
  final Map<String, Future<void>> _mountAttemptWrites =
      <String, Future<void>>{};
  // Cancellation quarantine persists until a later snapshot proves readiness.
  final Set<String> _blockedUntilFreshReady = <String>{};
  // This flag represents one queued capacity invalidation operation.
  bool _capacityRecheckScheduled = false;
  bool _disposed = false;

  /// Copies the current admission budget and refusal state for status views.
  ///
  /// The returned rows are deterministically ordered and cannot mutate the
  /// authority's private collections.
  StationAdmissionStatus get admissionStatus {
    final reservations = <({String bead, String? sessionId, DateTime since})>[
      for (final entry in _reservations.entries)
        (
          bead: entry.key,
          sessionId: entry.value.sessionId,
          since: entry.value.since,
        ),
    ]..sort((a, b) => a.bead.compareTo(b.bead));
    final refusals =
        <({String bead, String clause, DateTime since})>[
          for (final scope in _scopes.values)
            for (final entry in scope._mountEligibilityRefusals.entries)
              (
                bead: entry.key,
                clause: entry.value.clause,
                since: entry.value.since,
              ),
        ]..sort((a, b) {
          final byBead = a.bead.compareTo(b.bead);
          return byBead != 0 ? byBead : a.clause.compareTo(b.clause);
        });
    final zeroAdmissionWaiters =
        <({String bead, String substation, DateTime since})>[
          for (final scope in _scopes.entries)
            for (final entry in scope.value._zeroAdmissionSinceByBead.entries)
              (
                bead: entry.key,
                substation: scope.key.substationId,
                since: entry.value,
              ),
        ]..sort((a, b) {
          final bySubstation = a.substation.compareTo(b.substation);
          return bySubstation != 0 ? bySubstation : a.bead.compareTo(b.bead);
        });
    return StationAdmissionStatus(
      maxAgents: _maxConcurrentWork,
      reservations: reservations,
      refusals: refusals,
      zeroAdmissionWaiters: zeroAdmissionWaiters,
    );
  }

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

    _reconcileMountAttemptWrites(snapshot);
    _blockedUntilFreshReady.removeWhere(
      (beadId) => !snapshot.graph.beadsById.containsKey(beadId),
    );

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
      } else if (candidate.session?.pauseState == SessionPauseState.paused) {
        _release(candidate.bead.id, onlyScope: scopeKey);
      }
    }
    // Existing durable work consumes this substation's cap regardless of its
    // position in the pending priority order below.
    for (final candidate in supplied) {
      if (candidate.session case final session?
          when !session.isTerminal &&
              session.pauseState == SessionPauseState.none) {
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
        if (!entry.value.isTerminal &&
            entry.value.pauseState != SessionPauseState.paused &&
            (entry.value.pauseState != SessionPauseState.resumed ||
                _isMounted(entry.value.workBeadId)))
          entry.key,
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
      // The candidate carries the join's ordered frontier winner (or a retired
      // re-key). This classifies lifecycle only: the linked-session verdict
      // below still owns rival, disposition, and process-liveness refusals.
      // A mounted branch can need a fresh session reservation across the
      // close/re-key gap without spending another durable mount attempt.
      final retiredRound =
          candidate.session != null &&
          reworkRoundOf(bead.id, candidate.session!.workBeadId) != null;
      final alreadyMounted =
          scope._mountedIds.contains(bead.id) || retiredRound;
      final protectsLiveWork = switch (candidate.session) {
        final session? =>
          !session.isTerminal &&
              session.pauseState == SessionPauseState.none &&
              !retiredRound,
        null => false,
      };
      if (_blockedUntilFreshReady.contains(bead.id)) {
        if (snapshot.graph.readyIds.contains(bead.id) ||
            protectsLiveWork ||
            bead.isClosed) {
          _blockedUntilFreshReady.remove(bead.id);
        } else {
          // The pause-is-a-non-terminal-blocking-disposition precedent keeps
          // released, unmounted rows out of capacity until this authority
          // synchronously readmits them. Keeping this row out of
          // capacityWaiting lets the next ordered candidate claim the returned
          // slot in this same admission flush.
          if (candidate.session case final session?
              when !session.isTerminal &&
                  session.pauseState == SessionPauseState.none) {
            // A live retired round still consumes substation capacity while
            // its fresh successor remains quarantined.
          } else {
            scope._mountedIds.remove(bead.id);
          }
          waiting.add(candidate);
          continue;
        }
      }
      final linked = snapshot.linkedSessions(bead.id);
      final verdict = linkedSessionVerdictOf(linked);
      if (!bead.isClosed && verdict is BlockedLinkedSession) {
        if (sessionDispositionOf(verdict.session) is PausedSession) {
          _release(bead.id, onlyScope: scopeKey);
          refused.add(
            StationAdmissionRefusal(
              candidate: candidate,
              clause: 'paused',
              detail: 'the linked session has blocking disposition paused',
            ),
          );
          continue;
        }
      }
      final eligibility = _evaluateEligibility(
        snapshot,
        config,
        services,
        bead,
      );
      switch (eligibility) {
        case MountRefused(:final clause):
          _noteEligibilityRefusal(scope, services, bead.id, clause);
          if (!protectsLiveWork) {
            _release(bead.id, onlyScope: scopeKey);
            refused.add(
              StationAdmissionRefusal(
                candidate: candidate,
                clause: _clauseName(clause),
                detail: clause,
              ),
            );
            continue;
          }
        case MountEligible():
          _noteEligibilityRestored(scope, services, bead.id);
      }

      final trustRefusal = _trustRefusal(snapshot, services, bead);
      if (trustRefusal != null) {
        _release(bead.id, onlyScope: scopeKey);
        _reportTrustRefused(services, bead, trustRefusal);
        refused.add(
          StationAdmissionRefusal(
            candidate: candidate,
            clause: 'trust',
            detail: trustRefusal,
          ),
        );
        continue;
      }

      if (_retryTimers.containsKey(bead.id)) {
        waiting.add(candidate);
        continue;
      }

      if (bead.isClosed) {
        final disposition = sessionDispositionOf(verdict.winner);
        if (disposition is! LiveSession) {
          _release(bead.id, onlyScope: scopeKey);
        }
        final clause = switch (disposition) {
          LiveSession() => 'work-terminal',
          HeldSession() => 'held',
          DoneSession() => 'done',
          NoSession() || VoidedSession() || PausedSession() => 'work-terminal',
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
            _reportDuplicateLive(services, bead.id, session, rivals);
            _release(bead.id, onlyScope: scopeKey);
            final keptSessionId = session.sessionId ?? '';
            for (final rival in rivals) {
              _scheduleRivalCleanup(
                scope,
                services,
                workBeadId: bead.id,
                keptSessionId: keptSessionId,
                rival: rival,
              );
            }
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
          if (retiredRound && sessionId != null && sessionId.isNotEmpty) {
            var successor = _reservations[bead.id];
            if (successor != null && successor.scopeKey != scopeKey) {
              waiting.add(candidate);
              capacityWaiting.add(candidate);
              continue;
            }
            if (successor == null || successor.sessionId == sessionId) {
              successor = _UnsnapshottedReservation(
                scopeKey: scopeKey,
                mountAttempt: null,
                writeState: _MountAttemptWriteState.recorded,
                reservationToken: Object(),
                since: _clock().toUtc(),
                reclaimedSessionId: sessionId,
              );
              _reservations[bead.id] = successor;
            }
            if (successor.sessionId == null &&
                successor.reclaimedSessionId == sessionId) {
              scope._mountedIds.add(bead.id);
              admitted.add(
                _reservationValue(
                  StationAdmissionCandidate(bead: bead, session: session),
                  successor,
                ),
              );
              continue;
            }
          }
          final awaitsReadmission =
              session.pauseState == SessionPauseState.resumed &&
              !scope._mountedIds.contains(bead.id);
          if (awaitsReadmission &&
              !_hasCapacity(
                scope,
                config,
                durableLiveIds,
                candidateAlreadyCounted: false,
              )) {
            waiting.add(candidate);
            capacityWaiting.add(candidate);
            continue;
          }
          if (awaitsReadmission) {
            durableLiveIds.add(
              sessionId != null && sessionId.isNotEmpty
                  ? sessionId
                  : 'work:${bead.id}',
            );
          }
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
                reservationToken: null,
              ),
            );
            continue;
          }
          scope._mountedIds.add(bead.id);
          final ownedReservation = _reservations[bead.id];
          if (ownedReservation != null &&
              ownedReservation.scopeKey == scopeKey &&
              ownedReservation.sessionId == sessionId) {
            admitted.add(
              _reservationValue(
                StationAdmissionCandidate(bead: bead, session: session),
                ownedReservation,
              ),
            );
            continue;
          }
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
              reservationToken: null,
            ),
          );
          continue;
        case BlockedLinkedSession(:final session):
          _release(bead.id, onlyScope: scopeKey);
          final disposition = sessionDispositionOf(session);
          final name = switch (disposition) {
            HeldSession() => 'held',
            PausedSession() => 'paused',
            DoneSession() => 'done',
            NoSession() ||
            LiveSession() ||
            VoidedSession() => 'blocked-session',
          };
          refused.add(
            StationAdmissionRefusal(
              candidate: candidate,
              clause: name,
              detail: 'the linked session has blocking disposition $name',
            ),
          );
          continue;
        case RemintLinkedSession(:final session, :final surplus):
          final winnerAlive = staleFences(session).where(_liveness).toList();
          if (winnerAlive.isNotEmpty) {
            _reportVoidRefused(services, bead.id, session, winnerAlive);
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
            _reportSurplusAlive(services, bead.id, aliveSurplus);
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
        admitted.add(_reservationValue(candidate, reservation));
        continue;
      }

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
          reservationToken: Object(),
          since: _clock().toUtc(),
          reclaimedSessionId: null,
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
        reservationToken: Object(),
        since: _clock().toUtc(),
        reclaimedSessionId: null,
      );
      _reservations[bead.id] = reservation;
      scope._mountedIds.add(bead.id);
      admitted.add(_reservationValue(candidate, reservation));
      _scheduleMountAttempt(services, bead.id, attempt, reservation);
    }

    final capacityWaitingSignature = capacityWaiting
        .map((entry) => entry.bead.id)
        .join(',');
    if (capacityWaiting.isNotEmpty) {
      _flare(services, 'work.throttled', {
        'count': '${capacityWaiting.length}',
        'beadIds': capacityWaitingSignature,
      });
    }
    if (admitted.isEmpty && waiting.isNotEmpty) {
      final waitingIds = {for (final candidate in waiting) candidate.bead.id};
      scope._zeroAdmissionSinceByBead.removeWhere(
        (beadId, _) => !waitingIds.contains(beadId),
      );
      for (final beadId in waitingIds) {
        scope._zeroAdmissionSinceByBead.putIfAbsent(
          beadId,
          () => _clock().toUtc(),
        );
      }
    } else {
      scope._zeroAdmissionSinceByBead.clear();
    }
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
      trajectoryAdmissionHaltedClause(
        halted: _trajectoryAdmissionHalt?.halted ?? false,
      ),
      dispatchableWorkClause(resident: config.resident),
      driveListClause(config.driveList),
      // This per-candidate refusal does not perturb `ordered` above. Terminal
      // state also remains classified before pause, and neither disposition
      // can be resurrected by an eligible freshness result.
      freshCrossLinkReadClause(snapshot.stateCapturedAt),
      crossLinkExclusionClause(
        snapshot.frontierExclusionsByBeadId,
        snapshot.sessionsByWorkBead,
      ),
      sameStoreDependencyExclusionClause(
        snapshot.graph,
        BeadOwnershipPredicate(config.ownedSubstations),
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
      final reclaimedSessionId = reservation.reclaimedSessionId;
      return (sessionId == null || !durableLiveIds.contains(sessionId)) &&
          (reclaimedSessionId == null ||
              !durableLiveIds.contains(reclaimedSessionId));
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

  bool _isMounted(String workBeadId) =>
      _scopes.values.any((scope) => scope._mountedIds.contains(workBeadId));

  StationAdmissionReservation _reservationValue(
    StationAdmissionCandidate candidate,
    _UnsnapshottedReservation reservation,
  ) => StationAdmissionReservation(
    candidate: candidate,
    substationId: reservation.scopeKey.substationId,
    mountAttempt: reservation.writeState == _MountAttemptWriteState.recorded
        ? reservation.mountAttempt
        : null,
    sessionId: reservation.sessionId,
    adopted: false,
    reservationToken: reservation.reservationToken,
  );

  void _reconcileMountAttemptWrites(JoinedSnapshot snapshot) {
    for (final entry in snapshot.mountAttemptsByWorkBead.entries) {
      final recordedCount = entry.value.count;
      final reservation = _reservations[entry.key];
      final reservedAttempt = reservation?.mountAttempt;
      if (reservedAttempt != null && recordedCount >= reservedAttempt) {
        reservation!.writeState = _MountAttemptWriteState.recorded;
      }
      final prefix = '${entry.key}:';
      _mountAttemptWrites.removeWhere((key, _) {
        if (!key.startsWith(prefix)) return false;
        final attempt = int.tryParse(key.substring(prefix.length));
        return attempt != null && attempt <= recordedCount;
      });
    }
  }

  void _scheduleMountAttempt(
    ServiceBundle services,
    String workBeadId,
    int attempt,
    _UnsnapshottedReservation reservation,
  ) {
    final latch = '$workBeadId:$attempt';
    var write = _mountAttemptWrites[latch];
    if (write == null) {
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
    }
    scheduleMicrotask(() async {
      try {
        await write!;
        if (_disposed || !identical(_reservations[workBeadId], reservation)) {
          return;
        }
        reservation.writeState = _MountAttemptWriteState.recorded;
        _notifyListeners();
      } on Object catch (error) {
        if (identical(_mountAttemptWrites[latch], write)) {
          unawaited(_mountAttemptWrites.remove(latch));
        }
        if (!identical(_reservations[workBeadId], reservation)) return;
        _release(workBeadId);
        _flare(services, 'work.mountAttemptRecordFailed', {
          'beadId': workBeadId,
          'attempt': '$attempt',
          'reason': truncateReason('$error'),
          ...stateStoreDeadlineMetadata(error),
        });
        _scheduleRetryInvalidation(workBeadId);
        _notifyListeners();
      }
    });
  }

  /// Retires a voided dead key after verifying its recorded process fences.
  ///
  /// Returns null when retirement completed or the session id was empty. A
  /// non-null refusal means this authority already reported the fail-closed
  /// result and released the candidate's reservation.
  Future<StationAdmissionRefusal?> retireVoidedSession({
    required Bead workBead,
    required SessionProjection deadSession,
    required String reason,
    required ServiceBundle services,
  }) async {
    final alive = staleFences(deadSession).where(_liveness).toList();
    if (alive.isNotEmpty) {
      final scope = _scopeForBead(workBead.id);
      if (scope == null) {
        throw StateError(
          'void retirement refused: the work bead has no admission scope',
        );
      }
      _reportVoidRefused(services, workBead.id, deadSession, alive);
      _release(workBead.id);
      _notifyListeners();
      return StationAdmissionRefusal(
        candidate: StationAdmissionCandidate(
          bead: workBead,
          session: deadSession,
        ),
        clause: 'live-fence',
        detail: 'a voided linked session still has a live process',
      );
    }
    final deadId = deadSession.sessionId ?? '';
    if (deadId.isEmpty) return null;
    await _writer.update(
      deadId,
      metadata: voidRetireMetadata(
        workBeadId: workBead.id,
        deadSessionId: deadId,
        reason: reason,
      ),
    );
    _releaseSession(workBead.id, deadId);
    _notifyListeners();
    return null;
  }

  /// Creates and binds the session for a reservation, awaiting its exact
  /// authority-owned mount-attempt write when that write is still in flight.
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
      if (reservation.writeState == _MountAttemptWriteState.writing) {
        final attempt = reservation.mountAttempt;
        final write = attempt == null
            ? null
            : _mountAttemptWrites['${candidate.bead.id}:$attempt'];
        if (write == null) {
          throw StateError(
            'the in-flight mount-attempt reservation has no owned write',
          );
        }
        await write;
        if (!identical(_reservations[candidate.bead.id], reservation)) {
          throw StateError(
            'the admission reservation was released while its write settled',
          );
        }
      }
      final id = await _writer.createSession(
        substation: _stateSubstation,
        title: title,
        workBeadId: candidate.bead.id,
        metadata: metadata,
      );
      reservation.sessionId = id;
      reservation.reclaimedSessionId = null;
      _notifyListeners();
      return (sessionId: id, refusal: null);
    } finally {
      reservation.minting = false;
    }
  }

  /// Pours a fresh or orphaned molecule, durably voiding only a state-store
  /// mint timeout that belongs to this bead's freshly-created reservation.
  ///
  /// The mint-timeout class comprises the raw Dart timeout raised by the
  /// state-store read and the bd graph deadline identified by
  /// [stateStoreDeadlineMetadata]. Every other failure is rethrown unchanged.
  Future<Map<String, String>> pourMolecule(
    GraphApplyPlan plan, {
    required String workBeadId,
    required String sessionId,
    required Iterable<String> rootCrumbs,
    required ServiceBundle services,
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
    } on Object catch (error) {
      final deadline = stateStoreDeadlineMetadata(error);
      if (error is! TimeoutException &&
          deadline['deadlineConstant'] != 'BdCliService.pourTimeout') {
        rethrow;
      }
      final reservation = _reservations[workBeadId];
      if (reservation?.sessionId != sessionId) rethrow;
      await _voidCreatedSession(
        workBeadId: workBeadId,
        sessionId: sessionId,
        reason: kMintTimeoutVoidReason,
        services: services,
        retryAfterClose: true,
      );
      throw StationMintVoided(
        workBeadId: workBeadId,
        retiredSessionId: sessionId,
        cause: error,
      );
    }
  }

  /// Compensates a lifecycle cancellation only when this authority still owns
  /// the supplied attempt. Null and stale identities are harmless no-ops.
  ///
  /// [blockUntilFreshReady] quarantines only an identity-matched, unconsumed
  /// pre-session reservation. The bead then rejoins ordinary priority and
  /// capacity competition after a fresh snapshot reports it ready.
  Future<String?> abandonSessionAttempt({
    required String workBeadId,
    required String? sessionId,
    required Object? reservationToken,
    required ServiceBundle services,
    bool blockUntilFreshReady = false,
  }) async {
    final reservation = _reservations[workBeadId];
    if (sessionId == null) {
      if (reservationToken == null ||
          reservation == null ||
          !identical(reservation.reservationToken, reservationToken) ||
          reservation.sessionId != null ||
          reservation.minting) {
        return null;
      }
      if (blockUntilFreshReady) {
        _blockedUntilFreshReady.add(workBeadId);
      }
      _release(workBeadId);
      _notifyListeners();
      return null;
    }
    if (reservation?.sessionId != sessionId) {
      return null;
    }
    return _voidCreatedSession(
      workBeadId: workBeadId,
      sessionId: sessionId,
      reason: 'mint-abandoned',
      services: services,
      retryAfterClose: false,
    );
  }

  Future<String> _voidCreatedSession({
    required String workBeadId,
    required String sessionId,
    required String reason,
    required ServiceBundle services,
    required bool retryAfterClose,
  }) async {
    await _bestEffortReap(sessionId, reason, services);
    await _writer.update(
      sessionId,
      metadata: voidRetireMetadata(
        workBeadId: workBeadId,
        deadSessionId: sessionId,
        reason: reason,
      ),
    );
    await _writer.close(sessionId, reason: reason);
    _releaseSession(workBeadId, sessionId);
    if (retryAfterClose) {
      _scheduleRetryInvalidation(workBeadId);
    }
    _notifyListeners();
    return sessionId;
  }

  /// Writes [outcomeMetadata] when [outcomeMarked] is false; on the true call,
  /// optionally reaps, closes, and releases the attempt. This keeps the
  /// transition on the same authority object ratified by
  /// `the_grid#admission-authority-in-process-cut`; it adds no admission
  /// trajectory record and changes none of the authority's private latches.
  Future<void> completeSession({
    required String workBeadId,
    required String sessionId,
    required bool outcomeMarked,
    required Map<String, String> outcomeMetadata,
    required bool reapMolecule,
    required ServiceBundle services,
  }) async {
    if (!outcomeMarked) {
      await _writer.update(sessionId, metadata: outcomeMetadata);
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
    await _writer.closeOpenGatesForTerminal(
      sessionId: sessionId,
      trigger: GateCloseCause.workBeadClosed,
      disposition: GateSweepSessionDisposition.live,
      terminalWorkBead: terminalWorkBead,
    );
    _release(terminalWorkBead.id);
    _notifyListeners();
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
    await _writer.closeOpenGatesForTerminal(
      sessionId: sessionId,
      trigger: cause,
      disposition: disposition,
    );
    _notifyListeners();
  }

  /// Demotes terminal-only surplus linked rows through the incumbent void-key
  /// shape. Pre-authority open rivals reach this batch only after the authority
  /// has stopped their runtimes and closed them durably.
  Future<void> retireSurplusSessions({
    required String workBeadId,
    required String keptSessionId,
    required List<SessionProjection> surplus,
    required ServiceBundle services,
  }) async {
    final ordered = orderLinkedSessions(surplus);
    final verdict = linkedSessionVerdictOf(ordered);
    if (verdict is AdoptLinkedSession) return;
    for (final row in ordered) {
      final deadId = row.sessionId ?? '';
      if (deadId.isEmpty || !row.isTerminal) continue;
      if (_hasLiveFence(row)) {
        _reportSurplusAlive(services, workBeadId, [row]);
        continue;
      }
      final reason = _surplusRetirementReason(workBeadId, keptSessionId);
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
          ...stateStoreDeadlineMetadata(error),
        });
      }
    }
  }

  void _scheduleRivalCleanup(
    _AdmissionScopeState scope,
    ServiceBundle services, {
    required String workBeadId,
    required String keptSessionId,
    required SessionProjection rival,
  }) {
    final rivalId = rival.sessionId ?? '';
    if (rivalId.isEmpty) return;
    if (!scope._rivalCleanupsInFlight.add(rivalId)) return;
    scheduleMicrotask(() async {
      try {
        final running = _provider.listRunning('$rivalId/');
        for (final runtime in running) {
          await _provider.stop(runtime);
        }
        if (_hasLiveFence(rival)) {
          _reportSurplusAlive(services, workBeadId, [rival]);
          return;
        }
        final reason = _surplusRetirementReason(workBeadId, keptSessionId);
        await _bestEffortReap(rivalId, reason, services);
        await _writer.close(rivalId, reason: reason);
        await retireSurplusSessions(
          workBeadId: workBeadId,
          keptSessionId: keptSessionId,
          surplus: [rival.copyWith(isTerminal: true)],
          services: services,
        );
      } on Object catch (error) {
        _flare(services, 'work.sessionSurplusRetireFailed', {
          'beadId': workBeadId,
          'sessionId': rivalId,
          'reason': truncateReason('$error'),
          ...stateStoreDeadlineMetadata(error),
        });
      } finally {
        scope._rivalCleanupsInFlight.remove(rivalId);
      }
    });
  }

  bool _hasLiveFence(SessionProjection row) => staleFences(row).any(_liveness);

  static String _surplusRetirementReason(
    String workBeadId,
    String keptSessionId,
  ) =>
      'surplus linked session: "$workBeadId" keeps "$keptSessionId"; '
      'this closed row was demoted so the join stays single-valued';

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
        ...stateStoreDeadlineMetadata(error),
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
    scope._mountEligibilityRefusals[beadId] = (
      clause: clause,
      since: former != null && former.clause == clause
          ? former.since
          : _clock().toUtc(),
    );
    if (former?.clause != clause) {
      scope._mountEligibilityRecheckTimer ??= Timer(Duration.zero, () {
        scope._mountEligibilityRecheckTimer = null;
        _notifyListeners();
      });
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
    final former = scope._mountEligibilityRefusals.remove(beadId);
    if (former != null) {
      _flare(services, 'work.mountEligibilityRestored', {
        'beadId': beadId,
        'clause': former.clause,
      });
    }
  }

  void _reportTrustRefused(ServiceBundle services, Bead bead, String reason) {
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
    ServiceBundle services,
    String beadId,
    SessionProjection winner,
    List<SessionProjection> rivals,
  ) {
    _flare(services, 'work.duplicateLiveRefused', {
      'beadId': beadId,
      'sessionId': winner.sessionId ?? '',
      'rivalSessionIds': rivals.map((row) => row.sessionId ?? '').join(','),
    });
  }

  void _reportSurplusAlive(
    ServiceBundle services,
    String beadId,
    List<SessionProjection> alive,
  ) {
    _flare(services, 'work.sessionSurplusAlive', {
      'beadId': beadId,
      'sessionIds': alive.map((row) => row.sessionId ?? '').join(','),
    });
  }

  void _reportVoidRefused(
    ServiceBundle services,
    String beadId,
    SessionProjection session,
    List<AdoptFence> alive,
  ) {
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

  void _release(String workBeadId, {_ScopeKey? onlyScope}) {
    final reservation = _reservations[workBeadId];
    if (onlyScope != null &&
        reservation != null &&
        reservation.scopeKey != onlyScope) {
      return;
    }
    final releasedReservation = reservation != null;
    if (releasedReservation) _reservations.remove(workBeadId);
    if (onlyScope != null) {
      _scopes[onlyScope]?._mountedIds.remove(workBeadId);
    } else {
      for (final scope in _scopes.values) {
        scope._mountedIds.remove(workBeadId);
      }
    }
    if (releasedReservation &&
        _scopes.values.any(
          (scope) => scope._zeroAdmissionSinceByBead.isNotEmpty,
        )) {
      _scheduleCapacityRecheck();
    }
  }

  void _releaseSession(String workBeadId, String sessionId) {
    final reservation = _reservations[workBeadId];
    // A reworked/voided predecessor can close while a reservation for the next
    // round is already held. Never release that successor reservation.
    if (reservation != null && reservation.sessionId != sessionId) return;
    _release(
      workBeadId,
      onlyScope: reservation?.scopeKey ?? _lastScopeByBead[workBeadId],
    );
  }

  void _scheduleRetryInvalidation(String workBeadId) {
    if (_disposed || _retryTimers.containsKey(workBeadId)) return;
    _retryTimers[workBeadId] = Timer(Backoff.standard.delayFor(1), () {
      _retryTimers.remove(workBeadId);
      _notifyListeners();
    });
  }

  void _scheduleCapacityRecheck() {
    if (_disposed || _capacityRecheckScheduled) return;
    _capacityRecheckScheduled = true;
    scheduleMicrotask(() {
      if (_disposed || !_capacityRecheckScheduled) return;
      _capacityRecheckScheduled = false;
      _notifyListeners();
    });
  }

  void _notifyListeners() {
    if (_disposed) return;
    _capacityRecheckScheduled = false;
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
    _removeTrajectoryAdmissionHaltListener?.call();
    _removeTrajectoryAdmissionHaltListener = null;
    for (final scope in _scopes.values) {
      scope._mountEligibilityRecheckTimer?.cancel();
      scope._mountEligibilityRecheckTimer = null;
    }
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _blockedUntilFreshReady.clear();
    _capacityRecheckScheduled = false;
    _mountAttemptWrites.clear();
    _lastScopeByBead.clear();
    _listeners.clear();
  }
}
