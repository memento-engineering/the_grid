/// M1 — bd's tolerance of a sibling `trajectory` database under its own
/// server's data dir (storage-call.md stage-0 item 1).
///
/// The storage call's SAME-DB flip condition 1 and its separate-db safety gate
/// are the same fact: does bd keep working when a second database appears
/// beside its own under `.beads/dolt/`? This runs the question twice —
///
///   * **fresh**: `bd init --proxied-server` in scratch (the REAL deployment
///     mode: proxy + child dolt rooted at `.beads/dolt`), synthetic beads, a
///     baseline bd sweep, then CREATE DATABASE trajectory + the §4 schema on
///     that same child server, then the SAME sweep again;
///   * **copy-of-real**: a `cp` of the tranquility store into scratch, the
///     source never opened for write and its servers/pid/lock files never
///     touched. The copy is DEFANGED before any process starts — the listener
///     port is rewritten (the real child server holds the recorded port RIGHT
///     NOW, so an unrewritten copy would have bd's proxy dial the LIVE store),
///     pid/lock/log files are removed, and `sync.remote` is stripped so no
///     push can reach the real remote.
///
/// A live-copy inconsistency is a RECORDABLE OUTCOME, not a harness failure:
/// the source is a store under active write, and "the copy would not load"
/// is itself the answer to "can you snapshot this thing hot".
///
/// Run: `dart run tool/measurements/m1_bd_sibling_db.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// The real store M1b COPIES — a `.beads` dir named by
/// `GRID_TRAJECTORY_REAL_STORE`, read with `cp` only; its running server, pid,
/// lock, and proxy files are never opened by this harness.
///
/// There is NO default, deliberately: the store this half wants is one
/// operator's live deployment, and a hardcoded absolute path would be both a
/// personal path in a shared tree and a harness that silently measures
/// nothing (or the wrong store) on anyone else's machine. Unset ⇒ M1b is
/// skipped and says so; M1a is unaffected.
String? get realStoreBeadsDir =>
    Platform.environment['GRID_TRAJECTORY_REAL_STORE'];

const String bootstrapUser = 'gridboot';
const String bootstrapPassword = 'gridbootpw';

Future<void> main(List<String> args) async {
  final scratch = Directory(p.join(measurementScratchRoot, 'm1'));
  if (scratch.existsSync()) await scratch.delete(recursive: true);
  scratch.createSync(recursive: true);

  if (!args.contains('--only-copy')) {
    banner('M1a — fresh bd store, proxied-server mode');
    await _freshStoreHalf(p.join(scratch.path, 'fresh'));
  }

  if (args.contains('--skip-copy')) {
    say('M1b skipped by flag');
  } else {
    banner('M1b — copy of the live tranquility store');
    await _copyOfRealHalf(p.join(scratch.path, 'copy'));
  }
  // bd's proxies and the sockets this harness opened can outlive their own
  // shutdown; a measurement that has printed its numbers must not linger.
  exit(0);
}

// ── M1a ─────────────────────────────────────────────────────────────────────

Future<void> _freshStoreHalf(String root) async {
  Directory(root).createSync(recursive: true);
  // A git repo: bd's init wants one, and its absence changes bd's own setup
  // path (hooks, exclude) rather than the storage question under test.
  await _run('git', ['init', '-q'], cwd: root);
  await _run('git', ['config', 'user.email', 'm1@measure.local'], cwd: root);
  await _run('git', ['config', 'user.name', 'm1'], cwd: root);

  final init = await _run(
    'bd',
    [
      'init',
      '--prefix',
      'm1p',
      '--proxied-server',
      '--skip-agents',
      '--skip-hooks',
      '--non-interactive',
    ],
    cwd: root,
    env: {'BD_NON_INTERACTIVE': '1'},
  );
  say('bd init exit=${init.exitCode} mode=proxied-server');
  if (init.exitCode != 0) {
    say('bd init STDERR: ${init.stderr}');
    say('M1a BLOCKED — bd could not initialize headless; nothing further ran');
    return;
  }

  say('populating 200 synthetic beads');
  final createWatch = Stopwatch()..start();
  for (var i = 0; i < 200; i++) {
    final created = await _run('bd', [
      'create',
      'synthetic bead $i',
      '-p',
      '${i % 4}',
      '-d',
      'M1 population row $i',
    ], cwd: root);
    if (created.exitCode != 0) {
      say('bd create FAILED at $i: ${created.stderr}');
      break;
    }
  }
  createWatch.stop();
  say('200 creates in ${createWatch.elapsedMilliseconds}ms');

  final before = await _bdSweep(root, label: 'BEFORE sibling');

  // ── the sibling database ──────────────────────────────────────────────
  final beads = p.join(root, '.beads');
  final doltDir = p.join(beads, 'dolt');
  final port = _listenerPort(p.join(doltDir, 'config.yaml'));
  say('bd child listener port: $port');

  // bd's server has exactly one user: the auto `root@localhost`, which cannot
  // authenticate over the 127.0.0.1 TCP address any client actually dials
  // (measured: 1045 for root over both 127.0.0.1 and localhost), and dolt
  // opened no unix socket. So a wildcard-host credential has to be seeded
  // OFFLINE, with the server down — this is the operational cost of putting
  // anything on bd's server, and it belongs in the report.
  await _quiesceBd(doltDir);
  final createUser = await _run('dolt', [
    '--doltcfg-dir',
    p.join(doltDir, '.doltcfg'),
    'sql',
    '-q',
    "CREATE USER IF NOT EXISTS '$bootstrapUser'@'%' "
        "IDENTIFIED BY '$bootstrapPassword'; "
        "GRANT ALL ON *.* TO '$bootstrapUser'@'%' WITH GRANT OPTION;",
  ], cwd: doltDir);
  say('offline CREATE USER exit=${createUser.exitCode}');
  if (createUser.exitCode != 0) say('  stderr: ${createUser.stderr}');

  // Any bd command respawns proxy + child; the credential is now on disk.
  final respawn = await _run('bd', ['list', '--json'], cwd: root);
  say('bd list after offline user seed: exit=${respawn.exitCode}');
  final livePort = _listenerPort(p.join(doltDir, 'config.yaml'));

  final admin = await TrajectoryConnection.connect(
    TrajectoryEndpoint(
      host: '127.0.0.1',
      port: livePort,
      user: bootstrapUser,
      password: bootstrapPassword,
    ),
  );
  final databasesBefore = await admin.execute('SHOW DATABASES');
  say(
    'databases before: '
    '${databasesBefore.rows.map((r) => r.values.first).toList()}',
  );

  await createTrajectoryDatabase(admin);
  final credential = await provisionTrajectoryUser(admin, gridHome: root);
  say(
    'provisioned SQL user ${credential.user} (secret ${credential.secretPath})',
  );

  final service = await TrajectoryConnection.connect(
    TrajectoryEndpoint(
      host: '127.0.0.1',
      port: livePort,
      user: credential.user,
      password: credential.password,
      database: 'trajectory',
    ),
  );
  await applyTrajectorySchema(service);
  say('§4 schema applied on the sibling database');

  // The boundary, asserted rather than asserted-about: the service credential
  // is granted on trajectory.* only, so bd's own database must refuse it.
  try {
    await service.execute('SELECT COUNT(*) AS c FROM m1p.issues');
    say('BOUNDARY LEAK: the trajectory credential READ bd\'s database');
  } on Object catch (error) {
    say(
      'boundary holds — trajectory user refused on bd\'s database: '
      '${_oneLine('$error')}',
    );
  }

  // A real append through the fenced path, so the sibling is not merely
  // present but in use while bd works.
  final appender = TrajectoryAppender(
    db: service,
    station: 'm1',
    onEvent: (event) => say(
      '  service event: ${event.kind.name} '
      '${_oneLine(event.reason)}',
    ),
  );
  final claim = await appender.claimEpoch(pid: pid, pgid: pid);
  say('epoch claim: $claim');
  var landed = 0;
  for (final record in familyOneLifecycle(0, at: DateTime.utc(2026, 8, 31))) {
    final outcome = await appender.append(record);
    if (outcome is Appended) landed++;
  }
  say('$landed records appended to the sibling database');

  final after = await _bdSweep(root, label: 'AFTER sibling');
  _compare(before, after);

  final databasesAfter = await admin.execute('SHOW DATABASES');
  say(
    'databases after: '
    '${databasesAfter.rows.map((r) => r.values.first).toList()}',
  );

  // bd's own commit shape — the same-db flip's second condition, answered for
  // the record even though a sibling database puts it out of reach.
  final autoCommit = await _run('bd', [
    'config',
    'get',
    'dolt.auto-commit',
  ], cwd: root);
  say(
    'bd dolt.auto-commit = ${_oneLine(autoCommit.stdout as String)}'
    ' (exit ${autoCommit.exitCode})',
  );
  final sessionVars = File(p.join(doltDir, 'config.yaml')).readAsStringSync();
  say(
    'bd server config user_session_vars: '
    '${sessionVars.contains('user_session_vars: []') ? 'EMPTY '
              '(no dolt_transaction_commit)' : 'SET — inspect'}',
  );
  final ledgerLog = await admin.execute(
    'SELECT COUNT(*) AS c FROM m1p.dolt_log',
  );
  say('bd database dolt_log commits: ${ledgerLog.rows.first['c']}');
  final trajLog = await service.execute('SELECT COUNT(*) AS c FROM dolt_log');
  say('trajectory dolt_log commits: ${trajLog.rows.first['c']}');
  final messages = await admin.execute(
    'SELECT message FROM m1p.dolt_log ORDER BY date DESC LIMIT 5',
  );
  say(
    'bd commit messages (newest 5): '
    '${messages.rows.map((r) => r['message']).toList()}',
  );

  // The same-db flip's condition 2, measured rather than assumed: is bd's
  // commit `-a`-shaped? A stand-in table is created and dirtied INSIDE bd's
  // own database, then a bd write runs. If the stand-in leaves `dolt_status`
  // without anyone staging it, bd swept a table it does not own — which is
  // exactly what cohabiting bd's database would cost the trajectory tables.
  await admin.execute(
    'CREATE TABLE IF NOT EXISTS m1p.traj_standin (id INT PRIMARY KEY)',
  );
  await admin.execute('INSERT INTO m1p.traj_standin VALUES (1)');
  final dirty = await admin.execute(
    "SELECT table_name FROM m1p.dolt_status WHERE table_name = 'traj_standin'",
  );
  say('stand-in dirty before bd write: ${dirty.rows.isNotEmpty}');
  final bdWrite = await _run('bd', [
    'create',
    'sweep-capture probe',
    '-p',
    '1',
  ], cwd: root);
  say('bd create during dirty stand-in: exit=${bdWrite.exitCode}');
  final stillDirty = await admin.execute(
    "SELECT table_name FROM m1p.dolt_status WHERE table_name = 'traj_standin'",
  );
  say(
    stillDirty.rows.isNotEmpty
        ? 'bd commit is NOT -a-shaped — the stand-in stayed unstaged'
        : 'bd commit SWEPT the stand-in — an -a-shaped commit (same-db flip '
              'condition 2 FAILS)',
  );
  // Corroboration from the commit graph itself, not just from status going
  // quiet: dolt_diff names the tables each commit actually touched.
  final touched = await admin.execute(
    'SELECT commit_hash, table_name, message FROM m1p.dolt_diff '
    'ORDER BY date DESC LIMIT 6',
  );
  for (final row in touched.rows) {
    say('  dolt_diff: ${row['table_name']} in "${row['message']}"');
  }

  await service.close();
  await admin.close();
  await _quiesceBd(doltDir);
}

// ── M1b ─────────────────────────────────────────────────────────────────────

Future<void> _copyOfRealHalf(String root) async {
  final configured = realStoreBeadsDir;
  if (configured == null) {
    say(
      'GRID_TRAJECTORY_REAL_STORE is unset — M1b not run (it needs a real '
      '.beads dir to copy; export the path to run this half)',
    );
    return;
  }
  final source = Directory(configured);
  if (!source.existsSync()) {
    say('real store absent at $configured — M1b not run');
    return;
  }
  Directory(root).createSync(recursive: true);
  final destination = p.join(root, '.beads');

  say('copying $configured → $destination (source is READ-ONLY here)');
  final watch = Stopwatch()..start();
  // -c asks APFS for clonefile: near-instant, near-zero extra space, and
  // copy-on-write so nothing this harness does can reach the source blocks.
  var copy = await _run('cp', ['-Rc', source.path, destination]);
  if (copy.exitCode != 0) {
    say(
      'clonefile copy failed (${_oneLine(copy.stderr as String)}); '
      'falling back to a plain recursive copy',
    );
    copy = await _run('cp', ['-R', source.path, destination]);
  }
  watch.stop();
  say('copy exit=${copy.exitCode} in ${watch.elapsedMilliseconds}ms');
  if (copy.exitCode != 0) {
    say('M1b BLOCKED — the store could not be copied: ${copy.stderr}');
    return;
  }

  // DEFANG, before any process can look at this directory.
  final doltDir = p.join(destination, 'dolt');
  final freePort = await _freePort();
  _rewriteListenerPort(p.join(doltDir, 'config.yaml'), freePort);
  say(
    'copy listener port rewritten to $freePort (the source store\'s real '
    'child server still holds its own port — this is what stops bd\'s proxy '
    'from dialing the LIVE store)',
  );
  for (final name in const [
    'proxy.pid',
    'proxy-child.pid',
    'proxy.lock',
    'proxy-child.lock',
    'proxy.lock.pregc',
    'proxy-child.lock.pregc',
    'proxy.log',
    'server.log',
  ]) {
    final file = File(p.join(doltDir, name));
    if (file.existsSync()) file.deleteSync();
  }
  for (final name in const [
    'dolt-server.pid',
    'dolt-server.port',
    'dolt-server.lock',
    'dolt-server.log',
  ]) {
    final file = File(p.join(destination, name));
    if (file.existsSync()) file.deleteSync();
  }
  final config = File(p.join(destination, 'config.yaml'));
  if (config.existsSync()) {
    final scrubbed = const LineSplitter()
        .convert(config.readAsStringSync())
        .where((line) => !line.startsWith('sync.remote'))
        .join('\n');
    config.writeAsStringSync('$scrubbed\n');
    say('sync.remote stripped from the copy\'s config.yaml');
  }

  final size = await _run('du', ['-sh', destination]);
  say('copy size: ${_oneLine(size.stdout as String)}');

  // Does it load at all? bd's own answer, sandboxed (no auto-push).
  final load = await _run('bd', [
    '-C',
    root,
    '--sandbox',
    'list',
    '--json',
    '--limit',
    '5',
  ], timeout: const Duration(minutes: 6));
  say('bd list on the copy: exit=${load.exitCode}');
  if (load.exitCode != 0) {
    say('  stderr: ${_oneLine(load.stderr as String)}');
    say('M1b OUTCOME — the hot copy does not load; recorded, not a failure');
    await _quiesceBd(doltDir);
    return;
  }
  say('  stdout head: ${_oneLine(load.stdout as String, cap: 200)}');

  final count = await _run('bd', [
    '-C',
    root,
    '--sandbox',
    'count',
  ], timeout: const Duration(minutes: 6));
  say(
    'bd count on the copy: exit=${count.exitCode} '
    '${_oneLine(count.stdout as String)}',
  );

  final before = await _bdSweep(
    root,
    label: 'copy BEFORE sibling',
    directory: root,
  );

  // Same sibling experiment, on real data.
  await _quiesceBd(doltDir);
  final createUser = await _run(
    'dolt',
    [
      '--doltcfg-dir',
      p.join(doltDir, '.doltcfg'),
      'sql',
      '-q',
      "CREATE USER IF NOT EXISTS '$bootstrapUser'@'%' "
          "IDENTIFIED BY '$bootstrapPassword'; "
          "GRANT ALL ON *.* TO '$bootstrapUser'@'%' WITH GRANT OPTION;",
    ],
    cwd: doltDir,
    timeout: const Duration(minutes: 10),
  );
  say('offline CREATE USER on the copy: exit=${createUser.exitCode}');
  if (createUser.exitCode != 0) {
    say('  stderr: ${_oneLine(createUser.stderr as String)}');
    return;
  }

  final respawn = await _run('bd', [
    '-C',
    root,
    '--sandbox',
    'list',
    '--limit',
    '1',
  ], timeout: const Duration(minutes: 6));
  say('bd respawn after user seed: exit=${respawn.exitCode}');
  final livePort = _listenerPort(p.join(doltDir, 'config.yaml'));
  say('copy child listener now on $livePort');

  final admin = await TrajectoryConnection.connect(
    TrajectoryEndpoint(
      host: '127.0.0.1',
      port: livePort,
      user: bootstrapUser,
      password: bootstrapPassword,
    ),
  );
  final databases = await admin.execute('SHOW DATABASES');
  say(
    'databases on the copy: '
    '${databases.rows.map((r) => r.values.first).toList()}',
  );
  await createTrajectoryDatabase(admin);
  final credential = await provisionTrajectoryUser(admin, gridHome: root);
  final service = await TrajectoryConnection.connect(
    TrajectoryEndpoint(
      host: '127.0.0.1',
      port: livePort,
      user: credential.user,
      password: credential.password,
      database: 'trajectory',
    ),
  );
  await applyTrajectorySchema(service);
  say('§4 schema applied beside the copied tranquility database');

  final after = await _bdSweep(
    root,
    label: 'copy AFTER sibling',
    directory: root,
  );
  _compare(before, after);

  await service.close();
  await admin.close();
  await _quiesceBd(doltDir);
}

// ── helpers ─────────────────────────────────────────────────────────────────

/// One pass of bd's read and write surface, timed. Comparing two of these
/// across the CREATE DATABASE is the regression sweep the storage call asks
/// for.
Future<Map<String, String>> _bdSweep(
  String root, {
  required String label,
  String? directory,
}) async {
  final result = <String, String>{};
  Future<void> step(String name, List<String> args) async {
    final watch = Stopwatch()..start();
    final run = await _run(
      'bd',
      [
        if (directory != null) ...['-C', directory],
        '--sandbox',
        ...args,
      ],
      cwd: directory == null ? root : null,
      timeout: const Duration(minutes: 6),
    );
    watch.stop();
    result[name] = 'exit=${run.exitCode} ${watch.elapsedMilliseconds}ms';
    if (run.exitCode != 0) {
      result[name] = '${result[name]} err=${_oneLine(run.stderr as String)}';
    }
  }

  await step('list', ['list', '--limit', '50']);
  await step('list-json', ['list', '--json', '--limit', '50']);
  await step('ready', ['ready']);
  await step('count', ['count']);
  await step('create', ['create', 'sweep probe $label', '-p', '2']);
  await step('stats', ['stats']);
  say('$label sweep: $result');
  return result;
}

void _compare(Map<String, String> before, Map<String, String> after) {
  for (final key in before.keys) {
    final wasOk = before[key]!.startsWith('exit=0');
    final isOk = (after[key] ?? '').startsWith('exit=0');
    final verdict = wasOk == isOk ? 'unchanged' : 'REGRESSED';
    say('  $key: ${before[key]}  →  ${after[key]}  [$verdict]');
  }
}

/// Stops bd's proxy and child from the pid files the store itself wrote, then
/// clears the pid/lock residue — the standing "dolt-server kill needs proxy
/// cleanup" playbook, applied to SCRATCH stores only.
Future<void> _quiesceBd(String doltDir) async {
  for (final name in const ['proxy.pid', 'proxy-child.pid']) {
    final file = File(p.join(doltDir, name));
    if (!file.existsSync()) continue;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final pid = (decoded as Map<String, Object?>)['pid'];
      if (pid is int) {
        await _run('kill', ['-TERM', '$pid']);
      }
    } on Object catch (error) {
      say('  pid file $name unreadable ($error) — skipped');
    }
    file.deleteSync();
  }
  for (final name in const ['proxy.lock', 'proxy-child.lock']) {
    final file = File(p.join(doltDir, name));
    if (file.existsSync()) file.deleteSync();
  }
  await Future<void>.delayed(const Duration(seconds: 2));
}

int _listenerPort(String configPath) {
  final text = File(configPath).readAsStringSync();
  final match = RegExp(r'port:\s*(\d+)').firstMatch(text);
  if (match == null) throw StateError('no listener port in $configPath');
  return int.parse(match.group(1)!);
}

void _rewriteListenerPort(String configPath, int port) {
  final file = File(configPath);
  final text = file.readAsStringSync();
  file.writeAsStringSync(
    text.replaceAll(RegExp(r'port:\s*\d+'), 'port: $port'),
  );
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<ProcessResult> _run(
  String executable,
  List<String> args, {
  String? cwd,
  Map<String, String>? env,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: cwd,
    environment: env,
    runInShell: false,
  );
  final out = StringBuffer();
  final err = StringBuffer();
  final drained = Future.wait([
    process.stdout.transform(utf8.decoder).forEach(out.write),
    process.stderr.transform(utf8.decoder).forEach(err.write),
  ]);
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -9;
    },
  );
  await drained.timeout(const Duration(seconds: 10), onTimeout: () => []);
  return ProcessResult(process.pid, code, out.toString(), err.toString());
}

/// Collapses a captured stream into one loggable line, capped so a 500-line
/// bd error cannot swallow the measurement's own output.
String _oneLine(String value, {int cap = 400}) {
  final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= cap ? flat : '${flat.substring(0, cap)}…';
}
