import 'runtime_config.dart';
import 'runtime_event.dart';

/// Manages agent sessions — the Dart port of gc's `runtime.Provider`
/// (`gascity/internal/runtime/runtime.go:107-200`), **trimmed to M3**
/// (M3-BUILD-ORDER Track 2). A reference type (the `Provider` role name; no
/// extra classifier — predictable-flutter).
///
/// **What is CUT vs gc** (reference only): attach/`IsAttached`, `Nudge`/
/// `SendKeys`/interaction, the `*Meta` k/v store, `CopyTo`/`ClearScrollback`/
/// `RunLive`, and every optional extension interface (ACP/T3/dialog/idle-wait).
/// M3's dogfood needs only: spawn, supervise, observe, kill.
///
/// **API shape (CLAUDE.md):** Futures for acts ([start]/[stop]/[interrupt]),
/// Streams for observations ([events]/[output]), plus cheap point-in-time
/// queries. Implementations must be safe for concurrent use across distinct
/// session names; duplicate [start] of one name rejects consistently.
abstract interface class RuntimeProvider {
  // ---- Acts (Futures) ----

  /// Creates a new session named [name] with [config]. Completes when the
  /// process is spawned and its [RuntimeEvent.sessionStarted] has been emitted.
  /// Throws [SessionAlreadyExists] if a live session already holds [name].
  Future<void> start(String name, RuntimeConfig config);

  /// Destroys the named session and cleans up its process tree
  /// (SIGTERM→grace→SIGKILL of the whole group). Idempotent: completes normally
  /// if the session does not exist.
  Future<void> stop(String name);

  /// Sends a soft interrupt (SIGINT / Ctrl-C) to the named session — graceful
  /// nudge-to-stop before [stop]. Best-effort: completes normally if the session
  /// does not exist.
  Future<void> interrupt(String name);

  // ---- Observations (Streams) ----

  /// The lifecycle event stream across ALL sessions this provider owns
  /// (demultiplex by [RuntimeEvent.name]). Broadcast: late subscribers see
  /// events from their subscription point on.
  Stream<RuntimeEvent> get events;

  /// The live transcript (merged stdout+stderr lines) of the named session.
  /// Broadcast per session; empty for an unknown session.
  Stream<String> output(String name);

  // ---- Point-in-time queries ----

  /// Whether the named provider runtime exists (a session record is held). Does
  /// not by itself prove the agent process is alive — use [processAlive].
  bool isRunning(String name);

  /// Whether the named session's agent process is currently live in the OS.
  bool processAlive(String name);

  /// The last [lines] of captured output for the named session (all buffered
  /// output when `lines <= 0`); empty for an unknown session. gc's `Peek`.
  String peek(String name, int lines);

  /// The names of all running sessions whose name starts with [prefix] — orphan
  /// detection / listing. gc's `ListRunning`.
  List<String> listRunning(String prefix);

  /// The time of the last observed I/O activity in the named session, or null
  /// when unknown/unsupported. gc's `GetLastActivity`.
  DateTime? lastActivity(String name);

  /// The RETAINED terminal of the named session — the exact
  /// [RuntimeEvent.exited]/[RuntimeEvent.died] this provider emitted for it,
  /// inferred flag and reason intact — or null while the session is live,
  /// unknown, or released.
  ///
  /// A terminal is STATE, not just an instant on [events] (tg-uad): the
  /// provider latches it BEFORE emitting, so a consumer that subscribed after
  /// the emission (or whose emission fired with zero listeners on the
  /// unbuffered broadcast stream) can still query the outcome. The live path
  /// stays push ([events]); this held record is the state half of the standard
  /// state-then-stream pattern — consult [terminalOf] first, then subscribe.
  ///
  /// RELEASE semantics (deliberate; part of this contract):
  ///  - a new [start] of the same name CLEARS the prior incarnation's stale
  ///    terminal — the name is reborn, and an old outcome must never shadow
  ///    the new incarnation;
  ///  - [stop] of the name RELEASES it (the teardown / lease-release path: a
  ///    stopped session is silent by design AND holds no terminal);
  ///  - provider teardown (dispose/close) releases all held terminals.
  RuntimeEvent? terminalOf(String name);

  /// The OS identity of the named LIVE session — its leader pid and (when
  /// resolution succeeded at spawn) its pgid — or null when the session is
  /// unknown, already terminal, or its spawn has not yet stamped a pid.
  ///
  /// The synchronous surface an acquire that lost the `SessionStarted` race
  /// resolves a handle from (tg-090/D5): for a session that already existed,
  /// `SessionStarted` fired before this incarnation subscribed and never
  /// re-fires — never wait for it; query this (and [terminalOf], which covers
  /// the already-dead case) instead.
  ({int pid, int? pgid})? identityOf(String name);

  /// What this provider can reliably detect (gc's `Capabilities()`), so callers
  /// degrade explicitly.
  RuntimeCapabilities get capabilities;
}

/// Thrown by [RuntimeProvider.start] when a live session already holds the
/// requested name — gc's `ErrSessionExists` (`runtime.go:22-24`).
class SessionAlreadyExists implements Exception {
  const SessionAlreadyExists(this.name);

  final String name;

  @override
  String toString() => 'SessionAlreadyExists: session "$name" already exists';
}
