/// The closed gate-outcome set for `convergence.gate_outcome`.
///
/// Wire strings byte-identical to `gascity/internal/convergence/metadata.go:89-94`:
/// `pass` / `fail` / `timeout` / `error`.
///
/// An **enum** (closed set): these are the only values gc's gate runners ever
/// produce (gate.go `GateResult.Outcome` doc, gate.go:26). Note that gc's
/// crash-replay path reads the persisted outcome **verbatim without
/// validation** (handler.go:282); the metadata codec therefore surfaces an
/// out-of-set value as a typed decode failure while always preserving the raw
/// string for byte-faithful replay.
enum GateOutcome {
  /// metadata.go:90 — `GatePass = "pass"` (exit code 0).
  pass('pass'),

  /// metadata.go:91 — `GateFail = "fail"` (non-zero exit).
  fail('fail'),

  /// metadata.go:92 — `GateTimeout = "timeout"` (deadline exceeded).
  timeout('timeout'),

  /// metadata.go:93 — `GateError = "error"` (pre-exec failure).
  error('error');

  const GateOutcome(this.wire);

  /// The exact string gc writes to `convergence.gate_outcome`.
  final String wire;

  /// Resolves a wire string, or null when unrecognized.
  static GateOutcome? fromWire(String wire) {
    for (final outcome in values) {
      if (outcome.wire == wire) return outcome;
    }
    return null;
  }
}
