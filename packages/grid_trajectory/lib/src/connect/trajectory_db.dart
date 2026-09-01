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
/// **CODES ONLY — the message is deliberately NOT part of the predicate
/// (r12).** A denial answer LATCHES at its one caller: the gc cadence stops
/// for the whole process lifetime on a single match. A predicate that can
/// latch must be decidable from the error CODE, because a message is not a
/// contract — dolt carries both a denied `CALL` and a commit-time unique
/// violation on [sqlErrUnknownError], so matching the bare word "denied"
/// inside a 1105 let any unrelated 1105 whose text happened to contain it
/// disable reclamation forever, the working set then growing unbounded until
/// an operator noticed.
///
/// The cost is stated rather than hidden: dolt's own denied-`CALL` shape is a
/// 1105 and therefore no longer lands in this class. It falls to the ordinary
/// flare-and-rearm loop instead — a rate-limited `gcFailed` per cadence rather
/// than one `gcDisabled` — which is the SAFE direction for a wrong answer
/// (retrying a refused CALL costs a round trip; latching off a misclassified
/// one costs the database).
///
/// This is a POSTURE, not a failure: the scoped service credential is granted
/// `trajectory.*` only, by ratified design, and a caller that sees this stops
/// asking rather than retrying.
bool isPrivilegeDenied(Object error) =>
    error is MySQLServerException &&
    sqlErrAccessDenied.contains(error.errorCode);

/// A HINT, not a classification: does [error] READ like a privilege denial?
///
/// The message heuristic [isPrivilegeDenied] refuses to carry lives here
/// instead, where it can only decorate a one-shot operator verb's error line
/// with the remedy — the observed dolt shape is a 1105 saying
/// `command denied to user '<user>'@'%'`, and telling an operator about the
/// missing GRANT is worth a guess. NEVER latch a cadence, disable a
/// capability, or branch a control flow on this: guessing wrong here costs one
/// misleading sentence, and guessing wrong there costs the database.
bool readsAsPrivilegeDenial(Object error) =>
    isPrivilegeDenied(error) ||
    (error is MySQLServerException &&
        error.errorCode == sqlErrUnknownError &&
        error.message.toLowerCase().contains('command denied'));

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
