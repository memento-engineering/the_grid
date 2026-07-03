/// The resolved session identity an engine-private `SessionScope` provides to
/// its circuit subtree (ADR-0008 D4 / M4-P1 D-2).
///
/// Once `SessionScope` has adopt-or-minted the the_grid session bead, it
/// provides this handle via a stable `InheritedSeed<SessionHandle>` so the
/// `CircuitScope` + every `CapabilityHost` attach to the SAME session (the
/// per-step provider name is `'$sessionId/$nodePath/$stepId'`). Value-typed so
/// the inherited provider is stable (a re-mounted scope with the same id never
/// fan-rebuilds — D-6).
library;

/// An adopt-or-minted session's identity — the `sessionId` is the the_grid OWN
/// session bead all of the circuit's cursor writes target (A37 / invariant 4).
class SessionHandle {
  /// Wraps the resolved [sessionId].
  const SessionHandle(this.sessionId);

  /// The the_grid-owned session bead id (in the state store, e.g. `tgdog`).
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is SessionHandle && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;

  @override
  String toString() => 'SessionHandle($sessionId)';
}
