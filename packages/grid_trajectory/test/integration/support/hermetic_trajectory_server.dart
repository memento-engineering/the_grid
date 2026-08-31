/// A hermetic `dolt sql-server` for the Stage-0 guard tests: temp data dir,
/// ephemeral port, wildcard-host admin user created OFFLINE before the
/// server starts (dolt's auto root@localhost cannot authenticate over the
/// 127.0.0.1 TCP address — the beads_dart hermetic-server precedent). No bd,
/// and NEVER a real `.beads`/`.grid` store.
library;

import 'dart:async';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

class HermeticTrajectoryServer {
  HermeticTrajectoryServer._({
    required this.host,
    required this.port,
    required Process server,
    required Directory dataDir,
  }) : _server = server,
       _dataDir = dataDir;

  final String host;
  final int port;
  final Process _server;
  final Directory _dataDir;

  static const String user = 'grid';
  static const String password = 'gridpw';

  /// Server-level session coordinates (no database selected).
  TrajectoryEndpoint get serverEndpoint => TrajectoryEndpoint(
    host: host,
    port: port,
    user: user,
    password: password,
  );

  TrajectoryEndpoint endpointFor(String database) => TrajectoryEndpoint(
    host: host,
    port: port,
    user: user,
    password: password,
    database: database,
  );

  /// Null when no dolt binary is available (the caller markTestSkipped's —
  /// note the PR-gating CI job installs dolt, so a skip there is a failure
  /// by the stage0-guards-gate-prs decision).
  static Future<HermeticTrajectoryServer?> tryCreate() async {
    final dolt = _doltBinary();
    if (dolt == null) return null;

    final dataDir = Directory(
      (await Directory.systemTemp.createTemp(
        'traj_it_',
      )).resolveSymbolicLinksSync(),
    );

    Process? server;
    try {
      await Process.run(dolt, [
        'init',
        '--name',
        'traj',
        '--email',
        'traj@hermetic.test',
      ], workingDirectory: dataDir.path);
      final createUser = await Process.run(dolt, [
        'sql',
        '-q',
        "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$password'; "
            "GRANT ALL ON *.* TO '$user'@'%' WITH GRANT OPTION;",
      ], workingDirectory: dataDir.path);
      if (createUser.exitCode != 0) {
        fail('offline CREATE USER failed: ${createUser.stderr}');
      }

      final port = await _freePort();
      server = await Process.start(dolt, [
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
      await _awaitPort('127.0.0.1', port);

      return HermeticTrajectoryServer._(
        host: '127.0.0.1',
        port: port,
        server: server,
        dataDir: dataDir,
      );
    } on Object {
      server?.kill(ProcessSignal.sigkill);
      await _deleteQuietly(dataDir);
      rethrow;
    }
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

  static String? _doltBinary() {
    try {
      if (Process.runSync('which', ['dolt']).exitCode == 0) return 'dolt';
    } on Object {
      // fall through to the homebrew path
    }
    const homebrew = '/opt/homebrew/bin/dolt';
    return File(homebrew).existsSync() ? homebrew : null;
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<void> _awaitPort(String host, int port) async {
    for (var i = 0; i < 80; i++) {
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 250),
        );
        await socket.close();
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 125));
      }
    }
    fail('hermetic dolt sql-server did not accept connections on $host:$port');
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // Best effort.
    }
  }
}
