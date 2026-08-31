/// The SQL seam the DDL bootstrap and the fenced appender run over.
///
/// Deliberately write-capable — the bd-CLI-only-writes orthodoxy is a
/// LEDGER-database rule and does not apply here (decision:
/// trajectory-direct-sql-scope): the trajectory database's sole appender
/// writes it over direct SQL. Do not "fix" this seam back to SELECT-only or
/// reroute it through bd.
library;

import 'package:meta/meta.dart';
import 'package:mysql_client/exception.dart';

/// `1213` — dolt's serialization failure. On the epoch-claim path: re-read
/// MAX(epoch) and retry or refuse. On the append path: fenced out (§5).
const int sqlErrSerializationFailure = 1213;

/// `1105` — dolt's unknown-error carrier for unique violations detected at
/// COMMIT. The §5 contract branches on the constraint NAME in the message.
const int sqlErrUnknownError = 1105;

/// `1062` — duplicate key at statement time. The epoch-claim path must NOT
/// catch this (§4: 1213 arbitrates, not the PK); only the idempotent
/// `dolt_ignore` seed tolerates it.
const int sqlErrDuplicateEntry = 1062;

/// `1049` — unknown database. On the read path this is the ordinary "stage 0
/// was never bootstrapped on this grid home" answer, not a failure.
const int sqlErrUnknownDatabase = 1049;

bool _isServerError(Object error, int code) =>
    error is MySQLServerException && error.errorCode == code;

bool isSerializationFailure(Object error) =>
    _isServerError(error, sqlErrSerializationFailure);

bool isDuplicateEntry(Object error) =>
    _isServerError(error, sqlErrDuplicateEntry);

bool isUnknownDatabase(Object error) =>
    _isServerError(error, sqlErrUnknownDatabase);

/// True when [error] is a 1105 whose message names [constraint]
/// (e.g. `uq_idem`, `uq_epoch_seq`).
bool isUniqueViolationOn(Object error, String constraint) =>
    _isServerError(error, sqlErrUnknownError) &&
    (error as MySQLServerException).message.contains(constraint);

/// One statement's outcome, decoupled from the driver so unit tests can
/// script every §5 branch without a socket.
@immutable
class SqlResult {
  const SqlResult({
    this.affectedRows = 0,
    this.lastInsertId = 0,
    this.rows = const [],
  });

  final int affectedRows;
  final int lastInsertId;

  /// Raw column-name → string-value rows (`assoc()` shape, matching the
  /// DoltQueryService read-path precedent).
  final List<Map<String, String?>> rows;
}

/// A single SQL session against the dolt sql-server.
///
/// Implementations: [TrajectoryConnection] (real socket) and test fakes.
abstract interface class TrajectoryDb {
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]);

  Future<void> close();
}
