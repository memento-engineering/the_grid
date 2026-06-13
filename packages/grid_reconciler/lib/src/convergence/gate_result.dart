import 'package:freezed_annotation/freezed_annotation.dart';

import 'gate_outcome.dart';

part 'gate_result.freezed.dart';

/// Port of gc's `GateResult` (gate.go:25-33) — the full gate-evaluation
/// composite that step 7 branches on, step 5 persists (the eight-write
/// sequence, gates-exec.md §7), and step 8 embeds in event payloads.
///
/// Produced fresh by the Track-D gate runner; the **replay** branch
/// (handler.go:280-298) reconstructs it from the persisted
/// `convergence.gate_*` keys via `ConvergenceMetadata`'s replay readers:
/// `gateOutcomeWire` for [outcomeWire] (VERBATIM, handler.go:282 — never
/// the validating `gateOutcome` reading, which would silently rewrite a
/// persisted garbage outcome to `''`/no-gate-ran), `gateStdoutWire` /
/// `gateStderrWire` (handler.go:291-292), and the collapsing readers
/// `gateExitCodeOrNull`, `gateRetryCountOrZero`, `gateDurationOrZero`,
/// `gateTruncated`.
@freezed
abstract class GateResult with _$GateResult {
  const GateResult._();

  const factory GateResult({
    /// gc's `Outcome` is an **open string**, not the closed enum:
    ///
    /// * `''` means "no gate ran" — manual mode passes `GateResult{}`
    ///   (handler.go:305-306) and `GateResultToPayload` returns a nil
    ///   payload for it (events.go:195-206);
    /// * the replay branch reads the persisted value **verbatim** without
    ///   validation (handler.go:282).
    ///
    /// Step-7 branching compares wire literals (`== "pass"`,
    /// `== "timeout"`); anything else — including garbage — falls into the
    /// iterate-or-terminal path, exactly like gc. Use [outcome] for the
    /// typed view.
    @Default('') String outcomeWire,

    /// Null when no exit code applies (timeout/pre-exec error) — persisted
    /// as `""`, never `"0"` or absent (handler.go:780-784).
    int? exitCode,

    /// Timed-out attempts before the final one, ≤ 3; counts only timeouts
    /// (condition.go:269-287).
    @Default(0) int retryCount,

    /// Captured stdout, truncated to 4096 bytes (capture.go).
    @Default('') String stdout,

    /// Captured stderr — or the runner's error string on the `error`
    /// outcome (condition.go:385-391).
    @Default('') String stderr,

    /// Wall-clock gate duration; persisted as decimal milliseconds
    /// (handler.go:796).
    @Default(Duration.zero) Duration duration,

    /// True when either stream was truncated; persisted as `"true"` / `""`
    /// (handler.go:799-803).
    @Default(false) bool truncated,
  }) = _GateResult;

  /// A fresh result for a closed-set outcome (the Track-D runner only ever
  /// produces the four enum values).
  static GateResult of(
    GateOutcome outcome, {
    int? exitCode,
    int retryCount = 0,
    String stdout = '',
    String stderr = '',
    Duration duration = Duration.zero,
    bool truncated = false,
  }) => GateResult(
    outcomeWire: outcome.wire,
    exitCode: exitCode,
    retryCount: retryCount,
    stdout: stdout,
    stderr: stderr,
    duration: duration,
    truncated: truncated,
  );

  /// Typed view of [outcomeWire]: null for `''` (no gate ran) or an
  /// out-of-set persisted value.
  GateOutcome? get outcome =>
      outcomeWire.isEmpty ? null : GateOutcome.fromWire(outcomeWire);

  /// gc's `Outcome == GatePass` literal compare (handler.go:358).
  bool get isPass => outcomeWire == GateOutcome.pass.wire;

  /// gc's `Outcome == GateTimeout` literal compare (handler.go:345, 361).
  bool get isTimeout => outcomeWire == GateOutcome.timeout.wire;
}
