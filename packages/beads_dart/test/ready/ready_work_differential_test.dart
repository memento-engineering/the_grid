import 'dart:convert';

import 'package:beads_dart/src/models/bead_status.dart';
import 'package:beads_dart/src/ready/ready_work_differential.dart';
import 'package:beads_dart/src/ready/ready_work_filter.dart';
import 'package:beads_dart/src/ready/ready_work_query.dart';
import 'package:beads_dart/src/services/dolt_endpoint.dart';
import 'package:beads_dart/src/services/dolt_query_service.dart';
import 'package:test/test.dart';

import '../support/fake_bd_runner.dart';

/// A fake [DoltConnection] returning a fixed issue-pass result (no wisp family).
class _FixedConnection implements DoltConnection {
  _FixedConnection(this.ids);
  final List<String> ids;
  bool _open = true;

  @override
  bool get connected => _open;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    final upper = sql.trimLeft().toUpperCase();
    if (upper.startsWith('START TRANSACTION') ||
        upper.startsWith('COMMIT') ||
        upper.startsWith('ROLLBACK')) {
      return const [];
    }
    if (sql.contains('schema_migrations')) {
      return [
        {'v': 50},
      ];
    }
    // No wisp tables.
    if (sql.contains('LIMIT 1') &&
        (sql.contains('wisp_dependencies') || sql.contains('FROM wisps'))) {
      return const [];
    }
    if (sql.contains('FROM issues ')) {
      // Return the configured ids, already in the SQL ORDER BY order (no wisp
      // merge → SQL order is preserved).
      return [
        for (final id in ids)
          {
            'id': id,
            'priority': 2,
            'created_at': '2026-06-12 10:00:00',
            'status': 'open',
            'issue_type': 'task',
            'assignee': '',
            'defer_until': null,
          },
      ];
    }
    return const [];
  }

  @override
  Future<void> close() async {
    _open = false;
  }
}

const _endpoint = DoltEndpoint(
  host: '127.0.0.1',
  port: 34947,
  database: 'tg',
  user: 'root',
  password: 'fake',
);

String _oracleEnvelope(List<String> ids) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (final id in ids) {'id': id, 'title': id, 'status': 'open'},
  ],
});

ReadyWorkDifferential _harness(List<String> sqlIds, FakeBdRunner runner) {
  final svc = DoltQueryService(
    _endpoint,
    connectionFactory: (_) async => _FixedConnection(sqlIds),
  );
  return ReadyWorkDifferential(sqlPort: ReadyWorkQuery(svc), runner: runner);
}

void main() {
  group('ReadyWorkDifferential — oracle argv', () {
    test('default filter → ready --json --limit 0 --sort priority', () {
      final h = _harness(const [], FakeBdRunner());
      expect(h.oracleArgs(const ReadyWorkFilter()), [
        'ready',
        '--json',
        '--limit',
        '0',
        '--sort',
        'priority',
      ]);
    });

    test('filter knobs map to the right flags, metadata keys sorted', () {
      final h = _harness(const [], FakeBdRunner());
      final args = h.oracleArgs(
        const ReadyWorkFilter(
          sortPolicy: ReadyWorkSortPolicy.hybrid,
          includeEphemeral: true,
          includeDeferred: true,
          unassigned: true,
          priority: 1,
          type: 'task',
          labels: ['a', 'b'],
          excludeLabels: ['wip'],
          excludeTypes: ['spike'],
          parentId: 'tg-root',
          hasMetadataKey: 'k',
          metadataFields: {'team': 'core', 'env': 'prod'},
        ),
      );
      expect(args, containsAllInOrder(['--sort', 'hybrid']));
      expect(args, contains('--include-ephemeral'));
      expect(args, contains('--include-deferred'));
      expect(args, contains('--unassigned'));
      expect(args, containsAllInOrder(['--priority', '1']));
      expect(args, containsAllInOrder(['--type', 'task']));
      expect(args, containsAllInOrder(['--label', 'a', '--label', 'b']));
      expect(args, containsAllInOrder(['--exclude-label', 'wip']));
      expect(args, containsAllInOrder(['--exclude-type', 'spike']));
      expect(args, containsAllInOrder(['--parent', 'tg-root']));
      expect(args, containsAllInOrder(['--has-metadata-key', 'k']));
      // env sorts before team.
      expect(
        args,
        containsAllInOrder([
          '--metadata-field',
          'env=prod',
          '--metadata-field',
          'team=core',
        ]),
      );
    });

    test('a non-open status has no oracle and is rejected (trap #4)', () {
      final h = _harness(const [], FakeBdRunner());
      expect(
        () =>
            h.oracleArgs(const ReadyWorkFilter(status: BeadStatus.inProgress)),
        throwsArgumentError,
      );
    });
  });

  group('ReadyWorkDifferential — diff semantics (ADR-0003 D5)', () {
    test('identical ordered sets agree', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'ready',
          BdReply(stdout: _oracleEnvelope(['tg-1', 'tg-2'])),
        );
      final h = _harness(['tg-1', 'tg-2'], runner);
      final diff = await h.run(const ReadyWorkFilter());
      expect(diff.matches, isTrue);
      expect(diff.diverged, isFalse);
      expect(diff.sqlOnly, isEmpty);
      expect(diff.oracleOnly, isEmpty);
      expect(diff.describe(), contains('agree'));
    });

    test('a membership divergence is reported with per-side ids', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'ready',
          BdReply(stdout: _oracleEnvelope(['tg-1', 'tg-3'])),
        );
      final h = _harness(['tg-1', 'tg-2'], runner);
      final diff = await h.run(const ReadyWorkFilter());
      expect(diff.diverged, isTrue);
      expect(diff.sqlOnly, {'tg-2'});
      expect(diff.oracleOnly, {'tg-3'});
      expect(diff.orderOnlyDivergence, isFalse);
      expect(diff.describe(), contains('SQL-only: {tg-2}'));
    });

    test('an order-only divergence is flagged distinctly', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'ready',
          BdReply(stdout: _oracleEnvelope(['tg-2', 'tg-1'])),
        );
      final h = _harness(['tg-1', 'tg-2'], runner);
      final diff = await h.run(const ReadyWorkFilter());
      expect(diff.diverged, isTrue);
      expect(diff.sqlOnly, isEmpty);
      expect(diff.oracleOnly, isEmpty);
      expect(diff.orderOnlyDivergence, isTrue);
      expect(diff.describe(), contains('different order'));
    });

    test(
      'assertAgreement throws ReadyWorkDivergence on any divergence',
      () async {
        final runner = FakeBdRunner()
          ..stubCommand('ready', BdReply(stdout: _oracleEnvelope(['tg-9'])));
        final h = _harness(['tg-1'], runner);
        await expectLater(
          h.assertAgreement(const ReadyWorkFilter()),
          throwsA(isA<ReadyWorkDivergence>()),
        );
      },
    );

    test('assertAgreement returns the diff when both sides agree', () async {
      final runner = FakeBdRunner()
        ..stubCommand('ready', BdReply(stdout: _oracleEnvelope(['tg-1'])));
      final h = _harness(['tg-1'], runner);
      final diff = await h.assertAgreement(const ReadyWorkFilter());
      expect(diff.matches, isTrue);
    });

    test('a non-zero oracle exit surfaces as an error', () async {
      final runner = FakeBdRunner()
        ..stubCommand('ready', const BdReply(exitCode: 1, stderr: 'boom'));
      final h = _harness(['tg-1'], runner);
      await expectLater(
        h.run(const ReadyWorkFilter()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
