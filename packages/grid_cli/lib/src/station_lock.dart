/// RS-2 — the station lock (D-A1, `docs/adr/ADR-0014-the-resident-station.md`,
/// Accepted 2026-07-19).
///
/// **The named invariant: ONE supervisor per station STATE store.** Two
/// stations over the same session store observe the same ready bead,
/// double-spawn agents at it, and double-write session beads. The lock is
/// scoped per STATION state store — substations are partitions *inside* the
/// store and get no locks of their own (OQ-2, Nico's ruling).
///
/// Mechanism: exclusive-create `<grid-root>/.grid/station.lock` is the
/// ownership CLAIM; the [StationLockRecord] (`pid`/`pgid`/`startedAt`;
/// `controlUrl`/`token` are written LATER by the control surface — RS-4) is
/// PUBLISHED into that claim by an atomic same-directory `rename(2)` of a
/// sibling temp that is already mode 0600. A reader therefore only ever sees
/// the lock ABSENT or COMPLETE — never empty, never partial.
///
/// Arbitration on collision (decision
/// `the_grid#station-lock-holds-never-steals-an-unreadable-record`): a record
/// that PARSES and whose pid is live is a [StationRefusal] naming the pid, the
/// store, and the invariant; a record that parses and whose pid is dead is
/// stolen with a LOUD line (D-A1's stated rule); a record that does NOT parse
/// is HELD and re-probed over a bounded window and then REFUSED — an
/// unreadable lock is a young-or-mid-populate acquire, not proof of a crash,
/// so this code never deletes one. (`traj quiesce` already takes that posture
/// on the same file: "a torn lock cannot prove the station is down".)
/// Ownership (`pid` + `startedAt`) is re-verified against disk before every
/// rewrite and before the release delete. The guard principle throughout:
/// LOUD or gone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;
import 'package:grid_runtime/grid_runtime.dart'
    show establishStationProcessGroup;
import 'package:grid_sdk/grid_sdk.dart' show StationRefusal;

// `StationRefusal` moved to grid_sdk with the delegate contract (tg-at3r —
// the delegate's arming policy throws it too, and grid_sdk must not import
// grid_cli). Re-exported here so the lock's callers keep one import.
export 'package:grid_sdk/grid_sdk.dart' show StationRefusal;

/// The injected pid-liveness seam: true iff [pid] is a running process.
/// The real probe is [defaultPidProbe]; offline tests inject a fake.
typedef PidProbe = bool Function(int pid);

/// Sets POSIX mode 0600 on the file at `path`. THROWS on failure — a mode
/// that could not be set is terminal, never a warning. The real setter is
/// [defaultChmod600]; offline tests inject a fake.
typedef ModeSetter = Future<void> Function(String path);

/// The injected sleeper the unreadable-record hold backs off with; offline
/// tests inject a fake so the hold costs no wall time.
typedef HoldDelay = Future<void> Function(Duration duration);

/// Establishes the station-owned process group and returns its verified pgid.
typedef StationGroupPreparer = Future<int> Function(int stationPid);

Future<int> _defaultStationGroupPreparer(int stationPid) =>
    establishStationProcessGroup(stationPid: stationPid);

Future<void> _defaultDelay(Duration duration) => Future<void>.delayed(duration);

/// The REAL pid-liveness probe: `kill -0` (signal nothing, just check) — exit
/// 0 iff the pid exists and is signalable by this user. The station lock is a
/// same-user arbitration (one operator per store), so EPERM-as-dead is fine.
bool defaultPidProbe(int pid) =>
    Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// The REAL mode setter: `dart:io` cannot set POSIX modes, so shell out.
/// Throws a [FileSystemException] on a non-zero exit; the caller converts that
/// into a LOUD [StationRefusal] and aborts before any content exists.
Future<void> defaultChmod600(String path) async {
  final result = await Process.run('chmod', ['600', path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'chmod 600 failed (exit ${result.exitCode}): ${result.stderr}',
      path,
    );
  }
}

/// Reads the lock at [file], or null when it is absent or does not parse.
Future<StationLockRecord?> _readRecord(File file) async {
  try {
    return StationLockRecord.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, Object?>,
    );
  } on Object {
    return null;
  }
}

/// Publishes [record] at [file] ATOMICALLY: a sibling temp in the SAME
/// directory (`<lock>.tmp.<pid>`), mode 0600 applied BEFORE any content, JSON
/// written and flushed, then `rename(2)` over the target. A same-directory
/// rename is atomic, so a concurrent reader sees the target absent, the old
/// content, or the new content — never an empty or half-written record. The
/// temp is removed on any failure.
Future<void> _publishRecord({
  required File file,
  required StationLockRecord record,
  required ModeSetter applyMode,
}) async {
  final temp = File('${file.path}.tmp.${record.pid}');
  try {
    if (await temp.exists()) await temp.delete();
    await temp.create();
    await applyMode(temp.path);
    await temp.writeAsString(jsonEncode(record.toJson()), flush: true);
    await temp.rename(file.path);
  } on Object {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}

/// Describes [record] for a refusal line; `unreadable` when it does not parse.
String _describeRecord(StationLockRecord? record) => record == null
    ? 'unreadable'
    : 'pid ${record.pid} since ${record.startedAt.toIso8601String()}';

/// The station-lock service (Services layer: stateless I/O; the reference
/// type carries the classifier). Owns the exclusive-create / publish / probe /
/// hold / steal / refuse choreography over
/// `<state store root>/.grid/station.lock` ([stateWorkspaceDir] — the grid
/// root the resident station locks). The pid-liveness probe, the mode setter,
/// the hold's sleeper and the log sink are injected seams (Fakes, not mocks).
class StationLockService {
  /// Creates the service; [isPidAlive] defaults to the real [defaultPidProbe],
  /// [setMode] to the real [defaultChmod600], [delay] to `Future.delayed` and
  /// [log] to stdout. [holdWindow]/[holdInterval] bound the unreadable-record
  /// hold: probe at once, then back off from [holdInterval], doubling, and
  /// refuse once the accounted wait has reached [holdWindow].
  StationLockService({
    PidProbe? isPidAlive,
    void Function(String)? log,
    StationGroupPreparer? prepareProcessGroup,
    ModeSetter? setMode,
    HoldDelay? delay,
    Duration holdWindow = const Duration(seconds: 2),
    Duration holdInterval = const Duration(milliseconds: 100),
  }) : _isPidAlive = isPidAlive ?? defaultPidProbe,
       _log = log ?? stdout.writeln,
       _prepareProcessGroup =
           prepareProcessGroup ?? _defaultStationGroupPreparer,
       _setMode = setMode ?? defaultChmod600,
       _delay = delay ?? _defaultDelay,
       _holdWindow = holdWindow,
       _holdInterval = holdInterval;

  final PidProbe _isPidAlive;
  final void Function(String) _log;
  final StationGroupPreparer _prepareProcessGroup;
  final ModeSetter _setMode;
  final HoldDelay _delay;
  final Duration _holdWindow;
  final Duration _holdInterval;

  /// The lock path for a state store rooted at [stateWorkspaceDir].
  static String lockPath(String stateWorkspaceDir) =>
      '$stateWorkspaceDir/.grid/station.lock';

  /// Acquires the station lock for the state store at [stateWorkspaceDir], or
  /// throws a [StationRefusal] (exit 64) when a LIVE supervisor already holds
  /// it, or when the existing lock stays UNREADABLE through the hold window.
  /// A dead holder (crashed without releasing) is stolen with a LOUD log line
  /// and ONE retry of the exclusive create; losing that retry race refuses
  /// too. The record is published by temp + chmod 0600 + `rename(2)`, so the
  /// lock is never observable empty or partial.
  Future<StationLockHandle> acquire({
    required String stateWorkspaceDir,
    required int pid,
    required DateTime now,
  }) async {
    final int pgid;
    try {
      pgid = await _prepareProcessGroup(pid);
    } on Object catch (error) {
      final message =
          'grid run: refusing to write station.lock — could not establish '
          'station pid $pid as its own process-group leader: $error';
      _log(message);
      throw StationRefusal(message, code: 1);
    }
    if (pgid != pid) {
      final message =
          'grid run: refusing to write station.lock — station pid $pid '
          'resolved to non-owned pgid $pgid after group preparation';
      _log(message);
      throw StationRefusal(message, code: 1);
    }

    final file = File(lockPath(stateWorkspaceDir));
    await file.parent.create(recursive: true);
    final record = StationLockRecord(pid: pid, pgid: pgid, startedAt: now);

    for (var attempt = 0; ; attempt++) {
      try {
        await file.create(exclusive: true);
      } on PathExistsException {
        if (attempt >= 1) {
          // The one post-steal retry ALSO collided: another supervisor
          // re-minted the lock between our delete and create. Fail closed
          // rather than fight over the store.
          throw StationRefusal(
            'grid run: station.lock at ${file.path} reappeared during the '
            'stale-steal — another supervisor won the race for this store. '
            'ONE supervisor per station state store (D-A1); check '
            '`space status`.',
          );
        }
        await _arbitrate(file);
        continue;
      }
      // The CLAIM is ours (exclusive-create) and still empty. Publish the
      // record atomically — mode 0600 lands on the temp BEFORE any content,
      // so the file that carries the RS-4 bearer token is never
      // world-readable for an instant.
      try {
        await _publishRecord(file: file, record: record, applyMode: _applyMode);
      } on Object {
        // Fail closed: our claim is still empty, so unwind it rather than
        // leave a half-born lock for the next acquirer to arbitrate over.
        if (await file.exists()) await file.delete();
        rethrow;
      }
      return StationLockHandle._(
        file: file,
        record: record,
        applyMode: _applyMode,
        log: _log,
      );
    }
  }

  /// The collision path. Refuses on a LIVE holder; steals (deletes) LOUDLY a
  /// record that PARSES and whose pid is dead; HOLDS on an unreadable record
  /// and then refuses (never deletes). Returns normally without stealing when
  /// the lock VANISHED under us — the caller's one retry re-creates it.
  Future<void> _arbitrate(File file) async {
    final holder = await _awaitReadableHolder(file);
    if (holder == null) return;

    if (_isPidAlive(holder.pid)) {
      throw StationRefusal(
        'grid run: refusing to start — station.lock at ${file.path} is held '
        'by a LIVE supervisor (pid ${holder.pid}, since '
        '${holder.startedAt.toIso8601String()}). ONE supervisor per station '
        'state store (D-A1): a second station over the same session store '
        'double-spawns agents and double-writes session beads. Inspect the '
        'holder with `space status`; stop it before starting another.',
      );
    }

    _log(
      'grid run: STEALING stale station.lock at ${file.path} '
      '(pid ${holder.pid} dead — the previous supervisor crashed '
      'without releasing)',
    );
    if (await file.exists()) await file.delete();
  }

  /// Re-reads [file] on a doubling backoff until it PARSES (returns the
  /// record), it disappears (returns null — the holder released under us), or
  /// the bounded hold window is spent (throws a LOUD [StationRefusal] naming
  /// the path). An unreadable record is young-or-mid-populate, not proof of a
  /// crash: a human decides, this code never deletes it.
  Future<StationLockRecord?> _awaitReadableHolder(File file) async {
    var waited = Duration.zero;
    var backoff = _holdInterval;
    for (;;) {
      if (!await file.exists()) return null;
      final holder = await _readRecord(file);
      if (holder != null) return holder;
      if (waited >= _holdWindow) {
        final message =
            'grid run: refusing to start — station.lock at ${file.path} is '
            'UNREADABLE and stayed unreadable through the '
            '${_holdWindow.inMilliseconds}ms hold. An unreadable lock is a '
            'young or mid-populate acquire, not proof of a crash, so the '
            'grid never deletes one. Inspect it (`cat ${file.path}`, then '
            '`space status`) and remove it by hand once you have confirmed '
            'no supervisor owns this store.';
        _log(message);
        throw StationRefusal(message);
      }
      await _delay(backoff);
      waited += backoff;
      backoff *= 2;
    }
  }

  /// Applies mode 0600, converting ANY failure into a LOUD [StationRefusal]:
  /// the lock carries the RS-4 bearer token, so publishing content into a file
  /// whose mode could not be set is a credential leak. Terminal by design —
  /// never a log-and-continue.
  Future<void> _applyMode(String path) async {
    try {
      await _setMode(path);
    } on Object catch (error) {
      final message =
          'grid run: refusing to publish station.lock — could NOT chmod 600 '
          '$path: $error. The lock carries the control bearer token (RS-4); '
          'fix the store permissions and retry.';
      _log(message);
      throw StationRefusal(message, code: 1);
    }
  }
}

/// The held station lock, returned by [StationLockService.acquire]. The
/// control surface (RS-4) advertises through [updateControl]; the graceful
/// shutdown path (and the start-throw unwind) releases through [release].
/// Every write re-verifies OWNERSHIP against disk first — the on-disk record's
/// `pid` + `startedAt` must be the pair this handle minted at acquire (that
/// pair IS the nonce; `StationLockRecord` gains no field, per tg-vg5k).
class StationLockHandle {
  StationLockHandle._({
    required File file,
    required StationLockRecord record,
    required ModeSetter applyMode,
    required void Function(String) log,
  }) : _file = file,
       _record = record,
       _applyMode = applyMode,
       _log = log;

  final File _file;
  final ModeSetter _applyMode;
  final void Function(String) _log;
  StationLockRecord _record;

  /// The lock file path.
  String get path => _file.path;

  /// The current on-disk payload.
  StationLockRecord get record => _record;

  /// Advertises the control surface (RS-4): replaces the lock with
  /// [controlUrl]/[token], preserving the identity fields. Throws a
  /// [StationRefusal] when the on-disk record is not ours.
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  }) => _replace(
    _record.withControl(controlUrl: controlUrl, token: token),
    'updateControl',
  );

  /// Advertises this station's VM service: replaces the lock with
  /// [vmServiceUri], preserving every other field (the URI carries the service
  /// auth code, so the replacement is 0600 like every other). A JIT runner
  /// calls it with `grid_exploration`'s `stationVmServiceUri()`; an AOT runner
  /// never does. Throws a [StationRefusal] when the on-disk record is not ours.
  Future<void> updateVmService(String vmServiceUri) =>
      _replace(_record.withVmService(vmServiceUri), 'updateVmService');

  /// Ownership-verified atomic replacement: re-read the lock, refuse LOUDLY
  /// unless it is still ours, then publish [next] by temp + chmod + rename.
  /// The in-memory [record] advances only after the rename succeeds.
  Future<void> _replace(StationLockRecord next, String verb) async {
    final disk = await _readRecord(_file);
    if (!_isOurs(disk)) {
      final message =
          'grid run: refusing $verb on station.lock at ${_file.path} — the '
          'on-disk record is NOT ours (ours: pid ${_record.pid} since '
          '${_record.startedAt.toIso8601String()}; on disk: '
          '${_describeRecord(disk)}). Another supervisor re-minted this '
          'lock; ONE supervisor per station state store (D-A1).';
      _log(message);
      throw StationRefusal(message);
    }
    await _publishRecord(file: _file, record: next, applyMode: _applyMode);
    _record = next;
  }

  /// True iff [disk] is the record this handle minted: same `pid`, same
  /// `startedAt`. That pair is the ownership proof (no new record field).
  bool _isOurs(StationLockRecord? disk) =>
      disk != null &&
      disk.pid == _record.pid &&
      disk.startedAt.isAtSameMomentAs(_record.startedAt);

  /// Releases the lock (deletes the file) — only when the on-disk record is
  /// still OURS. A foreign or unreadable record is left alone with a LOUD
  /// line: deleting it would evict the supervisor that re-minted it.
  /// Idempotent — the graceful path and the start-throw unwind may both reach
  /// it.
  Future<void> release() async {
    if (!await _file.exists()) return;
    final disk = await _readRecord(_file);
    if (!_isOurs(disk)) {
      _log(
        'grid run: NOT releasing station.lock at ${_file.path} — the on-disk '
        'record is NOT ours (ours: pid ${_record.pid} since '
        '${_record.startedAt.toIso8601String()}; on disk: '
        '${_describeRecord(disk)}). Deleting it would evict the supervisor '
        'that owns this store.',
      );
      return;
    }
    await _file.delete();
  }
}
