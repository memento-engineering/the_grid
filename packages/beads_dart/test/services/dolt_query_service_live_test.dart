@TestOn('vm')
library;

import 'package:beads_dart/src/errors/bd_exception.dart';
import 'package:beads_dart/src/services/beads_workspace.dart';
import 'package:beads_dart/src/services/dolt_endpoint.dart';
import 'package:beads_dart/src/services/dolt_query_service.dart';
import 'package:beads_dart/src/services/dolt_schema_shape.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

import '../support/schema_probe_rows.dart';

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

    Map<String, List<Map<String, Object?>>> answers({int schemaVersion = 53}) {
      return {
        'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations': [
          {'v': schemaVersion},
        ],
        DoltSchemaShape.probeSql: kV53ProbeRows,
        'SELECT @@tg_working': [
          {'@@tg_working': 'hash-abc'},
        ],
        DoltQueryService.issuesSelect: [
          {'id': 'tg-1', 'title': 'one', 'status': 'open', 'ephemeral': 0},
          {'id': 'tg-2', 'title': 'two', 'status': 'open', 'ephemeral': 0},
        ],
        // The wisps half of the issues ∪ wisps snapshot: a poured convergence
        // wisp root (A15 shape — ephemeral, idempotency_key metadata) and its
        // gate-typed speculative step, already closed.
        DoltQueryService.wispsSelect: [
          {
            'id': 'tg-wisp-r1',
            'title': 'Convergence wisp iter 1',
            'status': 'open',
            'issue_type': 'epic',
            'metadata': '{"idempotency_key":"converge:tg-1:iter:1"}',
            'ephemeral': 1,
          },
          {
            'id': 'tg-wisp-s1',
            'title': 'iterate on tron',
            'status': 'closed',
            'issue_type': 'gate',
            'metadata': '{"gc.deferred_type":"task"}',
            'ephemeral': 1,
          },
        ],
        // labels ∪ wisp_labels arrive as one UNION ALL result set.
        DoltQueryService.labelsSelectFor(kV53Shape): [
          {'issue_id': 'tg-1', 'label': 'zeta'},
          {'issue_id': 'tg-1', 'label': 'alpha'},
          {'issue_id': 'tg-wisp-r1', 'label': 'converge'},
        ],
        // dependencies ∪ wisp_dependencies arrive as one UNION ALL result set:
        // the permanent edge plus the wisp root's parent-child edge.
        DoltQueryService.dependenciesSelectFor(kV53Shape): [
          {
            'issue_id': 'tg-1',
            'depends_on_id': 'tg-2',
            'type': 'blocks',
            'metadata': '{}',
          },
          {
            'issue_id': 'tg-wisp-r1',
            'depends_on_id': 'tg-1',
            'type': 'parent-child',
            'metadata': '{}',
          },
          {
            'issue_id': 'tg-wisp-s1',
            'depends_on_id': 'tg-wisp-r1',
            'type': 'parent-child',
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

        expect(parts.beads, hasLength(4));
        final one = parts.beads.firstWhere((b) => b.id == 'tg-1');
        final two = parts.beads.firstWhere((b) => b.id == 'tg-2');
        // labels arrive unsorted from SQL, sorted in the result.
        expect(one.labels, ['alpha', 'zeta']);
        // tg-1 owns one outgoing edge; tg-2 is the target of one. tg-1 is
        // also the target of the wisp root's parent-child edge.
        expect(one.dependencyCount, 1);
        expect(one.dependentCount, 1);
        expect(two.dependentCount, 1);
        expect(parts.dependencies, hasLength(3));
        expect(
          parts.dependencies.map((d) => d.edgeKey),
          contains('tg-1 tg-2 blocks'),
        );
      },
    );

    test(
      'snapshotParts includes the wisps tables: an A15-poured ephemeral wisp '
      'subtree (root + gate-typed step + parent-child edges) and a closed '
      'wisp are all visible',
      () async {
        // The M2 contract surface: closedWispCount / findByIdempotencyKey /
        // wispClosed detection are all snapshot reads — a snapshot that
        // missed the wisps tables would break every one of them.
        final fake = _FakeConnection(answers());
        final svc = DoltQueryService(
          endpoint,
          connectionFactory: (_) async => fake,
        );
        addTearDown(svc.close);
        final parts = await svc.snapshotParts();

        final root = parts.beads.singleWhere((b) => b.id == 'tg-wisp-r1');
        expect(root.ephemeral, isTrue);
        expect(root.metadata['idempotency_key'], 'converge:tg-1:iter:1');
        // wisp_labels rows attach through the same UNION'd label read.
        expect(root.labels, ['converge']);
        // The wisp root's parent-child edge to the convergence root counts
        // toward its out-degree like any other edge.
        expect(root.dependencyCount, 1);
        expect(root.dependentCount, 1);

        // The gate-typed speculative step remains visible when closed
        // (snapshot = all statuses; deriveIterationCount depends on it).
        final step = parts.beads.singleWhere((b) => b.id == 'tg-wisp-s1');
        expect(step.ephemeral, isTrue);
        expect(step.isClosed, isTrue);
        expect(step.metadata['gc.deferred_type'], 'task');

        expect(
          parts.dependencies.map((d) => d.edgeKey),
          containsAll([
            'tg-wisp-r1 tg-1 parent-child',
            'tg-wisp-s1 tg-wisp-r1 parent-child',
          ]),
        );
      },
    );

    test(
      'a far-newer migration version alone does NOT trip the guard',
      () async {
        // The regression this replaced a version pin to fix: every org store is
        // v53 under bd 1.1.0, and the old pin (50) refused all of them.
        for (final version in [50, 53, 999]) {
          final svc = DoltQueryService(
            endpoint,
            connectionFactory: (_) async =>
                _FakeConnection(answers(schemaVersion: version)),
          );
          addTearDown(svc.close);
          await svc.connect();
          expect(svc.shape.migrationVersion, version);
          expect(svc.shape.isSupported, isTrue);
        }
      },
    );

    test('a store missing a required column is refused LOUDLY', () async {
      final probeless = answers()
        ..[DoltSchemaShape.probeSql] = [
          for (final row in kV53ProbeRows)
            if (!(row['t'] == 'issues' && row['c'] == 'is_blocked')) row,
        ];
      final svc = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => _FakeConnection(probeless),
      );
      addTearDown(svc.close);
      await expectLater(
        svc.connect(),
        throwsA(
          isA<BdSchemaDriftException>().having(
            (e) => e.message,
            'message',
            contains('issues.is_blocked'),
          ),
        ),
      );
    });

    test('the shape is unreadable before connect()', () {
      final svc = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => _FakeConnection(answers()),
      );
      addTearDown(svc.close);
      // No SQL may be emitted from an unverified shape.
      expect(() => svc.shape, throwsStateError);
    });

    test(
      'the dependencies SELECT carries the probed target expression',
      () async {
        final svc = DoltQueryService(
          endpoint,
          connectionFactory: (_) async => _FakeConnection(answers()),
        );
        addTearDown(svc.close);
        await svc.connect();
        // ADR-0000 A44: a cross-store edge lives in depends_on_external, so the
        // alias must COALESCE it in or the edge vanishes from every SQL read.
        expect(svc.dependenciesSelect, contains('depends_on_external'));
        expect(svc.dependenciesSelect, contains('AS depends_on_id'));
      },
    );

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

      // snapshotParts now UNION-reads the wisp tables (issues ∪ wisps,
      // labels ∪ wisp_labels, dependencies ∪ wisp_dependencies) — this live
      // pass proves the UNION'd statements execute against the real schema.
      final parts = await svc.snapshotParts();
      // tg always has infrastructure beads; an empty result would be suspect.
      expect(parts.beads, isNotEmpty);
      // The two tables are disjoint by bd's invariant (issueops/search.go
      // errors on an id in both) — concatenation must not double-count.
      final ids = parts.beads.map((b) => b.id).toList();
      expect(
        ids.toSet().length,
        ids.length,
        reason: 'issues ∪ wisps produced a duplicate bead id',
      );
      // Every dependency edge references a real issue id is not asserted here
      // (cross-workspace edges exist); we only assert structural sanity.
      for (final dep in parts.dependencies.take(20)) {
        expect(dep.issueId, isNotEmpty);
        expect(dep.dependsOnId, isNotEmpty);
      }
    });
  });
}
