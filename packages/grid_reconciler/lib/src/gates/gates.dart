/// Track D — gate execution (ADR-0003 Decision 3, gates-exec.md).
///
/// The subprocess gate runner Service and its supporting ports: the process
/// SEAM, the env-contract assembler, the condition-path containment defenses,
/// the bounded output capture, and the artifact-dir helpers. Consumes Track A's
/// gate types ([GateConfig]/[GateResult]/[GateOutcome]/[GateMode]/[Verdict]/
/// [GoDuration]); produces Track A [GateResult]s.
///
/// This is an **internal** barrel for the `lib/src/gates/` slice; the package
/// barrel (`lib/grid_reconciler.dart`) is wired by the M2 orchestrator.
library;

export 'artifact_dir.dart';
export 'condition_env.dart';
export 'condition_path.dart';
export 'gate_runner_service.dart';
export 'output_capture.dart';
export 'process_runner.dart';
