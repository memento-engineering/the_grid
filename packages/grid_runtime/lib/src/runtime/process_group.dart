import 'dart:ffi';
import 'dart:io';

typedef _SetSidNative = Int32 Function();
typedef _SetSidDart = int Function();

/// Injectable POSIX `setsid()` call used by [establishStationProcessGroup].
typedef SetSidCall = int Function();

int _systemSetSid() => DynamicLibrary.process()
    .lookupFunction<_SetSidNative, _SetSidDart>('setsid')();

/// Makes [stationPid] the leader of a new session and process group.
///
/// An already-leading process is left unchanged. Otherwise the result is
/// verified through [ProcessGroupController.resolvePgid], keeping that seam as
/// the single source of process-group identity.
Future<int> establishStationProcessGroup({
  required int stationPid,
  ProcessGroupController controller = const SystemProcessGroupController(),
  SetSidCall setSid = _systemSetSid,
}) async {
  final before = await controller.resolvePgid(stationPid);
  if (before == stationPid) return stationPid;

  final result = setSid();
  if (result < 0) {
    throw StateError('setsid() failed for station pid $stationPid');
  }

  final after = await controller.resolvePgid(stationPid);
  if (after != stationPid) {
    throw StateError(
      'setsid() did not establish station pid $stationPid as group leader '
      '(resolved pgid: $after)',
    );
  }
  return stationPid;
}

/// The OS process-group SEAM — the single point where [SubprocessProvider]
/// touches process signalling and pgid resolution. A reference type (carries
/// the `Controller` role name; predictable-flutter).
///
/// Mirrors [ProcessRunner] / [BdRunner]: [SystemProcessGroupController] does the
/// real `dart:io` work; tests inject a fake that records signals and reports
/// programmed liveness, so the whole SIGTERM→grace→SIGKILL escalation and the
/// pgid guard run offline (Fakes, not mocks). The Dart port of gc's
/// `processgroup` package (`gascity/internal/processgroup/processgroup_unix.go`).
abstract interface class ProcessGroupController {
  /// Resolves the process-group id of [pid].
  ///
  /// Under `ProcessStartMode.detachedWithStdio` the Dart VM `setsid()`s the
  /// child into a NEW session + process group, but the child's pid is **not**
  /// its pgid (the VM forks an intermediate launcher), so the pgid must be read
  /// back from the OS. Returns null when the process is already gone or the pgid
  /// cannot be read — the caller fails closed (does not signal).
  Future<int?> resolvePgid(int pid);

  /// Whether [pid] still names a live process. gc's `alive` probe
  /// (`processgroup_unix.go:105-111`) is `kill(pid, 0)`; Dart does not expose
  /// signal 0, so the impl sends a harmless no-op signal (SIGWINCH) whose
  /// `killPid` boolean is false exactly when the process is gone.
  bool processAlive(int pid);

  /// Sends [signal] to the whole process group [pgid] (`kill(-pgid, signal)`).
  /// Returns false when the group is already gone (ESRCH). Never throws.
  bool signalGroup(int pgid, ProcessSignal signal);

  /// The caller's own process-group id — the [Terminate] self-group guard
  /// input (gc's `syscall.Getpgrp()`, `processgroup_unix.go:31-36`).
  int currentGroupId();
}

/// The result of a [terminateGroup] escalation, so the caller (and a test) can
/// assert which rung fired without scraping logs.
enum GroupTerminateResult {
  /// The group exited within the grace window after SIGTERM — no SIGKILL sent.
  exitedOnTerm,

  /// The group survived the grace window and was SIGKILLed.
  killed,

  /// The group was already gone when termination began (idempotent stop).
  alreadyGone,

  /// Refused: [pgid] failed the safety guard (`pgid <= 1` or `pgid ==`
  /// the caller's own group) — signalling it would hit the supervisor itself.
  refusedUnsafe,
}

/// Sends SIGTERM to [pgid], polls for the group to exit within [grace], then
/// escalates to SIGKILL — gc's `processgroup.Terminate`
/// (`processgroup_unix.go:53-68`), as a free function over the injected
/// [ProcessGroupController] seam.
///
/// **The guard is load-bearing** (`processgroup_unix.go:55-57`): a `pgid <= 1`
/// (init / unresolved) or a `pgid` equal to the caller's own group would, when
/// negated to `-pgid`, signal the supervisor's entire process tree — including
/// the_grid itself. Both are refused with [GroupTerminateResult.refusedUnsafe]
/// and NO signal is sent.
///
/// [leaderPid] is the spawned child's pid, used only as the liveness probe
/// subject (the group is considered exited when the leader is gone); pass the
/// `process.pid` from the detached spawn.
Future<GroupTerminateResult> terminateGroup({
  required ProcessGroupController controller,
  required int pgid,
  required int leaderPid,
  Duration grace = const Duration(seconds: 2),
  Duration pollPeriod = const Duration(milliseconds: 25),
}) async {
  // Safety guard FIRST — never signal an unsafe group (gc:55-57).
  if (pgid <= 1 || pgid == controller.currentGroupId()) {
    return GroupTerminateResult.refusedUnsafe;
  }
  if (!controller.processAlive(leaderPid)) {
    return GroupTerminateResult.alreadyGone;
  }

  controller.signalGroup(pgid, ProcessSignal.sigterm);
  if (await _waitForExit(controller, leaderPid, grace, pollPeriod)) {
    return GroupTerminateResult.exitedOnTerm;
  }

  controller.signalGroup(pgid, ProcessSignal.sigkill);
  // gc waits a second time after SIGKILL (gc:67); a process group cannot
  // survive SIGKILL, so this is just to confirm/settle the reap.
  await _waitForExit(controller, leaderPid, grace, pollPeriod);
  return GroupTerminateResult.killed;
}

/// Polls [ProcessGroupController.processAlive] until [leaderPid] is gone or
/// [timeout] elapses. Returns true when the process exited in time. gc's
/// `waitForExit` (`processgroup_unix.go:92-103`).
Future<bool> _waitForExit(
  ProcessGroupController controller,
  int leaderPid,
  Duration timeout,
  Duration pollPeriod,
) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (!controller.processAlive(leaderPid)) return true;
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(pollPeriod);
  }
}

/// The real seam: resolves pgid via `ps`, probes liveness with a harmless
/// signal, and signals groups via `Process.killPid(-pgid, …)`.
class SystemProcessGroupController implements ProcessGroupController {
  const SystemProcessGroupController();

  @override
  Future<int?> resolvePgid(int pid) async {
    // `ps -o pgid= -p <pid>` prints the bare pgid (header suppressed by `=`).
    final result = await Process.run('ps', <String>[
      '-o',
      'pgid=',
      '-p',
      '$pid',
    ]);
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).trim();
    if (out.isEmpty) return null;
    return int.tryParse(out);
  }

  @override
  bool processAlive(int pid) {
    // No signal-0 in Dart; SIGWINCH is a harmless no-op (window-size change)
    // that `killPid` reports as false exactly when the pid is gone (ESRCH).
    return Process.killPid(pid, ProcessSignal.sigwinch);
  }

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    // Negative pid = the whole process group (POSIX kill(2)).
    return Process.killPid(-pgid, signal);
  }

  @override
  int currentGroupId() => pid; // the_grid runs in its own group; pid≈pgid here.
}
