/// The real socket [TrajectoryDb] over `mysql_client`.
///
/// Mirrors DoltQueryService's connection shape (same `createConnection`
/// arguments, same `assoc()` row decoding) but is WRITE-CAPABLE by design —
/// see `trajectory_db.dart`'s header and the trajectory-direct-sql-scope
/// decision. Two invariants are asserted the moment the session exists:
///
///   * `@@dolt_force_transaction_commit` is BANNED (§5): dolt's own 1105 text
///     advertises it as the way to commit anyway, and setting it silently
///     disables the belt (probe T6f). Connect throws if it reads set, and
///     pins the session's own value to 0.
///   * the session is PINNED to branch `main` (probe T3: an in-server
///     checkout makes every dolt_ignore'd table vanish). Asserted at connect
///     and re-assertable ([assertMainBranch]) — fail closed on any change.
library;

import 'package:mysql_client/mysql_client.dart';

import 'trajectory_db.dart';

/// Where the write-capable session lands: the underlying server's listener
/// plus the trajectory credential. [database] is null only for the
/// server-level bootstrap session (CREATE DATABASE / CREATE USER), which has
/// no branch to pin.
class TrajectoryEndpoint {
  const TrajectoryEndpoint({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    this.database,
  });

  final String host;
  final int port;
  final String user;
  final String password;
  final String? database;
}

/// Refused connect-time invariant — the session never becomes usable.
class TrajectoryConnectionException implements Exception {
  TrajectoryConnectionException(this.message);

  final String message;

  @override
  String toString() => 'TrajectoryConnectionException: $message';
}

class TrajectoryConnection implements TrajectoryDb {
  TrajectoryConnection._(this._conn);

  final MySQLConnection _conn;

  static Future<TrajectoryConnection> connect(
    TrajectoryEndpoint endpoint,
  ) async {
    final raw = await MySQLConnection.createConnection(
      host: endpoint.host,
      port: endpoint.port,
      userName: endpoint.user,
      password: endpoint.password,
      databaseName: endpoint.database,
      // The bd-owned server offers no TLS (DoltQueryService precedent).
      secure: false,
    );
    await raw.connect();
    final conn = TrajectoryConnection._(raw);
    try {
      await conn._assertForceCommitUnset();
      if (endpoint.database != null) await conn.assertMainBranch();
    } on Object {
      await conn.close();
      rethrow;
    }
    return conn;
  }

  Future<void> _assertForceCommitUnset() async {
    final result = await execute('SELECT @@dolt_force_transaction_commit AS v');
    final value = result.rows.isEmpty ? null : result.rows.first['v'];
    if (value != null && value != '0' && value.toLowerCase() != 'false') {
      throw TrajectoryConnectionException(
        '@@dolt_force_transaction_commit is set ($value) — banned on every '
        'service connection (§5/T6f): it silently disables the belt',
      );
    }
    await execute('SET @@dolt_force_transaction_commit = 0');
  }

  /// Fail-closed branch pin: throws unless `active_branch()` is `main`.
  Future<void> assertMainBranch() async {
    final result = await execute('SELECT active_branch() AS b');
    final branch = result.rows.isEmpty ? null : result.rows.first['b'];
    if (branch != 'main') {
      throw TrajectoryConnectionException(
        'session branch is ${branch ?? 'unknown'}, not main — the service '
        'pins main and fails closed (probe T3: proj_* vanish off-branch)',
      );
    }
  }

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    final result = await _conn.execute(sql, params);
    return SqlResult(
      affectedRows: result.affectedRows.toInt(),
      lastInsertId: result.lastInsertID.toInt(),
      rows: [for (final row in result.rows) row.assoc()],
    );
  }

  @override
  Future<void> close() => _conn.close();
}
