import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_bd_runner.dart';
import '../support/schema_probe_rows.dart';

const _endpoint = DoltEndpoint(
  host: 'store.internal',
  port: 4407,
  database: 'custom',
  user: 'reader',
  password: 'secret',
);

void main() {
  test(
    'credentialed resolver endpoint selects SQL for an unknown mode',
    () async {
      final root = Directory.systemTemp.createTempSync('grid_runtime_factory_');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final beadsDir = Directory(p.join(root.path, '.beads'))..createSync();
      File(p.join(beadsDir.path, 'metadata.json')).writeAsStringSync(
        '{"dolt_mode":"custom-server","dolt_database":"custom"}',
      );
      final workspace = BeadsWorkspace.discover(
        start: root.path,
        endpointResolver: const _ResolvedEndpointResolver(),
      )!;
      expect(workspace.mode, DoltMode.unknown);
      expect(workspace.endpoint, same(_endpoint));

      final connection = _ShapeConnection();
      final bundle = await GridRuntimeFactory.build(
        workspace: workspace,
        runner: FakeBdRunner(),
        doltQueryServiceFactory: (endpoint) => DoltQueryService(
          endpoint,
          connectionFactory: (_) async => connection,
        ),
        probeInterval: const Duration(days: 1),
        syncFloorInterval: const Duration(days: 1),
      );
      addTearDown(bundle.shutdown);

      expect(bundle.readPath, ReadPath.sql);
      expect(bundle.dolt, isNotNull);
      expect(bundle.probeReader, isA<SqlBeadProbeReader>());
      expect(connection.queries, [
        'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations',
        DoltSchemaShape.probeSql,
      ]);
    },
  );

  test('bundle.shutdown closes the pooled connection', () async {
    final root = Directory.systemTemp.createTempSync('grid_runtime_factory_');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final beadsDir = Directory(p.join(root.path, '.beads'))..createSync();
    File(p.join(beadsDir.path, 'metadata.json')).writeAsStringSync(
      '{"dolt_mode":"custom-server","dolt_database":"custom"}',
    );
    final workspace = BeadsWorkspace.discover(
      start: root.path,
      endpointResolver: const _ResolvedEndpointResolver(),
    )!;
    final connection = _ShapeConnection();
    final bundle = await GridRuntimeFactory.build(
      workspace: workspace,
      runner: FakeBdRunner(),
      doltQueryServiceFactory: (endpoint) => DoltQueryService(
        endpoint,
        connectionFactory: (_) async => connection,
      ),
      probeInterval: const Duration(days: 1),
      syncFloorInterval: const Duration(days: 1),
    );
    expect(bundle.dolt, isNotNull);
    expect(connection.connected, isTrue);
    await bundle.shutdown();
    expect(connection.connected, isFalse);
  });
}

final class _ResolvedEndpointResolver implements EndpointResolver {
  const _ResolvedEndpointResolver();

  @override
  EndpointResolution resolve(EndpointResolutionRequest request) =>
      const EndpointResolution.resolved(_endpoint);
}

final class _ShapeConnection implements DoltConnection {
  final List<String> queries = [];
  bool _connected = true;

  @override
  bool get connected => _connected;

  @override
  Future<List<Map<String, Object?>>> query(String statement) async {
    queries.add(statement);
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
