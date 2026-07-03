import 'dart:async';
import 'dart:io';

import 'package:beads_dart/src/services/bd_runner.dart';
import 'package:beads_dart/src/services/dolt_endpoint.dart';
import 'package:test/test.dart';

/// A fully-hermetic `dolt sql-server` plus a server-mode beads workspace wired
/// to it — the only configuration in which **both** the SQL port
/// ([ReadyWorkQuery] over a [DoltQueryService]) and the `bd ready` oracle read
/// the *same* store, so the ADR-0003 Decision 5 differential can be run
/// runs-everywhere (no live `GC_DOLT_PASSWORD`) over seeded fixtures.
///
/// **Why a server, not the embedded [HermeticWorkspace].** `bd init` produces an
/// embedded Dolt store the SQL port cannot reach (no MySQL endpoint), and a
/// `dolt sql-server` cannot share that embedded store with a concurrent
/// embedded `bd` process — the store is single-writer-locked, so an embedded
/// `bd ready` *hangs* while a server holds the dir. Pointing `bd` itself at the
/// server (`bd init --server --external`) sidesteps the contention: seeding
/// writes, the oracle read, and the SQL-port read all flow through one server.
///
/// **The `127.0.0.1` auth gate (dolt 2.1.6).** `dolt sql-server` auto-creates a
/// `root@localhost` superuser that authenticates only over the loopback *name*,
/// not the `127.0.0.1` TCP address the MySQL client dials — connecting as that
/// root fails `Access denied`. The fix is to create a wildcard-host user
/// (`'grid'@'%'`) **offline** (`dolt sql -q "CREATE USER …; GRANT …"`) before
/// the server starts; the grant persists in the data-dir's `.doltcfg` and the
/// server serves it. (This is why the `-u/--user` sql-server flags, removed in
/// 2.x, are not needed.)
///
/// Hermetic and self-contained: a temp data-dir, a free ephemeral port, a temp
/// workspace; [dispose] kills the server and deletes both. Skips cleanly when
/// `dolt`/`bd` are not on PATH so the integration suite stays portable.
class HermeticDoltServer {
  HermeticDoltServer._({
    required this.endpoint,
    required this.runner,
    required Process server,
    required Directory dataDir,
    required Directory workspaceRoot,
  }) : _server = server,
       _dataDir = dataDir,
       _workspaceRoot = workspaceRoot;

  /// The endpoint the SQL port connects through (`grid@127.0.0.1:<port>`).
  final DoltEndpoint endpoint;

  /// A `bd` runner pointed at the server-mode workspace, carrying
  /// `BEADS_DOLT_PASSWORD` so `bd` authenticates as the same `grid` user.
  final ProcessBdRunner runner;

  final Process _server;
  final Directory _dataDir;
  final Directory _workspaceRoot;

  /// The workspace root containing `.beads/` (where `bd` runs).
  String get workspaceRoot => _workspaceRoot.path;

  static const String _user = 'grid';
  static const String _password = 'gridpw';

  /// Stands up the server + workspace, or returns null when the host lacks the
  /// `dolt`/`bd` tooling (the caller then [markTestSkipped]s). Fails the test on
  /// any *unexpected* setup error — a present-but-broken toolchain is a real
  /// failure, an absent one is a skip.
  static Future<HermeticDoltServer?> tryCreate({String? prefix}) async {
    if (!_onPath('dolt') || !_onPath('bd')) return null;

    final dataDir = await Directory.systemTemp.createTemp(
      '${prefix ?? 'grid_it_srv_'}data_',
    );
    final workspaceRoot = await Directory.systemTemp.createTemp(
      '${prefix ?? 'grid_it_srv_'}ws_',
    );
    // Resolve symlinks so the path bd records matches what we compare against
    // (macOS /tmp → /private/tmp).
    final data = Directory(dataDir.resolveSymbolicLinksSync());
    final ws = Directory(workspaceRoot.resolveSymbolicLinksSync());

    Process? server;
    try {
      // 1) Initialise the data-dir as a dolt database root and create a
      //    wildcard-host user OFFLINE (the server's auto root@localhost cannot
      //    authenticate over the 127.0.0.1 TCP address — see the class doc).
      final init = await Process.run('dolt', [
        'init',
        '--name',
        'grid',
        '--email',
        'grid@hermetic.test',
      ], workingDirectory: data.path);
      // `dolt init` is idempotent-ish; a non-zero "already initialised" is fine
      // because the CREATE USER below is the load-bearing step.
      final createUser = await Process.run('dolt', [
        'sql',
        '-q',
        "CREATE USER IF NOT EXISTS '$_user'@'%' IDENTIFIED BY '$_password'; "
            "GRANT ALL ON *.* TO '$_user'@'%' WITH GRANT OPTION;",
      ], workingDirectory: data.path);
      if (createUser.exitCode != 0) {
        fail(
          'offline CREATE USER failed (${createUser.exitCode}): '
          '${createUser.stderr}\n${createUser.stdout}\n'
          '(dolt init said: ${init.stderr})',
        );
      }

      // 2) Start the server on a free port over the data-dir.
      final port = await _freePort();
      server = await Process.start('dolt', [
        'sql-server',
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
        '--data-dir',
        data.path,
      ], workingDirectory: data.path);
      // Drain pipes so the child never blocks on a full buffer. These run for
      // the server's lifetime; we don't await them.
      unawaited(server.stdout.drain<void>());
      unawaited(server.stderr.drain<void>());
      await _awaitPort('127.0.0.1', port);

      // 3) bd init the workspace in external-server mode against the server. The
      //    database is named after the workspace dir; the prefix follows.
      final bdInit = await Process.run(
        'bd',
        [
          'init',
          '--server',
          '--external',
          '--server-host',
          '127.0.0.1',
          '--server-port',
          '$port',
          '--server-user',
          _user,
          '--non-interactive',
        ],
        workingDirectory: ws.path,
        environment: {
          ...Platform.environment,
          'BD_JSON_ENVELOPE': '1',
          'BD_NON_INTERACTIVE': '1',
          'BEADS_DOLT_PASSWORD': _password,
        },
        includeParentEnvironment: false,
        runInShell: false,
      );
      if (bdInit.exitCode != 0) {
        fail(
          'bd init --server --external failed (${bdInit.exitCode}): '
          '${bdInit.stderr}\n${bdInit.stdout}',
        );
      }

      // The database bd created is named after the workspace directory.
      final database = _basename(ws.path);
      final endpoint = DoltEndpoint(
        host: '127.0.0.1',
        port: port,
        database: database,
        user: _user,
        password: _password,
      );
      final runner = ProcessBdRunner(
        workspaceRoot: ws.path,
        environment: {
          ...Platform.environment,
          'BEADS_DOLT_PASSWORD': _password,
        },
      );

      return HermeticDoltServer._(
        endpoint: endpoint,
        runner: runner,
        server: server,
        dataDir: data,
        workspaceRoot: ws,
      );
    } on Object {
      // Best-effort teardown of a half-built server before rethrowing/failing.
      server?.kill(ProcessSignal.sigkill);
      await _deleteQuietly(data);
      await _deleteQuietly(ws);
      rethrow;
    }
  }

  /// Kills the server and deletes the temp data-dir + workspace. Safe in
  /// `tearDown`.
  Future<void> dispose() async {
    _server.kill(ProcessSignal.sigkill);
    try {
      await _server.exitCode.timeout(const Duration(seconds: 5));
    } on Object {
      // Already gone, or refused to die in time — the temp dirs are deleted
      // regardless.
    }
    await _deleteQuietly(_dataDir);
    await _deleteQuietly(_workspaceRoot);
  }

  // ---------------------------------------------------------------------------

  static bool _onPath(String exe) {
    try {
      final r = Process.runSync(Platform.isWindows ? 'where' : 'which', [exe]);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  /// Binds an ephemeral port, reads the assigned number, releases it. A short
  /// race window exists before the server claims it — acceptable for a test.
  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// Polls until [host]:[port] accepts a TCP connection, or fails after ~10s.
  static Future<void> _awaitPort(String host, int port) async {
    for (var i = 0; i < 80; i++) {
      try {
        final s = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 250),
        );
        await s.close();
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 125));
      }
    }
    fail('hermetic dolt sql-server did not accept connections on $host:$port');
  }

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? path : parts.last;
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // Best effort.
    }
  }
}
