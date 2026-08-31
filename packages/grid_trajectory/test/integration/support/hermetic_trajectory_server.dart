/// A hermetic `dolt sql-server` for the Stage-0 guard tests: temp data dir,
/// ephemeral port, wildcard-host admin user created OFFLINE before the
/// server starts (dolt's auto root@localhost cannot authenticate over the
/// 127.0.0.1 TCP address — the beads_dart hermetic-server precedent). No bd,
/// and NEVER a real `.beads`/`.grid` store.
library;

import 'dart:async';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class HermeticTrajectoryServer {
  HermeticTrajectoryServer._({
    required this.host,
    required this.port,
    required this.doltBinary,
    required Process server,
    required Directory dataDir,
  }) : _server = server,
       _dataDir = dataDir;

  final String host;
  final int port;

  /// The resolved `dolt` executable — the guards drive CLI ops with it.
  final String doltBinary;

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

  /// The server's data directory; each database is a directory beneath it.
  String get dataDirPath => _dataDir.path;

  /// The data dir's own `.doltcfg` — what `--doltcfg-dir` must be pointed at
  /// for CLI ops run from a database subdirectory (§5's T1 trap).
  String get doltcfgDirPath => p.join(_dataDir.path, '.doltcfg');

  String databaseDir(String database) => p.join(_dataDir.path, database);

  /// Runs a dolt CLI op. [cwd] defaults to the data dir; passing
  /// [doltcfgDir] applies the `--doltcfg-dir` discipline.
  ///
  /// The CLI talks to the running server (it detects the data dir's lock), so
  /// what it reports is the live working set, not a stale on-disk snapshot.
  Future<ProcessResult> runDolt(
    List<String> args, {
    String? cwd,
    String? doltcfgDir,
  }) => Process.run(doltBinary, [
    if (doltcfgDir != null) ...['--doltcfg-dir', doltcfgDir],
    ...args,
  ], workingDirectory: cwd ?? _dataDir.path);

  /// FAIL-CLOSED (decision: stage0-guards-gate-prs): no dolt means the guards
  /// fail, never skip — the PR-gating CI job installs dolt, and a guard that
  /// silently no-ops proves nothing at a stage cut.
  static Future<HermeticTrajectoryServer> create() async {
    final server = await _start();
    if (server == null) {
      fail(
        'no dolt binary on PATH — the Stage-0 guards fail closed rather '
        'than skip: install dolt to run them',
      );
    }
    return server;
  }

  static Future<HermeticTrajectoryServer?> _start() async {
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

      // The ephemeral port is picked-then-released, so another process can
      // steal it before dolt binds (TOCTOU — the two integration files run
      // concurrently). Bounded retries on a fresh port each time, killing
      // the losing child, keep the race from reddening a run.
      const bindAttempts = 3;
      for (var attempt = 1; ; attempt++) {
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
        if (await _awaitPort('127.0.0.1', port)) {
          return HermeticTrajectoryServer._(
            host: '127.0.0.1',
            port: port,
            doltBinary: dolt,
            server: server,
            dataDir: dataDir,
          );
        }
        server.kill(ProcessSignal.sigkill);
        if (attempt >= bindAttempts) {
          fail(
            'hermetic dolt sql-server never accepted connections '
            '($bindAttempts bind attempts on fresh ephemeral ports)',
          );
        }
      }
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

  /// PATH only, deliberately: a hardcoded install-location fallback would
  /// defeat both the fail-closed contract (no dolt = a RED run, observable)
  /// and CI's pinned dolt version. Absence fails the guard loudly.
  static String? _doltBinary() {
    try {
      if (Process.runSync('which', ['dolt']).exitCode == 0) return 'dolt';
    } on Object {
      // No `which` at all — same disposition as no dolt.
    }
    return null;
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
