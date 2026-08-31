/// The READ seam the `traj` verbs run over.
///
/// Read-only by construction here: the verbs SELECT and nothing else — the
/// write path belongs to the fenced appender alone (§5's sole-appender
/// invariant), and a forensics verb that could write would break it.
///
/// Opening is a sealed RESULT, not an exception, because "stage 0 was never
/// bootstrapped on this grid home" is an ordinary state of the world — the
/// trajectory database is additive and a station that never created it is
/// healthy. A server that exists but cannot be reached is the other thing:
/// that one is a refusal.
library;

import 'dart:convert';
import 'dart:io';

import 'package:mysql_client/exception.dart';

import '../codec/envelope.dart';
import '../connect/server_config.dart';
import '../connect/trajectory_connection.dart';
import '../connect/trajectory_db.dart';
import '../ddl/trajectory_provisioning.dart';

/// The sibling database the whole package targets (storage call, §10).
const String trajectoryDatabaseName = 'trajectory';

/// Rows the `traj` verbs read, decoded to §1 envelopes.
abstract interface class TrajectoryLogReader {
  /// Every row whose `work_bead_id`, `session_id`, or `attempt_id` is
  /// [subject], in `seq` order.
  Future<List<TrajectoryEnvelope>> rowsForSubject(
    String subject, {
    int limit = defaultReadLimit,
  });

  /// Distinct `session_id`s present in the log, oldest first.
  Future<List<String>> sessions({int limit = defaultReadLimit});

  Future<void> close();
}

/// Rows read per verb invocation unless `--limit` says otherwise. A forensics
/// verb reads a bounded window; the log is unbounded by design.
const int defaultReadLimit = 500;

/// The disposition of opening the log for reading.
sealed class TrajectoryOpen {
  const TrajectoryOpen();
}

/// A live read seam. The caller owns [reader] and must close it.
final class TrajectoryOpened extends TrajectoryOpen {
  const TrajectoryOpened(this.reader);

  final TrajectoryLogReader reader;
}

/// No trajectory database (or no credential) on this grid home — expected,
/// not an error: the verb says so and exits clean.
final class TrajectoryNotBootstrapped extends TrajectoryOpen {
  const TrajectoryNotBootstrapped(this.message);

  final String message;
}

/// The database should be there but could not be reached or read.
final class TrajectoryUnavailable extends TrajectoryOpen {
  const TrajectoryUnavailable(this.message);

  final String message;
}

/// How a verb acquires its reader; injected so tests script rows without a
/// socket.
typedef TrajectoryOpener = Future<TrajectoryOpen> Function(String gridHome);

/// Opens [gridHome]'s trajectory log read-only over the underlying dolt
/// sql-server — never through bd's proxy, never touching bd's pid/lock/secret
/// files (decision: trajectory-direct-sql-scope).
Future<TrajectoryOpen> openTrajectoryReader(String gridHome) async {
  final DoltServerListener listener;
  try {
    listener = resolveDoltServerListener(gridHome);
  } on TrajectoryConfigException catch (error) {
    return TrajectoryNotBootstrapped(
      'trajectory database not found under $gridHome — stage 0 not '
      'bootstrapped (${error.message})',
    );
  }
  final endpointLabel =
      '${listener.host}:${listener.port}/$trajectoryDatabaseName';

  final secret = File(trajectorySecretPath(gridHome));
  if (!secret.existsSync()) {
    return TrajectoryNotBootstrapped(
      'trajectory database not found at $endpointLabel — stage 0 not '
      'bootstrapped (no credential at ${secret.path})',
    );
  }
  final password = secret.readAsStringSync().trim();
  if (password.isEmpty) {
    return TrajectoryUnavailable('empty trajectory secret: ${secret.path}');
  }

  try {
    final connection = await TrajectoryConnection.connect(
      TrajectoryEndpoint(
        host: listener.host,
        port: listener.port,
        user: trajectoryUser,
        password: password,
        database: trajectoryDatabaseName,
      ),
    );
    return TrajectoryOpened(SqlTrajectoryLogReader(connection));
  } on MySQLServerException catch (error) {
    if (isUnknownDatabase(error)) {
      return TrajectoryNotBootstrapped(
        'trajectory database not found at $endpointLabel — stage 0 not '
        'bootstrapped',
      );
    }
    return TrajectoryUnavailable('$endpointLabel: ${error.message}');
  } on Object catch (error) {
    return TrajectoryUnavailable('$endpointLabel: $error');
  }
}

/// The SQL implementation of [TrajectoryLogReader] over any [TrajectoryDb].
class SqlTrajectoryLogReader implements TrajectoryLogReader {
  SqlTrajectoryLogReader(this._db);

  final TrajectoryDb _db;

  /// `SELECT *` deliberately: [TrajectoryEnvelope] decodes by §4 column name,
  /// so a column added to the DDL is inert here until the envelope knows it —
  /// a hand-listed forty columns would silently drift instead.
  static const String subjectSql =
      'SELECT * FROM trajectory '
      'WHERE work_bead_id = :id OR session_id = :id OR attempt_id = :id '
      'ORDER BY seq LIMIT :limit';

  static const String sessionsSql =
      'SELECT session_id, MIN(seq) AS first_seq FROM trajectory '
      'WHERE session_id IS NOT NULL '
      'GROUP BY session_id ORDER BY first_seq LIMIT :limit';

  @override
  Future<List<TrajectoryEnvelope>> rowsForSubject(
    String subject, {
    int limit = defaultReadLimit,
  }) async {
    final result = await _db.execute(subjectSql, {
      'id': subject,
      'limit': limit,
    });
    return [for (final row in result.rows) envelopeFromRow(row)];
  }

  @override
  Future<List<String>> sessions({int limit = defaultReadLimit}) async {
    final result = await _db.execute(sessionsSql, {'limit': limit});
    return [
      for (final row in result.rows)
        if (row['session_id'] case final String id) id,
    ];
  }

  @override
  Future<void> close() => _db.close();
}

/// Decodes one `assoc()` row — every column a nullable string — into the
/// typed §1 envelope.
///
/// DATETIME(6) columns come back without a zone; the appender writes them in
/// UTC, so they are re-read as UTC rather than reinterpreted as local time.
TrajectoryEnvelope envelopeFromRow(Map<String, String?> row) {
  int? number(String column) {
    final raw = row[column];
    return raw == null ? null : int.parse(raw);
  }

  String? instant(String column) {
    final raw = row[column]?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.endsWith('Z') || raw.contains('+')) return raw;
    return '${raw.replaceFirst(' ', 'T')}Z';
  }

  final payload = row['payload'];
  return TrajectoryEnvelope.fromJson(<String, Object?>{
    ...row,
    'seq': number('seq'),
    'epoch_seq': number('epoch_seq'),
    'type_version': number('type_version'),
    'boot_epoch': number('boot_epoch'),
    'fencing_token': number('fencing_token'),
    'round': number('round'),
    'step_round': number('step_round'),
    'incarnation': number('incarnation'),
    'occurred_at': instant('occurred_at'),
    'recorded_at': instant('recorded_at'),
    'expires_at': instant('expires_at'),
    'payload': payload == null || payload.isEmpty
        ? const <String, Object?>{}
        : (jsonDecode(payload) as Map).cast<String, Object?>(),
  });
}
