import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show BdEnvelope, BeadsWorkspace;
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
  environment: executable == 'bd'
      ? const <String, String>{'BD_JSON_ENVELOPE': '1'}
      : null,
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
    var store = runtimeDir;
    var mode = 'unknown';
    int? before;
    int? after;
    var path = 'discover';
    var flatten = 'skipped';
    var flattenReason = 'not_applicable';
    DateTime? startedAt;

    try {
      BeadsWorkspace? workspace;
      try {
        workspace = BeadsWorkspace.discover(start: runtimeDir);
      } on FormatException {
        _out(
          _receipt(
            disposition: 'skipped',
            store: store,
            mode: mode,
            before: before,
            after: after,
            path: path,
            reason: 'no_dolt_database',
            flatten: flatten,
            flattenReason: flattenReason,
          ),
        );
        return;
      }
      final database = workspace?.database;
      if (workspace == null ||
          p.canonicalize(workspace.root) != p.canonicalize(runtimeDir) ||
          database == null ||
          database.isEmpty) {
        _out(
          _receipt(
            disposition: 'skipped',
            store: store,
            mode: mode,
            before: before,
            after: after,
            path: path,
            reason: 'no_dolt_database',
            flatten: flatten,
            flattenReason: flattenReason,
          ),
        );
        return;
      }

      final sourceMetadata = await _readJsonObject(
        p.join(workspace.beadsDir, 'metadata.json'),
      );
      mode = _normalizeMode(sourceMetadata['dolt_mode']);
      if (mode != 'proxied-server') {
        _out(
          _receipt(
            disposition: 'skipped',
            store: runtimeDir,
            mode: mode,
            before: before,
            after: after,
            path: 'skip-unsupported-mode',
            reason: 'unsupported_mode',
            flatten: flatten,
            flattenReason: 'unsupported_mode',
          ),
        );
        return;
      }

      final proxyRoot = await _resolveProxyRoot(workspace.beadsDir);
      final databaseDir = p.join(proxyRoot, database);
      store = databaseDir;
      if (!await Directory(databaseDir).exists()) {
        _out(
          _receipt(
            disposition: 'skipped',
            store: store,
            mode: mode,
            before: before,
            after: after,
            path: path,
            reason: 'database_directory_absent',
            flatten: flatten,
            flattenReason: flattenReason,
          ),
        );
        return;
      }

      path = 'measure';
      before = await _readSize(databaseDir);
      if (before <= kStateStoreGcThresholdBytes) {
        after = before;
        _out(
          _receipt(
            disposition: 'skipped',
            store: store,
            mode: mode,
            before: before,
            after: after,
            path: 'skip-below-gc-threshold',
            reason: 'below_gc_threshold',
            flatten: flatten,
            flattenReason: 'below_gc_threshold',
            extra: 'threshold_bytes=$kStateStoreGcThresholdBytes',
          ),
        );
        return;
      }

      final shouldFlatten = before > kStateStoreFlattenThresholdBytes;
      path = shouldFlatten ? 'proxied-stop-flatten-restore' : 'gc-only';
      flattenReason = shouldFlatten ? 'pending' : 'below_threshold';
      startedAt = _now();
      final stopArguments = <String>['-C', runtimeDir, 'dolt', 'stop'];
      final stop = await _runProcess(
        'bd',
        stopArguments,
        workingDirectory: runtimeDir,
      );
      _requireExitZero('bd', stopArguments, stop);

      final failures = <Object>[];
      var proxyStateCleared = false;
      try {
        await _clearProxyState(proxyRoot);
        proxyStateCleared = true;
      } on Object catch (error) {
        failures.add(error);
      }

      if (shouldFlatten && proxyStateCleared) {
        final outcome = await _flatten(
          sourceMetadata: sourceMetadata,
          proxyRoot: proxyRoot,
        );
        failures.addAll(outcome.failures);
        flatten = outcome.complete ? 'complete' : 'skipped';
        flattenReason = outcome.reason;
        if (outcome.unverifiedFacade) {
          path = 'proxied-stop-skip-flatten-restore';
        }
      } else if (shouldFlatten) {
        flattenReason = 'proxy_state_cleanup_failed';
      }

      try {
        final gcArguments = const <String>['gc', '--full'];
        final gc = await _runProcess(
          'dolt',
          gcArguments,
          workingDirectory: databaseDir,
        );
        _requireExitZero('dolt', gcArguments, gc);
      } on Object catch (error) {
        failures.add(error);
      }

      try {
        final infoArguments = <String>['-C', runtimeDir, 'info', '--json'];
        final info = await _runProcess(
          'bd',
          infoArguments,
          workingDirectory: runtimeDir,
        );
        _requireExitZero('bd', infoArguments, info);
        final infoData = _decodeDataMap(info, command: 'bd info --json');
        if (_normalizeMode(infoData['mode']) != 'proxied-server') {
          throw FormatException(
            'bd info --json did not restore proxied-server mode: '
            '${info.stdout}',
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

      try {
        after = await _readSize(databaseDir);
      } on Object catch (error) {
        failures.add(error);
      }

      if (failures.isNotEmpty) {
        throw _MaintenanceFailures(failures);
      }

      final elapsed = _now().difference(startedAt).inMilliseconds;
      _out(
        _receipt(
          disposition: 'complete',
          store: store,
          mode: mode,
          before: before,
          after: after,
          path: path,
          flatten: flatten,
          flattenReason: flattenReason,
          elapsed: elapsed,
          extra: shouldFlatten
              ? null
              : 'flatten_threshold_bytes=$kStateStoreFlattenThresholdBytes',
        ),
      );
    } on Object catch (error) {
      final elapsed = startedAt == null
          ? 0
          : _now().difference(startedAt).inMilliseconds;
      _err(
        _receipt(
          disposition: 'FAILED',
          store: store,
          mode: mode,
          before: before,
          after: after,
          path: path,
          flatten: flatten,
          flattenReason: flattenReason == 'pending'
              ? 'flatten_failed'
              : flattenReason,
          elapsed: elapsed,
          error: error,
        ),
      );
    }
  }

  Future<_FlattenOutcome> _flatten({
    required Map<String, Object?> sourceMetadata,
    required String proxyRoot,
  }) async {
    final failures = <Object>[];
    Directory? facade;
    var complete = false;
    var reason = 'flatten_failed';
    var unverifiedFacade = false;
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

      final infoArguments = <String>['-C', facade.path, 'info', '--json'];
      final info = await _runProcess(
        'bd',
        infoArguments,
        workingDirectory: facade.path,
      );
      _requireExitZero('bd', infoArguments, info);
      final infoData = _decodeDataMap(info, command: 'bd info --json');
      if (!_isEmbeddedFacadeMode(infoData['mode'])) {
        reason = 'embedded_facade_unverified';
        unverifiedFacade = true;
        return _FlattenOutcome(
          failures: failures,
          complete: complete,
          reason: reason,
          unverifiedFacade: unverifiedFacade,
        );
      }

      final flattenArguments = <String>[
        '-C',
        facade.path,
        '--actor',
        'grid-controller',
        'flatten',
        '--force',
        '--json',
      ];
      final flatten = await _runProcess(
        'bd',
        flattenArguments,
        workingDirectory: facade.path,
      );
      _requireExitZero('bd', flattenArguments, flatten);
      final flattenData = _decodeDataMap(
        flatten,
        command: 'bd flatten --force --json',
      );
      if (flattenData['success'] != true) {
        throw FormatException(
          'bd flatten --force --json did not report data.success=true: '
          '${flatten.stdout}',
        );
      }
      complete = true;
      reason = 'none';
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
    return _FlattenOutcome(
      failures: failures,
      complete: complete,
      reason: reason,
      unverifiedFacade: unverifiedFacade,
    );
  }

  Map<String, dynamic> _decodeDataMap(
    ProcessResult result, {
    required String command,
  }) {
    final envelope = BdEnvelope.parse(result.stdout as String);
    try {
      return envelope.dataMap;
    } on Object catch (error) {
      throw FormatException('$command returned invalid envelope data: $error');
    }
  }

  void _requireExitZero(
    String executable,
    List<String> arguments,
    ProcessResult result,
  ) {
    if (result.exitCode == 0) return;
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
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

String _normalizeMode(Object? value) {
  if (value is! String || value.trim().isEmpty) return 'unknown';
  return value.trim().toLowerCase();
}

bool _isEmbeddedFacadeMode(Object? value) {
  final mode = _normalizeMode(value);
  return mode == 'embedded' || mode == 'direct';
}

String _receipt({
  required String disposition,
  required String store,
  required String mode,
  required int? before,
  required int? after,
  required String path,
  required String flatten,
  required String flattenReason,
  String? reason,
  int? elapsed,
  Object? error,
  String? extra,
}) {
  final fields = <String>[
    'state-store gc $disposition:',
    'store=$store',
    'mode=$mode',
    'before_bytes=${before ?? 'unavailable'}',
    'after_bytes=${after ?? 'unavailable'}',
    'path=$path',
    'flatten=$flatten',
    'flatten_reason=$flattenReason',
    if (reason != null) 'reason=$reason',
    if (elapsed != null) 'elapsed_ms=$elapsed',
    if (extra != null) extra,
    if (error != null) 'error=$error',
  ];
  return fields.join(' ');
}

final class _FlattenOutcome {
  const _FlattenOutcome({
    required this.failures,
    required this.complete,
    required this.reason,
    required this.unverifiedFacade,
  });

  final List<Object> failures;
  final bool complete;
  final String reason;
  final bool unverifiedFacade;
}

final class _MaintenanceFailures implements Exception {
  _MaintenanceFailures(this.failures);

  final List<Object> failures;

  @override
  String toString() => failures.join('; ');
}
