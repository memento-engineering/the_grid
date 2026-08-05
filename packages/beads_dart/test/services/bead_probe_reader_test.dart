import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import '../support/schema_probe_rows.dart';

void main() {
  group('CliBeadProbeReader', () {
    test('uses one filtered query for an exact id and allowed type', () async {
      final runner = _ScopedRunner();
      final reader = _reader(runner);

      final bead = await reader.beadById(
        'tg-step1',
        types: const {IssueType('step')},
      );

      expect(bead?.id, 'tg-step1');
      expect(runner.calls.where((args) => args.first == 'query'), [
        ['query', 'id=tg-step1', '--json'],
      ]);
      expect(runner.calls.where((args) => args.first == 'show'), isEmpty);
      expect(runner.calls.where((args) => args.first == 'export'), isEmpty);
    });

    test('empty allowed types make no calls', () async {
      final runner = _ScopedRunner();

      expect(
        await _reader(runner).beadById('tg-step1', types: const {}),
        isNull,
      );
      expect(runner.calls, isEmpty);
    });

    test(
      'returns null when the query has no exact id and type match',
      () async {
        final runner = _ScopedRunner();

        expect(
          await _reader(
            runner,
          ).beadById('tg-step1', types: const {IssueType('molecule')}),
          isNull,
        );
      },
    );

    test('refuses duplicate exact query matches', () async {
      final runner = _ScopedRunner(duplicateExactMatch: true);

      expect(
        () => _reader(
          runner,
        ).beadById('tg-step1', types: const {IssueType('step')}),
        throwsA(isA<BdParseException>()),
      );
    });

    test('propagates a failed query', () async {
      final runner = _ScopedRunner(failQuery: true);

      expect(
        () => _reader(
          runner,
        ).beadById('tg-step1', types: const {IssueType('step')}),
        throwsA(isA<BdCommandFailed>()),
      );
    });

    test('retains exact scoped open reads and supersedes edges', () async {
      final runner = _ScopedRunner();
      final reader = _reader(runner);

      final open = await reader.openBeads(
        types: const {IssueType('step'), IssueType('gate')},
      );
      final successors = await reader.openSuperseding({'tg-old'});

      expect(open.map((bead) => bead.id), ['tg-gate1']);
      expect(successors.map((bead) => bead.id), ['tg-gate1']);
      expect(runner.calls.where((args) => args.first == 'list'), [
        ['list', '-t', 'step', '--status', 'open', '--json'],
        ['list', '-t', 'gate', '--status', 'open', '--json'],
        ['list', '-t', 'step', '--status', 'open', '--json'],
        ['list', '-t', 'gate', '--status', 'open', '--json'],
      ]);
      expect(runner.calls.where((args) => args.first == 'show'), isEmpty);
      expect(runner.calls.where((args) => args.first == 'export'), isEmpty);
    });
  });

  group('SqlBeadProbeReader', () {
    test('quotes flat dotted metadata keys as literal JSON members', () async {
      final connection = _SqlConnection();
      final dolt = DoltQueryService(
        const DoltEndpoint(
          host: 'localhost',
          port: 3306,
          database: 'tg',
          user: 'root',
          password: '',
        ),
        poolSize: 1,
        connectionFactory: (_) async => connection,
      );
      await dolt.connect();
      final reader = SqlBeadProbeReader(dolt);

      await reader.openBeads(
        types: const {IssueType('step')},
        metadataAll: const {'grid.step.session': 'tgdog-sess1'},
        metadataAny: const {'grid.circuit.session': 'tgdog-sess1'},
      );

      final sql = connection.sql.where((sql) => sql.contains('JSON_EXTRACT'));
      expect(sql, isNotEmpty);
      expect(
        sql,
        everyElement(
          contains(
            'JSON_UNQUOTE(JSON_EXTRACT(CAST(metadata AS CHAR), '
            '\'\$."grid.step.session"\')) = \'tgdog-sess1\'',
          ),
        ),
      );
      expect(
        sql,
        everyElement(
          contains(
            'JSON_UNQUOTE(JSON_EXTRACT(CAST(metadata AS CHAR), '
            '\'\$."grid.circuit.session"\')) = \'tgdog-sess1\'',
          ),
        ),
      );
    });
  });
}

CliBeadProbeReader _reader(_ScopedRunner runner) => CliBeadProbeReader(
  BdCliService(runner),
  lifecycleTypes: const {IssueType('step'), IssueType('gate')},
);

class _ScopedRunner implements BdRunner {
  _ScopedRunner({this.duplicateExactMatch = false, this.failQuery = false});

  final bool duplicateExactMatch;
  final bool failQuery;
  final List<List<String>> calls = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    if (args.first == 'export') {
      return const BdResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Error: export is not supported in proxied-server mode',
      );
    }
    if (args.first == 'query') {
      if (args.length != 3 || args[1] != 'id=tg-step1' || args[2] != '--json') {
        throw StateError('unexpected query: $args');
      }
      if (failQuery) {
        return const BdResult(exitCode: 1, stdout: '', stderr: 'query failed');
      }
      final data = <Map<String, dynamic>>[
        {'id': 'tg-step1', 'issue_type': 'step', 'status': 'closed'},
        {'id': 'tg-other', 'issue_type': 'step', 'status': 'open'},
        {'id': 'tg-step1', 'issue_type': 'gate', 'status': 'open'},
        if (duplicateExactMatch)
          {'id': 'tg-step1', 'issue_type': 'step', 'status': 'open'},
      ];
      return BdResult(
        exitCode: 0,
        stdout: jsonEncode({'schema_version': 1, 'data': data}),
        stderr: '',
      );
    }
    if (args.first != 'list') throw StateError('unexpected call: $args');
    if (args.length != 6 ||
        args[1] != '-t' ||
        args[3] != '--status' ||
        args[4] != 'open' ||
        args[5] != '--json') {
      throw StateError('unexpected list: $args');
    }
    final type = args[2];
    final data = <Map<String, dynamic>>[];
    if (type == 'gate') {
      data.add({
        'id': 'tg-gate1',
        'issue_type': 'gate',
        'status': 'open',
        'dependencies': [
          {
            'issue_id': 'tg-gate1',
            'depends_on_id': 'tg-old',
            'type': 'supersedes',
          },
        ],
      });
    }
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode({'schema_version': 1, 'data': data}),
      stderr: '',
    );
  }
}

class _SqlConnection implements DoltConnection {
  final List<String> sql = [];
  bool _connected = true;

  @override
  bool get connected => _connected;

  @override
  Future<List<Map<String, Object?>>> query(String statement) async {
    sql.add(statement);
    if (statement.contains('schema_migrations')) {
      return const [
        {'v': 53},
      ];
    }
    if (statement == DoltSchemaShape.probeSql) return kV53ProbeRows;
    return const [];
  }

  @override
  Future<void> close() async => _connected = false;
}
