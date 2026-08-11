import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace;
import 'package:path/path.dart' as p;

/// State-store databases larger than this are collected before a live boot.
const int kStateStoreGcThresholdBytes = 1024 * 1024 * 1024;

typedef MaintenanceProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });
typedef DirectorySizeReader = Future<int> Function(String path);
typedef MaintenanceClock = DateTime Function();
typedef MaintenanceSink = void Function(String message);

Future<ProcessResult> runMaintenanceProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  runInShell: false,
);

Future<int> readDirectorySize(String path) async {
  var bytes = 0;
  await for (final entity in Directory(path).list(recursive: true)) {
    if (entity is File) bytes += await entity.length();
  }
  return bytes;
}

/// Performs threshold-gated offline collection of the station state store.
final class StateStoreGc {
  StateStoreGc({
    MaintenanceProcessRunner? runProcess,
    DirectorySizeReader? readSize,
    MaintenanceClock? now,
    MaintenanceSink? out,
    MaintenanceSink? err,
  }) : _runProcess = runProcess ?? runMaintenanceProcess,
       _readSize = readSize ?? readDirectorySize,
       _now = now ?? DateTime.now,
       _out = out ?? stdout.writeln,
       _err = err ?? stderr.writeln;

  final MaintenanceProcessRunner _runProcess;
  final DirectorySizeReader _readSize;
  final MaintenanceClock _now;
  final MaintenanceSink _out;
  final MaintenanceSink _err;

  Future<void> run({required String gridHome}) async {
    final runtimeDir = p.join(gridHome, '.grid');
    final workspace = BeadsWorkspace.discover(start: runtimeDir);
    final database = workspace?.database;
    if (workspace == null ||
        p.canonicalize(workspace.root) != p.canonicalize(runtimeDir) ||
        database == null ||
        database.isEmpty) {
      _out('state-store gc skipped: store=$runtimeDir reason=no dolt_database');
      return;
    }

    final proxyRoot = p.join(workspace.beadsDir, 'dolt');
    final databaseDir = p.join(proxyRoot, database);
    if (!await Directory(databaseDir).exists()) {
      _out(
        'state-store gc skipped: store=$databaseDir '
        'reason=database directory absent',
      );
      return;
    }

    final before = await _readSize(databaseDir);
    if (before <= kStateStoreGcThresholdBytes) {
      _out(
        'state-store gc skipped: store=$databaseDir before_bytes=$before '
        'threshold_bytes=$kStateStoreGcThresholdBytes',
      );
      return;
    }

    final startedAt = _now();
    try {
      final stop = await _runProcess('bd', const <String>[
        'dolt',
        'stop',
      ], workingDirectory: runtimeDir);
      if (stop.exitCode != 0) {
        throw ProcessException(
          'bd',
          const <String>['dolt', 'stop'],
          '${stop.stdout}${stop.stderr}',
          stop.exitCode,
        );
      }

      await _clearProxyState(proxyRoot);
      final gc = await _runProcess('dolt', const <String>[
        'gc',
        '--full',
      ], workingDirectory: databaseDir);
      if (gc.exitCode != 0) {
        throw ProcessException(
          'dolt',
          const <String>['gc', '--full'],
          '${gc.stdout}${gc.stderr}',
          gc.exitCode,
        );
      }

      final after = await _readSize(databaseDir);
      final elapsed = _now().difference(startedAt).inMilliseconds;
      _out(
        'state-store gc complete: store=$databaseDir before_bytes=$before '
        'after_bytes=$after elapsed_ms=$elapsed',
      );
    } on Object catch (error) {
      final elapsed = _now().difference(startedAt).inMilliseconds;
      _err(
        'state-store gc FAILED: store=$databaseDir before_bytes=$before '
        'elapsed_ms=$elapsed error=$error',
      );
    }
  }

  Future<void> _clearProxyState(String proxyRoot) async {
    await for (final entity in Directory(proxyRoot).list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          (name == 'proxy.pid' ||
              name == 'proxy.lock' ||
              name.startsWith('proxy-child.'))) {
        await entity.delete();
      }
    }
  }
}
