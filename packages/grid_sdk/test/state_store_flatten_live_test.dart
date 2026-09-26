@Tags(<String>['integration'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String? _bdMissing = _probeBd();

String? _probeBd() {
  try {
    final result = Process.runSync('bd', ['--version']);
    if (result.exitCode == 0) return null;
    return 'bd --version exited ${result.exitCode}; these tests bootstrap '
        'proxied bd stores';
  } on ProcessException catch (error) {
    return 'bd is not on PATH (${error.message}); these tests bootstrap '
        'proxied bd stores';
  }
}

void main() {
  test('proxied flatten restores a writable store', skip: _bdMissing, () async {
    final fixture = await _LiveFixture.create('flatten');
    addTearDown(fixture.dispose);
    await fixture.createBead(
      id: 'tgliveflatten-seed',
      title: 'committed fixture data',
    );
    final receipts = <String>[];
    var sizeReads = 0;

    await StateStoreGc(
      readSize: (path) async => sizeReads++ == 0
          ? kStateStoreFlattenThresholdBytes + 1
          : _readSize(path),
      out: receipts.add,
      err: (receipt) => fail(receipt),
    ).run(gridHome: fixture.gridHome);

    expect(receipts, hasLength(1));
    expect(receipts.single, contains('mode=proxied-server'));
    expect(receipts.single, contains('path=proxied-stop-flatten-restore'));
    expect(receipts.single, contains('flatten=complete'));
    expect(receipts.single, contains('before_bytes=8589934593'));
    expect(receipts.single, matches(RegExp(r'after_bytes=\d+')));
    expect(fixture.proxyPid.existsSync(), isTrue);
    await fixture.createBead(
      id: 'tgliveflatten-write-probe',
      title: 'tg-l5qd post-flatten write probe',
    );
  });

  test(
    'proxied below-threshold skip preserves pids and stays writable',
    skip: _bdMissing,
    () async {
      final fixture = await _LiveFixture.create('skip');
      addTearDown(fixture.dispose);
      await fixture.createBead(
        id: 'tgliveskip-seed',
        title: 'committed fixture data',
      );
      final proxyPidBefore = fixture.proxyPid.readAsStringSync();
      final proxyChildPidBefore = fixture.proxyChildPid.readAsStringSync();
      final receipts = <String>[];

      await StateStoreGc(
        readSize: (_) async => kStateStoreGcThresholdBytes,
        out: receipts.add,
        err: (receipt) => fail(receipt),
      ).run(gridHome: fixture.gridHome);

      expect(receipts, hasLength(1));
      expect(receipts.single, contains('mode=proxied-server'));
      expect(receipts.single, contains('path=skip-below-gc-threshold'));
      expect(
        receipts.single,
        contains('before_bytes=$kStateStoreGcThresholdBytes'),
      );
      expect(
        receipts.single,
        contains('after_bytes=$kStateStoreGcThresholdBytes'),
      );
      expect(fixture.proxyPid.readAsStringSync(), proxyPidBefore);
      expect(fixture.proxyChildPid.readAsStringSync(), proxyChildPidBefore);
      await fixture.createBead(
        id: 'tgliveskip-write-probe',
        title: 'tg-l5qd post-flatten write probe',
      );
    },
  );
}

final class _LiveFixture {
  _LiveFixture._({
    required this.temp,
    required this.gridHome,
    required this.runtimeDir,
  });

  final Directory temp;
  final String gridHome;
  final String runtimeDir;

  File get proxyPid => File(p.join(runtimeDir, '.beads', 'dolt', 'proxy.pid'));
  File get proxyChildPid =>
      File(p.join(runtimeDir, '.beads', 'dolt', 'proxy-child.pid'));

  static Future<_LiveFixture> create(String name) async {
    final temp = Directory.systemTemp.createTempSync('state-store-live-$name-');
    final gridHome = p.join(temp.path, 'home');
    final runtimeDir = p.join(gridHome, '.grid');
    Directory(runtimeDir).createSync(recursive: true);
    final init = await _runBd(
      <String>[
        'init',
        '--non-interactive',
        '--quiet',
        '--skip-agents',
        '--skip-hooks',
        '--prefix',
        'tglive$name',
        '--proxied-server',
      ],
      workingDirectory: runtimeDir,
      explicitDirectory: false,
    );
    if (init.exitCode != 0) {
      await temp.delete(recursive: true);
      throw ProcessException(
        'bd',
        const <String>['init', '--proxied-server'],
        '${init.stdout}${init.stderr}',
        init.exitCode,
      );
    }
    return _LiveFixture._(
      temp: temp,
      gridHome: gridHome,
      runtimeDir: runtimeDir,
    );
  }

  Future<void> createBead({required String id, required String title}) async {
    final result = await _runBd(<String>[
      '--actor',
      'grid-controller',
      'create',
      '--id',
      id,
      '--title',
      title,
      '--type',
      'task',
      '--json',
    ], workingDirectory: runtimeDir);
    if (result.exitCode != 0) {
      throw ProcessException(
        'bd',
        const <String>['create', '--json'],
        '${result.stdout}${result.stderr}',
        result.exitCode,
      );
    }
    final decoded = jsonDecode(result.stdout as String);
    expect(decoded, isA<Map<String, dynamic>>());
    final envelope = decoded as Map<String, dynamic>;
    expect(envelope['schema_version'], 1);
    expect(envelope['data'], containsPair('id', id));
  }

  Future<void> dispose() async {
    await _fenceProxiedStore(runtimeDir, temp.path);
    await temp.delete(recursive: true);
  }
}

Future<int> _readSize(String path) async {
  var bytes = 0;
  await for (final entity in Directory(path).list(recursive: true)) {
    if (entity is File) bytes += await entity.length();
  }
  return bytes;
}

Future<ProcessResult> _runBd(
  List<String> arguments, {
  required String workingDirectory,
  bool explicitDirectory = true,
}) => Process.run(
  'bd',
  <String>[
    if (explicitDirectory) ...<String>['-C', workingDirectory],
    ...arguments,
  ],
  workingDirectory: workingDirectory,
  environment: const <String, String>{'BD_JSON_ENVELOPE': '1'},
  runInShell: false,
);

bool _pidAlive(int pid) => Process.killPid(pid, ProcessSignal.sigwinch);

int? _parsePidFile(String contents) {
  final plainPid = int.tryParse(contents.trim());
  if (plainPid != null && plainPid > 0) return plainPid;
  try {
    final decoded = jsonDecode(contents);
    if (decoded case {'pid': final int pid} when pid > 0) return pid;
  } on FormatException {
    return null;
  }
  return null;
}

Future<bool> _waitForPidExit(int pid) async {
  for (var poll = 0; poll < 100; poll++) {
    if (!_pidAlive(pid)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return !_pidAlive(pid);
}

Future<List<String>> _doltSqlServersUnder(String tempPath) async {
  final result = await Process.run('ps', ['-axo', 'command=']);
  expect(result.exitCode, 0, reason: 'ps census failed: ${result.stderr}');
  final resolvedTemp = Directory(tempPath).resolveSymbolicLinksSync();
  final tempPrefix = '$resolvedTemp${Platform.pathSeparator}';
  final configArgument = RegExp(
    r'''(?:^|\s)--config(?:=|\s+)(?:"([^"]+)"|'([^']+)'|(\S+))''',
  );

  return (result.stdout as String)
      .split('\n')
      .where((command) {
        if (!command.contains('dolt sql-server')) return false;
        for (final match in configArgument.allMatches(command)) {
          final configPath =
              match.group(1) ?? match.group(2) ?? match.group(3)!;
          final config = File(configPath);
          final resolvedConfig = config.existsSync()
              ? config.resolveSymbolicLinksSync()
              : config.absolute.path;
          if (resolvedConfig.startsWith(tempPrefix)) return true;
        }
        return false;
      })
      .toList(growable: false);
}

Future<void> _fenceProxiedStore(String root, String tempPath) async {
  const pidFilePaths = <String>[
    '.beads/dolt/proxy.pid',
    '.beads/dolt/proxy-child.pid',
  ];
  final recordedPids = <String, int>{};
  final pidReadFailures = <String>[];
  for (final relativePath in pidFilePaths) {
    final path = p.join(root, relativePath);
    try {
      final pid = _parsePidFile(File(path).readAsStringSync());
      if (pid == null) {
        pidReadFailures.add('$path did not contain a positive PID');
      } else {
        recordedPids[path] = pid;
      }
    } on Object catch (error) {
      pidReadFailures.add('$path: $error');
    }
  }

  await _runBd(const <String>[
    'dolt',
    'stop',
    '--force',
  ], workingDirectory: root);

  for (final pid in recordedPids.values) {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
  final pidExited = await Future.wait(
    recordedPids.entries.map(
      (entry) async => MapEntry(entry.key, await _waitForPidExit(entry.value)),
    ),
  );
  final stillLivePids = <String>[
    for (final entry in pidExited)
      if (!entry.value) '${entry.key}: ${recordedPids[entry.key]}',
  ];
  final survivingServers = await _doltSqlServersUnder(tempPath);

  expect(
    pidReadFailures,
    isEmpty,
    reason: 'failed to capture every proxied-store PID before cleanup',
  );
  expect(
    stillLivePids,
    isEmpty,
    reason: 'proxied-store processes survived SIGKILL',
  );
  expect(
    survivingServers,
    isEmpty,
    reason: 'Dolt sql-server processes survived under $tempPath',
  );
}
