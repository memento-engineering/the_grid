import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _Fixture {
  _Fixture._(this.temp, this.gridHome, this.runtimeDir, this.databaseDir);

  final Directory temp;
  final String gridHome;
  final String runtimeDir;
  final String databaseDir;

  static _Fixture create({bool metadata = true, bool database = true}) {
    final temp = Directory.systemTemp.createTempSync('state-store-gc-');
    final gridHome = p.join(temp.path, 'home');
    final runtimeDir = p.join(gridHome, '.grid');
    final beadsDir = p.join(runtimeDir, '.beads');
    Directory(beadsDir).createSync(recursive: true);
    if (metadata) {
      File(p.join(beadsDir, 'metadata.json')).writeAsStringSync(
        '{"dolt_mode":"proxied-server","dolt_database":"tranquility"}',
      );
    }
    final databaseDir = p.join(beadsDir, 'dolt', 'tranquility');
    if (database) Directory(databaseDir).createSync(recursive: true);
    return _Fixture._(temp, gridHome, runtimeDir, databaseDir);
  }

  void dispose() => temp.deleteSync(recursive: true);
}

ProcessResult _result(int exitCode, {String stdout = '', String stderr = ''}) =>
    ProcessResult(1, exitCode, stdout, stderr);

void _seedProxy(String proxyRoot, {required int port}) {
  Directory(proxyRoot).createSync(recursive: true);
  File(
    p.join(proxyRoot, 'proxy.pid'),
  ).writeAsStringSync('{"pid":1,"port":$port}');
  File(p.join(proxyRoot, 'beads_dart.secret')).writeAsStringSync('secret');
}

void _seedParentWorkspace(String root, {required int port}) {
  final beadsDir = Directory(p.join(root, '.beads'))
    ..createSync(recursive: true);
  File(
    p.join(beadsDir.path, 'metadata.json'),
  ).writeAsStringSync('{"dolt_mode":"proxied-server","dolt_database":"work"}');
  _seedProxy(p.join(beadsDir.path, 'dolt'), port: port);
}

void main() {
  test('at or under threshold skips loudly', () async {
    for (final size in <int>[
      kStateStoreGcThresholdBytes - 1,
      kStateStoreGcThresholdBytes,
    ]) {
      final fixture = _Fixture.create();
      try {
        final output = <String>[];
        var processCalls = 0;
        await StateStoreGc(
          readSize: (_) async => size,
          runProcess: (_, __, {required workingDirectory}) async {
            processCalls++;
            return _result(0);
          },
          out: output.add,
        ).run(gridHome: fixture.gridHome);
        expect(processCalls, 0);
        expect(output.single, contains('store=${fixture.databaseDir}'));
        expect(output.single, contains('before_bytes=$size'));
        expect(
          output.single,
          contains('threshold_bytes=$kStateStoreGcThresholdBytes'),
        );
      } finally {
        fixture.dispose();
      }
    }
  });

  test(
    'gc cwd is exact database directory and success receipt is complete',
    () async {
      final fixture = _Fixture.create();
      addTearDown(fixture.dispose);
      final calls = <String>[];
      final output = <String>[];
      var sizeRead = 0;
      final times = <DateTime>[
        DateTime.utc(2026, 8, 11),
        DateTime.utc(2026, 8, 11, 0, 0, 2, 345),
      ].iterator;
      await StateStoreGc(
        readSize: (_) async =>
            sizeRead++ == 0 ? kStateStoreGcThresholdBytes + 1 : 42,
        now: () {
          times.moveNext();
          return times.current;
        },
        runProcess: (executable, arguments, {required workingDirectory}) async {
          calls.add('$executable ${arguments.join(' ')}@$workingDirectory');
          if (executable == 'bd' && arguments.first == 'info') {
            _seedProxy(p.dirname(fixture.databaseDir), port: 65101);
          }
          return _result(0);
        },
        out: output.add,
      ).run(gridHome: fixture.gridHome);

      expect(calls, <String>[
        'bd dolt stop@${fixture.runtimeDir}',
        'dolt gc --full@${fixture.databaseDir}',
        'bd info --json@${fixture.runtimeDir}',
      ]);
      expect(output.single, contains('store=${fixture.databaseDir}'));
      expect(
        output.single,
        contains('before_bytes=${kStateStoreGcThresholdBytes + 1}'),
      );
      expect(output.single, contains('after_bytes=42'));
      expect(output.single, contains('elapsed_ms=2345'));
    },
  );

  test('missing metadata and database skip without measurement', () async {
    for (final fixture in <_Fixture>[
      _Fixture.create(metadata: false),
      _Fixture.create(database: false),
    ]) {
      try {
        final output = <String>[];
        var measured = false;
        await StateStoreGc(
          readSize: (_) async {
            measured = true;
            return 0;
          },
          out: output.add,
        ).run(gridHome: fixture.gridHome);
        expect(measured, isFalse);
        expect(output.single, contains('state-store gc skipped'));
      } finally {
        fixture.dispose();
      }
    }
  });

  test('malformed metadata skips without subprocess', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    File(
      p.join(fixture.runtimeDir, '.beads', 'metadata.json'),
    ).writeAsStringSync('{malformed');
    final output = <String>[];
    var measured = false;
    var processCalls = 0;

    await StateStoreGc(
      readSize: (_) async {
        measured = true;
        return 0;
      },
      runProcess: (_, __, {required workingDirectory}) async {
        processCalls++;
        return _result(0);
      },
      out: output.add,
    ).run(gridHome: fixture.gridHome);

    expect(measured, isFalse);
    expect(processCalls, 0);
    expect(output.single, contains('state-store gc skipped'));
    expect(output.single, contains('store=${fixture.runtimeDir}'));
    expect(output.single, contains('reason=no dolt_database'));
  });

  test('initial size failure is loud and returns normally', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final errors = <String>[];
    var processCalls = 0;

    await StateStoreGc(
      readSize: (_) async => throw const FileSystemException('size failed'),
      runProcess: (_, __, {required workingDirectory}) async {
        processCalls++;
        return _result(0);
      },
      err: errors.add,
    ).run(gridHome: fixture.gridHome);

    expect(processCalls, 0);
    expect(errors.single, contains('state-store gc FAILED'));
    expect(errors.single, contains('store=${fixture.databaseDir}'));
    expect(errors.single, contains('elapsed_ms=0'));
    expect(errors.single, contains('size failed'));
  });

  test('stop failure is loud, skips cleanup and gc, and returns', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final proxyPid = File(p.join(p.dirname(fixture.databaseDir), 'proxy.pid'))
      ..writeAsStringSync('live');
    final errors = <String>[];
    var calls = 0;
    await StateStoreGc(
      readSize: (_) async => kStateStoreGcThresholdBytes + 1,
      runProcess: (_, __, {required workingDirectory}) async {
        calls++;
        return _result(7, stderr: 'cannot stop');
      },
      err: errors.add,
    ).run(gridHome: fixture.gridHome);
    expect(calls, 1);
    expect(proxyPid.existsSync(), isTrue);
    expect(errors.single, contains('state-store gc FAILED'));
    expect(errors.single, contains('before_bytes='));
  });

  test('gc failure is loud and returns normally', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final errors = <String>[];
    var calls = 0;
    await StateStoreGc(
      readSize: (_) async => kStateStoreGcThresholdBytes + 1,
      runProcess: (_, __, {required workingDirectory}) async {
        calls++;
        return calls == 1 ? _result(0) : _result(9, stderr: 'gc failed');
      },
      err: errors.add,
    ).run(gridHome: fixture.gridHome);
    expect(calls, 2);
    expect(errors.single, contains('state-store gc FAILED'));
    expect(errors.single, contains('gc failed'));
  });

  test('proxy restart failure is loud and returns normally', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final errors = <String>[];
    var calls = 0;
    await StateStoreGc(
      readSize: (_) async => kStateStoreGcThresholdBytes + 1,
      runProcess: (_, __, {required workingDirectory}) async {
        calls++;
        return calls == 3
            ? _result(11, stderr: 'proxy restart failed')
            : _result(0);
      },
      err: errors.add,
    ).run(gridHome: fixture.gridHome);
    expect(calls, 3);
    expect(errors.single, contains('state-store gc FAILED'));
    expect(errors.single, contains('proxy restart failed'));
  });

  test('zero-exit proxy restart without proxy.pid is loud', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final errors = <String>[];
    var calls = 0;
    var reads = 0;
    await StateStoreGc(
      readSize: (_) async {
        reads++;
        return kStateStoreGcThresholdBytes + 1;
      },
      runProcess: (_, __, {required workingDirectory}) async {
        calls++;
        return _result(0);
      },
      err: errors.add,
    ).run(gridHome: fixture.gridHome);
    final proxyPid = p.join(p.dirname(fixture.databaseDir), 'proxy.pid');
    expect(calls, 3);
    expect(reads, 1, reason: 'post-gc size waits for a verified proxy');
    expect(errors.single, contains('state-store gc FAILED'));
    expect(errors.single, contains(proxyPid));
  });

  test('stop cleanup gc then restarts and resolves the own proxy', () async {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final proxyRoot = p.dirname(fixture.databaseDir);
    _seedParentWorkspace(fixture.gridHome, port: 65202);
    final stale = <File>[
      File(p.join(proxyRoot, 'proxy.pid')),
      File(p.join(proxyRoot, 'proxy.lock')),
      File(p.join(proxyRoot, 'proxy-child.123.pid')),
      File(p.join(proxyRoot, 'proxy-child.123.lock')),
    ];
    for (final file in stale) {
      file.writeAsStringSync('stale');
    }
    final retained = File(p.join(proxyRoot, 'server.log'))
      ..writeAsStringSync('keep');
    final workStore = Directory(p.join(proxyRoot, 'work-store'))
      ..createSync(recursive: true);
    File(p.join(workStore.path, 'data')).writeAsStringSync('untouched');
    final events = <String>[];
    var reads = 0;

    await StateStoreGc(
      readSize: (path) async {
        expect(path, fixture.databaseDir);
        if (reads++ == 0) return kStateStoreGcThresholdBytes + 1;
        expect(events, <String>['stop', 'gc', 'info']);
        return 100;
      },
      runProcess: (executable, arguments, {required workingDirectory}) async {
        if (executable == 'bd' && arguments.first == 'dolt') {
          expect(workingDirectory, fixture.runtimeDir);
          events.add('stop');
        } else if (executable == 'dolt') {
          expect(events, <String>['stop']);
          expect(stale.every((file) => !file.existsSync()), isTrue);
          expect(workingDirectory, fixture.databaseDir);
          events.add('gc');
        } else {
          expect(executable, 'bd');
          expect(arguments, <String>['info', '--json']);
          expect(workingDirectory, fixture.runtimeDir);
          expect(events, <String>['stop', 'gc']);
          _seedProxy(proxyRoot, port: 65101);
          events.add('info');
        }
        return _result(0);
      },
    ).run(gridHome: fixture.gridHome);

    expect(events, <String>['stop', 'gc', 'info']);
    expect(retained.existsSync(), isTrue);
    expect(
      File(p.join(workStore.path, 'data')).readAsStringSync(),
      'untouched',
    );
    final workspace = BeadsWorkspace.discover(start: fixture.runtimeDir);
    expect(workspace, isNotNull);
    expect(p.canonicalize(workspace!.root), p.canonicalize(fixture.runtimeDir));
    expect(workspace.endpoint, isNotNull);
    expect(workspace.endpoint!.port, 65101);
    expect(workspace.endpoint!.port, isNot(65202));
  });
}
