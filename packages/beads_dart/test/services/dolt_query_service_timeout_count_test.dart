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

/// A short test deadline: the production one is [DoltQueryService.queryTimeout].
const _deadline = Duration(milliseconds: 50);

/// Answers normally until [hanging] is set; then every statement NEVER
/// completes — the shape a saturated sql-server leaves on the wire, and the
/// one `mysql_client`'s `execute()` (no timeout of its own) would wait on
/// forever.
final class _SaturatedConnection implements DoltConnection {
  _SaturatedConnection({this.hanging = false});

  bool hanging;
  bool closed = false;

  @override
  bool get connected => !closed;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    if (hanging) return Completer<List<Map<String, Object?>>>().future;
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
  Future<void> close() async => closed = true;
}

void main() {
  test('a statement that never completes dies on the deadline, is counted, '
      'and its connection is evicted (tg-6n18)', () async {
    final connections = <_SaturatedConnection>[];
    var saturated = false;
    final service = DoltQueryService(
      _endpoint,
      poolSize: 1,
      queryDeadline: _deadline,
      connectionFactory: (_) async {
        final connection = _SaturatedConnection(hanging: saturated);
        connections.add(connection);
        return connection;
      },
    );
    await service.connect();
    addTearDown(service.close);

    await service.probe();
    expect(service.timedOutReads, 0, reason: 'an answered read is not one');

    saturated = true;
    connections.single.hanging = true;
    await expectLater(service.probe(), throwsA(isA<TimeoutException>()));
    await expectLater(
      service.runReadTransaction((select) => select('SELECT 1')),
      throwsA(isA<TimeoutException>()),
    );
    expect(service.timedOutReads, 2);
    expect(
      connections.first.closed,
      isTrue,
      reason: 'a wedged socket never serves another read',
    );

    // The server recovers: a fresh connection answers; the count is
    // process-lifetime.
    saturated = false;
    await service.probe();
    expect(service.timedOutReads, 2);
    expect(connections.length, greaterThan(1));
  });

  test('a timeout inside a NESTED read (the read transaction\'s lazy shape '
      'probe) is counted ONCE', () async {
    final service = DoltQueryService(
      _endpoint,
      queryDeadline: _deadline,
      connectionFactory: (_) async => _SaturatedConnection(hanging: true),
    );
    addTearDown(service.close);

    // Never connected: runReadTransaction probes the shape first, through the
    // same counted select path, and that probe is what times out.
    await expectLater(
      service.runReadTransaction((select) => select('SELECT 1')),
      throwsA(isA<TimeoutException>()),
    );
    expect(service.timedOutReads, 1);
  });
}
