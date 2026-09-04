/// The per-capability, per-kind retry declaration.
///
/// Retry policy is declared SEPARATELY from the error: a failure object carries
/// no policy hint, so nothing an agent wrote can select its own retries. The
/// engine-private host resolves the declaration after a failure is reported.
library;

import 'capability_failure.dart';
import 'circuit.dart' show Backoff;

/// What happens when a kind's restart budget is spent.
enum ExhaustionBehavior {
  /// Latch `failed` with no cooldown: the node is circuit-broken, and
  /// `SessionScope` escalates + closes (ADR-0008 Decision 7 — today's `work`
  /// path, unchanged).
  latchFailed,

  /// Park the node at a `type=gate` bead FROM the failing leaf host, leaving the
  /// round reworkable (the gate primitive of ADR-0008 Decision 9, already used
  /// by a declined route and by an exhausted infra failure).
  parkAtGate,
}

/// One kind's retry declaration. Every field is optional; a null field INHERITS
/// the owning `Circuit`'s value, which stays the compatibility default.
class RetryPolicy {
  /// Declares an override; omitted fields inherit.
  const RetryPolicy({this.maxRestarts, this.backoff, this.onExhaustion});

  /// This kind's restart budget, or null to inherit `Circuit.maxRestarts`.
  ///
  /// CLAMPED to the circuit's budget by `resolveRetryPolicy`: the PURE frontier
  /// predicate (`isStepBroken` / `_runnableState`) reads
  /// `Circuit.maxRestarts` to decide whether a failed node may re-mount, so a
  /// declared budget ABOVE it would write cooldowns the predicate refuses to
  /// honour. A capability may only TIGHTEN.
  final int? maxRestarts;

  /// This kind's cooldown schedule, or null to inherit `Circuit.backoff`
  /// (`Backoff.harnessThrottle` remains the resolved default for an `infra`
  /// class).
  final Backoff? backoff;

  /// What to do at exhaustion, or null for this kind's default.
  final ExhaustionBehavior? onExhaustion;

  @override
  bool operator ==(Object other) =>
      other is RetryPolicy &&
      other.maxRestarts == maxRestarts &&
      other.backoff == backoff &&
      other.onExhaustion == onExhaustion;

  @override
  int get hashCode => Object.hash(maxRestarts, backoff, onExhaustion);

  @override
  String toString() =>
      'RetryPolicy(maxRestarts: $maxRestarts, backoff: $backoff, '
      'onExhaustion: $onExhaustion)';
}

/// A capability's whole supervision declaration — a per-kind [RetryPolicy] map.
///
/// Identity-compared on purpose: it is a pure method result, never mounted in
/// the tree and never serialized (ADR-0008 D-H — config is a VALUE in the tree;
/// this is neither config nor state).
class SupervisionPolicy {
  /// Declares per-kind overrides.
  const SupervisionPolicy({this.byKind = const {}});

  /// Inherit every value from the owning `Circuit` (the default).
  const SupervisionPolicy.inherit() : byKind = const {};

  /// The declared override per failure kind; an absent kind inherits.
  final Map<CapabilityFailureKind, RetryPolicy> byKind;

  /// The declaration for [kind] (an all-inherit policy when undeclared).
  RetryPolicy policyFor(CapabilityFailureKind kind) =>
      byKind[kind] ?? const RetryPolicy();
}
