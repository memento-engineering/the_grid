/// The closed timeout-action set for `convergence.gate_timeout_action`.
///
/// Wire strings byte-identical to `gascity/internal/convergence/metadata.go:74-78`:
/// `iterate` / `retry` / `manual` / `terminate`.
///
/// An **enum** (closed set): gc validates the value and errors on anything
/// else (`ParseGateConfig`, gate.go:70-77 — "invalid gate timeout action %q").
enum GateTimeoutAction {
  /// metadata.go:74 — `TimeoutActionIterate = "iterate"`.
  iterate('iterate'),

  /// metadata.go:75 — `TimeoutActionRetry = "retry"` (bounded by [maxGateRetries]).
  retry('retry'),

  /// metadata.go:76 — `TimeoutActionManual = "manual"`.
  manual('manual'),

  /// metadata.go:77 — `TimeoutActionTerminate = "terminate"`.
  terminate('terminate');

  const GateTimeoutAction(this.wire);

  /// The exact string gc writes to `convergence.gate_timeout_action`.
  final String wire;

  /// gc's default when the key is absent or empty (`ParseGateConfig`,
  /// gate.go:69).
  static const GateTimeoutAction defaultAction = iterate;

  /// gc's retry budget for `retry` (`MaxGateRetries`, gate.go:14).
  static const int maxGateRetries = 3;

  /// Resolves a wire string, or null when unrecognized.
  static GateTimeoutAction? fromWire(String wire) {
    for (final action in values) {
      if (action.wire == wire) return action;
    }
    return null;
  }
}
