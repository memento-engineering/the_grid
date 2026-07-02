/// The pure eligibility predicate (ADR-0008 D4 / M4-P1 Track A, §4 step 2).
///
/// A free function over `(Formula, FormulaCursor, nodePath)` that computes which
/// steps should currently be MOUNTED — the depth-analogue of `WorkList`'s
/// child-set predicate. Zero I/O, zero `Seed`, fully golden-testable: the
/// inflater (Track D) maps the returned steps to child Seeds, and the await-all
/// barrier IS this predicate withholding a downstream step until its deps reach
/// a positive terminal.
///
/// The rules (M4-P1 §4):
/// - **depsSatisfied** — every `dependsOn` resolves to a sibling's POSITIVE
///   TERMINAL (a job `complete` or a daemon `ready`; a sub-formula dep resolves
///   to its terminal-step descendant). Fail-closed: a dangling dep or an
///   unresolvable sub-formula is never satisfied.
/// - **retired** — a completed [StepKind.job] is pruned (its host unmounts).
/// - **circuitBroken** — a failed step that exhausted [Formula.maxRestarts] (the
///   D-5 escalation term) is withheld.
/// - the cursor-state gate — `pending`/`running` mount; a `daemon` at `ready`
///   stays mounted; a `failed` step within budget AND past cooldown re-keys.
library;

import 'cursor.dart';
import 'formula.dart';

/// The full path of [stepId] within a formula rooted at [nodePath]
/// (`'$nodePath/$stepId'`, or just [stepId] at an empty root).
String stepPath(String nodePath, String stepId) =>
    nodePath.isEmpty ? stepId : '$nodePath/$stepId';

/// The [NodeCursor] at [path], defaulting to a fresh `pending` cursor for a node
/// that has never run.
NodeCursor cursorNodeAt(FormulaCursor cursor, String path) =>
    cursor[path] ?? const NodeCursor();

/// The [StepState] at [path], defaulting to [StepState.pending].
StepState cursorStateAt(FormulaCursor cursor, String path) =>
    cursorNodeAt(cursor, path).state;

/// Resolves the cursor path a `dependsOn` on [depId] is satisfied by — the
/// dep's own path for a [CapabilityStep], or its terminal-step descendant for a
/// [SubFormulaStep]. Returns null (unsatisfiable, fail-closed) for a dangling
/// dep id or an unresolvable sub-formula.
String? depTerminalPath(
  Formula formula,
  String nodePath,
  String depId,
  Formula? Function(String formulaId) formulaById,
) {
  final dep = formula.stepById(depId);
  return switch (dep) {
    null => null,
    CapabilityStep() => stepPath(nodePath, depId),
    SubFormulaStep(:final formulaId) => () {
      final sub = formulaById(formulaId);
      if (sub == null) return null;
      return stepPath(stepPath(nodePath, depId), sub.terminalStepId);
    }(),
  };
}

/// Whether every `dependsOn` of [step] resolves to a sibling's POSITIVE TERMINAL
/// (M4-P1 §4 step 2). The barrier IS multiple deps; await-all is "not yet
/// satisfied". Fail-closed on a dangling/unresolvable dep.
bool depsSatisfied(
  Formula formula,
  FormulaStep step,
  FormulaCursor cursor,
  String nodePath, {
  required Formula? Function(String formulaId) formulaById,
}) {
  for (final depId in step.dependsOn) {
    final path = depTerminalPath(formula, nodePath, depId, formulaById);
    if (path == null) return false;
    if (!cursorNodeAt(cursor, path).isPositiveTerminal) return false;
  }
  return true;
}

/// Whether [step] is a completed [StepKind.job] — pruned from the frontier
/// (M4-P1 §4 step 2). A daemon never completes; a sub-formula is never retired
/// (it stays mounted to keep its daemons alive until the parent tears down).
bool isRetired(
  FormulaStep step,
  FormulaCursor cursor,
  String nodePath,
) =>
    step is CapabilityStep &&
    step.kind == StepKind.job &&
    cursorStateAt(cursor, stepPath(nodePath, step.stepId)) == StepState.complete;

/// Whether [step] failed AND exhausted its restart budget (the D-5 escalation
/// term) — withheld from the frontier; its emptiness is "broken", never "done".
bool isCircuitBroken(
  Formula formula,
  FormulaStep step,
  FormulaCursor cursor,
  String nodePath,
) {
  final node = cursorNodeAt(cursor, stepPath(nodePath, step.stepId));
  return node.state == StepState.failed && node.restartCount >= formula.maxRestarts;
}

/// Whether [step]'s cursor state permits it to be mounted right now (given its
/// deps are already satisfied): `pending`/`running` mount; a [StepKind.daemon]
/// at `ready` stays; a `failed` step mounts only within budget AND past cooldown
/// (the re-key); a completed/exhausted state does not.
bool _runnableState(
  Formula formula,
  FormulaStep step,
  FormulaCursor cursor,
  String nodePath,
  DateTime now,
) {
  final node = cursorNodeAt(cursor, stepPath(nodePath, step.stepId));
  return switch (node.state) {
    StepState.pending => true,
    StepState.running => true,
    StepState.ready => step is CapabilityStep && step.kind == StepKind.daemon,
    StepState.complete => false,
    StepState.failed => node.restartCount < formula.maxRestarts &&
        (node.cooldownUntil == null || !now.isBefore(node.cooldownUntil!)),
    // Parked at a human gate — never runnable until the gate resolves (the
    // re-arm flips it back to pending; D-7).
    StepState.gated => false,
  };
}

/// The eligible frontier of [formula] under [cursor] at [nodePath] — the steps
/// that should currently be MOUNTED, in declaration order (M4-P1 §4 step 2).
///
/// [formulaById] resolves a [SubFormulaStep]'s nested formula (for terminal-path
/// dep resolution); [now] gates the supervised-restart cooldown (injected so the
/// predicate stays pure — the kernel owns the wall clock).
List<FormulaStep> eligibleSteps(
  Formula formula,
  FormulaCursor cursor,
  String nodePath, {
  required Formula? Function(String formulaId) formulaById,
  required DateTime now,
}) =>
    [
      for (final step in formula.steps)
        if (depsSatisfied(formula, step, cursor, nodePath,
                formulaById: formulaById) &&
            !isRetired(step, cursor, nodePath) &&
            !isCircuitBroken(formula, step, cursor, nodePath) &&
            _runnableState(formula, step, cursor, nodePath, now))
          step,
    ];

/// Whether [formula]'s terminal step reached a POSITIVE TERMINAL — the formula
/// is "done" (D-2: the session close fires; D-5: distinguishes
/// empty-because-complete from empty-because-broken).
///
/// Symmetric with [depTerminalPath]: when [Formula.terminalStepId] names a
/// [SubFormulaStep], the terminal resolves to its terminal-step DESCENDANT — a
/// sub-formula has no host, so its own node is never written and reading it
/// directly would report `pending` forever, leaving the subtree mounted
/// indefinitely (the exact failure D-5 forbids). A dangling/unresolvable
/// terminal is fail-closed (never complete).
bool isFormulaComplete(
  Formula formula,
  FormulaCursor cursor,
  String nodePath, {
  required Formula? Function(String formulaId) formulaById,
}) {
  final path =
      depTerminalPath(formula, nodePath, formula.terminalStepId, formulaById);
  if (path == null) return false;
  return cursorNodeAt(cursor, path).isPositiveTerminal;
}

/// Whether any step in [formula] is circuit-broken (D-5) — an empty frontier
/// that is "broken" (escalate + tear down), never "done". Shallow (this level
/// only); [isFormulaBrokenDeep] descends into sub-formulas.
bool isFormulaBroken(
  Formula formula,
  FormulaCursor cursor,
  String nodePath,
) =>
    formula.steps.any((s) => isCircuitBroken(formula, s, cursor, nodePath));

/// Whether [formula] is broken ANYWHERE in its subtree (D-5) — a step at this
/// level is circuit-broken, OR a nested sub-formula is broken-deep. This is what
/// `SessionScope` (the one lifecycle owner, D-2) checks to escalate + tear down,
/// because a nested harness can exhaust its breaker BELOW the top formula (the
/// top-level [isFormulaBroken] would miss it). Fail-open on an unresolvable
/// sub-formula (it cannot be inspected, so it is not reported broken here — its
/// own un-satisfied dep withholds whatever depends on it).
bool isFormulaBrokenDeep(
  Formula formula,
  FormulaCursor cursor,
  String nodePath, {
  required Formula? Function(String formulaId) formulaById,
}) =>
    firstBrokenNode(formula, cursor, nodePath, formulaById: formulaById) != null;

/// The FIRST circuit-broken node in [formula]'s subtree — its full `nodePath`
/// plus its [NodeCursor] — mirroring [isFormulaBrokenDeep]'s traversal
/// (declaration order, depth-first). Null when nothing is broken.
///
/// Capture-only (FT-1, tg-pez): the ESCALATE decision is [isFormulaBrokenDeep];
/// this only names WHICH node + reason to record beside the escalation marker
/// (`SessionScope`). Never gates orchestration.
({String nodePath, NodeCursor node})? firstBrokenNode(
  Formula formula,
  FormulaCursor cursor,
  String nodePath, {
  required Formula? Function(String formulaId) formulaById,
}) {
  for (final step in formula.steps) {
    if (isCircuitBroken(formula, step, cursor, nodePath)) {
      final path = stepPath(nodePath, step.stepId);
      return (nodePath: path, node: cursorNodeAt(cursor, path));
    }
    if (step is SubFormulaStep) {
      final sub = formulaById(step.formulaId);
      if (sub != null) {
        final found = firstBrokenNode(
          sub,
          cursor,
          stepPath(nodePath, step.stepId),
          formulaById: formulaById,
        );
        if (found != null) return found;
      }
    }
  }
  return null;
}
