import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'env_allowlist.dart';
import 'incarnation_env.dart';
import 'process_group.dart';
import 'runtime_config.dart';
import 'runtime_event.dart';
import 'runtime_provider.dart';

/// The Process SEAM for spawning agents — the single point where
/// [SubprocessProvider] touches `Process.start`. Mirrors grid_reconciler's
/// [ProcessRunner] / beads_dart's [BdRunner]: the real impl
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
class SystemSubprocessSpawner implements SubprocessSpawner {
  const SystemSubprocessSpawner();

  @override
  Future<SpawnedProcess> spawn({
    required String executable,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    final process = await Process.start(
      executable,
      args,
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
class SubprocessProvider implements RuntimeProvider {
  SubprocessProvider({
    SubprocessSpawner spawner = const SystemSubprocessSpawner(),
    ProcessGroupController groupController =
        const SystemProcessGroupController(),
    AgentEnvAllowlist allowlist = const AgentEnvAllowlist(),
    Map<String, String>? parentEnvironment,
    Duration stopGrace = const Duration(seconds: 2),
    Duration livenessPollPeriod = const Duration(milliseconds: 100),
    int peekBufferLines = 2000,
    Random? random,
  }) : _spawner = spawner,
       _groups = groupController,
       _allowlist = allowlist,
       _parentEnv = parentEnvironment ?? systemEnvironment(),
       _stopGrace = stopGrace,
       _pollPeriod = livenessPollPeriod,
       _peekBufferLines = peekBufferLines,
       _random = random;

  final SubprocessSpawner _spawner;
  final ProcessGroupController _groups;
  final AgentEnvAllowlist _allowlist;
  final Map<String, String> _parentEnv;
  final Duration _stopGrace;
  final Duration _pollPeriod;
  final int _peekBufferLines;
  final Random? _random;

  final Map<String, _Session> _sessions = <String, _Session>{};
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

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_sessions.containsKey(name)) {
      throw SessionAlreadyExists(name);
    }
    // Reserve the name synchronously so a concurrent same-name start rejects.
    final session = _Session(
      name: name,
      peekBufferLines: _peekBufferLines,
      lifecycle: config.lifecycle,
    );
    _sessions[name] = session;

    final SpawnedProcess spawned;
    try {
      spawned = await _spawner.spawn(
        executable: config.command,
        args: config.args,
        workingDirectory: config.workDir,
        environment: _buildChildEnv(name, config),
      );
    } on Object {
      _sessions.remove(name);
      rethrow;
    }

    session.pid = spawned.pid;
    session.pgid = await _groups.resolvePgid(spawned.pid);
    session.startedAt = DateTime.now();
    session.lastActivity = session.startedAt;

    // Pipe the transcript: merge stdout+stderr into the per-session line stream
    // and the bounded peek buffer.
    session.attachTranscript(spawned.stdout, spawned.stderr);

    _emit(
      RuntimeEvent.sessionStarted(
        name: name,
        pid: spawned.pid,
        pgid: session.pgid,
        beadId: config.env['GRID_BEAD_ID'] ?? '',
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
        exitFuture.then((code) {
          if (session.stopping || !_sessions.containsKey(name)) return;
          session.observedExitCode = code;
          session.cancelSupervision();
          _emitExit(session);
        }).catchError((_) {}),
      );
    }
    session.supervise(
      poll: () => session.pid != null && _groups.processAlive(session.pid!),
      pollPeriod: _pollPeriod,
      onDeath: () {
        if (!_sessions.containsKey(name)) return; // stopped, not died
        _emitExit(session);
      },
    );
    return;
  }

  @override
  Future<void> stop(String name) async {
    final session = _sessions.remove(name);
    if (session == null) return; // idempotent
    session.stopping = true;
    session.cancelSupervision();

    final pgid = session.pgid;
    final pid = session.pid;
    if (pgid != null && pid != null) {
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
    } else if (pid != null) {
      // pgid resolution failed at spawn — best-effort direct kill.
      Process.killPid(pid, ProcessSignal.sigterm);
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    session.close();
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
  Stream<String> output(String name) =>
      _sessions[name]?.transcript ?? const Stream<String>.empty();

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

  void _emit(RuntimeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _emitExit(_Session session) {
    // Guard against a double-emit when the exit-code future and the liveness
    // poll both fire for the same death.
    if (session.exitEmitted) return;
    session.exitEmitted = true;
    _sessions.remove(session.name);
    final code = session.observedExitCode;
    if (code != null) {
      _emit(RuntimeEvent.exited(name: session.name, exitCode: code));
    } else if (session.lifecycle == Lifecycle.oneTurn) {
      // A run-once agent that disappears has COMPLETED its single turn. The
      // detached spawn gives no readable exit code, so we cannot prove `0` —
      // but a one-shot exit is success-by-intent (whether the WORK succeeded is
      // judged by its commit, separately). Emit a clean exit so the actuator
      // parks it asleep instead of treating success as a crash and
      // crash-looping/quarantining it (the bug the first genesis arm exposed).
      _emit(RuntimeEvent.exited(name: session.name, exitCode: 0));
    } else {
      // A longLived agent that vanishes really did die unexpectedly → crash.
      _emit(RuntimeEvent.died(name: session.name, reason: 'process vanished'));
    }
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
    await _events.close();
  }
}

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

  /// Set once the death event has been emitted, so a near-simultaneous
  /// exit-future resolution and liveness-poll miss cannot double-emit.
  bool exitEmitted = false;

  /// An exit code, set only if the spawner surfaced one (the system spawner
  /// cannot read it for a detached process; a fake can provide it). Null ⇒
  /// death is reported as [RuntimeEvent.died].
  int? observedExitCode;

  final StreamController<String> _transcript =
      StreamController<String>.broadcast();
  final List<String> _peekBuffer = <String>[];
  Timer? _superviseTimer;
  bool _closed = false;

  Stream<String> get transcript => _transcript.stream;

  /// Merges [out] and [err] byte streams into newline-delimited transcript
  /// lines, fanned to the broadcast stream and the bounded peek ring.
  void attachTranscript(Stream<List<int>> out, Stream<List<int>> err) {
    void onLine(String line) {
      lastActivity = DateTime.now();
      _peekBuffer.add(line);
      if (_peekBuffer.length > peekBufferLines) {
        _peekBuffer.removeRange(0, _peekBuffer.length - peekBufferLines);
      }
      if (!_transcript.isClosed) _transcript.add(line);
    }

    out
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {}, cancelOnError: false);
    err
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {}, cancelOnError: false);
  }

  /// Polls [poll] every [pollPeriod]; calls [onDeath] once when it first reports
  /// the process gone.
  void supervise({
    required bool Function() poll,
    required Duration pollPeriod,
    required void Function() onDeath,
  }) {
    _superviseTimer = Timer.periodic(pollPeriod, (timer) {
      if (_closed || stopping) {
        timer.cancel();
        return;
      }
      if (!poll()) {
        timer.cancel();
        onDeath();
      }
    });
  }

  void cancelSupervision() {
    _superviseTimer?.cancel();
    _superviseTimer = null;
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
    if (!_transcript.isClosed) _transcript.close();
  }
}
