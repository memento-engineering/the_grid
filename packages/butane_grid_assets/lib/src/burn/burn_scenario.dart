/// The SCRIPTED drive scenario + the DIRECT perception channel (ADR-0011 D9).
///
/// The burn's second channel is `leonard_drive` ↔ the follower app's
/// `ext.exploration.*`, point-to-point over the follower's VM service — **NOT
/// tunneled through the federation bus** (perception ⊥ observability, ADR-0012).
/// This pass it is **SCRIPTED**: zero inference on either box (a real
/// regression), driven by a [DriveScenario] of `observe`/`invoke` steps each with
/// a substring expectation.
///
/// [LeonardDrive] is the seam: the REAL impl is lenny's credential-free,
/// zero-model `leonard_drive` (proven A40/tg-e28); offline tests inject a scripted
/// fake. `runDriveScenario` is pure orchestration over the seam — the I/O is the
/// injected drive.
library;

import 'burn_report.dart';
import 'follower.dart';

/// The kind of one scripted drive step over the perception channel.
enum DriveAction {
  /// Read a perceived path (`leonard_drive` `observe`).
  observe,

  /// Invoke a tool (`leonard_drive` `invoke`).
  invoke,
}

/// One SCRIPTED step of a drive scenario (ADR-0011 D9) — an `observe`/`invoke`
/// over the direct perception channel plus the substring the result must contain
/// (zero inference: an exact, scripted assertion). An empty [expectContains]
/// asserts only that the step ran without error.
class DriveStep {
  /// An `observe <path>` step asserting the observed value contains
  /// [expectContains].
  const DriveStep.observe(this.path, {this.expectContains = ''})
    : action = DriveAction.observe,
      tool = '',
      args = const {};

  /// An `invoke <tool>` step (with [args]) asserting the result contains
  /// [expectContains].
  const DriveStep.invoke(this.tool, {this.args = const {}, this.expectContains = ''})
    : action = DriveAction.invoke,
      path = '';

  /// Whether this step observes a path or invokes a tool.
  final DriveAction action;

  /// The path to observe (for [DriveAction.observe]).
  final String path;

  /// The tool to invoke (for [DriveAction.invoke]).
  final String tool;

  /// The invoke arguments (for [DriveAction.invoke]).
  final Map<String, String> args;

  /// The substring the step's result must contain to pass (empty = ran-ok only).
  final String expectContains;

  /// A human-readable description of the step (its action + target).
  String get description => switch (action) {
    DriveAction.observe => 'observe $path',
    DriveAction.invoke => 'invoke $tool',
  };
}

/// A named, SCRIPTED drive scenario (ADR-0011 D9) — the ordered steps the
/// `burn-host` order runs against the leased follower app over the direct
/// perception channel.
class DriveScenario {
  /// Creates a scenario [name]d over its ordered [steps].
  const DriveScenario({required this.name, required this.steps});

  /// The scenario name (recorded on the [TestReport]).
  final String name;

  /// The ordered scripted steps.
  final List<DriveStep> steps;
}

/// The DIRECT perception channel (ADR-0011 D9) — `leonard_drive` ↔ the follower
/// app's `ext.exploration.*` over its VM service, point-to-point on the LAN, NOT
/// tunneled through the federation bus. Credential-free + zero-model (A40/tg-e28).
///
/// The REAL impl is lenny's `leonard_drive`; offline tests inject a scripted fake.
/// Acts return [Future]s.
abstract interface class LeonardDrive {
  /// Attaches to the follower app at [endpoint]'s VM service. (An act.)
  Future<void> attach(FollowerEndpoint endpoint);

  /// Reads the perceived value at [path]. (An observation, point-read.)
  Future<String> observe(String path);

  /// Invokes [tool] with [args] and returns the result. (An act.)
  Future<String> invoke(String tool, Map<String, String> args);

  /// Detaches + releases the perception channel. (An act; idempotent.)
  Future<void> close();
}

/// Runs a SCRIPTED [scenario] against an already-attached [drive] over the direct
/// perception channel and collects a [TestReport] for [endpoint] (ADR-0011 D9).
///
/// Each step's result is checked against its substring expectation (zero
/// inference); EVERY step is recorded even after the first failure, and the
/// aggregate verdict is "every step passed AND at least one ran". A step's I/O
/// error is recorded as a failed step (the drive channel hiccuped) rather than
/// thrown — the burn collects a report either way. [isCancelled] (when given) is
/// polled between steps so a host unmount stops the drive politely.
Future<TestReport> runDriveScenario({
  required LeonardDrive drive,
  required DriveScenario scenario,
  required FollowerEndpoint endpoint,
  bool Function()? isCancelled,
}) async {
  final results = <DriveStepResult>[];
  for (final step in scenario.steps) {
    if (isCancelled?.call() ?? false) break;
    String observed;
    bool passed;
    try {
      observed = switch (step.action) {
        DriveAction.observe => await drive.observe(step.path),
        DriveAction.invoke => await drive.invoke(step.tool, step.args),
      };
      passed = step.expectContains.isEmpty || observed.contains(step.expectContains);
    } on Object catch (e) {
      observed = 'drive error: $e';
      passed = false;
    }
    results.add(
      DriveStepResult(
        description: step.description,
        observed: observed,
        passed: passed,
      ),
    );
  }
  return TestReport(
    scenario: scenario.name,
    endpoint: endpoint.vmServiceUri,
    steps: results,
    passed: results.isNotEmpty && results.every((r) => r.passed),
  );
}
