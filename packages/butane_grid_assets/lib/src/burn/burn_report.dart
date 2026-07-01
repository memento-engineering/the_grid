/// The burn's domain-defined result value types (ADR-0011 D9): a [TestReport]
/// collected by the `burn-host` order after it drives the leased follower app
/// over the DIRECT perception channel.
///
/// Plain immutable value types (predictable-flutter: value types are plain), no
/// codegen — the butane domain owns its own result shape, exactly as the compute
/// domain owns `CommandResult`.
library;

import 'package:meta/meta.dart';

/// The outcome of ONE scripted drive step (ADR-0011 D9) — what the host
/// observed/invoked over `ext.exploration.*` and whether it satisfied the
/// step's scripted expectation.
@immutable
class DriveStepResult {
  /// Creates a step result: a human [description] (`observe cli` /
  /// `invoke grid.ready`), the [observed] output read over the perception
  /// channel, and whether the scripted assertion [passed].
  const DriveStepResult({
    required this.description,
    required this.observed,
    required this.passed,
  });

  /// A human-readable description of the step (the action + its target).
  final String description;

  /// The output observed/returned over the direct perception channel.
  final String observed;

  /// Whether the step's scripted expectation held (a substring match; zero
  /// inference).
  final bool passed;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'description': description,
    'observed': observed,
    'passed': passed,
  };

  @override
  String toString() =>
      'DriveStepResult($description, passed: $passed)';
}

/// The burn's collected report (ADR-0011 D9) — the domain result the `burn-host`
/// order produces after running a SCRIPTED scenario against the leased follower
/// app. The engine records a summary on the_grid's OWN session bead; the full
/// value type is the domain's to interpret.
@immutable
class TestReport {
  /// Creates a report for [scenario] driven against [endpoint], with the per-step
  /// [steps] results and the aggregate [passed] verdict.
  const TestReport({
    required this.scenario,
    required this.endpoint,
    required this.steps,
    required this.passed,
  });

  /// The scenario name that was driven.
  final String scenario;

  /// The follower VM-service endpoint that was driven (the direct channel).
  final String endpoint;

  /// The per-step results, in execution order.
  final List<DriveStepResult> steps;

  /// Whether EVERY step passed (and at least one ran).
  final bool passed;

  /// The total number of steps that ran.
  int get total => steps.length;

  /// The number of steps whose scripted assertion failed.
  int get failures => steps.where((s) => !s.passed).length;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'scenario': scenario,
    'endpoint': endpoint,
    'passed': passed,
    'total': total,
    'failures': failures,
    'steps': [for (final s in steps) s.toJson()],
  };

  @override
  String toString() =>
      'TestReport($scenario, passed: $passed, $failures/$total failed)';
}
