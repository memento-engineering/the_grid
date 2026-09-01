/// `traj gc` — operator-run reclamation for the trajectory database (tg-3o6b
/// item 2).
///
/// Two landed contracts collide and the boundary wins. M2 measured online
/// `CALL DOLT_GC()` at ~120 ms reclaiming ~98%, so the harness runs it on a
/// cadence — but `DOLT_GC` needs SERVER-level privilege, and the ratified
/// provision boundary grants the service credential `trajectory.*` ONLY
/// (stage1-wiring §4 / r2 minor 15). The service grant is NOT widened. On a
/// scoped-grant home the harness disables its cadence after one
/// `trajectory.gcDisabled` flare and reclamation becomes THIS verb, run by the
/// operator under the **gridboot** credential from
/// `.grid/trajectory/gridboot.secret` — the same bootstrap identity
/// `traj provision` uses, never the service secret, and never bd's proxy
/// files.
///
/// Online by construction: nothing is stopped, no lock is taken, no quiesce is
/// required. The one thing this verb will not do is invent a credential — a
/// home without the bootstrap secret is told to run the §4 step-1b window
/// (`traj provision` prints it) rather than being handed a widened grant.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../connect/server_config.dart';
import '../connect/trajectory_connection.dart';
import '../connect/trajectory_db.dart';
import 'traj_flags.dart';
import 'traj_provision_command.dart'
    show ListenerResolver, gridbootSecretPath, gridbootUser;
import 'traj_quiesce.dart' show TrajSqlConnect;
import 'trajectory_reader.dart' show trajectoryDatabaseName;

Future<TrajectoryDb> _defaultConnect(TrajectoryEndpoint endpoint) =>
    TrajectoryConnection.connect(endpoint);

/// The verb.
class TrajGcCommand extends Command<int> {
  TrajGcCommand({TrajSqlConnect? connect, ListenerResolver? resolve})
    : _connect = connect ?? _defaultConnect,
      _resolve = resolve ?? resolveDoltServerListener {
    addGridHomeOption(argParser);
  }

  final TrajSqlConnect _connect;
  final ListenerResolver _resolve;

  @override
  final String name = 'gc';

  @override
  final String description =
      'Reclaim the trajectory database (CALL DOLT_GC) as the gridboot '
      'credential — the operator half of gc on a scoped-grant home.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln(
        'traj gc: unexpected argument "${argResults!.rest.first}".',
      );
      return 64;
    }
    final gridHome = gridHomeFrom(argResults!, stderr.writeln, 'gc');
    if (gridHome == null) return 64;
    return runTrajGc(gridHome: gridHome, connect: _connect, resolve: _resolve);
  }
}

/// Runs the collection and prints what it did. 0 on success; 1 on any refusal.
Future<int> runTrajGc({
  required String gridHome,
  TrajSqlConnect connect = _defaultConnect,
  ListenerResolver resolve = resolveDoltServerListener,
  Stopwatch? stopwatch,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final void Function(String) write = out ?? stdout.writeln;
  final void Function(String) writeErr = err ?? stderr.writeln;
  write(
    'traj gc — operator reclamation (tg-3o6b; the service grant stays '
    'scoped)',
  );

  final bootSecret = File(gridbootSecretPath(gridHome));
  if (!bootSecret.existsSync()) {
    writeErr(
      'traj gc: no bootstrap credential at ${bootSecret.path} — gc needs '
      'SERVER-level privilege and the trajectory service user is granted '
      'trajectory.* only. Seed gridboot with the §4 step-1b window '
      '(`traj provision` prints it) and re-run.',
    );
    return 1;
  }
  final password = bootSecret.readAsStringSync().trim();
  if (password.isEmpty) {
    writeErr('traj gc: empty bootstrap secret: ${bootSecret.path}');
    return 1;
  }

  final elapsed = (stopwatch ?? Stopwatch())..start();
  try {
    // Resolved per connect (§4's reconnect rule): bd rewrites the child
    // server's port on its own terms.
    final listener = resolve(gridHome);
    final db = await connect(
      TrajectoryEndpoint(
        host: listener.host,
        port: listener.port,
        user: gridbootUser,
        password: password,
        database: trajectoryDatabaseName,
      ),
    );
    try {
      await db.execute('CALL DOLT_GC()');
    } finally {
      await db.close();
    }
  } on Object catch (error) {
    // A one-shot operator verb decorating its error line with the remedy —
    // the SAME classification the harness's gc latch keys on, so the sentence
    // an operator reads and the posture the cadence takes can never disagree
    // about what a denial is.
    writeErr(
      'traj gc: $error'
      '${isPrivilegeDenied(error) ? ' — the gridboot credential is '
                'missing GRANT ALL ON *.*; re-seed it per §4 step 1b' : ''}',
    );
    return 1;
  }
  elapsed.stop();
  write(
    '  collected: $trajectoryDatabaseName reclaimed in '
    '${elapsed.elapsedMilliseconds} ms',
  );
  return 0;
}
