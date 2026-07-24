/// RS-5a — `StationAttach`: the station attach client (tg-3s8.5, D-C3/D-C4,
/// `docs/SCRATCH-resident-station.md` §3).
///
/// The thin client any asset app composes into its own verbs (`space status`
/// / `space down` — space_station, RS-5b): read the station lock
/// (`station_lock.dart`) → classify reachability against the RS-4
/// [StationControl](`station_control.dart`) surface, and a graceful-stop
/// helper that rides OS signals, never HTTP (D-C3 — "lifecycle rides OS
/// signals, not HTTP"). **Read-only + signals: this client can never mutate
/// over HTTP — there is nothing to call** (D-C4, the control plane is
/// GET-only by construction). Deleting or rewriting the lock file is likewise
/// out of scope here — a lingering stale lock is the NEXT `up`'s stale-steal
/// to reap ([StationLockService]), not this client's job.
///
/// No `Command`/`CommandRunner` lives here (scope fence) — that composition,
/// and the store-fallback render `space status` does when a station is down,
/// belong to space_station (RS-5b).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;

import 'station_lock.dart';

// ---------------------------------------------------------------------------
// Injected seams (Fakes, not mocks — house style)
// ---------------------------------------------------------------------------

/// The injected `HttpClient` construction seam — the real impl is
/// `HttpClient.new`; offline tests may inject a factory that pins
/// `connectionTimeout`/other knobs, though the real ephemeral-port
/// [StationControl] round-trips need no faking.
typedef HttpClientFactory = HttpClient Function();

/// The injected SIGTERM seam — real impl is `Process.killPid`; offline tests
/// inject a fake that records the call instead of signaling a real process.
typedef ProcessSignaller = bool Function(int pid, ProcessSignal signal);

// ---------------------------------------------------------------------------
// AttachResult (status())
// ---------------------------------------------------------------------------

/// The station's observed reachability, from [StationAttach.status] — a
/// value snapshot at the moment of the call (never cached, never polled in
/// the background). Sealed so a consumer's dispatch (`space status`) is
/// exhaustive (house style).
sealed class AttachResult {
  const AttachResult();
}

/// The station answered `GET /status` with a valid bearer. [payload] is the
/// raw decoded JSON body (the [StationStatus](`station_control.dart`) wire
/// shape — this client stays thin and does not re-parse it into that type);
/// [record] is the lock this attach read.
class Up extends AttachResult {
  /// Creates an up result carrying the decoded [payload] and the [record]
  /// read to reach it.
  const Up({required this.payload, required this.record});

  /// The decoded `/status` JSON body.
  final Map<String, Object?> payload;

  /// The lock record this attach was made through.
  final StationLockRecord record;
}

/// No station is attached: no lock file at all (nothing has ever bound this
/// state store, or a prior station released cleanly), OR the lock file
/// exists but is unreadable/malformed (a torn write from a crashed acquire —
/// mirrors [StationLockService]'s own stale-steal treatment of a torn write:
/// no live holder can be named, so there is nothing addressable to attach
/// to).
class Down extends AttachResult {
  /// Const-constructible — carries no data.
  const Down();
}

/// A lock file names [pid], but the station cannot be confirmed reachable:
/// either [pid] is dead (a crash without releasing the lock), or it is alive
/// but not answering (connection refused, a request timeout, or a lock read
/// after `acquire` but before the control surface finished advertising
/// `controlUrl`/`token` — a boot-order race). [record] is the lock read.
class Stale extends AttachResult {
  /// Creates a stale result naming the lock's [pid] and its [record].
  const Stale({required this.pid, required this.record});

  /// The pid the lock names (dead, or alive-but-unreachable).
  final int pid;

  /// The lock record read.
  final StationLockRecord record;
}

/// The station answered, but rejected the bearer token (401) — a wrong or
/// expired credential. DISTINCT from [Stale] by construction: the process is
/// demonstrably alive and serving, just not to this token, so it must never
/// be swallowed into the generic unreachable bucket.
class Unauthorized extends AttachResult {
  /// Creates an unauthorized result naming the [record] whose token was
  /// rejected.
  const Unauthorized(this.record);

  /// The lock record whose token the station rejected.
  final StationLockRecord record;
}

// ---------------------------------------------------------------------------
// StopResult (stop())
// ---------------------------------------------------------------------------

/// The outcome of [StationAttach.stop] — sealed so a consumer's dispatch
/// (`space down`) is exhaustive.
sealed class StopResult {
  const StopResult();
}

/// No live station to stop: no lock, an unreadable lock, or a lock naming a
/// pid that is already dead. A clean no-op — [StationAttach.stop] never
/// mutates the lock file itself.
class AlreadyDown extends StopResult {
  /// Const-constructible — carries no data.
  const AlreadyDown();
}

/// SIGTERM landed and, within the grace window, [pid] exited AND its lock
/// file was removed (the target runner's own graceful-shutdown release) — a
/// clean stop.
class Stopped extends StopResult {
  /// Creates a stopped result naming the [pid] that exited.
  const Stopped(this.pid);

  /// The pid that was signaled and confirmed exited.
  final int pid;
}

/// SIGTERM landed but [pid] and/or its lock file were still present when the
/// grace window elapsed. LOUD by construction — a distinct sealed variant a
/// caller cannot silently collapse into [Stopped]. This client NEVER
/// escalates to SIGKILL; force-kill is the supervisor's call, not this
/// client's.
class TimedOut extends StopResult {
  /// Creates a timed-out result naming the [pid] that was signaled.
  const TimedOut(this.pid);

  /// The pid that was signaled but not confirmed exited in time.
  final int pid;
}

// ---------------------------------------------------------------------------
// StationAttach
// ---------------------------------------------------------------------------

/// The station attach client (Services: stateless I/O; the reference type
/// carries the classifier). Reads the [StationLockService] lock, classifies
/// reachability against the RS-4 [StationControl] HTTP surface, and offers a
/// bounded graceful-stop over OS signals. Every seam is injected (Fakes, not
/// mocks): [isPidAlive] defaults to the real [defaultPidProbe], [signal] to
/// the real `Process.killPid`, [httpClientFactory] to `HttpClient.new`, and
/// [clock] to `DateTime.now`.
class StationAttach {
  /// Creates the client; every seam defaults to its real implementation.
  StationAttach({
    PidProbe? isPidAlive,
    ProcessSignaller? signal,
    ProcessGroupController? groups,
    void Function(String)? log,
    HttpClientFactory? httpClientFactory,
    DateTime Function()? clock,
  }) : _isPidAlive = isPidAlive ?? defaultPidProbe,
       _signal = signal ?? Process.killPid,
       _groups = groups ?? const SystemProcessGroupController(),
       _log = log ?? stdout.writeln,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now;

  final PidProbe _isPidAlive;
  final ProcessSignaller _signal;
  final ProcessGroupController _groups;
  final void Function(String) _log;
  final HttpClientFactory _httpClientFactory;
  final DateTime Function() _clock;

  /// Classifies the station rooted at [stateWorkspaceDir]: no lock (or an
  /// unreadable one) → [Down]; a lock naming a dead pid → [Stale]; a lock
  /// naming a live pid → `GET /status` over the advertised `controlUrl` with
  /// a bounded [timeout] → [Up] on 200, [Unauthorized] on 401 (never
  /// [Stale]), [Stale] on any other outcome (connection refused, timeout, a
  /// non-200/401 response, or a lock read before the control surface
  /// finished advertising itself).
  Future<AttachResult> status({
    required String stateWorkspaceDir,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final record = await _readLock(stateWorkspaceDir);
    if (record == null) return const Down();
    if (!_isPidAlive(record.pid)) {
      return Stale(pid: record.pid, record: record);
    }

    final controlUrl = record.controlUrl;
    final token = record.token;
    if (controlUrl == null || token == null) {
      // A live pid, but the lock was read before RS-4 finished advertising
      // controlUrl/token (a boot-order race) — nothing to attach to yet.
      return Stale(pid: record.pid, record: record);
    }

    final client = _httpClientFactory()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('$controlUrl/status'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(timeout);

      if (response.statusCode == HttpStatus.unauthorized) {
        await response.drain<void>();
        return Unauthorized(record);
      }
      final body = await response
          .transform(const Utf8Decoder())
          .join()
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return Stale(pid: record.pid, record: record);
      }
      return Up(
        payload: jsonDecode(body) as Map<String, Object?>,
        record: record,
      );
    } on Object {
      // Connection refused, DNS failure, a timeout, or a malformed body — a
      // live pid that is not answering correctly.
      return Stale(pid: record.pid, record: record);
    } finally {
      client.close(force: true);
    }
  }

  /// Gracefully stops the station rooted at [stateWorkspaceDir]: no lock (or
  /// an unreadable one, or one naming an already-dead pid) → [AlreadyDown],
  /// a clean no-op. Otherwise SIGTERMs the lock's pid and polls (every
  /// [pollInterval]) for BOTH the pid exiting AND its lock file being
  /// removed — the target runner's own graceful-shutdown release — up to
  /// [grace]. Returns
  /// [Stopped] on a clean exit within the window, or [TimedOut] (LOUD —
  /// never silently escalated to SIGKILL) when the window elapses first.
  Future<StopResult> stop({
    required String stateWorkspaceDir,
    Duration grace = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final record = await _readLock(stateWorkspaceDir);
    if (record == null) return const AlreadyDown();
    if (!_isPidAlive(record.pid)) return const AlreadyDown();

    await _signalStation(record);

    final lockFile = File(StationLockService.lockPath(stateWorkspaceDir));
    final deadline = _clock().add(grace);
    while (true) {
      final exited = !_isPidAlive(record.pid) && !await lockFile.exists();
      if (exited) return Stopped(record.pid);
      if (!_clock().isBefore(deadline)) return TimedOut(record.pid);
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<void> _signalStation(StationLockRecord record) async {
    final actualPgid = await _groups.resolvePgid(record.pid);
    final safeOwnedGroup =
        actualPgid == record.pgid &&
        record.pgid > 1 &&
        record.pgid != _groups.currentGroupId();
    if (safeOwnedGroup) {
      _groups.signalGroup(record.pgid, ProcessSignal.sigterm);
      return;
    }
    _log(
      'space down: station.lock group mismatch/unsafe — pid ${record.pid}, '
      'recorded pgid ${record.pgid}, actual pgid $actualPgid; '
      'falling back to PID-scoped SIGTERM',
    );
    _signal(record.pid, ProcessSignal.sigterm);
  }

  /// Reads + parses the lock at [stateWorkspaceDir], or null when there is
  /// no lock file or it is unreadable/malformed (a torn write — no live
  /// holder can be named).
  Future<StationLockRecord?> _readLock(String stateWorkspaceDir) async {
    final file = File(StationLockService.lockPath(stateWorkspaceDir));
    if (!await file.exists()) return null;
    try {
      return StationLockRecord.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }
}
