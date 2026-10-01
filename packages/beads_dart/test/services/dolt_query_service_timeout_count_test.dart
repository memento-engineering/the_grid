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

List<Map<String, Object?>> _answer(String sql) => switch (sql) {
  'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations' => [
    {'v': 53},
  ],
  DoltSchemaShape.probeSql => kV53ProbeRows,
  'SELECT @@tg_working' => [
    {'@@tg_working': 'hash-abc'},
  ],
  _ => const [],
};

/// Answers normally until [hanging] is set; then every statement NEVER
/// completes — the shape a saturated sql-server leaves on the wire, and the
/// one `mysql_client`'s `execute()` (no timeout of its own) would wait on
/// forever. [delay] makes each answer slow but finite.
final class _SaturatedConnection implements DoltConnection {
  _SaturatedConnection({this.hanging = false});

  bool hanging;
  Duration? delay;
  bool closed = false;
  final List<String> statements = [];

  @override
  bool get connected => !closed;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    statements.add(sql);
    if (hanging) return Completer<List<Map<String, Object?>>>().future;
    if (delay case final wait?) await Future<void>.delayed(wait);
    return _answer(sql);
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  test('a statement that never completes dies on the deadline as a '
      'DoltStatementTimeout, is counted, and its connection is evicted '
      '(tg-6n18)', () async {
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
    await expectLater(service.probe(), throwsA(isA<DoltStatementTimeout>()));
    await expectLater(
      service.runReadTransaction((select) => select('SELECT 1')),
      throwsA(isA<DoltStatementTimeout>()),
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
      throwsA(isA<DoltStatementTimeout>()),
    );
    expect(service.timedOutReads, 1);
  });

  test('a read that times out WAITING behind other statements on its '
      'connection evicts nothing and is not counted; the statements ahead '
      'of it finish', () async {
    const deadline = Duration(milliseconds: 500);
    final connection = _SaturatedConnection();
    final service = DoltQueryService(
      _endpoint,
      poolSize: 1,
      queryDeadline: deadline,
      connectionFactory: (_) async => connection,
    );
    await service.connect();
    addTearDown(service.close);

    // Every statement takes 300 ms — inside its own deadline. Transactions A
    // and B interleave statement by statement on the one connection; C's
    // START waits behind A's and B's (600 ms) and gives up at 500 ms.
    connection.delay = const Duration(milliseconds: 300);
    Future<List<Map<String, Object?>>> read() =>
        service.runReadTransaction((select) => select('SELECT 7'));
    final a = read();
    final b = read();
    final c = read();

    await expectLater(
      c,
      throwsA(
        isA<TimeoutException>().having(
          (error) => error is DoltStatementTimeout,
          'is a statement deadline',
          isFalse,
        ),
      ),
    );
    await a;
    await b;
    expect(connection.closed, isFalse, reason: 'the busy socket survives');
    expect(service.timedOutReads, 0);
    expect(
      connection.statements.where((sql) => sql == 'SELECT 7'),
      hasLength(2),
      reason: 'C never reached the wire — no stacked statement',
    );
  });

  test('a timeout raised by the transaction BODY still rolls back and keeps '
      'the connection', () async {
    final connection = _SaturatedConnection();
    final service = DoltQueryService(
      _endpoint,
      poolSize: 1,
      queryDeadline: _deadline,
      connectionFactory: (_) async => connection,
    );
    await service.connect();
    addTearDown(service.close);

    await expectLater(
      service.runReadTransaction<void>(
        (select) async => throw TimeoutException('body gave up'),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(connection.statements, contains('ROLLBACK'));
    expect(connection.closed, isFalse);
    expect(service.timedOutReads, 0);
    expect(await service.probe(), 'hash-abc');
  });
}
