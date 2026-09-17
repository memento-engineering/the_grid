import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace;
import 'package:path/path.dart' as p;

/// State-store databases larger than this are collected before a live boot.
const int kStateStoreGcThresholdBytes = 1024 * 1024 * 1024;

/// State-store databases larger than this are flattened before collection.
const int kStateStoreFlattenThresholdBytes = 8 * 1024 * 1024 * 1024;

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

/// Performs threshold-gated offline maintenance of the station state store.
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
    var failureStore = runtimeDir;
    int? failureBefore;
    DateTime? startedAt;
    try {
      BeadsWorkspace? workspace;
      try {
        workspace = BeadsWorkspace.discover(start: runtimeDir);
      } on FormatException {
        _out(
          'state-store gc skipped: store=$runtimeDir reason=no dolt_database',
        );
        return;
      }
      final database = workspace?.database;
      if (workspace == null ||
          p.canonicalize(workspace.root) != p.canonicalize(runtimeDir) ||
          database == null ||
          database.isEmpty) {
        _out(
          'state-store gc skipped: store=$runtimeDir reason=no dolt_database',
        );
        return;
      }

      final sourceMetadata = await _readJsonObject(
        p.join(workspace.beadsDir, 'metadata.json'),
      );
      final proxyRoot = await _resolveProxyRoot(workspace.beadsDir);
      final databaseDir = p.join(proxyRoot, database);
      failureStore = databaseDir;
      if (!await Directory(databaseDir).exists()) {
        _out(
          'state-store gc skipped: store=$databaseDir '
          'reason=database directory absent',
        );
        return;
      }

      final before = await _readSize(databaseDir);
      failureBefore = before;
      if (before <= kStateStoreGcThresholdBytes) {
        _out(
          'state-store gc skipped: store=$databaseDir before_bytes=$before '
          'threshold_bytes=$kStateStoreGcThresholdBytes',
        );
        return;
      }

      startedAt = _now();
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

      final failures = <Object>[];
      var proxyStateCleared = false;
      try {
        await _clearProxyState(proxyRoot);
        proxyStateCleared = true;
      } on Object catch (error) {
        failures.add(error);
      }

      final shouldFlatten = before > kStateStoreFlattenThresholdBytes;
      if (shouldFlatten && proxyStateCleared) {
        failures.addAll(
          await _flatten(sourceMetadata: sourceMetadata, proxyRoot: proxyRoot),
        );
      }

      try {
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
      } on Object catch (error) {
        failures.add(error);
      }

      // The first store-scoped bd client call restarts the persistent proxy
      // whose local artifacts were cleared above. Boot may resolve the state
      // endpoint immediately after this method returns, so existence is part
      // of maintenance success rather than a later client concern.
      try {
        final info = await _runProcess('bd', const <String>[
          'info',
          '--json',
        ], workingDirectory: runtimeDir);
        if (info.exitCode != 0) {
          throw ProcessException(
            'bd',
            const <String>['info', '--json'],
            '${info.stdout}${info.stderr}',
            info.exitCode,
          );
        }
        final proxyPid = File(p.join(proxyRoot, 'proxy.pid'));
        if (!await proxyPid.exists()) {
          throw FileSystemException(
            'bd info --json did not restore the state-store proxy',
            proxyPid.path,
          );
        }
      } on Object catch (error) {
        failures.add(error);
      }

      if (failures.isNotEmpty) {
        throw _MaintenanceFailures(failures);
      }

      final after = await _readSize(databaseDir);
      final elapsed = _now().difference(startedAt).inMilliseconds;
      final flattenReceipt = shouldFlatten
          ? 'flatten=complete'
          : 'flatten=skipped flatten_reason=below_threshold '
                'flatten_threshold_bytes=$kStateStoreFlattenThresholdBytes';
      _out(
        'state-store gc complete: store=$databaseDir before_bytes=$before '
        'after_bytes=$after elapsed_ms=$elapsed $flattenReceipt',
      );
    } on Object catch (error) {
      final elapsed = startedAt == null
          ? 0
          : _now().difference(startedAt).inMilliseconds;
      final beforeText = failureBefore == null
          ? ''
          : ' before_bytes=$failureBefore';
      _err(
        'state-store gc FAILED: store=$failureStore$beforeText '
        'elapsed_ms=$elapsed error=$error',
      );
    }
  }

  Future<List<Object>> _flatten({
    required Map<String, Object?> sourceMetadata,
    required String proxyRoot,
  }) async {
    final failures = <Object>[];
    Directory? facade;
    try {
      facade = await Directory.systemTemp.createTemp('state-store-flatten-');
      final beadsDir = Directory(p.join(facade.path, '.beads'));
      await beadsDir.create();
      final facadeMetadata = Map<String, Object?>.of(sourceMetadata)
        ..['dolt_mode'] = 'embedded';
      await File(
        p.join(beadsDir.path, 'metadata.json'),
      ).writeAsString(jsonEncode(facadeMetadata));
      await Link(p.join(beadsDir.path, 'embeddeddolt')).create(proxyRoot);

      final flatten = await _runProcess('bd', const <String>[
        'flatten',
        '--force',
        '--json',
      ], workingDirectory: facade.path);
      if (flatten.exitCode != 0) {
        throw ProcessException(
          'bd',
          const <String>['flatten', '--force', '--json'],
          '${flatten.stdout}${flatten.stderr}',
          flatten.exitCode,
        );
      }
      final decoded = jsonDecode(flatten.stdout as String);
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw FormatException(
          'bd flatten --force --json did not report success: '
          '${flatten.stdout}',
        );
      }
    } on Object catch (error) {
      failures.add(error);
    } finally {
      if (facade != null) {
        try {
          await facade.delete(recursive: true);
        } on Object catch (error) {
          failures.add(error);
        }
      }
    }
    return failures;
  }

  Future<Map<String, Object?>> _readJsonObject(String path) async {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map<String, Object?>) {
      throw FormatException('$path must contain a JSON object');
    }
    return decoded;
  }

  Future<String> _resolveProxyRoot(String beadsDir) async {
    final fallback = p.join(beadsDir, 'dolt');
    final sidecar = File(p.join(beadsDir, 'proxied_server_client_info.json'));
    if (!await sidecar.exists()) return fallback;

    final decoded = await _readJsonObject(sidecar.path);
    final rootPath = decoded['root_path'];
    if (rootPath == null || rootPath is String && rootPath.trim().isEmpty) {
      return fallback;
    }
    if (rootPath is! String) {
      throw FormatException('${sidecar.path} root_path must be a string');
    }
    final configuredRoot = rootPath.trim();
    return p.normalize(
      p.isAbsolute(configuredRoot)
          ? configuredRoot
          : p.join(beadsDir, configuredRoot),
    );
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

final class _MaintenanceFailures implements Exception {
  _MaintenanceFailures(this.failures);

  final List<Object> failures;

  @override
  String toString() => failures.join('; ');
}
