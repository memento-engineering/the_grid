import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _Fixture {
  _Fixture._(
    this.temp,
    this.gridHome,
    this.runtimeDir,
    this.beadsDir,
    this.proxyRoot,
    this.databaseDir,
  );

  final Directory temp;
  final String gridHome;
  final String runtimeDir;
  final String beadsDir;
  final String proxyRoot;
  final String databaseDir;

  static _Fixture create({
    String mode = 'proxied-server',
    bool metadata = true,
    bool database = true,
    bool sidecarProxyRoot = false,
  }) {
    final temp = Directory.systemTemp.createTempSync('state-store-gc-');
    final gridHome = p.join(temp.path, 'home');
    final runtimeDir = p.join(gridHome, '.grid');
    final beadsDir = p.join(runtimeDir, '.beads');
    Directory(beadsDir).createSync(recursive: true);
    if (metadata) {
      File(p.join(beadsDir, 'metadata.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'dolt_mode': mode,
          'dolt_database': 'tranquility',
        }),
      );
    }
    final proxyRoot = p.join(
      beadsDir,
      sidecarProxyRoot ? 'owned-proxy' : 'dolt',
    );
    if (sidecarProxyRoot) {
      File(
        p.join(beadsDir, 'proxied_server_client_info.json'),
      ).writeAsStringSync('{"root_path":"owned-proxy"}');
    }
    final databaseDir = p.join(proxyRoot, 'tranquility');
    if (database) Directory(databaseDir).createSync(recursive: true);
    return _Fixture._(
      temp,
      gridHome,
      runtimeDir,
      beadsDir,
      proxyRoot,
      databaseDir,
    );
  }

  void dispose() => temp.deleteSync(recursive: true);
}

final class _ProcessCall {
  const _ProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  String get command => '$executable ${arguments.join(' ')}';
}

final class _FakeMaintenanceRunner {
  _FakeMaintenanceRunner(this._respond);

  final Future<ProcessResult> Function(_ProcessCall call) _respond;
  final calls = <_ProcessCall>[];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final processCall = _ProcessCall(
      executable: executable,
      arguments: List<String>.unmodifiable(arguments),
      workingDirectory: workingDirectory,
    );
    calls.add(processCall);
    return _respond(processCall);
  }
}

ProcessResult _result(int exitCode, {String stdout = '', String stderr = ''}) =>
    ProcessResult(1, exitCode, stdout, stderr);

ProcessResult _envelope(Map<String, Object?> data, {int schemaVersion = 1}) =>
    _result(
      0,
      stdout: jsonEncode(<String, Object?>{
        'schema_version': schemaVersion,
        'data': data,
      }),
    );

void _seedProxy(String proxyRoot, {required int port}) {
  Directory(proxyRoot).createSync(recursive: true);
  File(
    p.join(proxyRoot, 'proxy.pid'),
  ).writeAsStringSync('{"pid":1,"port":$port}');
  File(p.join(proxyRoot, 'beads_dart.secret')).writeAsStringSync('secret');
}

void _expectCompleteFields(
  String receipt, {
  required String mode,
  required Object before,
  required Object after,
  required String path,
}) {
  expect(receipt, contains('mode=$mode'));
  expect(receipt, contains('before_bytes=$before'));
  expect(receipt, contains('after_bytes=$after'));
  expect(receipt, contains('path=$path'));
}

void main() {
  test('unsupported mode skips before measurement and subprocesses', () async {
    final fixture = _Fixture.create(mode: '  EMBEDDED  ');
    addTearDown(fixture.dispose);
    final output = <String>[];
    var measured = false;
    final runner = _FakeMaintenanceRunner((_) async => _result(0));

    await StateStoreGc(
      readSize: (_) async {
        measured = true;
        return 1;
      },
      runProcess: runner.call,
      out: output.add,
    ).run(gridHome: fixture.gridHome);

    expect(measured, isFalse);
    expect(runner.calls, isEmpty);
    _expectCompleteFields(
      output.single,
      mode: 'embedded',
      before: 'unavailable',
      after: 'unavailable',
      path: 'skip-unsupported-mode',
    );
    expect(output.single, contains('reason=unsupported_mode'));
  });

  test('below gc threshold leaves the proxy untouched', () async {
    for (final size in <int>[
      kStateStoreGcThresholdBytes - 1,
      kStateStoreGcThresholdBytes,
    ]) {
      final fixture = _Fixture.create();
      try {
        final proxyPid = File(p.join(fixture.proxyRoot, 'proxy.pid'))
          ..writeAsStringSync('{"pid":12,"port":65101}');
        final output = <String>[];
        final runner = _FakeMaintenanceRunner((_) async => _result(0));

        await StateStoreGc(
          readSize: (_) async => size,
          runProcess: runner.call,
          out: output.add,
        ).run(gridHome: fixture.gridHome);

        expect(runner.calls, isEmpty);
        expect(proxyPid.readAsStringSync(), '{"pid":12,"port":65101}');
        _expectCompleteFields(
          output.single,
          mode: 'proxied-server',
          before: size,
          after: size,
          path: 'skip-below-gc-threshold',
        );
        expect(output.single, contains('reason=below_gc_threshold'));
      } finally {
        fixture.dispose();
      }
    }
  });

  test('gc-only targets the runtime and measures after restoration', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final output = <String>[];
    final events = <String>[];
    var sizeReads = 0;
    final runner = _FakeMaintenanceRunner((call) async {
      events.add(call.command);
      if (call.arguments.contains('info')) {
        _seedProxy(fixture.proxyRoot, port: 65102);
        return _envelope(<String, Object?>{'mode': 'proxied-server'});
      }
      return _result(0);
    });

    await StateStoreGc(
      readSize: (path) async {
        expect(path, fixture.databaseDir);
        if (sizeReads++ == 0) return kStateStoreFlattenThresholdBytes;
        expect(events.last, contains('info --json'));
        return 42;
      },
      runProcess: runner.call,
      out: output.add,
    ).run(gridHome: fixture.gridHome);

    expect(runner.calls.map((call) => call.command), <String>[
      'bd -C ${fixture.runtimeDir} dolt stop',
      'dolt gc --full',
      'bd -C ${fixture.runtimeDir} info --json',
    ]);
    expect(runner.calls[0].workingDirectory, fixture.runtimeDir);
    expect(runner.calls[1].workingDirectory, fixture.databaseDir);
    expect(runner.calls[2].workingDirectory, fixture.runtimeDir);
    _expectCompleteFields(
      output.single,
      mode: 'proxied-server',
      before: kStateStoreFlattenThresholdBytes,
      after: 42,
      path: 'gc-only',
    );
    expect(output.single, contains('flatten=skipped'));
    expect(output.single, contains('flatten_reason=below_threshold'));
  });

  test('oversized store flattens through a verified embedded facade', () async {
    final fixture = _Fixture.create(sidecarProxyRoot: true);
    addTearDown(fixture.dispose);
    const sourceMetadata = <String, Object?>{
      'dolt_mode': 'proxied-server',
      'dolt_database': 'tranquility',
      'prefix': 'lunar',
      'extra': <String, Object?>{'kept': true},
    };
    final metadataFile = File(p.join(fixture.beadsDir, 'metadata.json'))
      ..writeAsStringSync(jsonEncode(sourceMetadata));
    for (final name in <String>[
      'proxy.pid',
      'proxy.lock',
      'proxy-child.pid',
      'proxy-child.lock',
    ]) {
      File(p.join(fixture.proxyRoot, name)).writeAsStringSync('stale');
    }
    final retained = File(p.join(fixture.proxyRoot, 'server.log'))
      ..writeAsStringSync('keep');
    final output = <String>[];
    String? facadePath;
    var reads = 0;
    final runner = _FakeMaintenanceRunner((call) async {
      if (call.arguments.contains('info') &&
          call.workingDirectory != fixture.runtimeDir) {
        facadePath = call.workingDirectory;
        final facadeBeads = p.join(call.workingDirectory, '.beads');
        expect(
          jsonDecode(
            File(p.join(facadeBeads, 'metadata.json')).readAsStringSync(),
          ),
          <String, Object?>{...sourceMetadata, 'dolt_mode': 'embedded'},
        );
        final embedded = Link(p.join(facadeBeads, 'embeddeddolt'));
        expect(embedded.existsSync(), isTrue);
        expect(
          p.canonicalize(embedded.targetSync()),
          p.canonicalize(fixture.proxyRoot),
        );
        expect(
          <String>[
            'proxy.pid',
            'proxy.lock',
            'proxy-child.pid',
            'proxy-child.lock',
          ].every(
            (name) => !File(p.join(fixture.proxyRoot, name)).existsSync(),
          ),
          isTrue,
        );
        return _envelope(<String, Object?>{'mode': 'direct'});
      }
      if (call.arguments.contains('flatten')) {
        expect(call.workingDirectory, facadePath);
        return _envelope(<String, Object?>{'success': true});
      }
      if (call.arguments.contains('info')) {
        _seedProxy(fixture.proxyRoot, port: 65103);
        return _envelope(<String, Object?>{'mode': 'proxied-server'});
      }
      return _result(0);
    });

    await StateStoreGc(
      readSize: (_) async =>
          reads++ == 0 ? kStateStoreFlattenThresholdBytes + 1 : 73,
      runProcess: runner.call,
      out: output.add,
    ).run(gridHome: fixture.gridHome);

    expect(runner.calls.map((call) => call.command), <String>[
      'bd -C ${fixture.runtimeDir} dolt stop',
      'bd -C $facadePath info --json',
      'bd -C $facadePath --actor grid-controller flatten --force --json',
      'dolt gc --full',
      'bd -C ${fixture.runtimeDir} info --json',
    ]);
    expect(facadePath, isNotNull);
    expect(Directory(facadePath!).existsSync(), isFalse);
    expect(jsonDecode(metadataFile.readAsStringSync()), sourceMetadata);
    expect(retained.readAsStringSync(), 'keep');
    _expectCompleteFields(
      output.single,
      mode: 'proxied-server',
      before: kStateStoreFlattenThresholdBytes + 1,
      after: 73,
      path: 'proxied-stop-flatten-restore',
    );
    expect(output.single, contains('flatten=complete'));
  });

  test(
    'unverified facade skips flatten but still collects and restores',
    () async {
      final fixture = _Fixture.create();
      addTearDown(fixture.dispose);
      final output = <String>[];
      var reads = 0;
      final runner = _FakeMaintenanceRunner((call) async {
        if (call.arguments.contains('info') &&
            call.workingDirectory != fixture.runtimeDir) {
          return _envelope(<String, Object?>{'mode': 'proxied-server'});
        }
        if (call.arguments.contains('flatten')) {
          fail('flatten must not run against an unverified facade');
        }
        if (call.arguments.contains('info')) {
          _seedProxy(fixture.proxyRoot, port: 65104);
          return _envelope(<String, Object?>{'mode': 'proxied-server'});
        }
        return _result(0);
      });

      await StateStoreGc(
        readSize: (_) async =>
            reads++ == 0 ? kStateStoreFlattenThresholdBytes + 1 : 64,
        runProcess: runner.call,
        out: output.add,
      ).run(gridHome: fixture.gridHome);

      expect(runner.calls.map((call) => call.arguments.last), <String>[
        'stop',
        '--json',
        '--full',
        '--json',
      ]);
      _expectCompleteFields(
        output.single,
        mode: 'proxied-server',
        before: kStateStoreFlattenThresholdBytes + 1,
        after: 64,
        path: 'proxied-stop-skip-flatten-restore',
      );
      expect(output.single, contains('flatten=skipped'));
      expect(
        output.single,
        contains('flatten_reason=embedded_facade_unverified'),
      );
    },
  );

  test('flatten gc and restore failures accumulate before reporting', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final errors = <String>[];
    var reads = 0;
    final runner = _FakeMaintenanceRunner((call) async {
      if (call.arguments.contains('info') &&
          call.workingDirectory != fixture.runtimeDir) {
        return _envelope(<String, Object?>{'mode': 'embedded'});
      }
      if (call.arguments.contains('flatten')) {
        return _envelope(<String, Object?>{
          'success': false,
          'error': 'flatten refused',
        });
      }
      if (call.executable == 'dolt') {
        return _result(9, stderr: 'gc failed');
      }
      if (call.arguments.contains('info')) {
        return _result(11, stderr: 'restore failed');
      }
      return _result(0);
    });

    await StateStoreGc(
      readSize: (_) async =>
          reads++ == 0 ? kStateStoreFlattenThresholdBytes + 1 : 91,
      runProcess: runner.call,
      err: errors.add,
    ).run(gridHome: fixture.gridHome);

    expect(reads, 2, reason: 'post-stop measurement is unconditional');
    expect(errors, hasLength(1));
    final receipt = errors.single;
    final flattenIndex = receipt.indexOf('data.success=true');
    final gcIndex = receipt.indexOf('gc failed');
    final restoreIndex = receipt.indexOf('restore failed');
    expect(flattenIndex, greaterThanOrEqualTo(0));
    expect(gcIndex, greaterThan(flattenIndex));
    expect(restoreIndex, greaterThan(gcIndex));
    _expectCompleteFields(
      receipt,
      mode: 'proxied-server',
      before: kStateStoreFlattenThresholdBytes + 1,
      after: 91,
      path: 'proxied-stop-flatten-restore',
    );
    expect(receipt, contains('flatten=skipped'));
    expect(receipt, contains('flatten_reason=flatten_failed'));
  });

  test('schema drift in preflight still restores and measures', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final errors = <String>[];
    var reads = 0;
    final runner = _FakeMaintenanceRunner((call) async {
      if (call.arguments.contains('info') &&
          call.workingDirectory != fixture.runtimeDir) {
        return _envelope(<String, Object?>{
          'mode': 'embedded',
        }, schemaVersion: 2);
      }
      if (call.arguments.contains('info')) {
        _seedProxy(fixture.proxyRoot, port: 65105);
        return _envelope(<String, Object?>{'mode': 'proxied-server'});
      }
      return _result(0);
    });

    await StateStoreGc(
      readSize: (_) async =>
          reads++ == 0 ? kStateStoreFlattenThresholdBytes + 1 : 88,
      runProcess: runner.call,
      err: errors.add,
    ).run(gridHome: fixture.gridHome);

    expect(
      runner.calls.where((call) => call.arguments.contains('flatten')),
      isEmpty,
    );
    expect(File(p.join(fixture.proxyRoot, 'proxy.pid')).existsSync(), isTrue);
    expect(reads, 2);
    expect(errors.single, contains('schema_version 2'));
    expect(errors.single, contains('after_bytes=88'));
  });

  test('zero-exit restore without owned proxy pid is a failure', () async {
    final fixture = _Fixture.create(sidecarProxyRoot: true);
    addTearDown(fixture.dispose);
    final errors = <String>[];
    var reads = 0;
    final runner = _FakeMaintenanceRunner((call) async {
      if (call.arguments.contains('info')) {
        return _envelope(<String, Object?>{'mode': 'proxied-server'});
      }
      return _result(0);
    });

    await StateStoreGc(
      readSize: (_) async =>
          reads++ == 0 ? kStateStoreGcThresholdBytes + 1 : 77,
      runProcess: runner.call,
      err: errors.add,
    ).run(gridHome: fixture.gridHome);

    expect(reads, 2);
    expect(errors.single, contains(p.join(fixture.proxyRoot, 'proxy.pid')));
    _expectCompleteFields(
      errors.single,
      mode: 'proxied-server',
      before: kStateStoreGcThresholdBytes + 1,
      after: 77,
      path: 'gc-only',
    );
  });

  test(
    'discovery skips and measurement failures carry complete receipts',
    () async {
      final missing = _Fixture.create(metadata: false);
      final malformed = _Fixture.create();
      File(
        p.join(malformed.beadsDir, 'metadata.json'),
      ).writeAsStringSync('{bad');
      addTearDown(missing.dispose);
      addTearDown(malformed.dispose);

      for (final fixture in <_Fixture>[missing, malformed]) {
        final output = <String>[];
        await StateStoreGc(out: output.add).run(gridHome: fixture.gridHome);
        _expectCompleteFields(
          output.single,
          mode: 'unknown',
          before: 'unavailable',
          after: 'unavailable',
          path: 'discover',
        );
      }

      final measured = _Fixture.create();
      addTearDown(measured.dispose);
      final errors = <String>[];
      await StateStoreGc(
        readSize: (_) async => throw const FileSystemException('size failed'),
        err: errors.add,
      ).run(gridHome: measured.gridHome);
      _expectCompleteFields(
        errors.single,
        mode: 'proxied-server',
        before: 'unavailable',
        after: 'unavailable',
        path: 'measure',
      );
      expect(errors.single, contains('size failed'));
    },
  );

  test('stop failure does not clear or attempt restoration', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final proxyPid = File(p.join(fixture.proxyRoot, 'proxy.pid'))
      ..writeAsStringSync('live');
    final errors = <String>[];
    final runner = _FakeMaintenanceRunner(
      (_) async => _result(7, stderr: 'cannot stop'),
    );

    await StateStoreGc(
      readSize: (_) async => kStateStoreGcThresholdBytes + 1,
      runProcess: runner.call,
      err: errors.add,
    ).run(gridHome: fixture.gridHome);

    expect(runner.calls, hasLength(1));
    expect(proxyPid.readAsStringSync(), 'live');
    _expectCompleteFields(
      errors.single,
      mode: 'proxied-server',
      before: kStateStoreGcThresholdBytes + 1,
      after: 'unavailable',
      path: 'gc-only',
    );
  });

  test('restoration resolves the state store own proxy root', () async {
    final fixture = _Fixture.create(sidecarProxyRoot: true);
    addTearDown(fixture.dispose);
    final parentRoot = p.join(fixture.beadsDir, 'dolt');
    _seedProxy(parentRoot, port: 65202);
    var reads = 0;
    final runner = _FakeMaintenanceRunner((call) async {
      if (call.arguments.contains('info')) {
        _seedProxy(fixture.proxyRoot, port: 65106);
        return _envelope(<String, Object?>{'mode': 'proxied-server'});
      }
      return _result(0);
    });

    await StateStoreGc(
      readSize: (_) async =>
          reads++ == 0 ? kStateStoreGcThresholdBytes + 1 : 100,
      runProcess: runner.call,
      out: (_) {},
    ).run(gridHome: fixture.gridHome);

    final workspace = BeadsWorkspace.discover(start: fixture.runtimeDir);
    expect(workspace, isNotNull);
    expect(workspace!.endpoint, isNotNull);
    expect(workspace.endpoint!.port, 65106);
    expect(workspace.endpoint!.port, isNot(65202));
  });
}
