/// THE QUIESCE FENCE — the check `traj replay` runs before it touches a
/// projection table.
///
/// Every in-tree replay scans the WHOLE log before opening its transaction and
/// rewrites the table from that pre-transaction fold, so a record committed
/// between the scan and the COMMIT has its fold effect silently erased — and
/// no wave-1 detector can see the hole (the appender's next append re-advances
/// the shared `'fold'` cursor, so the lag rule reads current, and the
/// generation guard would make a mirror ADOPT the truncated fold with health
/// still `live`). Replay is therefore QUIESCE-ONLY: station DOWN, full stop.
/// There is no `--swap` and no force flag.
///
/// Two witnesses, in order, neither of them a projection table:
///
///   1. **RS-2, the station lock** — `<grid home>/.grid/station.lock`, read by
///      PATH and parsed here. This package is a LEAF (decision:
///      grid-trajectory-leaf-package): it cannot import `grid_cli`'s
///      `StationLockService`, and the lock's on-disk shape (`pid`/`pgid`/…)
///      is the contract it reads, the same way `traj provision` reads the
///      server's own `config.yaml` rather than bd's proxy files. A lock that
///      cannot be parsed REFUSES: a torn lock cannot prove the station is
///      down, and this verb is destructive.
///   2. **The trajectory fence** — the newest `traj_epoch` row per station
///      names the claiming `pid`/`pgid`. It is consulted only while a lock
///      file EXISTS: epoch rows are permanent history, and a released lock
///      means the claimer is gone, so a recycled pid must never make a
///      quiesced home un-replayable. With a stale lock present it is the
///      second witness — a harness that outlived its supervisor's lock.
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../connect/trajectory_connection.dart';
import '../connect/trajectory_db.dart';

/// How a `traj` verb opens a SQL session; injected so the guard suite can
/// drive a hermetic server and a unit test can script statements without a
/// socket. Structurally the seam `traj provision` opens under its own
/// credential.
typedef TrajSqlConnect =
    Future<TrajectoryDb> Function(TrajectoryEndpoint endpoint);

/// The pid-liveness seam: true iff [pid] is a running process.
typedef PidLiveness = bool Function(int pid);

/// The REAL probe: `kill -0` — exit 0 iff the pid exists and is signalable by
/// this user. Same-user arbitration (one operator per grid home), so
/// EPERM-as-dead matches the station lock's own rule.
bool defaultPidLiveness(int pid) {
  try {
    return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
  } on Object {
    // No `kill` at all: treat the holder as ALIVE. A destructive verb that
    // cannot run its liveness probe refuses; it never assumes down.
    return true;
  }
}

/// RS-2's lock file for the grid home at [gridHome].
String stationLockPath(String gridHome) =>
    p.join(gridHome, '.grid', 'station.lock');

/// The verdict.
@immutable
sealed class StationQuiescence {
  const StationQuiescence();

  /// One line for the verb's report.
  String get detail;
}

/// Nothing is holding this home: the replay may proceed.
final class StationQuiesced extends StationQuiescence {
  const StationQuiesced(this.detail);

  @override
  final String detail;
}

/// A live station (or a lock we cannot read past) owns this home.
final class StationArmed extends StationQuiescence {
  const StationArmed(this.detail);

  @override
  final String detail;
}

/// The newest epoch row per station — the fence's second witness.
const String liveEpochSql =
    'SELECT e.station AS station, e.epoch AS epoch, e.pid AS pid, '
    'e.pgid AS pgid FROM traj_epoch e '
    'JOIN (SELECT station, MAX(epoch) AS epoch FROM traj_epoch '
    'GROUP BY station) live '
    'ON live.station = e.station AND live.epoch = e.epoch';

/// Runs the fence for [gridHome].
///
/// [db] is optional so the lock half can be answered before a connection
/// exists; when it is supplied AND a lock file is present, the epoch witness
/// runs too. Neither witness reads a `proj_*` table.
Future<StationQuiescence> probeStationQuiescence({
  required String gridHome,
  TrajectoryDb? db,
  PidLiveness isPidAlive = defaultPidLiveness,
}) async {
  final lock = File(stationLockPath(gridHome));
  if (!lock.existsSync()) {
    return const StationQuiesced('no station.lock — the station is DOWN');
  }

  int? holder;
  try {
    final record = jsonDecode(lock.readAsStringSync()) as Map<String, Object?>;
    holder = record['pid'] as int?;
  } on Object {
    holder = null;
  }
  if (holder == null) {
    return StationArmed(
      'station.lock at ${lock.path} names no readable pid — a torn lock '
      'cannot prove the station is down; stop the station (or remove the '
      'lock once you have) and re-run',
    );
  }
  if (isPidAlive(holder)) {
    return StationArmed(
      'station.lock at ${lock.path} is held by a LIVE supervisor (pid '
      '$holder) — replay rewrites projections from a pre-transaction fold '
      'and would silently erase whatever the live appender commits '
      'meanwhile',
    );
  }

  if (db != null) {
    final rows = (await db.execute(liveEpochSql)).rows;
    for (final row in rows) {
      final pid = int.tryParse(row['pid'] ?? '');
      if (pid == null || !isPidAlive(pid)) continue;
      return StationArmed(
        'the trajectory fence names a LIVE authority: station '
        '${row['station']} epoch ${row['epoch']} claimed by pid $pid '
        '(pgid ${row['pgid']}) — a harness outliving its supervisor\'s lock '
        'is still an appender',
      );
    }
  }

  return StationQuiesced(
    'stale station.lock at ${lock.path} (holder pid $holder is dead) and no '
    'live epoch authority',
  );
}
