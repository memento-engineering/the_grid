/// The pure eligibility predicate (ADR-0008 D4 / M4-P1 Track A, §4 step 2).
///
/// A free function over `(Circuit, CircuitCursor, nodePath)` that computes which
/// steps should currently be MOUNTED — the depth-analogue of `WorkList`'s
/// child-set predicate. Zero I/O, zero `Seed`, fully golden-testable: the
/// inflater (Track D) maps the returned steps to child Seeds, and the await-all
/// barrier IS this predicate withholding a downstream step until its deps reach
/// a positive terminal.
///
/// The rules (M4-P1 §4):
/// - **depsSatisfied** — every `dependsOn` resolves to a sibling's POSITIVE
///   TERMINAL (a job `complete` or a daemon `ready`; a sub-circuit dep resolves
///   to its terminal-step descendant). Fail-closed: a dangling dep or an
///   unresolvable sub-circuit is never satisfied.
/// - **retired** — a completed [StepKind.job] is pruned (its host unmounts).
/// - **stepBroken** — a failed step that exhausted [Circuit.maxRestarts] (the
///   D-5 escalation term) is withheld.
/// - the cursor-state gate — `pending`/`running` mount; a `daemon` at `ready`
///   stays mounted; a `failed` step within budget AND past cooldown re-keys.
library;

import 'cursor.dart';
import 'circuit.dart';

/// The full path of [stepId] within a circuit rooted at [nodePath]
/// (`'$nodePath/$stepId'`, or just [stepId] at an empty root).
String stepPath(String nodePath, String stepId) =>
    nodePath.isEmpty ? stepId : '$nodePath/$stepId';

/// The [NodeCursor] at [path], defaulting to a fresh `pending` cursor for a node
/// that has never run.
NodeCursor cursorNodeAt(CircuitCursor cursor, String path) =>
    cursor[path] ?? const NodeCursor();

/// The [StepState] at [path], defaulting to [StepState.pending].
StepState cursorStateAt(CircuitCursor cursor, String path) =>
    cursorNodeAt(cursor, path).state;

/// Resolves the cursor path a `dependsOn` on [depId] is satisfied by — the
/// dep's own path for a [CapabilityStep], or its terminal-step descendant for a
/// [SubCircuitStep]. Returns null (unsatisfiable, fail-closed) for a dangling
/// dep id or an unresolvable sub-circuit.
String? depTerminalPath(
  Circuit circuit,
  String nodePath,
  String depId,
  Circuit? Function(String circuitId) circuitById,
) {
  final dep = circuit.stepById(depId);
  return switch (dep) {
    null => null,
    CapabilityStep() => stepPath(nodePath, depId),
    SubCircuitStep(:final circuitId) => () {
      final sub = circuitById(circuitId);
      if (sub == null) return null;
      return stepPath(stepPath(nodePath, depId), sub.terminalStepId);
    }(),
  };
}

/// Whether every `dependsOn` of [step] resolves to a sibling's POSITIVE TERMINAL
/// (M4-P1 §4 step 2). The barrier IS multiple deps; await-all is "not yet
/// satisfied". Fail-closed on a dangling/unresolvable dep.
bool depsSatisfied(
  Circuit circuit,
  CircuitStep step,
  CircuitCursor cursor,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
}) {
  for (final depId in step.dependsOn) {
    final path = depTerminalPath(circuit, nodePath, depId, circuitById);
    if (path == null) return false;
    if (!cursorNodeAt(cursor, path).isPositiveTerminal) return false;
  }
  return true;
}

/// Whether [step] is a completed [StepKind.job] — pruned from the frontier
/// (M4-P1 §4 step 2). A daemon never completes; a sub-circuit is never retired
/// (it stays mounted to keep its daemons alive until the parent tears down).
bool isRetired(
  CircuitStep step,
  CircuitCursor cursor,
  String nodePath,
) =>
    step is CapabilityStep &&
    step.kind == StepKind.job &&
    cursorStateAt(cursor, stepPath(nodePath, step.stepId)) == StepState.complete;

/// Whether [step] failed AND exhausted its restart budget (the D-5 escalation
/// term) — withheld from the frontier; its emptiness is "broken", never "done".
bool isStepBroken(
  Circuit circuit,
  CircuitStep step,
  CircuitCursor cursor,
  String nodePath,
) {
  final node = cursorNodeAt(cursor, stepPath(nodePath, step.stepId));
  return node.state == StepState.failed && node.restartCount >= circuit.maxRestarts;
}

/// Whether [step]'s cursor state permits it to be mounted right now (given its
/// deps are already satisfied): `pending`/`running` mount; a [StepKind.daemon]
/// at `ready` stays; a `failed` step mounts only within budget AND past cooldown
/// (the re-key); a completed/exhausted state does not.
bool _runnableState(
  Circuit circuit,
  CircuitStep step,
  CircuitCursor cursor,
  String nodePath,
  DateTime now,
) {
  final node = cursorNodeAt(cursor, stepPath(nodePath, step.stepId));
  return switch (node.state) {
    StepState.pending => true,
    StepState.running => true,
    StepState.ready => step is CapabilityStep && step.kind == StepKind.daemon,
    StepState.complete => false,
    StepState.failed => node.restartCount < circuit.maxRestarts &&
        (node.cooldownUntil == null || !now.isBefore(node.cooldownUntil!)),
    // Parked at a human gate — never runnable until the gate resolves (the
    // re-arm flips it back to pending; D-7).
    StepState.gated => false,
  };
}

/// The eligible frontier of [circuit] under [cursor] at [nodePath] — the steps
/// that should currently be MOUNTED, in declaration order (M4-P1 §4 step 2).
///
/// [circuitById] resolves a [SubCircuitStep]'s nested circuit (for terminal-path
/// dep resolution); [now] gates the supervised-restart cooldown (injected so the
/// predicate stays pure — the kernel owns the wall clock).
List<CircuitStep> eligibleSteps(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
  required DateTime now,
}) =>
    [
      for (final step in circuit.steps)
        if (depsSatisfied(circuit, step, cursor, nodePath,
                circuitById: circuitById) &&
            !isRetired(step, cursor, nodePath) &&
            !isStepBroken(circuit, step, cursor, nodePath) &&
            _runnableState(circuit, step, cursor, nodePath, now))
          step,
    ];

/// Whether [circuit]'s terminal step reached a POSITIVE TERMINAL — the circuit
/// is "done" (D-2: the session close fires; D-5: distinguishes
/// empty-because-complete from empty-because-broken).
///
/// Symmetric with [depTerminalPath]: when [Circuit.terminalStepId] names a
/// [SubCircuitStep], the terminal resolves to its terminal-step DESCENDANT — a
/// sub-circuit has no host, so its own node is never written and reading it
/// directly would report `pending` forever, leaving the subtree mounted
/// indefinitely (the exact failure D-5 forbids). A dangling/unresolvable
/// terminal is fail-closed (never complete).
bool isCircuitComplete(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
}) {
  final path =
      depTerminalPath(circuit, nodePath, circuit.terminalStepId, circuitById);
  if (path == null) return false;
  return cursorNodeAt(cursor, path).isPositiveTerminal;
}

/// Whether any step in [circuit] is circuit-broken (D-5) — an empty frontier
/// that is "broken" (escalate + tear down), never "done". Shallow (this level
/// only); [isCircuitBrokenDeep] descends into sub-circuits.
bool isCircuitBroken(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath,
) =>
    circuit.steps.any((s) => isStepBroken(circuit, s, cursor, nodePath));

/// Whether [circuit] is broken ANYWHERE in its subtree (D-5) — a step at this
/// level is circuit-broken, OR a nested sub-circuit is broken-deep. This is what
/// `SessionScope` (the one lifecycle owner, D-2) checks to escalate + tear down,
/// because a nested harness can exhaust its breaker BELOW the top circuit (the
/// top-level [isCircuitBroken] would miss it). Fail-open on an unresolvable
/// sub-circuit (it cannot be inspected, so it is not reported broken here — its
/// own un-satisfied dep withholds whatever depends on it).
bool isCircuitBrokenDeep(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
}) =>
    firstBrokenNode(circuit, cursor, nodePath, circuitById: circuitById) != null;

/// The FIRST circuit-broken node in [circuit]'s subtree — its full `nodePath`
/// plus its [NodeCursor] — mirroring [isCircuitBrokenDeep]'s traversal
/// (declaration order, depth-first). Null when nothing is broken.
///
/// Capture-only (FT-1, tg-pez): the ESCALATE decision is [isCircuitBrokenDeep];
/// this only names WHICH node + reason to record beside the escalation marker
/// (`SessionScope`). Never gates orchestration.
({String nodePath, NodeCursor node})? firstBrokenNode(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
}) {
  for (final step in circuit.steps) {
    if (isStepBroken(circuit, step, cursor, nodePath)) {
      final path = stepPath(nodePath, step.stepId);
      return (nodePath: path, node: cursorNodeAt(cursor, path));
    }
    if (step is SubCircuitStep) {
      final sub = circuitById(step.circuitId);
      if (sub != null) {
        final found = firstBrokenNode(
          sub,
          cursor,
          stepPath(nodePath, step.stepId),
          circuitById: circuitById,
        );
        if (found != null) return found;
      }
    }
  }
  return null;
}
