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
  test('requested SQL fallback reports the endpoint diagnostic once', () async {
    final root = Directory.systemTemp.createTempSync('grid_runtime_factory_');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final beadsDir = Directory(p.join(root.path, '.beads'))..createSync();
    File(p.join(beadsDir.path, 'metadata.json')).writeAsStringSync(
      '{"dolt_mode":"proxied-server","dolt_database":"custom"}',
    );
    const diagnostic = 'proxy.pid is missing for the cold store';
    final workspace = BeadsWorkspace.discover(
      start: root.path,
      endpointResolver: const _UnavailableEndpointResolver(diagnostic),
    )!;
    final refusals = <String>[];

    final bundle = await GridRuntimeFactory.build(
      workspace: workspace,
      runner: FakeBdRunner(),
      onReadRefusal: refusals.add,
    );
    addTearDown(bundle.shutdown);

    expect(bundle.readPath, ReadPath.cli);
    expect(refusals, [
      'SQL read path unavailable at boot for ${workspace.root}; using bd CLI '
          'reads — $diagnostic',
    ]);
  });

  test('deliberate CLI selection does not report endpoint fallback', () async {
    final root = Directory.systemTemp.createTempSync('grid_runtime_factory_');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final beadsDir = Directory(p.join(root.path, '.beads'))..createSync();
    File(
      p.join(beadsDir.path, 'metadata.json'),
    ).writeAsStringSync('{"dolt_mode":"embedded","dolt_database":"custom"}');
    final workspace = BeadsWorkspace.discover(start: root.path)!;
    final refusals = <String>[];

    final bundle = await GridRuntimeFactory.build(
      workspace: workspace,
      preferSql: false,
      runner: FakeBdRunner(),
      onReadRefusal: refusals.add,
    );
    addTearDown(bundle.shutdown);

    expect(bundle.readPath, ReadPath.cli);
    expect(refusals, isEmpty);
  });

  test(
    'resolved endpoint without credentials reports the named fallback',
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
        endpointResolver: const _NoCredentialEndpointResolver(),
      )!;
      final refusals = <String>[];

      final bundle = await GridRuntimeFactory.build(
        workspace: workspace,
        runner: FakeBdRunner(),
        onReadRefusal: refusals.add,
      );
      addTearDown(bundle.shutdown);

      expect(bundle.readPath, ReadPath.cli);
      expect(refusals, [
        'SQL read path unavailable at boot for ${workspace.root}; using bd CLI '
            'reads — resolved SQL endpoint has no credential.',
      ]);
    },
  );

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

  test(
    'cold proxied workspace warms before resolution and selects SQL',
    () async {
      final root = Directory.systemTemp.createTempSync('grid_runtime_factory_');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final beadsDir = Directory(p.join(root.path, '.beads'))..createSync();
      File(p.join(beadsDir.path, 'metadata.json')).writeAsStringSync(
        '{"dolt_mode":"proxied-server","dolt_database":"custom"}',
      );
      final runner = _MaterializingWarmRunner(root.path);

      final workspace = await BeadsWorkspace.discoverWarmed(
        start: root.path,
        warmRunnerFactory: (_) => runner,
      );

      expect(workspace, isNotNull);
      expect(workspace!.endpoint, isNotNull);
      expect(runner.calls, [
        const [
          'query',
          'id=grid-endpoint-warm',
          '--all',
          '--json',
          '--limit',
          '0',
        ],
      ]);
      expect(runner.calls.single, isNot(contains('show')));
      expect(runner.timeouts, [const Duration(seconds: 15)]);

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
    },
  );

  test(
    'connect failure is loud, closes the candidate, and falls back',
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
      final connection = _ThrowingConnection(StateError('socket refused'));
      final refusals = <String>[];

      final bundle = await GridRuntimeFactory.build(
        workspace: workspace,
        runner: FakeBdRunner(),
        doltQueryServiceFactory: (endpoint) => DoltQueryService(
          endpoint,
          connectionFactory: (_) async => connection,
        ),
        onReadRefusal: refusals.add,
      );
      addTearDown(bundle.shutdown);

      expect(bundle.readPath, ReadPath.cli);
      expect(bundle.dolt, isNull);
      expect(connection.connected, isFalse);
      expect(refusals, [contains('SQL endpoint connect failed (StateError):')]);
      expect(refusals.single, contains('socket refused'));
    },
  );

  test('A54 shape-probe drift has a distinct loud fallback', () async {
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
    final connection = _ShapeDriftConnection();
    final refusals = <String>[];

    final bundle = await GridRuntimeFactory.build(
      workspace: workspace,
      runner: FakeBdRunner(),
      doltQueryServiceFactory: (endpoint) => DoltQueryService(
        endpoint,
        connectionFactory: (_) async => connection,
      ),
      onReadRefusal: refusals.add,
    );
    addTearDown(bundle.shutdown);

    expect(bundle.readPath, ReadPath.cli);
    expect(connection.connected, isFalse);
    expect(refusals, hasLength(1));
    expect(
      refusals.single,
      startsWith(
        'SQL endpoint schema shape probe failed (BdSchemaDriftException):',
      ),
    );
    expect(refusals.single, contains('missing dependencies'));
  });

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

final class _UnavailableEndpointResolver implements EndpointResolver {
  const _UnavailableEndpointResolver(this.diagnostic);

  final String diagnostic;

  @override
  EndpointResolution resolve(EndpointResolutionRequest request) =>
      EndpointResolution.unavailable(diagnostic);
}

final class _NoCredentialEndpointResolver implements EndpointResolver {
  const _NoCredentialEndpointResolver();

  @override
  EndpointResolution resolve(EndpointResolutionRequest request) =>
      const EndpointResolution.resolved(
        DoltEndpoint(host: 'store.internal', port: 4407, database: 'custom'),
      );
}

final class _MaterializingWarmRunner implements BdRunner {
  _MaterializingWarmRunner(this.root);

  final String root;
  final List<List<String>> calls = [];
  final List<Duration?> timeouts = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    timeouts.add(timeout);
    final doltDir = Directory(p.join(root, '.beads', 'dolt'))
      ..createSync(recursive: true);
    File(
      p.join(doltDir.path, 'proxy.pid'),
    ).writeAsStringSync('{"pid":1,"port":4407}');
    File(p.join(doltDir.path, 'beads_dart.secret')).writeAsStringSync('secret');
    return const BdResult(exitCode: 0, stdout: '{}', stderr: '');
  }
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

final class _ThrowingConnection implements DoltConnection {
  _ThrowingConnection(this.error);

  final Object error;
  bool _connected = true;

  @override
  bool get connected => _connected;

  @override
  Future<List<Map<String, Object?>>> query(String statement) =>
      Future.error(error);

  @override
  Future<void> close() async => _connected = false;
}

final class _ShapeDriftConnection implements DoltConnection {
  bool _connected = true;

  @override
  bool get connected => _connected;

  @override
  Future<List<Map<String, Object?>>> query(String statement) async {
    if (statement.contains('schema_migrations')) {
      return const [
        {'v': 53},
      ];
    }
    if (statement == DoltSchemaShape.probeSql) return const [];
    return const [];
  }

  @override
  Future<void> close() async => _connected = false;
}
