/// The closed gate-mode set for `convergence.gate_mode`.
///
/// Wire strings byte-identical to `gascity/internal/convergence/metadata.go:66-70`:
/// `manual` / `condition` / `hybrid`.
///
/// An **enum** (closed set): gc validates the value and errors on anything
/// else (`ParseGateConfig`, gate.go:50-55 — "invalid gate mode %q"), so an
/// unseen mode is upstream drift, surfaced as a typed decode failure by the
/// metadata codec rather than coerced.
enum GateMode {
  /// metadata.go:67 — `GateModeManual = "manual"`.
  manual('manual'),

  /// metadata.go:68 — `GateModeCondition = "condition"`.
  condition('condition'),

  /// metadata.go:69 — `GateModeHybrid = "hybrid"`.
  hybrid('hybrid');

  const GateMode(this.wire);

  /// The exact string gc writes to `convergence.gate_mode`.
  final String wire;

  /// gc's default when the key is absent or empty: `ParseGateConfig`
  /// (gate.go:46-48) and `CreateHandler` (create.go:55-57) both fall back to
  /// manual.
  static const GateMode defaultMode = manual;

  /// Resolves a wire string, or null when unrecognized.
  static GateMode? fromWire(String wire) {
    for (final mode in values) {
      if (mode.wire == wire) return mode;
    }
    return null;
  }
}
