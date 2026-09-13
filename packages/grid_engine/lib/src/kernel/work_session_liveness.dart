import 'dart:async';

import '../domain/joined_snapshot.dart';
import '../domain/session_projection.dart';
import '../sdk/capability.dart';
import '../sdk/relay.dart';

enum _DeadlineSource { fallback, startedAt, durable, absorbed }

enum _EpisodeState { idle, inFlight, escalated }

final class _TrackedSession {
  _TrackedSession({
    required this.sessionId,
    required this.workBeadId,
    required this.startedAt,
    required this.deadline,
    required this.deadlineSource,
  });

  final String sessionId;
  String workBeadId;
  DateTime? startedAt;
  DateTime deadline;
  _DeadlineSource deadlineSource;
  _EpisodeState episode = _EpisodeState.idle;
  DateTime? episodeDeadline;
  bool wasObserved = false;
}

final class _RelayMount {
  _RelayMount({required this.observer, required this.ceiling});

  final RelayObserver observer;
  final int ceiling;
  int unsettled = 0;
  bool disposed = false;
}

/// Station-lifetime coordinator for durable work-session inspection horizons.
///
/// [refresh] consumes the existing joined per-bead change signal. The
/// coordinator owns no timer, scheduler, stream subscription, work admission,
/// or terminal session operation: [onFencedTick] is called by the station's
/// already-owned trajectory tick and expiry can only observe or emit a flare.
final class WorkSessionLiveness implements RelayRegistrar {
  /// Creates a coordinator whose absorb verdicts persist through
  /// [writeHorizon].
  WorkSessionLiveness({
    required RelayHorizonWriter writeHorizon,
    ExplorationTransport? transport,
    Duration timeToLive = kDefaultWorkSessionTimeToLive,
    Duration observationTimeout = kDefaultRelayObservationTimeout,
    DateTime Function()? clock,
    RelayTimeout? timeout,
  }) : _writeHorizon = writeHorizon,
       _transport = transport,
       _timeToLive = timeToLive,
       _observationTimeout = observationTimeout,
       _clock = clock ?? DateTime.now,
       _timeout = timeout ?? _defaultTimeout;

  final RelayHorizonWriter _writeHorizon;
  final ExplorationTransport? _transport;
  final Duration _timeToLive;
  final Duration _observationTimeout;
  final DateTime Function() _clock;
  final RelayTimeout _timeout;
  final Map<String, _TrackedSession> _sessions = <String, _TrackedSession>{};

  _RelayMount? _relay;
  bool _active = false;
  bool _disposed = false;

  static Future<RelayVerdict> _defaultTimeout(
    Future<RelayVerdict> operation,
    Duration limit,
  ) => operation.timeout(limit);

  /// Replaces the cached projection with all distinct live published and
  /// surplus session rows in [snapshot].
  ///
  /// A durable horizon never regresses. A newly available `startedAt` may
  /// correct only a fallback baseline that has not yet been observed.
  void refresh(JoinedSnapshot snapshot) {
    if (_disposed) return;
    final now = _clock();
    final seen = <String>{};
    final rows = <({String workBeadId, SessionProjection session})>[];
    final workBeadIds = <String>{
      ...snapshot.sessionsByWorkBead.keys,
      ...snapshot.surplusSessionsByWorkBead.keys,
    }.toList()..sort();
    for (final workBeadId in workBeadIds) {
      for (final session in snapshot.linkedSessions(workBeadId)) {
        final sessionId = session.sessionId;
        if (sessionId == null || sessionId.isEmpty || session.isTerminal) {
          continue;
        }
        if (seen.add(sessionId)) {
          rows.add((workBeadId: workBeadId, session: session));
        }
      }
    }

    for (final row in rows) {
      final projection = row.session;
      final sessionId = projection.sessionId!;
      final workBeadId = projection.workBeadId.isEmpty
          ? row.workBeadId
          : projection.workBeadId;
      final durable = projection.relayNextObservationAt?.toUtc();
      final startedAt = projection.startedAt;
      final existing = _sessions[sessionId];
      if (existing == null) {
        final deadline =
            durable ?? (startedAt?.add(_timeToLive) ?? now.add(_timeToLive));
        _sessions[sessionId] = _TrackedSession(
          sessionId: sessionId,
          workBeadId: workBeadId,
          startedAt: startedAt,
          deadline: deadline,
          deadlineSource: durable != null
              ? _DeadlineSource.durable
              : startedAt != null
              ? _DeadlineSource.startedAt
              : _DeadlineSource.fallback,
        );
        continue;
      }

      existing.workBeadId = workBeadId;
      if (durable != null) {
        final previousDeadline = existing.deadline;
        if (existing.deadlineSource == _DeadlineSource.fallback ||
            existing.deadlineSource == _DeadlineSource.startedAt ||
            durable.isAfter(existing.deadline)) {
          existing.deadline = durable;
          existing.deadlineSource = _DeadlineSource.durable;
        }
        final episodeDeadline = existing.episodeDeadline;
        if (existing.episode == _EpisodeState.escalated &&
            episodeDeadline != null &&
            durable.isAfter(episodeDeadline)) {
          existing.deadline = durable.isAfter(previousDeadline)
              ? durable
              : previousDeadline;
          existing.deadlineSource = _DeadlineSource.durable;
          existing.episode = _EpisodeState.idle;
          existing.episodeDeadline = null;
        }
      } else if (existing.deadlineSource == _DeadlineSource.fallback &&
          !existing.wasObserved &&
          startedAt != null) {
        existing.deadline = startedAt.add(_timeToLive);
        existing.deadlineSource = _DeadlineSource.startedAt;
      }
      existing.startedAt = startedAt ?? existing.startedAt;
    }

    _sessions.removeWhere((sessionId, _) => !seen.contains(sessionId));
  }

  /// Arms evaluation. Repeated activation is intentionally a no-op.
  void activate() {
    if (!_disposed) _active = true;
  }

  /// Evaluates every due session once, in stable session-id order.
  ///
  /// This method is synchronous: relay futures continue independently of the
  /// fenced tick and cannot hold its fixpoint loop open.
  void onFencedTick() {
    if (!_active || _disposed) return;
    final now = _clock();
    final due =
        _sessions.values
            .where(
              (session) =>
                  session.episode == _EpisodeState.idle &&
                  !session.deadline.isAfter(now),
            )
            .toList()
          ..sort((left, right) => left.sessionId.compareTo(right.sessionId));

    for (final session in due) {
      session.wasObserved = true;
      session.episodeDeadline = session.deadline;
      final relay = _relay;
      if (relay == null || relay.disposed) {
        _escalate(session, kRelayAbsentFlare, now, 'no relay is mounted');
        continue;
      }
      if (relay.unsettled >= relay.ceiling) {
        _escalate(session, kRelayCapacityFlare, now, 'relay ceiling exhausted');
        continue;
      }
      _observe(session, relay, now);
    }
  }

  @override
  RelayRegistration mountRelay({
    required RelayObserver observer,
    required int ceiling,
  }) {
    if (ceiling <= 0) {
      throw ArgumentError.value(ceiling, 'ceiling', 'must be positive');
    }
    if (_disposed) {
      throw StateError('WorkSessionLiveness is disposed');
    }
    final current = _relay;
    if (current != null && !current.disposed) {
      throw StateError('A relay is already mounted');
    }
    final mount = _RelayMount(observer: observer, ceiling: ceiling);
    _relay = mount;
    return _RelayRegistration(this, mount);
  }

  /// Disposes this station-lifetime coordinator. Repeated calls are harmless.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final relay = _relay;
    if (relay != null) relay.disposed = true;
    _relay = null;
    _sessions.clear();
  }

  void _observe(
    _TrackedSession session,
    _RelayMount relay,
    DateTime observedAt,
  ) {
    session.episode = _EpisodeState.inFlight;
    relay.unsettled += 1;
    final observation = RelayObservation(
      sessionId: session.sessionId,
      workBeadId: session.workBeadId,
      startedAt: session.startedAt,
      deadline: session.deadline,
      observedAt: observedAt,
    );

    late final Future<RelayVerdict> operation;
    try {
      operation = relay.observer.observe(observation);
    } catch (error) {
      relay.unsettled -= 1;
      _escalate(session, kRelayErrorFlare, observedAt, error.toString());
      return;
    }

    var operationSettled = false;
    unawaited(
      operation.then<void>(
        (_) {
          operationSettled = true;
          relay.unsettled -= 1;
        },
        onError: (Object _, StackTrace __) {
          operationSettled = true;
          relay.unsettled -= 1;
        },
      ),
    );

    late final Future<RelayVerdict> bounded;
    try {
      bounded = _timeout(operation, _observationTimeout);
    } catch (error) {
      _escalate(session, kRelayErrorFlare, observedAt, error.toString());
      return;
    }
    unawaited(
      _resolve(
        session,
        bounded,
        observedAt,
        operationSettled: () => operationSettled,
      ),
    );
  }

  Future<void> _resolve(
    _TrackedSession session,
    Future<RelayVerdict> bounded,
    DateTime observedAt, {
    required bool Function() operationSettled,
  }) async {
    late final RelayVerdict verdict;
    try {
      verdict = await bounded;
    } on TimeoutException catch (error) {
      _escalate(
        session,
        operationSettled() ? kRelayErrorFlare : kRelayTimeoutFlare,
        observedAt,
        error.toString(),
      );
      return;
    } catch (error) {
      _escalate(session, kRelayErrorFlare, observedAt, error.toString());
      return;
    }
    if (!_isCurrentInFlight(session)) return;

    switch (verdict) {
      case RelayAbsorb(:final nextHorizon):
        if (nextHorizon <= Duration.zero) {
          _escalate(
            session,
            kRelayErrorFlare,
            observedAt,
            'relay absorb horizon must be positive',
          );
          return;
        }
        final nextAt = _clock().add(nextHorizon).toUtc();
        try {
          await _writeHorizon(session.sessionId, nextAt);
        } catch (error) {
          _escalate(session, kRelayErrorFlare, observedAt, error.toString());
          return;
        }
        if (!_isCurrentInFlight(session)) return;
        if (nextAt.isAfter(session.deadline)) session.deadline = nextAt;
        session.deadlineSource = _DeadlineSource.absorbed;
        session.episode = _EpisodeState.idle;
        session.episodeDeadline = null;
      case RelayEscalate(:final reason):
        if (reason.trim().isEmpty) {
          _escalate(
            session,
            kRelayErrorFlare,
            observedAt,
            'relay escalation reason must not be empty',
          );
          return;
        }
        _escalate(session, kRelayEscalatedFlare, observedAt, reason);
    }
  }

  bool _isCurrentInFlight(_TrackedSession session) =>
      !_disposed &&
      identical(_sessions[session.sessionId], session) &&
      session.episode == _EpisodeState.inFlight;

  void _escalate(
    _TrackedSession session,
    String flare,
    DateTime observedAt,
    String reason,
  ) {
    if (_disposed || !identical(_sessions[session.sessionId], session)) return;
    session.episode = _EpisodeState.escalated;
    session.episodeDeadline ??= session.deadline;
    try {
      _transport?.flare(flare, <String, String>{
        'sessionId': session.sessionId,
        'workBeadId': session.workBeadId,
        'deadline': session.deadline.toUtc().toIso8601String(),
        'observedAt': observedAt.toUtc().toIso8601String(),
        'reason': reason,
      });
    } catch (_) {
      // Exploration is emit-only: transport loss cannot break orchestration.
    }
  }
}

final class _RelayRegistration implements RelayRegistration {
  _RelayRegistration(this._owner, this._mount);

  final WorkSessionLiveness _owner;
  final _RelayMount _mount;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _mount.disposed = true;
    if (identical(_owner._relay, _mount)) _owner._relay = null;
  }
}
