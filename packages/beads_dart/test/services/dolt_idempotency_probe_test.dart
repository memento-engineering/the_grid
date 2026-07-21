@TestOn('vm')
library;

import 'package:beads_dart/src/services/dolt_endpoint.dart';
import 'package:beads_dart/src/services/dolt_query_service.dart';
import 'package:beads_dart/src/services/dolt_schema_shape.dart';
import 'package:test/test.dart';

import '../support/schema_probe_rows.dart';

/// A fake [DoltConnection] that records every SQL it sees and answers from a
/// canned table. The probe runs inside `runReadTransaction`, so the control
/// statements (`START TRANSACTION READ ONLY`/`COMMIT`/`ROLLBACK`) flow through
/// here too and are answered with an empty result.
class _RecordingConnection implements DoltConnection {
  _RecordingConnection(this._answers);

  final Map<String, List<Map<String, Object?>>> _answers;
  final List<String> seen = [];
  bool _open = true;

  @override
  bool get connected => _open;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    seen.add(sql);
    return _answers[sql] ?? const [];
  }

  @override
  Future<void> close() async {
    _open = false;
  }
}

void main() {
  const endpoint = DoltEndpoint(
    host: '127.0.0.1',
    port: 34947,
    database: 'tg',
    user: 'root',
    password: 'fake',
  );

  const driftSql =
      'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations';

  group('findWispByIdempotencyKey — the LIVE idempotency probe (A15/A17)', () {
    test(
      'the probe SQL is SELECT-only (writes impossible by construction)',
      () {
        final sql = DoltQueryService.idempotencyProbeSql(
          'tg-root',
          'converge:tg-root:iter:1',
          shape: kV53Shape,
        );
        // The guard rejects anything that is not a read — a passing call proves
        // the probe is a SELECT.
        expect(() => DoltQueryService.assertSelectOnly(sql), returnsNormally);
        expect(sql.trimLeft().toUpperCase(), startsWith('SELECT'));
        // No mutating verb anywhere in the statement.
        expect(
          sql.toUpperCase(),
          isNot(
            matches(RegExp(r'\b(INSERT|UPDATE|DELETE|REPLACE|DROP|ALTER)\b')),
          ),
        );
      },
    );

    test('the probe reads the parent-child edge + idempotency_key', () {
      final sql = DoltQueryService.idempotencyProbeSql(
        'tg-root',
        'converge:tg-root:iter:3',
        shape: kV53Shape,
      );
      // child id parented under tg-root via a parent-child edge …
      expect(sql, contains("type = 'parent-child'"));
      expect(sql, contains("'tg-root'"));
      // … matched on metadata.idempotency_key (JSON column on issues ∪ wisps).
      expect(sql, contains("JSON_EXTRACT(metadata, '\$.idempotency_key')"));
      expect(sql, contains("'converge:tg-root:iter:3'"));
      expect(sql, contains('FROM issues'));
      expect(sql, contains('FROM wisps'));
      // oldest match wins (gc SortCreatedAsc).
      expect(sql, contains('ORDER BY created_at ASC'));
    });

    test('a key with a quote is escaped (stays inside the literal)', () {
      // Bead ids / keys never contain ';' (the guard's multi-statement
      // tripwire), but a stray single quote must be doubled so it cannot
      // break out of the literal.
      final sql = DoltQueryService.idempotencyProbeSql(
        "tg-root'or'1",
        "converge:x'y:iter:1",
        shape: kV53Shape,
      );
      // Single quotes are doubled, so the text stays a literal — no break-out.
      expect(sql, contains("'tg-root''or''1'"));
      expect(sql, contains("'converge:x''y:iter:1'"));
      // Still a single read.
      expect(() => DoltQueryService.assertSelectOnly(sql), returnsNormally);
    });

    test('a HIT returns the matching child id', () async {
      final probeSql = DoltQueryService.idempotencyProbeSql(
        'tg-root',
        'converge:tg-root:iter:1',
        shape: kV53Shape,
      );
      final conn = _RecordingConnection({
        driftSql: [
          {'v': 53},
        ],
        DoltSchemaShape.probeSql: kV53ProbeRows,
        probeSql: [
          {'id': 'tg-wisp-1', 'created_at': '2026-06-13 00:00:00'},
        ],
      });
      final service = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => conn,
      );

      final id = await service.findWispByIdempotencyKey(
        'tg-root',
        'converge:tg-root:iter:1',
      );

      expect(id, 'tg-wisp-1');
      // The probe ran inside a READ ONLY transaction.
      expect(conn.seen, contains('START TRANSACTION READ ONLY'));
      expect(conn.seen, contains('COMMIT'));
      expect(conn.seen, contains(probeSql));
    });

    test('a MISS returns null (no child carries the key)', () async {
      final conn = _RecordingConnection({
        driftSql: [
          {'v': 53},
        ],
        DoltSchemaShape.probeSql: kV53ProbeRows,
        // no probe answer ⇒ empty result ⇒ miss.
      });
      final service = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => conn,
      );

      final id = await service.findWispByIdempotencyKey(
        'tg-root',
        'converge:tg-root:iter:7',
      );

      expect(id, isNull);
    });
  });
}
