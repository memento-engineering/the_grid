import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'env_allowlist.dart';
import 'incarnation_env.dart';
import 'process_group.dart';
import 'runtime_config.dart';
import 'runtime_event.dart';
import 'runtime_provider.dart';

/// The env var naming the per-session file the REAPER PARENT writes the real
/// leader exit code into. [SubprocessProvider.start] sets it (the provider owns
/// the path); [SystemSubprocessSpawner.spawn] reads it to decide whether to
/// compose the reaper; the provider reads the FILE on vanish. Absent or empty ⇒
/// no reaper is composed and the spawn is byte-for-byte what it was before, so
/// any caller outside the provider is unchanged.
const String kExitStatusFileEnv = 'GRID_EXIT_STATUS_FILE';

/// How long a session whose LEADER is gone but whose OWNED process group still
/// has live members is given to drain before that group is signalled. Generous
/// on purpose: a legitimately-backgrounded flush deserves to finish, and the
/// session cannot advance the circuit while the grace runs anyway.
const Duration kOrphanGrace = Duration(seconds: 30);

/// The REAPER PARENT script. `detachedWithStdio` buys the process group but
/// costs the exit code (`Process.exitCode` throws for a detached process), so a
/// vanish had to be INFERRED — and a murdered agent vanishes exactly like a
/// finished one. This wrapper IS the leader: it runs the harness as its child in
/// the SAME group, WAITS for it, writes the real code, and exits with it.
///
/// `"$@"` keeps argv positional, so the no-shell contract still holds (no word
/// splitting; gc `condition.go:319`). The write is atomic (`.part` then
/// `mv -f`) and completes BEFORE the wrapper exits, so a provider that only
/// reads the file once the leader is gone can never observe a torn value; if
/// `mv` itself fails the `.part` file is inert and the provider falls back to
/// the INFERRED reading rather than reading half a number.
const String kReaperScript = r'''
"$@"
__grid_code=$?
if [ -n "$GRID_EXIT_STATUS_FILE" ]; then
  printf '%s\n' "$__grid_code" > "$GRID_EXIT_STATUS_FILE.part" 2>/dev/null &&
    mv -f "$GRID_EXIT_STATUS_FILE.part" "$GRID_EXIT_STATUS_FILE" 2>/dev/null
fi
exit $__grid_code
''';

/// The Process SEAM for spawning agents — the single point where
/// [SubprocessProvider] touches `Process.start`. Mirrors
/// beads_dart's [BdRunner]: the real impl
/// ([SystemSubprocessSpawner]) spawns; tests inject a fake that returns a
/// programmed handle, so the supervision/event/env logic runs offline (Fakes,
/// not mocks). A reference type (the `Spawner` role name).
abstract interface class SubprocessSpawner {
  /// Spawns [executable] with [args] in [workingDirectory], with EXACTLY
  /// [environment] as the child env (`includeParentEnvironment: false`), in a
  /// NEW PROCESS GROUP (`ProcessStartMode.detachedWithStdio`). Returns a handle
  /// over the live process. Never runs a shell (no word-splitting; the exit-code
  /// contract holds — gc `condition.go:319`).
  Future<SpawnedProcess> spawn({
    required String executable,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  });
}

/// A handle over one spawned agent process — the seam's return value, so a fake
/// can synthesize stdout/stderr streams and an exit signal without a real OS
/// process.
abstract interface class SpawnedProcess {
  /// The OS pid of the spawned process.
  int get pid;

  /// Merged child stdout as a byte stream.
  Stream<List<int>> get stdout;

  /// Merged child stderr as a byte stream.
  Stream<List<int>> get stderr;

  /// The process exit code, when the spawner can read it — null for a real
  /// `detachedWithStdio` process (Dart throws `Bad state: Process is detached`
  /// for `Process.exitCode` in detached modes, so the system spawner cannot
  /// provide it and the supervisor reports death via liveness-poll →
  /// [RuntimeEvent.died]). A fake spawner provides it so the supervisor emits a
  /// precise [RuntimeEvent.exited] with the code.
  Future<int>? get exitCode;

  /// Writes [bytes] unchanged to the child's stdin and flushes them.
  Future<void> write(List<int> bytes);

  /// Closes the child's stdin exactly once.
  Future<void> closeInput();
}

/// Spawns real agent subprocesses via `dart:io` with the Track-2 contract.
///
/// **Spawn mode — `detachedWithStdio`, justified.** The child MUST land in a new
/// process group so [stop] can kill the *whole tree* with `kill(-pgid, …)`
/// (gc's `Setpgid`, `processgroup_unix.go:46-51`). Dart exposes no `Setpgid`
/// flag; the portable options were (a) a `setsid` wrapper — but `setsid` is
/// absent on macOS — or (b) a `sh -c exec` wrapper — but `sh -c` does NOT start
/// a new process group. `ProcessStartMode.detachedWithStdio` is the one
/// mechanism that both **`setsid()`s** the child into a fresh session+group AND
/// keeps the stdio pipes connected for transcript streaming. Its cost — that
/// `Process.exitCode` is unavailable for detached processes (it throws
/// `Bad state: Process is detached`) — is paid by [SubprocessProvider] polling
/// process liveness via the [ProcessGroupController] seam instead, which is the
/// honest signal anyway (a backgrounded grandchild can hold the stdout pipe open
/// long after the agent exits, so stdout-EOF is NOT a reliable death signal).
///
/// Its second cost — that a detached exit code is unreadable AT ALL — is paid by
/// [kReaperScript]: the spawned leader is a tiny `sh` parent that waits on the
/// harness and records its real status, so the provider reads a fact instead of
/// inferring one.
class SystemSubprocessSpawner implements SubprocessSpawner {
  const SystemSubprocessSpawner();

  @override
  Future<SpawnedProcess> spawn({
    required String executable,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    // Compose the reaper parent when the caller asked for a real exit status.
    // `$0` is `grid-reaper` so an operator reading `ps` can see what it is.
    final statusFile = environment[kExitStatusFileEnv] ?? '';
    final reaped = statusFile.isNotEmpty;
    final process = await Process.start(
      reaped ? '/bin/sh' : executable,
      reaped
          ? <String>['-c', kReaperScript, 'grid-reaper', executable, ...args]
          : args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
      mode: ProcessStartMode.detachedWithStdio,
    );
    return _SystemSpawnedProcess(process);
  }
}

class _SystemSpawnedProcess implements SpawnedProcess {
  _SystemSpawnedProcess(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  // Unavailable for a detached process — see [SpawnedProcess.exitCode].
  @override
  Future<int>? get exitCode => null;

  @override
  Future<void> write(List<int> bytes) async {
    _process.stdin.add(List<int>.unmodifiable(bytes));
    await _process.stdin.flush();
  }

  @override
  Future<void> closeInput() => _process.stdin.close();
}

/// The dogfood-default [RuntimeProvider]: spawns a `claude` agent per ready bead
/// in its worktree as a no-shell, allowlist-env, new-process-group subprocess;
/// supervises it; streams its transcript; and surfaces lifecycle as
/// [RuntimeEvent]s (M3-BUILD-ORDER Track 2).
///
/// **Env policy (the security boundary).** The child env is built fresh:
/// [AgentEnvAllowlist] over the parent env (forwards `CLAUDE_CODE_OAUTH_TOKEN`
/// and the other allowlist entries, drops `GC_DOLT_PASSWORD` and all other host
/// secrets), then the per-incarnation [IncarnationEnv] `GRID_*` vars, then any
/// explicit [RuntimeConfig.env] on top. `includeParentEnvironment: false`
/// guarantees nothing else leaks.
///
/// **CUT (Track 2):** no inference-provider abstraction, no per-session Unix
/// control socket (this in-process registry of [_Session] handles suffices for
/// Tier-1), no attach/nudge. The `TmuxProvider` adapter lands with Track 1.
/// Renders [d] for a human reading a death reason ('2h', '90m', '30s', '300ms')
/// — a watchdog that cannot say what limit it enforced is half a refusal. Never
/// rounds a real duration to a bare '0'.
String _humanize(Duration d) {
  if (d.inHours > 0 && d.inMinutes % 60 == 0) return '${d.inHours}h';
  if (d.inMinutes > 0 && d.inSeconds % 60 == 0) return '${d.inMinutes}m';
  if (d.inSeconds > 0) return '${d.inSeconds}s';
  return '${d.inMilliseconds}ms';
}

class SubprocessProvider implements RuntimeProvider {
  SubprocessProvider({
    SubprocessSpawner spawner = const SystemSubprocessSpawner(),
    ProcessGroupController groupController =
        const SystemProcessGroupController(),
    AgentEnvAllowlist allowlist = const AgentEnvAllowlist(),
    Map<String, String>? parentEnvironment,
    Duration stopGrace = const Duration(seconds: 2),
    Duration livenessPollPeriod = const Duration(milliseconds: 100),
    Duration? agentDeadline = const Duration(hours: 2),
    Duration orphanGrace = kOrphanGrace,
    Directory? exitStatusDirectory,
    int peekBufferLines = 2000,
    Random? random,
  }) : _spawner = spawner,
       _groups = groupController,
       _allowlist = allowlist,
       _parentEnv = parentEnvironment ?? systemEnvironment(),
       _stopGrace = stopGrace,
       _pollPeriod = livenessPollPeriod,
       _agentDeadline = agentDeadline,
       _orphanGrace = orphanGrace,
       _exitStatusDirectory = exitStatusDirectory,
       _peekBufferLines = peekBufferLines,
       _random = random;

  final SubprocessSpawner _spawner;
  final ProcessGroupController _groups;
  final AgentEnvAllowlist _allowlist;
  final Map<String, String> _parentEnv;
  final Duration _stopGrace;
  final Duration _pollPeriod;
  final Duration _orphanGrace;

  /// Where per-session reaper status files land. Injected by tests; otherwise a
  /// provider-owned temp dir created on first use and deleted by [dispose].
  /// It is deliberately OUTSIDE the agent's worktree: a status file written
  /// into the worktree would read as uncommitted work to the engine's
  /// `committedWorkspace` completion fence and turn every proven completion
  /// into a respawn loop.
  Directory? _exitStatusDirectory;
  bool _ownsStatusDirectory = false;

  /// The WATCHDOG deadline: how long ONE agent may live before it is presumed
  /// hung and killed. Null disarms it (the tests' default posture).
  ///
  /// The station could see an agent DIE, but never an agent that was ALIVE and
  /// doing NOTHING — so a hang latched its node at `running` FOREVER, silently,
  /// with no telemetry and no error. That is exactly how a one-line stdin bug
  /// (the_grid #57) cost an overnight arm: the wedge had no time limit, so it
  /// had no end.
  ///
  /// It is an ABSOLUTE deadline from spawn, deliberately NOT an inactivity
  /// timer: `claude -p --output-format json` prints NOTHING until it finishes,
  /// so "no output for N minutes" would shoot every healthy claude agent. Time
  /// since spawn is the one signal that means the same thing for every harness.
  ///
  /// Generous by design — this is a BACKSTOP against the infinite, not a
  /// performance budget. It must sit well above the slowest legitimate step (a
  /// grinding specify has burned ~137K tokens over tens of minutes), because a
  /// false kill costs a whole round while a missed hang costs the whole arm.
  final Duration? _agentDeadline;
  final int _peekBufferLines;
  final Random? _random;

  final Map<String, _Session> _sessions = <String, _Session>{};

  /// Each session's RETAINED terminal, latched by [_emitExit] BEFORE the event
  /// is emitted — a terminal is STATE, not just an instant on the unbuffered
  /// broadcast stream (tg-uad). See [RuntimeProvider.terminalOf] for the
  /// release contract this map implements ([start] clears, [stop] releases,
  /// [dispose] drops all).
  final Map<String, RuntimeEvent> _terminals = <String, RuntimeEvent>{};

  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  /// Builds the complete child environment for [name]/[config]: allowlist over
  /// the parent env, then the `GRID_*` incarnation vars, then explicit config
  /// env. Exposed (package-private via the provider) only through [start]; the
  /// layering order is the contract a test asserts.
  Map<String, String> _buildChildEnv(String name, RuntimeConfig config) {
    final env = _allowlist.build(_parentEnv);
    final incarnation = IncarnationEnv.mint(
      sessionId: name,
      beadId: config.env['GRID_BEAD_ID'] ?? '',
      random: _random,
    );
    env.addAll(incarnation.toEnv());
    // Explicit config env wins last (a caller can override e.g. GRID_BEAD_ID or
    // thread the token explicitly), but it is layered on top of, never instead
    // of, the allowlist+incarnation base.
    env.addAll(config.env);
    return env;
  }

  /// The provider's own status-file directory, created on first use.
  ///
  /// This holds an OWNED RESOURCE HANDLE, not an ambient tree dependency — the
  /// ADR-0008 D-H "never `??=`-cache" rule is about values read from the tree,
  /// and nothing here is read from one.
  Directory _statusDirectory() {
    final existing = _exitStatusDirectory;
    if (existing != null) return existing;
    final created = Directory.systemTemp.createTempSync('grid_exit_status_');
    _ownsStatusDirectory = true;
    _exitStatusDirectory = created;
    return created;
  }

  /// The per-incarnation status file for [name]. Session names carry slashes
  /// (`<sessionId>/<nodePath>`), so they are sanitized; [token] (the
  /// incarnation's `GRID_INSTANCE_TOKEN`) keeps two sanitized names from ever
  /// sharing one file.
  File _exitStatusFileFor(String name, String token) {
    final safe = name.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    return File(p.join(_statusDirectory().path, '$safe-$token.status'));
  }

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_sessions.containsKey(name)) {
      throw SessionAlreadyExists(name);
    }
    // A NEW incarnation of [name]: clear the prior incarnation's retained
    // terminal (the [terminalOf] release contract — the name is reborn, and a
    // stale outcome must never shadow the new process).
    _terminals.remove(name);
    // Reserve the name synchronously so a concurrent same-name start rejects.
    final session = _Session(
      name: name,
      peekBufferLines: _peekBufferLines,
      lifecycle: config.lifecycle,
    );
    _sessions[name] = session;

    final env = _buildChildEnv(name, config);
    // The provider OWNS the reaper contract, so its path wins over any
    // `config.env` entry of the same name.
    final statusFile = _exitStatusFileFor(
      name,
      env['GRID_INSTANCE_TOKEN'] ?? '',
    );
    env[kExitStatusFileEnv] = statusFile.path;
    session.exitStatusFile = statusFile;

    final SpawnedProcess spawned;
    try {
      spawned = await _spawner.spawn(
        executable: config.command,
        args: config.args,
        workingDirectory: config.workDir,
        environment: env,
      );
    } on Object {
      _sessions.remove(name);
      session.close();
      rethrow;
    }

    session.pid = spawned.pid;
    session.bind(spawned);
    var stopRacedSpawn = false;
    try {
      if (config.lifecycle == Lifecycle.oneTurn) {
        // CLOSE argv-only one-turn stdin before the next asynchronous operation.
        // An open, never-written pipe means input is still pending: `codex exec`
        // waits for EOF before opening its thread, leaving the session hung with
        // no transcript or terminal event when the close is delayed.
        await session.closeInput();
      }
    } finally {
      session.pgid = await _groups.resolvePgid(spawned.pid);
      session.startedAt = DateTime.now();
      session.lastActivity = session.startedAt;

      // A `stop` raced this spawn (a teardown walked the tree while we were
      // suspended in the spawner). It found no pid to kill and deregistered us,
      // so NOTHING else will ever reap this process — kill it HERE, through the
      // same guarded path `stop` uses. This `finally` keeps the hand-off live
      // even when one-turn stdin closure throws.
      stopRacedSpawn = session.stopping || !identical(_sessions[name], session);
      if (stopRacedSpawn) {
        await _terminateSession(session);
        session.close();
      }
    }
    if (stopRacedSpawn) {
      return;
    }

    // Pipe the transcript: merge stdout+stderr into the per-session line stream
    // and the bounded peek buffer.
    final stdout = config.lifecycle == Lifecycle.longLived
        ? session.tapStdout(spawned.stdout)
        : spawned.stdout;
    session.attachTranscript(stdout, spawned.stderr);

    final effectiveDeadline = config.deadline ?? _agentDeadline;

    _emit(
      RuntimeEvent.sessionStarted(
        name: name,
        pid: spawned.pid,
        pgid: session.pgid,
        beadId: config.env['GRID_BEAD_ID'] ?? '',
        deadline: effectiveDeadline,
        // Read off the SAME env the child receives, exactly like [beadId]
        // above — never minted here. The caller's `config.env` layers LAST in
        // [_buildChildEnv], so this is the engine's attempt id (the one on the
        // `grid.lease.*` breadcrumb), not a value this provider invented
        // (stage1-wiring §2.1).
        attemptId: config.env['GRID_ATTEMPT_ID'] ?? '',
      ),
    );

    // Supervise. Two death signals, whichever fires first:
    //   1. A readable exit code (the fake spawner / any non-detached path) —
    //      precise → RuntimeEvent.exited with the code.
    //   2. Liveness-poll going false (the real detached path, which has no
    //      readable code) → RuntimeEvent.died.
    final exitFuture = spawned.exitCode;
    if (exitFuture != null) {
      unawaited(
        exitFuture
            .then((code) {
              if (session.stopping || !_sessions.containsKey(name)) return;
              session.observedExitCode = code;
              session.cancelSupervision();
              _emitExit(session);
            })
            .catchError((_) {}),
      );
    }
    session.supervise(
      poll: () => _groupAlive(session),
      pollPeriod: _pollPeriod,
      onDeath: () {
        if (!_sessions.containsKey(name)) return;
        _emitExit(session);
      },
    );
    // The watchdog is per spawned runtime session: agents use the provider
    // default; validation and critic lanes can pass a tighter config deadline.
    if (effectiveDeadline != null) {
      session.armDeadline(effectiveDeadline, () {
        if (!_sessions.containsKey(name)) return;
        session.deadlineReason =
            'watchdog: session exceeded its ${_humanize(effectiveDeadline)} '
            'deadline and was killed (presumed hung)';
        unawaited(
          _terminateSession(session).whenComplete(() {
            session.cancelSupervision();
            _emitExit(session);
          }),
        );
      });
    }
    return;
  }

  @override
  Future<void> stop(String name) async {
    // The [terminalOf] release contract: stop RELEASES the retained terminal —
    // both for a live session being torn down and for one already dead (the
    // lease-release path stops the name after its terminal settled the step).
    _terminals.remove(name);
    final session = _sessions.remove(name);
    if (session == null) return; // idempotent
    session.stopping = true;
    session.cancelSupervision();

    // [start] reserves the name synchronously but stamps `pid`/`pgid` only once
    // the spawner returns, so a `stop` that lands while the spawn is IN FLIGHT
    // has NO kill target: it can signal nothing. HAND OFF instead — the session
    // is already marked `stopping` and deregistered, so the landing spawn reaps
    // its OWN group and closes. Closing the transcript here would pull it out
    // from under that spawn, so leave it to the one that still owns it.
    if (session.pid == null) return;

    await _terminateSession(session);
    session.close();
  }

  /// The guarded group kill for ONE session — SIGTERM→grace→SIGKILL over the
  /// whole process group ([terminateGroup]), with a direct-pid fallback when the
  /// pgid is unusable (unresolved, or refused by the `pgid <= 1`/own-group
  /// safety guard — which is never bypassed) so an agent is never left running.
  ///
  /// THE single kill path: [stop] runs it, and so does a [start] whose spawn
  /// landed into an already-stopped session (the hand-off) — the two can
  /// therefore never drift.
  Future<void> _terminateSession(_Session session) async {
    final pid = session.pid;
    if (pid == null) return; // no target (callers check; belt-and-braces)
    final pgid = session.pgid;
    if (pgid != null) {
      final result = await terminateGroup(
        controller: _groups,
        pgid: pgid,
        leaderPid: pid,
        grace: _stopGrace,
      );
      // refusedUnsafe → fall back to a direct single-process kill so an
      // unresolved/unsafe pgid never leaves the agent running.
      if (result == GroupTerminateResult.refusedUnsafe) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
      return;
    }
    // pgid resolution failed at spawn — best-effort direct kill.
    Process.killPid(pid, ProcessSignal.sigterm);
    Process.killPid(pid, ProcessSignal.sigkill);
  }

  /// The session's liveness: the LEADER, or — once the leader is gone — any live
  /// member of the OWNED process group.
  ///
  /// A leader that backgrounds a descendant and exits is NOT terminal. Its group
  /// is still burning resources and still mutating the worktree, and a terminal
  /// there would let the circuit advance on a lie. The first time this is
  /// observed the session is reported ORPHANED and a bounded grace is armed. A
  /// group that empties on its own BEFORE the grace elapses reaches the normal
  /// terminal path with no orphan kill — a backgrounded flush that finished.
  ///
  /// The group probe runs ONLY once the cheap leader probe says gone, so a
  /// healthy session never shells out. A group we could never signal (no pgid,
  /// `pgid <= 1`, our own group — the [terminateGroup] refusals) is no evidence
  /// at all: the leader's death stays the terminal, exactly as before.
  Future<bool> _groupAlive(_Session session) async {
    final pid = session.pid;
    if (pid == null) return false;
    if (_groups.processAlive(pid)) return true;
    final pgid = session.pgid;
    if (pgid == null || pgid <= 1 || pgid == _groups.currentGroupId()) {
      return false;
    }
    final members = await _groups.groupMembers(pgid);
    if (members.isEmpty) return false;
    _noteOrphaned(session, pgid: pgid, memberCount: members.length);
    return true;
  }

  /// Reports the orphan ONCE and arms the bounded grace. When it elapses the
  /// group is signalled through the SAME guarded path [stop] uses, and the
  /// session is latched terminal afterwards: whatever survives a full
  /// SIGTERM→grace→SIGKILL escalation is unkillable by us, and a node stuck at
  /// `running` with no event is the wedge the watchdog exists to prevent.
  void _noteOrphaned(
    _Session session, {
    required int pgid,
    required int memberCount,
  }) {
    if (session.orphanReported) return;
    session.orphanReported = true;
    _emit(
      RuntimeEvent.sessionOrphaned(
        name: session.name,
        pgid: pgid,
        memberCount: memberCount,
        pid: session.pid,
      ),
    );
    session.armOrphanGrace(_orphanGrace, () {
      if (!_sessions.containsKey(session.name)) return;
      session.orphanKillReason =
          'orphaned descendants killed: the leader exited but process group '
          '$pgid still had live members after a ${_humanize(_orphanGrace)} '
          'grace';
      unawaited(
        _terminateSession(session).whenComplete(() {
          session.cancelSupervision();
          _emitExit(session);
        }),
      );
    });
  }

  @override
  Future<void> interrupt(String name) async {
    final session = _sessions[name];
    final pid = session?.pid;
    if (pid == null) return; // best-effort
    // SIGINT to the group so the agent and its children get the Ctrl-C.
    final pgid = session!.pgid;
    if (pgid != null && pgid > 1 && pgid != _groups.currentGroupId()) {
      _groups.signalGroup(pgid, ProcessSignal.sigint);
    } else {
      Process.killPid(pid, ProcessSignal.sigint);
    }
  }

  @override
  Future<void> write(String name, List<int> bytes) {
    final session = _sessions[name];
    if (session == null || _terminals.containsKey(name)) {
      throw SessionNotWritable(name, 'unknown or terminal session');
    }
    return session.write(bytes);
  }

  @override
  Stream<String> output(String name) =>
      _sessions[name]?.transcript ?? const Stream<String>.empty();

  @override
  Stream<List<int>> interactionOutput(String name) {
    final session = _sessions[name];
    if (session == null ||
        session.lifecycle != Lifecycle.longLived ||
        _terminals.containsKey(name)) {
      throw SessionNotWritable(name, 'no long-lived interaction stream');
    }
    return session.interaction;
  }

  @override
  bool isRunning(String name) => _sessions.containsKey(name);

  @override
  bool processAlive(String name) {
    final pid = _sessions[name]?.pid;
    return pid != null && _groups.processAlive(pid);
  }

  @override
  String peek(String name, int lines) {
    final session = _sessions[name];
    if (session == null) return '';
    return session.peek(lines);
  }

  @override
  List<String> listRunning(String prefix) =>
      _sessions.keys.where((n) => n.startsWith(prefix)).toList(growable: false);

  @override
  DateTime? lastActivity(String name) => _sessions[name]?.lastActivity;

  @override
  RuntimeEvent? terminalOf(String name) => _terminals[name];

  @override
  ({int pid, int? pgid})? identityOf(String name) {
    final session = _sessions[name];
    final pid = session?.pid;
    if (pid == null) return null;
    return (pid: pid, pgid: session!.pgid);
  }

  void _emit(RuntimeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _emitExit(_Session session) {
    // Guard against a double-emit when the exit-code future and the liveness
    // poll both fire for the same death.
    if (session.exitEmitted) return;
    session.exitEmitted = true;
    _sessions.remove(session.name);
    // A WATCHDOG kill is a DEATH, and outranks every other reading. A `oneTurn`
    // agent that vanishes is normally an inferred success — and a hung agent we
    // just shot vanishes EXACTLY like a finished one, so without this branch the
    // watchdog would report the hang it caught as a clean completion.
    final RuntimeEvent terminal;
    final killed = session.deadlineReason;
    // The pid this terminal belongs to, carried so a consumer joining the exit
    // back to the start it observed can prove the two are the SAME process
    // (the session name is a slot, and a stop racing a respawn can refill it).
    final pid = session.pid;
    // The REAL leader exit status, when the reaper parent wrote one.
    final reaped = session.readReapedExitCode();
    final orphaned = session.orphanKillReason;
    if (killed != null) {
      terminal = RuntimeEvent.died(
        name: session.name,
        reason: killed,
        pid: pid,
      );
    } else if (orphaned != null) {
      // A session we had to shoot for its survivors is NEVER a clean success,
      // however its leader exited — the descendants may have been mid-write.
      // `Died` is the only terminal that carries a reason, so the fence and the
      // harvest can both see WHY.
      terminal = RuntimeEvent.died(
        name: session.name,
        reason: reaped == null ? orphaned : '$orphaned (leader exit $reaped)',
        pid: pid,
      );
    } else {
      // A code the spawner READ outranks the reaper's file (same value by
      // construction — the wrapper exits with the harness's code — but it is
      // the more direct observation); the file is the detached path's proof.
      final code = session.observedExitCode ?? reaped;
      if (code != null) {
        terminal = RuntimeEvent.exited(
          name: session.name,
          exitCode: code,
          pid: pid,
        );
      } else if (session.lifecycle == Lifecycle.oneTurn) {
        // No reaper status file: a run-once agent that disappears has COMPLETED
        // its single turn (completion-by-intent), but the 0 is INFERRED from the
        // vanish, not read — a murdered agent vanishes identically, so the
        // engine's completion fence proves it against the workspace before it
        // advances the circuit.
        terminal = RuntimeEvent.exited(
          name: session.name,
          exitCode: 0,
          inferred: true,
          pid: pid,
        );
      } else {
        // A longLived agent that vanishes really did die unexpectedly → crash.
        terminal = RuntimeEvent.died(
          name: session.name,
          reason: 'process vanished',
          pid: pid,
        );
      }
    }
    // LATCH the terminal as retained STATE **before** emitting (tg-uad): the
    // emission below may fire with zero listeners on the unbuffered broadcast
    // stream (the leased path's acquire→dispatch window), and this emit also
    // just disarmed the watchdog — the one backstop. Held first, a dropped
    // emission remains queryable through [terminalOf] and a late consumer
    // settles from state instead of latching at `running` forever.
    _terminals[session.name] = terminal;
    _emit(terminal);
    session.close();
  }

  /// Tears down the provider: cancels all supervision and closes the event
  /// stream. Does NOT kill live sessions (call [stop] per session first) — this
  /// is the controller-shutdown path.
  Future<void> dispose() async {
    for (final session in _sessions.values) {
      session.cancelSupervision();
      session.close();
    }
    _sessions.clear();
    // Provider teardown releases every retained terminal (the [terminalOf]
    // release contract).
    _terminals.clear();
    if (_ownsStatusDirectory) {
      final dir = _exitStatusDirectory;
      if (dir != null) {
        try {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } on Object {
          // Best-effort teardown of a temp dir; never fails a dispose.
        }
      }
    }
    await _events.close();
  }
}

/// Exposes [name]'s raw interaction controller to tests without widening the
/// [RuntimeProvider] contract.
@visibleForTesting
Stream<List<int>> interactionBufferForTesting(
  SubprocessProvider provider,
  String name,
) => provider._sessions[name]?.interaction ?? const Stream<List<int>>.empty();

/// In-process state for one supervised session — the registry entry that stands
/// in for gc's per-session Unix control socket (CUT for Tier-1).
class _Session {
  _Session({
    required this.name,
    required this.peekBufferLines,
    this.lifecycle = Lifecycle.longLived,
  });

  final String name;
  final int peekBufferLines;

  /// The expected lifetime of this session's command (from its [RuntimeConfig]).
  /// A `oneTurn` (run-once) agent that disappears has COMPLETED its single turn,
  /// not crashed — detached mode gives no exit code, so the provider would
  /// otherwise report every exit as a `died` (`process vanished`) and the
  /// actuator would crash-loop/quarantine a SUCCESSFUL agent. See [_emitExit].
  final Lifecycle lifecycle;

  int? pid;
  int? pgid;
  DateTime? startedAt;
  DateTime? lastActivity;
  bool stopping = false;
  SpawnedProcess? _process;
  bool _inputClosed = false;

  /// Set once the death event has been emitted, so a near-simultaneous
  /// exit-future resolution and liveness-poll miss cannot double-emit.
  bool exitEmitted = false;

  /// An exit code, set only if the spawner surfaced one (the system spawner
  /// cannot read it for a detached process; a fake can provide it). Null ⇒
  /// death is reported as [RuntimeEvent.died].
  int? observedExitCode;

  /// Set when the WATCHDOG killed this session for outliving its deadline —
  /// carries the reason for the [RuntimeEvent.died]. Its presence also FORCES
  /// the died path: a `oneTurn` agent that vanishes is normally reported as an
  /// inferred success, and a hung agent we shot must NEVER look like one.
  String? deadlineReason;

  /// The reaper parent's status file for this incarnation, or null when the
  /// session was never spawned through [SubprocessProvider.start].
  File? exitStatusFile;

  /// Set once the ORPHAN has been reported, so the event fires exactly once.
  bool orphanReported = false;

  /// Set when the orphan GRACE elapsed and the group was signalled — carries
  /// the reason for the [RuntimeEvent.died]. Its presence FORCES the died path:
  /// a session whose descendants we had to shoot must never read as a clean
  /// success, whatever the leader's own exit status was.
  String? orphanKillReason;

  Timer? _orphanTimer;
  bool _polling = false;

  Timer? _deadlineTimer;

  /// Arms the watchdog: [onDeadline] fires once if this session is still alive
  /// [after] its start.
  void armDeadline(Duration after, void Function() onDeadline) {
    _deadlineTimer = Timer(after, () {
      if (_closed || stopping) return;
      onDeadline();
    });
  }

  void cancelDeadline() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
  }

  /// The real leader exit code the REAPER PARENT wrote, or null when there is no
  /// status file (a caller that supplied none, or a leader killed before the
  /// wrapper could write). Never throws: an unreadable or malformed file is "no
  /// code", which falls back to the INFERRED reading rather than inventing one.
  int? readReapedExitCode() {
    final file = exitStatusFile;
    if (file == null) return null;
    try {
      if (!file.existsSync()) return null;
      return int.tryParse(file.readAsStringSync().trim());
    } on Object {
      return null;
    }
  }

  /// Arms the bounded orphan grace: [onGrace] fires once, [after] the orphan was
  /// first observed, if this session is still live.
  void armOrphanGrace(Duration after, void Function() onGrace) {
    _orphanTimer?.cancel();
    _orphanTimer = Timer(after, () {
      if (_closed || stopping) return;
      onGrace();
    });
  }

  final StreamController<String> _transcript =
      StreamController<String>.broadcast();
  final StreamController<List<int>> _interaction =
      StreamController<List<int>>();
  final List<String> _peekBuffer = <String>[];
  final List<StreamSubscription<String>> _transcriptSubs =
      <StreamSubscription<String>>[];
  Timer? _superviseTimer;
  bool _closed = false;

  Stream<String> get transcript => _transcript.stream;

  Stream<List<int>> get interaction => _interaction.stream;

  void bind(SpawnedProcess process) {
    _process = process;
  }

  Future<void> write(List<int> bytes) async {
    final process = _process;
    if (lifecycle != Lifecycle.longLived ||
        process == null ||
        _closed ||
        stopping) {
      throw SessionNotWritable(name, 'session is not a live long-lived child');
    }
    await process.write(List<int>.unmodifiable(bytes));
  }

  Future<void> closeInput() async {
    if (_inputClosed) return;
    _inputClosed = true;
    final process = _process;
    if (process != null) await process.closeInput();
  }

  Stream<List<int>> tapStdout(Stream<List<int>> source) => source.transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (bytes, sink) {
        final copy = List<int>.unmodifiable(bytes);
        if (!_interaction.isClosed) _interaction.add(copy);
        sink.add(copy);
      },
      handleError: (Object error, StackTrace stack, sink) {
        if (!_interaction.isClosed) {
          _interaction.addError(error, stack);
        }
        sink.addError(error, stack);
      },
    ),
  );

  /// Merges [out] and [err] byte streams into newline-delimited transcript
  /// lines, fanned to the broadcast stream and the bounded peek ring. The
  /// subscriptions are RETAINED and cancelled only by [close] — the transcript
  /// follows the GROUP, not the leader, so a survivor's output is still captured
  /// after the leader exits.
  void attachTranscript(Stream<List<int>> out, Stream<List<int>> err) {
    void onLine(String line) {
      lastActivity = DateTime.now();
      _peekBuffer.add(line);
      if (_peekBuffer.length > peekBufferLines) {
        _peekBuffer.removeRange(0, _peekBuffer.length - peekBufferLines);
      }
      if (!_transcript.isClosed) _transcript.add(line);
    }

    _transcriptSubs.add(
      out
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine, onError: (_) {}, cancelOnError: false),
    );
    _transcriptSubs.add(
      err
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine, onError: (_) {}, cancelOnError: false),
    );
  }

  /// Polls [poll] every [pollPeriod]; calls [onDeath] once when it first reports
  /// the process gone. [poll] is ASYNC because its group half shells out; an
  /// overlapping tick is SKIPPED rather than queued, so a slow probe can never
  /// stack up probes behind itself.
  void supervise({
    required Future<bool> Function() poll,
    required Duration pollPeriod,
    required void Function() onDeath,
  }) {
    _superviseTimer = Timer.periodic(pollPeriod, (timer) async {
      if (_closed || stopping) {
        timer.cancel();
        return;
      }
      if (_polling) return;
      _polling = true;
      try {
        final alive = await poll();
        if (_closed || stopping || !timer.isActive) return;
        if (!alive) {
          timer.cancel();
          onDeath();
        }
      } finally {
        _polling = false;
      }
    });
  }

  void cancelSupervision() {
    _superviseTimer?.cancel();
    _superviseTimer = null;
    _orphanTimer?.cancel();
    _orphanTimer = null;
    cancelDeadline();
  }

  String peek(int lines) {
    if (_peekBuffer.isEmpty) return '';
    final slice = lines <= 0 || lines >= _peekBuffer.length
        ? _peekBuffer
        : _peekBuffer.sublist(_peekBuffer.length - lines);
    return slice.join('\n');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    cancelSupervision();
    for (final sub in _transcriptSubs) {
      unawaited(sub.cancel());
    }
    _transcriptSubs.clear();
    final statusFile = exitStatusFile;
    if (statusFile != null) {
      try {
        if (statusFile.existsSync()) statusFile.deleteSync();
      } on Object {
        // Best-effort: a leftover status file is inert — the provider's temp
        // dir goes with [SubprocessProvider.dispose].
      }
    }
    unawaited(closeInput().catchError((Object _) {}));
    if (!_interaction.isClosed) unawaited(_interaction.close());
    if (!_transcript.isClosed) _transcript.close();
  }
}
