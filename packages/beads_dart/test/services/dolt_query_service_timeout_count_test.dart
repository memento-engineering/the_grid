@TestOn('vm')
library;

import 'dart:async';

import 'package:beads_dart/src/services/dolt_endpoint.dart';
import 'package:beads_dart/src/services/dolt_query_service.dart';
import 'package:beads_dart/src/services/dolt_schema_shape.dart';
import 'package:test/test.dart';

import '../support/schema_probe_rows.dart';

const _endpoint = DoltEndpoint(
  host: '127.0.0.1',
  port: 34947,
  database: 'tg',
  user: 'root',
  password: 'fake',
);

/// Answers the connect-time shape probe, then times out every statement while
/// [timingOut] is set — the shape a saturated sql-server leaves on the wire.
final class _SaturatedConnection implements DoltConnection {
  bool timingOut = false;

  @override
  bool get connected => true;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    if (timingOut) {
      throw TimeoutException('query', DoltQueryService.queryTimeout);
    }
    return switch (sql) {
      'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations' => [
        {'v': 53},
      ],
      DoltSchemaShape.probeSql => kV53ProbeRows,
      'SELECT @@tg_working' => [
        {'@@tg_working': 'hash-abc'},
      ],
      _ => const [],
    };
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('counts every read that dies on the query deadline, and only those '
      '(tg-6n18)', () async {
    final connection = _SaturatedConnection();
    final service = DoltQueryService(
      _endpoint,
      connectionFactory: (_) async => connection,
    );
    await service.connect();
    addTearDown(service.close);

    await service.probe();
    expect(service.timedOutReads, 0, reason: 'an answered read is not one');

    connection.timingOut = true;
    await expectLater(service.probe(), throwsA(isA<TimeoutException>()));
    await expectLater(
      service.runReadTransaction((select) => select('SELECT 1')),
      throwsA(isA<TimeoutException>()),
    );
    expect(service.timedOutReads, 2);

    connection.timingOut = false;
    await service.probe();
    expect(service.timedOutReads, 2, reason: 'a process-lifetime count');
  });
}
