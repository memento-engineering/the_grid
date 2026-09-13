/// Contracts for observing a work session after its durable inspection horizon.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'relay.freezed.dart';

/// The immutable context supplied to a mounted relay for one due session.
@freezed
abstract class RelayObservation with _$RelayObservation {
  /// Creates a relay observation at [observedAt] for a session whose inspection
  /// horizon elapsed at [deadline].
  const factory RelayObservation({
    required String sessionId,
    required String workBeadId,
    DateTime? startedAt,
    required DateTime deadline,
    required DateTime observedAt,
  }) = _RelayObservation;
}

/// The relay's exhaustive decision for an observed work session.
@freezed
sealed class RelayVerdict with _$RelayVerdict {
  /// Confirms the session remains healthy and requests another inspection
  /// after [nextHorizon].
  const factory RelayVerdict.absorb({required Duration nextHorizon}) =
      RelayAbsorb;

  /// Raises the session to the governor with a human-readable [reason].
  const factory RelayVerdict.escalate({required String reason}) = RelayEscalate;
}

/// Observes due work sessions and returns an explicit governor-facing verdict.
abstract interface class RelayObserver {
  /// Observes [observation] once and returns whether to absorb or escalate it.
  Future<RelayVerdict> observe(RelayObservation observation);
}

/// Mounts the station's single relay observer under an independent ceiling.
abstract interface class RelayRegistrar {
  /// Mounts [observer], allowing at most [ceiling] unsettled relay executions.
  RelayRegistration mountRelay({
    required RelayObserver observer,
    required int ceiling,
  });
}

/// The identity-bound lifetime of one mounted relay.
abstract interface class RelayRegistration {
  /// Unmounts this registration; repeated calls have no effect.
  void dispose();
}

/// Persists the next observation horizon on the owned session bead.
typedef RelayHorizonWriter =
    Future<void> Function(String sessionId, DateTime nextObservationAt);

/// Bounds a relay operation without changing the lifetime of that operation.
typedef RelayTimeout =
    Future<RelayVerdict> Function(
      Future<RelayVerdict> operation,
      Duration limit,
    );

/// The default interval before an unconfigured work session is inspected.
const Duration kDefaultWorkSessionTimeToLive = Duration(hours: 24);

/// The default maximum time allowed for one relay verdict.
const Duration kDefaultRelayObservationTimeout = Duration(minutes: 5);

/// Governor flare emitted when a due session has no mounted relay.
const String kRelayAbsentFlare = 'relay.absent';

/// Governor flare emitted when relay execution or horizon persistence fails.
const String kRelayErrorFlare = 'relay.error';

/// Governor flare emitted when the relay verdict exceeds its timeout.
const String kRelayTimeoutFlare = 'relay.timeout';

/// Governor flare emitted when the independent relay ceiling is exhausted.
const String kRelayCapacityFlare = 'relay.capacity';

/// Governor flare emitted for an explicit relay escalation verdict.
const String kRelayEscalatedFlare = 'relay.escalated';
