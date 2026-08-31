/// A hermetic dolt sql-server posing as a grid home's state-store server —
/// for the W1 harness integration test ONLY. Temp data dir, ephemeral port,
/// wildcard-host admin user created OFFLINE before the server starts (the
/// grid_trajectory / beads_dart hermetic-server precedent). No bd, and NEVER
/// a real `.beads`/`.grid` store.
///
/// Beyond the server, this helper materializes the grid-home shape the
/// harness's DEFAULT connect path resolves: `.grid/.beads/dolt/config.yaml`
/// naming the listener, and the runbook's step-2 provisioning (database,
/// schema, `trajectory` user + secret under `.grid/trajectory/`).
library;

import 'dart:async';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class HermeticGridHome {
  HermeticGridHome._({
    required this.host,
    required this.port,
    required this.homePath,
    required Process server,
    required Directory dataDir,
  }) : _server = server,
       _dataDir = dataDir;

  final String host;
  final int port;

  /// The fabricated grid home — what the harness gets as `gridHome`.
  final String homePath;

  final Process _server;
  final Directory _dataDir;

  static const String adminUser = 'grid';
  static const String adminPassword = 'gridpw';

  TrajectoryEndpoint get adminServerEndpoint => TrajectoryEndpoint(
    host: host,
    port: port,
    user: adminUser,
    password: adminPassword,
  );

  TrajectoryEndpoint adminEndpointFor(String database) => TrajectoryEndpoint(
    host: host,
    port: port,
    user: adminUser,
    password: adminPassword,
    database: database,
  );

  /// FAIL-CLOSED (the stage0-guards-gate-prs convention): no dolt on PATH
  /// means the guard FAILS, never skips.
  static Future<HermeticGridHome> create() async {
    if (Process.runSync('which', ['dolt']).exitCode != 0) {
      fail(
        'no dolt binary on PATH — the Stage-1 harness guard fails closed '
        'rather than skip: install dolt to run it',
      );
    }

    final dataDir = Directory(
      (await Directory.systemTemp.createTemp(
        'traj_w1_',
      )).resolveSymbolicLinksSync(),
    );
    Process? server;
    try {
      await Process.run('dolt', [
        'init',
        '--name',
        'traj',
        '--email',
        'traj@hermetic.test',
      ], workingDirectory: dataDir.path);
      // Offline admin seed: dolt's auto root@localhost cannot authenticate
      // over the 127.0.0.1 TCP address a client dials.
      final createUser = await Process.run('dolt', [
        'sql',
        '-q',
        "CREATE USER IF NOT EXISTS '$adminUser'@'%' IDENTIFIED BY "
            "'$adminPassword'; "
            "GRANT ALL ON *.* TO '$adminUser'@'%' WITH GRANT OPTION;",
      ], workingDirectory: dataDir.path);
      if (createUser.exitCode != 0) {
        fail('offline CREATE USER failed: ${createUser.stderr}');
      }

      // Picked-then-released ephemeral port: bounded retries on the TOCTOU.
      const bindAttempts = 3;
      for (var attempt = 1; ; attempt++) {
        final port = await _freePort();
        server = await Process.start('dolt', [
          'sql-server',
          '--host',
          '127.0.0.1',
          '--port',
          '$port',
          '--data-dir',
          dataDir.path,
        ], workingDirectory: dataDir.path);
        unawaited(server.stdout.drain<void>());
        unawaited(server.stderr.drain<void>());
        if (await _awaitPort('127.0.0.1', port)) {
          final home = Directory(p.join(dataDir.path, 'home'))
            ..createSync(recursive: true);
          final hermetic = HermeticGridHome._(
            host: '127.0.0.1',
            port: port,
            homePath: home.path,
            server: server,
            dataDir: dataDir,
          );
          hermetic._writeListenerConfig();
          return hermetic;
        }
        server.kill(ProcessSignal.sigkill);
        if (attempt >= bindAttempts) {
          fail(
            'hermetic dolt sql-server never accepted connections '
            '($bindAttempts bind attempts)',
          );
        }
      }
    } on Object {
      server?.kill(ProcessSignal.sigkill);
      await _deleteQuietly(dataDir);
      rethrow;
    }
  }

  /// The runbook's step 2 (live provisioning over SQL): database → schema →
  /// `trajectory` user + secret. Idempotent, like the verb it stands in for.
  Future<void> provision() async {
    // Server-level session for the database + user; a database-scoped one for
    // the schema (its branch pin needs a database to pin).
    final admin = await TrajectoryConnection.connect(adminServerEndpoint);
    try {
      await createTrajectoryDatabase(admin);
      final db = await TrajectoryConnection.connect(
        adminEndpointFor('trajectory'),
      );
      try {
        await applyTrajectorySchema(db);
      } finally {
        await db.close();
      }
      await provisionTrajectoryUser(admin, gridHome: homePath);
    } finally {
      await admin.close();
    }
  }

  /// What `resolveDoltServerListener` reads: the plain (non-proxied) layout's
  /// `.grid/.beads/dolt/config.yaml`.
  void _writeListenerConfig() {
    final configFile = File(
      p.join(homePath, '.grid', '.beads', 'dolt', 'config.yaml'),
    )..createSync(recursive: true);
    configFile.writeAsStringSync('listener:\n  host: $host\n  port: $port\n');
  }

  Future<void> dispose() async {
    _server.kill(ProcessSignal.sigkill);
    try {
      await _server.exitCode.timeout(const Duration(seconds: 5));
    } on Object {
      // Temp dir is deleted regardless.
    }
    await _deleteQuietly(_dataDir);
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<bool> _awaitPort(String host, int port) async {
    for (var i = 0; i < 80; i++) {
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 250),
        );
        await socket.close();
        return true;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 125));
      }
    }
    return false;
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // Best effort.
    }
  }
}
