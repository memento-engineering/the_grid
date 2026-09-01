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

/// The classic MySQL access-denied codes. dolt answers a denied `CALL` with
/// [sqlErrUnknownError] instead (tg-3o6b, observed live), but a server that
/// uses these must land in the same class.
const Set<int> sqlErrAccessDenied = {1044, 1045, 1142, 1143, 1370};

/// The SHAPE dolt's own denied `CALL` carries inside [sqlErrUnknownError]:
/// `command denied to user '<user>'@'<host>'`. This is the server's own
/// phrasing for a privilege refusal — NOT the bare word "denied", which any
/// catch-all 1105 may happen to contain.
const String sqlDeniedCallMarker = 'command denied to user';

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

/// True when [error] is the server refusing on PRIVILEGE (tg-3o6b).
///
/// **THE CLASS IS `codes ∪ the 1105 DENIED-CALL SHAPE` (cut-wiring C0's
/// normative rule, restored r13).** The design states it in as many words —
/// "1105 privilege-denied ⇒ flare `trajectory.gcDisabled` once, never re-arm
/// this process; other errors keep flare-and-rearm" — and 1105 is the ONLY
/// code dolt actually answers a denied `CALL` with, so a codes-only predicate
/// makes disable-on-deny unreachable on every scoped-grant home: the cadence
/// then flares `gcFailed` and re-arms forever, which is the posture the design
/// exists to replace.
///
/// The r12 correction this restores is kept in its narrow form: the predicate
/// LATCHES at its one caller (the gc cadence stops for the process lifetime on
/// a single match), so the 1105 arm matches [sqlDeniedCallMarker] — the
/// server's own denial phrasing — and NOT the bare word "denied". dolt carries
/// commit-time unique violations on [sqlErrUnknownError] too, and an unrelated
/// 1105 whose text merely mentions a denial must never disable reclamation.
///
/// This is a POSTURE, not a failure: the scoped service credential is granted
/// `trajectory.*` only, by ratified design, and a caller that sees this stops
/// asking rather than retrying.
bool isPrivilegeDenied(Object error) {
  if (error is! MySQLServerException) return false;
  if (sqlErrAccessDenied.contains(error.errorCode)) return true;
  return error.errorCode == sqlErrUnknownError &&
      error.message.toLowerCase().contains(sqlDeniedCallMarker);
}

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
