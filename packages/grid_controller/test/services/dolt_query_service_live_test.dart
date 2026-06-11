@TestOn('vm')
library;

import 'package:grid_controller/src/errors/bd_exception.dart';
import 'package:grid_controller/src/services/beads_workspace.dart';
import 'package:grid_controller/src/services/dolt_endpoint.dart';
import 'package:grid_controller/src/services/dolt_query_service.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

/// A fake [DoltConnection] backed by a canned query→rows table, with a
/// programmable "reaped" flip so the reconnect path can be exercised offline.
class _FakeConnection implements DoltConnection {
  _FakeConnection(this._answers, {this.failFirstWith});

  final Map<String, List<Map<String, Object?>>> _answers;

  /// If set, the first [query] call throws this and then marks the connection
  /// closed (simulating the 30s idle reap mid-query).
  Object? failFirstWith;
  bool _open = true;
  int queries = 0;

  @override
  bool get connected => _open;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    queries++;
    final fail = failFirstWith;
    if (fail != null) {
      failFirstWith = null;
      _open = false;
      throw fail;
    }
    if (!_open) {
      throw const MySQLClientException(
        'Can not execute query: connection closed',
      );
    }
    return _answers[sql] ?? const [];
  }

  @override
  Future<void> close() async {
    _open = false;
  }
}

void main() {
  // ------------------------------------------------------------------------
  // Offline unit coverage: the pool / drift-guard / SELECT-only logic runs
  // against a fake connection, no real socket required.
  // ------------------------------------------------------------------------
  group('DoltQueryService (offline, fake connection)', () {
    const endpoint = DoltEndpoint(
      host: '127.0.0.1',
      port: 34947,
      database: 'tg',
      user: 'root',
      password: 'fake',
    );

    Map<String, List<Map<String, Object?>>> answers({int schemaVersion = 50}) {
      return {
        'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations': [
          {'v': schemaVersion},
        ],
        'SELECT @@tg_working': [
          {'@@tg_working': 'hash-abc'},
        ],
        'SELECT * FROM issues': [
          {'id': 'tg-1', 'title': 'one', 'status': 'open', 'ephemeral': 0},
          {'id': 'tg-2', 'title': 'two', 'status': 'open', 'ephemeral': 0},
        ],
        'SELECT issue_id, label FROM labels': [
          {'issue_id': 'tg-1', 'label': 'zeta'},
          {'issue_id': 'tg-1', 'label': 'alpha'},
        ],
        DoltQueryService.dependenciesSelect: [
          {
            'issue_id': 'tg-1',
            'depends_on_id': 'tg-2',
            'type': 'blocks',
            'metadata': '{}',
          },
        ],
      };
    }

    test(
      'probe returns the working-set hash from SELECT @@tg_working',
      () async {
        final fake = _FakeConnection(answers());
        final svc = DoltQueryService(
          endpoint,
          connectionFactory: (_) async => fake,
        );
        addTearDown(svc.close);
        await svc.connect();
        expect(svc.probeSql, 'SELECT @@tg_working');
        expect(await svc.probe(), 'hash-abc');
      },
    );

    test(
      'snapshotParts composes beads with labels (sorted) + degree counts',
      () async {
        final fake = _FakeConnection(answers());
        final svc = DoltQueryService(
          endpoint,
          connectionFactory: (_) async => fake,
        );
        addTearDown(svc.close);
        final parts = await svc.snapshotParts();

        expect(parts.beads, hasLength(2));
        final one = parts.beads.firstWhere((b) => b.id == 'tg-1');
        final two = parts.beads.firstWhere((b) => b.id == 'tg-2');
        // labels arrive unsorted from SQL, sorted in the result.
        expect(one.labels, ['alpha', 'zeta']);
        // tg-1 owns one outgoing edge; tg-2 is the target of one.
        expect(one.dependencyCount, 1);
        expect(two.dependentCount, 1);
        expect(parts.dependencies, hasLength(1));
        expect(parts.dependencies.single.edgeKey, 'tg-1 tg-2 blocks');
      },
    );

    test('a newer schema version trips the drift guard at connect()', () async {
      final fake = _FakeConnection(answers(schemaVersion: 51));
      final svc = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => fake,
      );
      addTearDown(svc.close);
      await expectLater(svc.connect(), throwsA(isA<BdSchemaDriftException>()));
    });

    test('an equal-or-older schema version is accepted', () async {
      final svc = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => _FakeConnection(answers()),
      );
      addTearDown(svc.close);
      await svc.connect();
      // 49 < 50 must not throw either.
      final older = DoltQueryService(
        endpoint,
        connectionFactory: (_) async =>
            _FakeConnection(answers(schemaVersion: 49)),
      );
      addTearDown(older.close);
      await older.connect();
    });

    test(
      'reconnects transparently when an idle socket is reaped mid-query',
      () async {
        var opened = 0;
        final svc = DoltQueryService(
          endpoint,
          connectionFactory: (_) async {
            opened++;
            // First connection fails its first query (reaped), rest are healthy.
            return _FakeConnection(
              answers(),
              failFirstWith: opened == 1
                  ? const MySQLClientException(
                      'Can not execute query: connection closed',
                    )
                  : null,
            );
          },
        );
        addTearDown(svc.close);
        // connect() opens conn #1 and runs the drift probe, which trips the reap;
        // it transparently reconnects to conn #2 and succeeds.
        await svc.connect();
        expect(await svc.probe(), 'hash-abc');
        expect(opened, greaterThanOrEqualTo(2));
      },
    );

    test('SELECT-only guard rejects writes and statement batching', () {
      expect(
        () => DoltQueryService.assertSelectOnly('UPDATE issues SET x=1'),
        throwsArgumentError,
      );
      expect(
        () => DoltQueryService.assertSelectOnly('DELETE FROM issues'),
        throwsArgumentError,
      );
      expect(
        () => DoltQueryService.assertSelectOnly('INSERT INTO labels VALUES(1)'),
        throwsArgumentError,
      );
      expect(
        () => DoltQueryService.assertSelectOnly("CALL DOLT_COMMIT('-m','x')"),
        throwsArgumentError,
      );
      expect(
        () => DoltQueryService.assertSelectOnly('SELECT 1; DROP TABLE issues'),
        throwsArgumentError,
      );
      // A legitimate read (and a leading-CTE read) is allowed.
      expect(
        () => DoltQueryService.assertSelectOnly('SELECT * FROM issues'),
        returnsNormally,
      );
      expect(
        () => DoltQueryService.assertSelectOnly(
          '-- comment\nWITH x AS (SELECT 1) SELECT * FROM x',
        ),
        returnsNormally,
      );
    });
  });

  // ------------------------------------------------------------------------
  // Live test: self-skips without GC_DOLT_PASSWORD; runs read-only against the
  // real gc-managed Dolt server when creds are present (ADR-0000 A8).
  // ------------------------------------------------------------------------
  group('DoltQueryService (live, requires GC_DOLT_PASSWORD)', () {
    test('probe is stable when idle; snapshotParts returns beads', () async {
      final ws = BeadsWorkspace.discover();
      final endpoint = ws?.endpoint;
      if (endpoint == null || !endpoint.hasCredential) {
        markTestSkipped(
          'no live Dolt endpoint with credentials '
          '(GC_DOLT_PASSWORD unset) — SQL read path not exercised',
        );
        return;
      }

      final svc = DoltQueryService(endpoint);
      addTearDown(svc.close);

      try {
        await svc.connect();
      } on BdSchemaDriftException catch (e) {
        // Forward drift is an acceptable live outcome — it is exactly the
        // signal that tells the controller to fall back to the bd CLI.
        markTestSkipped('live schema drift: ${e.message}');
        return;
      }

      // Two idle probes must agree (no write between them).
      final first = await svc.probe();
      final second = await svc.probe();
      expect(second, first, reason: 'working-set hash flapped while idle');

      final parts = await svc.snapshotParts();
      // tg always has infrastructure beads; an empty result would be suspect.
      expect(parts.beads, isNotEmpty);
      // Every dependency edge references a real issue id is not asserted here
      // (cross-workspace edges exist); we only assert structural sanity.
      for (final dep in parts.dependencies.take(20)) {
        expect(dep.issueId, isNotEmpty);
        expect(dep.dependsOnId, isNotEmpty);
      }
    });
  });
}
