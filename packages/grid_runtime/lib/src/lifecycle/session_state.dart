/// A Dart port of gc's session `state` transition table
/// (`gascity/internal/session/state_machine.go:106-144`), trimmed to the
/// lifecycle M3's subprocess dogfood actually drives.
///
/// the_grid's *durable* state notion stays the binary the bead STATUS carries
/// (open = live, closed = retired — M1's [SessionState] on the `AgentSession`
/// projection). gc's finer-grained lifecycle string lives on `metadata.state`
/// (ADR-0000 A14), and *that* string is what this table governs:
/// `start_pending → spawning → active → {idle/asleep, draining, quarantined,
/// closed}`. The [RuntimeActuator] writes the resulting state through the
/// `GridBeadWriter` chokepoint as a `bd update --metadata {state: …}`.
///
/// This is a pure, total reducer — no I/O — so it is tested before any bd write
/// is wired (predictable-flutter: pure logic before IO).
library;

/// The fine-grained session lifecycle state stamped on `metadata.state`.
///
/// Modeled as an extension type over the wire string (the same posture as
/// `IssueType`/`BeadStatus` in grid_controller) because gc treats the value as
/// a free-form string the projection preserves verbatim — a strict closed enum
/// would throw on a gc-written state the_grid does not model. Named constants
/// cover the M3 lifecycle; the type still round-trips any string gc writes.
extension type const LifecycleState(String wire) {
  /// The virtual state before a session bead exists. The only legal source for
  /// [LifecycleCommand.create].
  static const none = LifecycleState('');

  /// The session bead is minted; the runtime process has not been confirmed
  /// alive yet (gc's `start_pending`).
  static const startPending = LifecycleState('start_pending');

  /// The runtime is starting the process (gc's `spawning`). The
  /// provider-`start` boundary: between mint and the first liveness signal.
  static const spawning = LifecycleState('spawning');

  /// The process is confirmed alive and doing work (gc's `active`).
  static const active = LifecycleState('active');

  /// The process exited normally / went idle and is parked (gc's `asleep`).
  static const asleep = LifecycleState('asleep');

  /// Graceful shutdown in progress (gc's `draining`).
  static const draining = LifecycleState('draining');

  /// Blocked from restart after the crash-loop threshold was exceeded (gc's
  /// `quarantined`).
  static const quarantined = LifecycleState('quarantined');

  /// Terminal. The bead STATUS becomes `closed` regardless of the prior
  /// `metadata.state`; this value records the lifecycle was closed.
  static const closed = LifecycleState('closed');

  /// True for the terminal state.
  bool get isTerminal => this == closed;
}

/// What triggered a state change — the verb the runtime invoked, not the
/// resulting state (gc's `TransitionCommand` vocabulary, `state_machine.go`).
enum LifecycleCommand {
  /// Mint a new session bead. `none → start_pending`.
  create,

  /// The runtime began spawning the process. `start_pending → spawning`.
  spawn,

  /// The process is confirmed alive / activity observed. `spawning → active`,
  /// and `asleep → active` (a re-activated session).
  activate,

  /// The process exited cleanly / went idle. `active → asleep`.
  sleep,

  /// Begin graceful shutdown. `active → draining`.
  drain,

  /// Crash-loop threshold exceeded — block restart. `active`/`asleep` →
  /// `quarantined`.
  quarantine,

  /// Restart a parked/quarantined/draining session back to spawning (a fresh
  /// incarnation). `asleep`/`quarantined`/`draining` → `spawning`.
  restart,

  /// Hard-close the session. Any non-none state → `closed`.
  close,
}

/// Raised when [transition] is asked for a (state, command) pair the table does
/// not allow — the analog of gc's `ErrIllegalTransition`. Callers either guard
/// with [transitionOrNull] or treat this as a programmer error.
class IllegalLifecycleTransition implements Exception {
  IllegalLifecycleTransition(this.from, this.command);

  final LifecycleState from;
  final LifecycleCommand command;

  @override
  String toString() =>
      'IllegalLifecycleTransition: state "${from.wire}" does not accept '
      'command "${command.name}"';
}

/// The allowed `(command, from-state) → to-state` table — the Dart port of gc's
/// `transitions` map (`state_machine.go:106-144`), trimmed to the M3 commands.
///
/// `close` is the only command legal from *any* non-none state (gc's
/// `anyState` sentinel), so it is handled in [transitionOrNull] rather than
/// enumerated per source.
const Map<LifecycleCommand, Map<LifecycleState, LifecycleState>>
_transitions = {
  LifecycleCommand.create: {LifecycleState.none: LifecycleState.startPending},
  LifecycleCommand.spawn: {
    LifecycleState.startPending: LifecycleState.spawning,
  },
  LifecycleCommand.activate: {
    LifecycleState.spawning: LifecycleState.active,
    LifecycleState.active: LifecycleState.active,
    LifecycleState.asleep: LifecycleState.active,
  },
  LifecycleCommand.sleep: {LifecycleState.active: LifecycleState.asleep},
  LifecycleCommand.drain: {LifecycleState.active: LifecycleState.draining},
  LifecycleCommand.quarantine: {
    LifecycleState.active: LifecycleState.quarantined,
    LifecycleState.asleep: LifecycleState.quarantined,
  },
  LifecycleCommand.restart: {
    LifecycleState.asleep: LifecycleState.spawning,
    LifecycleState.quarantined: LifecycleState.spawning,
    LifecycleState.draining: LifecycleState.spawning,
  },
  // `close` is anyState → closed; resolved in [transitionOrNull].
};

/// Validates that applying [command] to a session in [from] is legal and
/// returns the new state, or null when the transition is disallowed (the
/// non-throwing analog of gc's `Transition`).
LifecycleState? transitionOrNull(
  LifecycleState from,
  LifecycleCommand command,
) {
  // `close` closes any non-none state (gc's anyState sentinel).
  if (command == LifecycleCommand.close) {
    return from == LifecycleState.none ? null : LifecycleState.closed;
  }
  return _transitions[command]?[from];
}

/// Validates the transition and returns the new state, throwing
/// [IllegalLifecycleTransition] when disallowed (gc's `Transition`).
LifecycleState transition(LifecycleState from, LifecycleCommand command) {
  final to = transitionOrNull(from, command);
  if (to == null) throw IllegalLifecycleTransition(from, command);
  return to;
}

/// The commands legal from [from] (gc's `AllowedCommands`), sorted by name for
/// a stable rendering — useful for diagnostics / "what can happen next?".
List<LifecycleCommand> allowedCommands(LifecycleState from) {
  final out = <LifecycleCommand>[
    for (final command in LifecycleCommand.values)
      if (transitionOrNull(from, command) != null) command,
  ]..sort((a, b) => a.name.compareTo(b.name));
  return out;
}
