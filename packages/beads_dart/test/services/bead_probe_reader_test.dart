import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import '../support/schema_probe_rows.dart';

void main() {
  group('CliBeadProbeReader', () {
    test(
      'uses scoped lists for multi-status lookup and supersedes edges',
      () async {
        final runner = _ScopedRunner();
        final reader = CliBeadProbeReader(
          BdCliService(runner),
          lifecycleTypes: const {IssueType('step'), IssueType('gate')},
        );

        final bead = await reader.beadById(
          'tg-step1',
          types: const {IssueType('step')},
        );
        final lookupCalls = runner.calls
            .where((args) => args.first == 'list')
            .toList();
        final successors = await reader.openSuperseding({'tg-old'});

        expect(bead?.id, 'tg-step1');
        expect(successors.map((bead) => bead.id), ['tg-gate1']);
        expect(lookupCalls, hasLength(BeadStatus.builtIns.length));
        expect(runner.calls.where((args) => args.first == 'export'), isEmpty);
        expect(
          runner.calls.where((args) => args.first == 'list'),
          everyElement(
            predicate<List<String>>(
              (args) =>
                  args.length == 6 &&
                  args[1] == '-t' &&
                  args[3] == '--status' &&
                  args[5] == '--json',
            ),
          ),
        );
      },
    );
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

class _ScopedRunner implements BdRunner {
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
    if (args.first != 'list') throw StateError('unexpected call: $args');
    final type = args[2];
    final status = args[4];
    final data = <Map<String, dynamic>>[];
    if (type == 'step' && status == 'closed') {
      data.add({'id': 'tg-step1', 'issue_type': 'step', 'status': 'closed'});
    }
    if (type == 'gate' && status == 'open') {
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
