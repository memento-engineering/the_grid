/// RS-2 — the station lock (D-A1, `docs/SCRATCH-resident-station.md` §4,
/// RATIFIED Nico 2026-07-02).
///
/// **The named invariant: ONE supervisor per station STATE store.** Two
/// stations over the same session store observe the same ready bead,
/// double-spawn agents at it, and double-write session beads. The lock is
/// scoped per STATION state store — substations are partitions *inside* the
/// store and get no locks of their own (OQ-2, Nico's ruling).
///
/// Mechanism: exclusive-create `<grid-root>/.grid/station.lock` holding
/// a [StationLockRecord] (`pid`/`pgid`/`startedAt`; `controlUrl`/`token` are
/// written LATER by the control surface — RS-4). The runner acquires it before
/// mounting the tree and releases it on the graceful shutdown path (rides
/// RS-1's signal contract) and on the boot-throw unwind. Stale detection is a
/// pid-liveness probe behind a seam: a dead holder is stolen with a LOUD line;
/// a live holder is a [StationRefusal] naming the pid, the store, and the
/// invariant (the guard principle: LOUD or gone).
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show establishStationProcessGroup;

/// A composition-time refusal (a live lock holder, a lost steal race) — the
/// runner prints [message] and exits with [code]. The one arming gate the
/// resident-station survivors still throw (the old `station_runner` assembly
/// that also raised it is deleted; the boot path moved to the asset's own
/// runner + `runGrid`).
class StationRefusal implements Exception {
  /// Creates the refusal with its user-facing [message] and exit [code].
  const StationRefusal(this.message, {this.code = 64});

  /// The user-facing refusal text.
  final String message;

  /// The process exit code (64 = usage, 1 = environment).
  final int code;

  @override
  String toString() => message;
}

/// The injected pid-liveness seam: true iff [pid] is a running process.
/// The real probe is [defaultPidProbe]; offline tests inject a fake.
typedef PidProbe = bool Function(int pid);

/// Establishes the station-owned process group and returns its verified pgid.
typedef StationGroupPreparer = Future<int> Function(int stationPid);

Future<int> _defaultStationGroupPreparer(int stationPid) =>
    establishStationProcessGroup(stationPid: stationPid);

/// The REAL pid-liveness probe: `kill -0` (signal nothing, just check) — exit
/// 0 iff the pid exists and is signalable by this user. The station lock is a
/// same-user arbitration (one operator per store), so EPERM-as-dead is fine.
bool defaultPidProbe(int pid) =>
    Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// The `station.lock` payload. [controlUrl]/[token] are absent until the
/// control surface (RS-4) advertises itself through
/// [StationLockHandle.updateControl] — the codec is forward-compatible with
/// their absence (and tolerant of unknown extra keys), so an RS-2 lock and an
/// RS-4 lock round-trip through the same type.
class StationLockRecord {
  /// Creates the payload; the control fields default to absent.
  const StationLockRecord({
    required this.pid,
    required this.pgid,
    required this.startedAt,
    this.controlUrl,
    this.token,
    this.vmServiceUri,
  });

  /// Parses a lock payload. Throws (any [Object]) on a malformed shape — the
  /// service treats that as a torn write from a crashed acquire.
  factory StationLockRecord.fromJson(Map<String, Object?> json) =>
      StationLockRecord(
        pid: json['pid'] as int,
        pgid: json['pgid'] as int,
        startedAt: DateTime.parse(json['startedAt'] as String),
        controlUrl: json['controlUrl'] as String?,
        token: json['token'] as String?,
        vmServiceUri: json['vmServiceUri'] as String?,
      );

  /// The holder's process id (the liveness-probe target).
  final int pid;

  /// The holder's process group id (the spawned-agent group root).
  final int pgid;

  /// When the holder acquired the lock.
  final DateTime startedAt;

  /// The RS-4 loopback control endpoint; null until advertised.
  final String? controlUrl;

  /// The RS-4 per-boot bearer token; null until advertised. This field is why
  /// the lock file is 0600.
  final String? token;

  /// The station's VM-service URI — advertised ONLY by a JIT station started
  /// with `--enable-vm-service` (the dev-mode hot-reload target); null on an AOT
  /// station, which cannot be reloaded. It carries the service auth code, which
  /// is the OTHER reason this file is 0600.
  final String? vmServiceUri;

  /// Serializes the payload; absent optional fields are OMITTED (not null).
  Map<String, Object?> toJson() => <String, Object?>{
    'pid': pid,
    'pgid': pgid,
    'startedAt': startedAt.toIso8601String(),
    if (controlUrl != null) 'controlUrl': controlUrl,
    if (token != null) 'token': token,
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
  };

  /// The RS-4 advertisement: the same identity with the control fields set.
  StationLockRecord withControl({
    required String controlUrl,
    required String token,
  }) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    controlUrl: controlUrl,
    token: token,
    // PRESERVED: the control advertisement must not erase a dev-mode station's
    // VM-service URI — which advertisement lands first is the runner's business.
    vmServiceUri: vmServiceUri,
  );

  /// The dev-mode advertisement: the same identity with [vmServiceUri] set.
  StationLockRecord withVmService(String vmServiceUri) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    controlUrl: controlUrl,
    token: token,
    vmServiceUri: vmServiceUri,
  );
}

/// The station-lock service (Services layer: stateless I/O; the reference
/// type carries the classifier). Owns the exclusive-create / probe / steal /
/// refuse choreography over `<state-workspace>/.grid/station.lock`. The
/// pid-liveness probe and the log sink are injected seams (Fakes, not mocks).
/// The choreography runs over `<state store root>/.grid/station.lock`
/// ([stateWorkspaceDir] — the grid root the resident station locks).
class StationLockService {
  /// Creates the service; [isPidAlive] defaults to the real [defaultPidProbe]
  /// and [log] to stdout.
  StationLockService({
    PidProbe? isPidAlive,
    void Function(String)? log,
    StationGroupPreparer? prepareProcessGroup,
  }) : _isPidAlive = isPidAlive ?? defaultPidProbe,
       _log = log ?? stdout.writeln,
       _prepareProcessGroup =
           prepareProcessGroup ?? _defaultStationGroupPreparer;

  final PidProbe _isPidAlive;
  final void Function(String) _log;
  final StationGroupPreparer _prepareProcessGroup;

  /// The lock path for a state store rooted at [stateWorkspaceDir].
  static String lockPath(String stateWorkspaceDir) =>
      '$stateWorkspaceDir/.grid/station.lock';

  /// Acquires the station lock for the state store at [stateWorkspaceDir], or
  /// throws a [StationRefusal] (exit 64) when a LIVE supervisor already holds
  /// it. A dead holder (crashed without releasing) is stolen with a LOUD log
  /// line and ONE retry of the exclusive create; losing that retry race
  /// refuses too. The lock file is chmod 0600 (it will carry the RS-4 bearer
  /// token).
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
        await _probeAndSteal(file);
        continue;
      }
      // Mode BEFORE content: the file must never be world-readable with a
      // payload in it (it will carry the RS-4 bearer token).
      await _chmod600(file.path);
      await file.writeAsString(jsonEncode(record.toJson()), flush: true);
      return StationLockHandle._(file: file, record: record, chmod: _chmod600);
    }
  }

  /// The collision path: refuse on a live holder; steal (delete) LOUDLY on a
  /// dead or unreadable one so the retry can exclusive-create.
  Future<void> _probeAndSteal(File file) async {
    StationLockRecord? holder;
    try {
      holder = StationLockRecord.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } on Object {
      // A torn write from a crashed acquire — no live holder can be named,
      // and a live supervisor always leaves a well-formed lock.
      holder = null;
    }

    if (holder != null && _isPidAlive(holder.pid)) {
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
      holder == null
          ? 'grid run: STEALING corrupt station.lock at ${file.path} '
                '(unreadable — a torn write from a crashed acquire; no live '
                'holder to name)'
          : 'grid run: STEALING stale station.lock at ${file.path} '
                '(pid ${holder.pid} dead — the previous supervisor crashed '
                'without releasing)',
    );
    if (await file.exists()) await file.delete();
  }

  /// `dart:io` cannot set POSIX modes — shell out. Failure is LOUD, never
  /// silent: the lock will carry the RS-4 bearer token, so a world-readable
  /// lock is a credential leak.
  Future<void> _chmod600(String path) async {
    final result = await Process.run('chmod', ['600', path]);
    if (result.exitCode != 0) {
      _log(
        'grid run: could NOT chmod 600 $path (exit ${result.exitCode}) — the '
        'station.lock carries the control bearer token (RS-4); fix the store '
        'permissions. ${result.stderr}',
      );
    }
  }
}

/// The held station lock, returned by [StationLockService.acquire]. The
/// control surface (RS-4) advertises through [updateControl]; the graceful
/// shutdown path (and the start-throw unwind) releases through [release].
class StationLockHandle {
  StationLockHandle._({
    required File file,
    required StationLockRecord record,
    required Future<void> Function(String) chmod,
  }) : _file = file,
       _record = record,
       _chmod = chmod;

  final File _file;
  final Future<void> Function(String) _chmod;
  StationLockRecord _record;

  /// The lock file path.
  String get path => _file.path;

  /// The current on-disk payload.
  StationLockRecord get record => _record;

  /// Advertises the control surface (RS-4): rewrites the lock with
  /// [controlUrl]/[token], preserving the identity fields, and re-asserts
  /// 0600 (the token is exactly why the mode matters).
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  }) async {
    _record = _record.withControl(controlUrl: controlUrl, token: token);
    await _file.writeAsString(jsonEncode(_record.toJson()), flush: true);
    await _chmod(_file.path);
  }

  /// Advertises this station's VM service: rewrites the lock with
  /// [vmServiceUri], preserving every other field, and re-asserts 0600 (the URI
  /// carries the service auth code). A JIT runner calls it with
  /// `grid_exploration`'s `stationVmServiceUri()`; an AOT runner never does.
  Future<void> updateVmService(String vmServiceUri) async {
    _record = _record.withVmService(vmServiceUri);
    await _file.writeAsString(jsonEncode(_record.toJson()), flush: true);
    await _chmod(_file.path);
  }

  /// Releases the lock (deletes the file). Idempotent — the graceful path and
  /// the start-throw unwind may both reach it.
  Future<void> release() async {
    if (await _file.exists()) await _file.delete();
  }
}
