import 'package:freezed_annotation/freezed_annotation.dart';

import 'gate_mode.dart';
import 'gate_timeout_action.dart';
import 'go_duration.dart';
import 'verdict.dart';

part 'gate_config.freezed.dart';

/// Port of gc's `GateConfig` (gate.go:17-22) — the **parse product** of
/// `ParseGateConfig(meta)` (gate.go:44-85) with the defaults already applied
/// (mode → manual, timeout → 5m, timeoutAction → iterate; gates-exec.md §0).
///
/// The reducer performs the step-3a parse (handler.go:218-228 — BEFORE the
/// speculative pour, so invalid config never leaves a successor wisp behind;
/// parse failures become `ReconcilerAction.failed`) and ships this product
/// to the Track-D runner via `ReconcilerAction.evaluateGate`. Track D never
/// re-reads or re-parses metadata.
@freezed
abstract class GateConfig with _$GateConfig {
  const GateConfig._();

  const factory GateConfig({
    /// `convergence.gate_mode`, defaulted to manual (gate.go:46-48).
    required GateMode mode,

    /// `convergence.gate_condition` — gate script path, taken verbatim;
    /// empty for manual-only (gate.go:81).
    required String condition,

    /// `convergence.gate_timeout`, defaulted to 5m; parse errors and
    /// non-positive values are step-3a failures, never carried here
    /// (gate.go:57-67).
    required GoDuration timeout,

    /// `convergence.gate_timeout_action`, defaulted to iterate
    /// (gate.go:69-77).
    required GateTimeoutAction timeoutAction,
  }) = _GateConfig;

  /// Port of `GateConfig.NeedsConditionExecution` (gate.go:90-99): manual
  /// never executes; condition/hybrid execute iff a condition is configured.
  bool get needsConditionExecution => switch (mode) {
    GateMode.manual => false,
    GateMode.condition || GateMode.hybrid => condition.isNotEmpty,
  };

  /// Port of `HybridNeedsManual` (hybrid.go:25-27): no condition script
  /// configured. Callers guard `mode == hybrid` themselves, exactly like gc
  /// (handler.go:250-251, 309-310).
  bool get hybridNeedsManual => condition.isEmpty;

  /// gc's retry-budget derivation, duplicated at both call sites
  /// (handler.go:739-742, hybrid.go:16-19): `MaxGateRetries` (3) when
  /// [timeoutAction] is retry, else 0.
  int get retryBudget => timeoutAction == GateTimeoutAction.retry
      ? GateTimeoutAction.maxGateRetries
      : 0;
}

/// Snapshot-derived inputs the Track-D runner needs to assemble gc's
/// `ConditionEnv` (condition.go:57-73; assembled at handler.go:743-760)
/// **without re-reading live metadata** — the same snapshot-only rule as
/// `EventEmission`.
///
/// Track D derives the rest itself: `GC_ARTIFACT_DIR` =
/// `ArtifactDirFor(cityPath, beadId, iteration)` (template.go:23-25,
/// handler.go:751), `StorePath` from its own runtime config
/// (handler.go:148-149, 748), and the full env whitelist per
/// gates-exec.md §1.
@freezed
abstract class GateEnvInputs with _$GateEnvInputs {
  const GateEnvInputs._();

  const factory GateEnvInputs({
    /// `convergence.city_path` (set during create; handler.go:743) — feeds
    /// `HOME`, `GC_CITY`/`GC_CITY_PATH`, and the artifact-dir base. Empty
    /// sandboxes `HOME` to the temp dir (condition.go:80-86).
    @Default('') String cityPath,

    /// Root-bead metadata `var.doc_path` (handler.go:750) — `GC_DOC_PATH`
    /// when non-empty.
    @Default('') String docPath,

    /// `convergence.max_iterations` via gc's collapsing read
    /// (handler.go:759-760) — `GC_MAX_ITERATIONS`.
    @Default(0) int maxIterations,

    /// `closedAt − createdAt` of the closed wisp (`computeDurations`,
    /// handler.go:829-850) — `GC_ITERATION_DURATION_MS`.
    @Default(Duration.zero) Duration iterationDuration,

    /// Σ closed convergence-keyed children durations (handler.go:837-849) —
    /// `GC_CUMULATIVE_DURATION_MS`.
    @Default(Duration.zero) Duration cumulativeDuration,

    /// The step-4 **gate-path** verdict (handler.go:317-324): normalized
    /// when scoped to the closed wisp, else the `block` substitute — NOT
    /// the event payload's `''` (`EventEmission.agentVerdict`). Hybrid mode
    /// feeds it to `GC_AGENT_VERDICT` (hybrid.go:14); pure condition mode
    /// receives but never exports it (gates-exec.md §1b #16).
    @Default(Verdict.block) Verdict agentVerdict,
  }) = _GateEnvInputs;
}
