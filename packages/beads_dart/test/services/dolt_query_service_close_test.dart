@TestOn('vm')
library;

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

Map<String, List<Map<String, Object?>>> _answers() => {
  'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations': [
    {'v': 53},
  ],
  DoltSchemaShape.probeSql: kV53ProbeRows,
  'SELECT @@tg_working': [
    {'@@tg_working': 'hash-abc'},
  ],
};

/// A [DoltConnection] that lives in a shared ledger of open handles. It leaves
/// the ledger only when its own [close] completes, so a test can count the
/// sockets the service still holds.
final class _LedgerConnection implements DoltConnection {
  _LedgerConnection(this._ledger) {
    _ledger.add(this);
  }

  final Set<_LedgerConnection> _ledger;

  /// Flips this connection to not-`connected` without closing it — the shape
  /// the server's own teardown leaves behind.
  bool reaped = false;

  /// Refuses this many close attempts before allowing one to complete.
  int failCloses = 0;

  @override
  bool get connected => !reaped && _ledger.contains(this);

  @override
  Future<List<Map<String, Object?>>> query(String sql) async =>
      _answers()[sql] ?? const [];

  @override
  Future<void> close() async {
    if (failCloses > 0) {
      failCloses -= 1;
      throw StateError('close refused');
    }
    _ledger.remove(this);
  }
}

void main() {
  test(
    'close() drains a connection whose eviction close was refused',
    () async {
      final ledger = <_LedgerConnection>{};
      final service = DoltQueryService(
        _endpoint,
        connectionFactory: (_) async => _LedgerConnection(ledger),
      );

      await service.connect();
      expect(ledger, isNotEmpty, reason: 'sanity: the pool filled');
      // The server reaped one socket without the client noticing. Its first
      // close refuses, so the next acquire evicts it from the pool but the
      // service must retain the handle in its opened-connection ledger.
      final reaped = ledger.first
        ..reaped = true
        ..failCloses = 1;
      expect(await service.probe(), 'hash-abc');
      expect(
        ledger,
        contains(reaped),
        reason: 'a refused close must leave the handle tracked',
      );

      await service.close();

      expect(ledger, isEmpty, reason: 'no handle survives close()');
    },
  );

  test('close() is idempotent over the ledger', () async {
    final ledger = <_LedgerConnection>{};
    final service = DoltQueryService(
      _endpoint,
      connectionFactory: (_) async => _LedgerConnection(ledger),
    );
    await service.connect();
    await service.close();
    await service.close();
    expect(ledger, isEmpty);
  });
}
