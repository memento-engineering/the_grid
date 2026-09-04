/// The typed capability-failure vocabulary — the engine's answer to
/// "the capability failed" being three different facts.
library;

import '../domain/session_bead.dart' show truncateReason;

/// WHY a capability's turn failed — the engine-owned discriminant that replaces
/// the transitional boolean on `Failed`.
///
/// A capability can only report these three. `StepFailureClass.storeUnavailable`
/// is a HOST observation (a dropped chokepoint write) and is never emitted by a
/// capability.
enum CapabilityFailureKind {
  /// The capability RAN and produced a valid NEGATIVE result (a critic that
  /// graded F, a build that failed). The only kind that counts as substantive
  /// failed work.
  work,

  /// No usable result or artifact was produced at all.
  noResult,

  /// A result/artifact exists but violates the capability's declared contract.
  invalidResult,
}

/// A typed failure a `ProcessCapability`'s `result` /
/// `probeCompletionArtifact` body may THROW to name its own failure kind.
///
/// Carries ONLY the [kind] and a bounded [reason] — never a retry policy, never
/// a state transition. Retry policy is declared separately
/// (`Capability.supervisionPolicy`) so no payload an agent produced can steer
/// supervision.
class CapabilityFailure implements Exception {
  /// Creates a failure of [kind]; [reason] is bounded AT CONSTRUCTION through
  /// the engine's one bound ([truncateReason]), never widened downstream.
  CapabilityFailure(this.kind, String reason) : reason = truncateReason(reason);

  /// No usable result/artifact was produced.
  CapabilityFailure.noResult(String reason)
    : this(CapabilityFailureKind.noResult, reason);

  /// A result exists but violates the declared contract.
  CapabilityFailure.invalidResult(String reason)
    : this(CapabilityFailureKind.invalidResult, reason);

  /// Why the turn failed.
  final CapabilityFailureKind kind;

  /// The bounded diagnostic (capture-only telemetry).
  final String reason;

  @override
  String toString() => 'CapabilityFailure(${kind.name}): $reason';
}
