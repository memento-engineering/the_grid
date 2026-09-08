import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const <Seed>[]);
}

final class _NullResolver implements SessionResolver {
  const _NullResolver();

  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('never reached');
}

class _RecordingDelegate extends GridDelegate {
  _RecordingDelegate({this.rootPath = '/grid/home'});

  final String rootPath;
  final events = <String>[];

  @override
  String get root => rootPath;

  @override
  void didLaunch() => events.add('didLaunch');

  @override
  Future<void> boot(GridConfiguration configuration) async {
    events.add('boot');
  }

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    events.add('build');
    return const _Leaf();
  }
}

final class _EnabledDelegate extends _RecordingDelegate {
  _EnabledDelegate({super.rootPath});

  var postureReads = 0;

  @override
  bool get maintainsStateStoreOnBoot {
    postureReads++;
    return true;
  }
}

final class _UnavailableStateDelegate extends _EnabledDelegate {
  _UnavailableStateDelegate({required super.rootPath, required this.workRoot});

  final String workRoot;
  bool disposed = false;

  @override
  Future<void> boot(GridConfiguration configuration) async {
    events.add('boot');
    await assembleStationWork(
      stateStore: GridStateStore.forGridRoot(rootPath),
      substations: [SubstationWorkSpec(name: 'proj', root: workRoot)],
      resolver: const _NullResolver(),
      dryRun: false,
      preferSql: false,
      providerOverride: DryRunProvider(),
      gitOverride: DryStationGitService(),
    );
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

final class _ByteConsumer implements StreamConsumer<List<int>> {
  final _bytes = <int>[];

  String get text => utf8.decode(_bytes);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

final class _RecordingStderr implements Stdout {
  _RecordingStderr(_ByteConsumer consumer) : _sink = IOSink(consumer);

  final IOSink _sink;

  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  String lineTerminator = '\n';
  @override
  Future<void> get done => _sink.done;
  @override
  bool get hasTerminal => false;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  IOSink get nonBlocking => _sink;
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> flush() => _sink.flush();
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
}

Directory _repositoryRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (Directory(
      p.join(candidate.path, 'packages', 'grid_sdk'),
    ).existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('repository root not found from ${Directory.current}');
    }
    candidate = parent;
  }
}

void _seedEmbeddedStore(String root, {required String database}) {
  Directory(p.join(root, '.beads')).createSync(recursive: true);
  File(
    p.join(root, '.beads', 'metadata.json'),
  ).writeAsStringSync('{"dolt_mode":"embedded","dolt_database":"$database"}');
}

void _seedProxiedStore(String root, {required String database, int? port}) {
  final doltDir = Directory(p.join(root, '.beads', 'dolt'))
    ..createSync(recursive: true);
  File(p.join(root, '.beads', 'metadata.json')).writeAsStringSync(
    '{"dolt_mode":"proxied-server","dolt_database":"$database"}',
  );
  File(
    p.join(doltDir.path, 'beads_dart.secret'),
  ).writeAsStringSync('$database-secret');
  if (port != null) {
    File(
      p.join(doltDir.path, 'proxy.pid'),
    ).writeAsStringSync('{"pid":2,"port":$port}');
  }
}

void main() {
  test(
    'enabled maintenance runs once after didLaunch and before boot',
    () async {
      final gridHome = Directory.systemTemp.createTempSync(
        'run-grid-maintenance-',
      );
      addTearDown(() => gridHome.deleteSync(recursive: true));
      final delegate = _EnabledDelegate(rootPath: gridHome.path);
      var calls = 0;

      final handle = await runGrid(
        delegate,
        maintainStateStore: ({required gridHome}) async {
          calls++;
          delegate.events.add('maintenance:$gridHome');
        },
      );
      addTearDown(handle.teardown);

      expect(calls, 1);
      expect(delegate.postureReads, 1);
      expect(delegate.events, <String>[
        'didLaunch',
        'maintenance:${gridHome.path}',
        'boot',
        'build',
      ]);
    },
  );

  test(
    'maintenance posture defaults off and enabled runs exactly once',
    () async {
      var calls = 0;
      Future<void> maintain({required String gridHome}) async {
        calls++;
      }

      final defaultDelegate = _RecordingDelegate();
      final defaultHandle = await runGrid(
        defaultDelegate,
        maintainStateStore: maintain,
      );
      addTearDown(defaultHandle.teardown);
      expect(defaultDelegate.maintainsStateStoreOnBoot, isFalse);
      expect(calls, 0);

      final enabledDelegate = _EnabledDelegate();
      final enabledHandle = await runGrid(
        enabledDelegate,
        maintainStateStore: maintain,
      );
      addTearDown(enabledHandle.teardown);
      expect(calls, 1);
      expect(enabledDelegate.postureReads, 1);
    },
  );

  test(
    'maintenance failure reaches onError or stderr and never aborts boot',
    () async {
      final reportedDelegate = _EnabledDelegate();
      final refusals = <GridHookError>[];
      final reportedHandle = await runGrid(
        reportedDelegate,
        maintainStateStore: ({required gridHome}) async {
          reportedDelegate.events.add('maintenance');
          throw StateError('reported failure');
        },
        onError: refusals.add,
      );
      addTearDown(reportedHandle.teardown);

      expect(refusals, hasLength(1));
      expect(refusals.single.hook, 'maintenance');
      expect(refusals.single.delegateType, _EnabledDelegate);
      expect(refusals.single.cause, isA<StateError>());
      expect(reportedDelegate.events, <String>[
        'didLaunch',
        'maintenance',
        'boot',
        'build',
      ]);

      final defaultDelegate = _EnabledDelegate();
      final bytes = _ByteConsumer();
      final capturedStderr = _RecordingStderr(bytes);
      late GridHandle defaultHandle;
      await IOOverrides.runZoned(() async {
        defaultHandle = await runGrid(
          defaultDelegate,
          maintainStateStore: ({required gridHome}) async {
            defaultDelegate.events.add('maintenance');
            throw StateError('line one\r\nline two\nline three');
          },
        );
      }, stderr: () => capturedStderr);
      addTearDown(defaultHandle.teardown);
      await capturedStderr.flush();

      expect(bytes.text.split('\n').where((line) => line.isNotEmpty), <String>[
        'station.maintenanceError: '
            '${defaultDelegate.runtimeType}.maintenance() threw — '
            'Bad state: line one line two line three',
      ]);
      expect(defaultDelegate.events, <String>[
        'didLaunch',
        'maintenance',
        'boot',
        'build',
      ]);
    },
  );

  test(
    'unavailable live state endpoint aborts through the boot rail',
    () async {
      final gridHome = Directory.systemTemp.createTempSync(
        'run-grid-state-endpoint-',
      );
      addTearDown(() => gridHome.deleteSync(recursive: true));
      final workRoot = p.join(gridHome.path, 'project');
      final runtimeDir = p.join(gridHome.path, '.grid');
      _seedEmbeddedStore(workRoot, database: 'proj');
      _seedProxiedStore(runtimeDir, database: 'tgstate');
      _seedProxiedStore(gridHome.path, database: 'work', port: 65202);
      final statePid = p.join(runtimeDir, '.beads', 'dolt', 'proxy.pid');
      final delegate = _UnavailableStateDelegate(
        rootPath: gridHome.path,
        workRoot: workRoot,
      );
      final advisoryReports = <GridHookError>[];

      await expectLater(
        runGrid(
          delegate,
          maintainStateStore: ({required gridHome}) async {
            delegate.events.add('maintenance:$gridHome');
          },
          onError: advisoryReports.add,
        ),
        throwsA(
          isA<GridHookError>()
              .having((error) => error.hook, 'hook', 'boot')
              .having(
                (error) => error.cause,
                'cause',
                isA<StoreRefusal>()
                    .having(
                      (refusal) => refusal.message,
                      'message',
                      contains(runtimeDir),
                    )
                    .having(
                      (refusal) => refusal.message,
                      'message',
                      contains(statePid),
                    ),
              ),
        ),
      );

      expect(advisoryReports, isEmpty);
      expect(delegate.events, <String>[
        'didLaunch',
        'maintenance:${gridHome.path}',
        'boot',
      ]);
      expect(delegate.disposed, isTrue);
    },
  );

  test('runGrid is the sole state-store maintenance invocation site', () async {
    final root = _repositoryRoot();
    final declaration = p.canonicalize(
      p.join(
        root.path,
        'packages',
        'grid_sdk',
        'lib',
        'src',
        'stores',
        'state_store_gc.dart',
      ),
    );
    final owners = <String>{};
    final invocation = RegExp(r'\bStateStoreGc\s*\(|\bmaintainStateStore\s*\(');

    await for (final entity in Directory(
      p.join(root.path, 'packages'),
    ).list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = p.canonicalize(entity.path);
      if (!normalized.contains('${p.separator}lib${p.separator}') ||
          normalized == declaration) {
        continue;
      }
      if (invocation.hasMatch(await entity.readAsString())) {
        owners.add(
          p.relative(normalized, from: root.path).replaceAll(p.separator, '/'),
        );
      }
    }

    expect(owners, <String>{'packages/grid_sdk/lib/src/run/run_grid.dart'});
  });
}
