@Tags(<String>['integration'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _requiredCopyRoot = '/private/tmp/tg-zcjr-lunar-state-copy';
const String _requiredAck = 'tg-zcjr-copy';

final String? _copyRoot = Platform.environment['GRID_STATE_STORE_FLATTEN_COPY'];
final String? _copyAck =
    Platform.environment['GRID_STATE_STORE_FLATTEN_COPY_ACK'];
final String? _receiptPath =
    Platform.environment['GRID_STATE_STORE_FLATTEN_RECEIPT'];
final String? _skipReason =
    _copyRoot == null || _copyAck != _requiredAck || _receiptPath == null
    ? 'set GRID_STATE_STORE_FLATTEN_COPY, '
          'GRID_STATE_STORE_FLATTEN_COPY_ACK=$_requiredAck, and '
          'GRID_STATE_STORE_FLATTEN_RECEIPT to run the copy-only proof'
    : null;

void main() {
  test(
    'real copied state store shrinks and restores its proxy',
    skip: _skipReason,
    () async {
      final copyRoot = _copyRoot!;
      final receiptPath = _receiptPath!;
      expect(copyRoot, _requiredCopyRoot);

      final runtimeDir = p.join(copyRoot, '.grid');
      final beadsDir = p.join(runtimeDir, '.beads');
      final proxyRoot = p.join(beadsDir, 'dolt');
      for (final path in <String>[copyRoot, runtimeDir, beadsDir, proxyRoot]) {
        _requireRealDirectory(path);
      }

      final metadata = _readJsonObject(p.join(beadsDir, 'metadata.json'));
      expect(metadata['dolt_mode'], 'proxied-server');
      final rawDatabase = metadata['dolt_database'];
      if (rawDatabase is! String || rawDatabase.trim().isEmpty) {
        fail('copied metadata must name a non-empty dolt_database');
      }
      final database = rawDatabase;
      if (p.isAbsolute(database) ||
          p.basename(database) != database ||
          database == '.' ||
          database == '..') {
        fail('copied dolt_database must stay inside the copied proxy root');
      }

      final sidecar = File(p.join(beadsDir, 'proxied_server_client_info.json'));
      if (sidecar.existsSync()) {
        final configured = _readJsonObject(sidecar.path)['root_path'];
        expect(configured, anyOf(isNull, isA<String>()));
        if (configured is String && configured.trim().isNotEmpty) {
          final resolved = p.normalize(
            p.isAbsolute(configured)
                ? configured
                : p.join(beadsDir, configured),
          );
          expect(
            resolved,
            p.normalize(proxyRoot),
            reason: 'the copied store must not redirect to a source proxy',
          );
        }
      }

      final databaseDir = p.join(proxyRoot, database);
      _requireRealDirectory(databaseDir);
      _deleteCopiedProxyArtifacts(proxyRoot);

      addTearDown(() async {
        await Process.run(
          'bd',
          const <String>['dolt', 'stop', '--force'],
          workingDirectory: runtimeDir,
          runInShell: false,
        );
      });

      await _runChecked('bd', const <String>[
        'info',
        '--json',
      ], workingDirectory: runtimeDir);
      final rssBefore = await _readDoltRss(proxyRoot);
      final diskBefore = await _readAllocatedKib(databaseDir);

      final maintenanceReceipts = <String>[];
      await StateStoreGc(
        out: maintenanceReceipts.add,
        err: (receipt) => throw StateError(receipt),
      ).run(gridHome: copyRoot);

      expect(maintenanceReceipts, contains(contains('flatten=complete')));
      final diskAfter = await _readAllocatedKib(databaseDir);
      expect(diskAfter, lessThan(diskBefore));
      final proxyPid = File(p.join(proxyRoot, 'proxy.pid'));
      expect(proxyPid.existsSync(), isTrue);
      final rssAfter = await _readDoltRss(proxyRoot);
      expect(rssBefore, isPositive);
      expect(rssAfter, isPositive);

      await _runChecked('bd', const <String>[
        'create',
        '--title',
        'tg-zcjr flatten write probe',
        '--type',
        'task',
        '--json',
      ], workingDirectory: runtimeDir);

      final receipt =
          'state-store flatten live receipt: '
          'disk_before_kib=$diskBefore disk_after_kib=$diskAfter '
          'dolt_rss_before_kib=$rssBefore dolt_rss_after_kib=$rssAfter '
          'proxy_pid_present=true bd_write_succeeded=true';
      await File(receiptPath).writeAsString('$receipt\n');
      stdout.writeln(receipt);
    },
  );
}

void _requireRealDirectory(String path) {
  expect(
    FileSystemEntity.typeSync(path, followLinks: false),
    FileSystemEntityType.directory,
    reason: '$path must be a real directory, not a symlink',
  );
}

Map<String, Object?> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    fail('$path must contain a JSON object');
  }
  return decoded;
}

void _deleteCopiedProxyArtifacts(String proxyRoot) {
  for (final entity in Directory(proxyRoot).listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name != 'proxy.pid' &&
        name != 'proxy.lock' &&
        !name.startsWith('proxy-child.')) {
      continue;
    }
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.link) {
      fail('refusing to delete non-file copied proxy artifact ${entity.path}');
    }
    entity.deleteSync();
  }
}

Future<ProcessResult> _runChecked(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

Future<int> _readAllocatedKib(String databaseDir) async {
  final result = await _runChecked('du', <String>[
    '-sk',
    databaseDir,
  ], workingDirectory: databaseDir);
  final fields = (result.stdout as String).trim().split(RegExp(r'\s+'));
  final value = fields.isEmpty ? null : int.tryParse(fields.first);
  if (value == null || value <= 0) {
    throw FormatException('du -sk returned no positive size: ${result.stdout}');
  }
  return value;
}

Future<int> _readDoltRss(String proxyRoot) async {
  final child = _readJsonObject(p.join(proxyRoot, 'proxy-child.pid'));
  final pid = child['pid'];
  if (pid is! int || pid <= 0) {
    throw FormatException('proxy-child.pid has no positive pid');
  }
  final result = await _runChecked('ps', <String>[
    '-o',
    'rss=',
    '-p',
    '$pid',
  ], workingDirectory: proxyRoot);
  final value = int.tryParse((result.stdout as String).trim());
  if (value == null || value <= 0) {
    throw FormatException('ps returned no positive RSS: ${result.stdout}');
  }
  return value;
}
