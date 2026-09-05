/// Pure failure-class + retry-policy resolution.
///
/// The host alone can combine the capability's reported kind with its OWN
/// evidence (how long the effect ran, whether the write dropped), so the
/// mapping lives beside the host — and stays pure, so it is unit-testable
/// without a tree.
library;

import 'package:grid_runtime/grid_runtime.dart' show StepFailureClass;

import '../sdk/capability_failure.dart';
import '../sdk/circuit.dart' show Backoff;
import '../sdk/supervision_policy.dart';
import 'harness_throttle.dart';

/// The durable class for a reported [kind] plus the host's [ranFor] evidence.
///
/// A protocol-declared [CapabilityFailureKind.noResult] is
/// [StepFailureClass.infra] irrespective of elapsed time. An undeclared fast
/// `noResult` specializes to `infra` through the existing harness-silence
/// evidence, unchanged. `StepFailureClass.storeUnavailable` is never produced
/// here: it is a host observation about its OWN write, not a capability
/// outcome.
StepFailureClass resolveFailureClass({
  required CapabilityFailureKind kind,
  required Duration? ranFor,
  bool kindDeclared = false,
}) => switch ((kind, kindDeclared)) {
  (CapabilityFailureKind.work, _) => StepFailureClass.work,
  (CapabilityFailureKind.noResult, true) => StepFailureClass.infra,
  (CapabilityFailureKind.noResult, false) =>
    isHarnessSilence(kind: kind, ranFor: ranFor)
        ? StepFailureClass.infra
        : StepFailureClass.noResult,
  (CapabilityFailureKind.invalidResult, _) => StepFailureClass.invalidResult,
};

/// The exhaustion behaviour a [kind] gets when the capability declares none.
///
/// A NON-RESULT never produced gradeable work, so its exhaustion parks at a
/// gate and the round survives for rework; `work` keeps ADR-0008 Decision 7's
/// latch-and-escalate.
ExhaustionBehavior defaultExhaustionFor(CapabilityFailureKind kind) =>
    switch (kind) {
      CapabilityFailureKind.work => ExhaustionBehavior.latchFailed,
      CapabilityFailureKind.noResult ||
      CapabilityFailureKind.invalidResult => ExhaustionBehavior.parkAtGate,
    };

/// The backoff a [failureClass] gets when the capability declares none — the
/// circuit's, except for `infra`, which keeps the wall-clock throttle schedule.
Backoff defaultBackoffFor(StepFailureClass failureClass, Backoff circuit) =>
    failureClass == StepFailureClass.infra ? Backoff.harnessThrottle : circuit;

/// The schedule the host applies to one reported failure.
typedef ResolvedRetry = ({
  Backoff backoff,
  int maxRestarts,
  ExhaustionBehavior onExhaustion,
});

/// Resolves [declared] against the owning circuit's defaults for one failure.
///
/// The budget is CLAMPED to [circuitMaxRestarts]: the pure frontier predicate
/// reads `Circuit.maxRestarts`, so a declared budget above it could never be
/// honoured. A capability may only tighten.
ResolvedRetry resolveRetryPolicy({
  required SupervisionPolicy declared,
  required CapabilityFailureKind kind,
  required StepFailureClass failureClass,
  required Backoff circuitBackoff,
  required int circuitMaxRestarts,
}) {
  final policy = declared.policyFor(kind);
  final budget = policy.maxRestarts;
  return (
    backoff: policy.backoff ?? defaultBackoffFor(failureClass, circuitBackoff),
    maxRestarts: budget == null || budget > circuitMaxRestarts
        ? circuitMaxRestarts
        : budget,
    onExhaustion: policy.onExhaustion ?? defaultExhaustionFor(kind),
  );
}

/// The gate reason written when a NON-RESULT class spends its budget.
String nonResultGateReason({
  required StepFailureClass failureClass,
  required String sessionId,
  required String nodePath,
  required int attempts,
  required String reason,
}) =>
    '${failureClass.wire} exhausted: $attempts attempt(s) produced no usable '
    'result — session $sessionId, step $nodePath'
    '${reason.isEmpty ? '' : ' — $reason'}';
