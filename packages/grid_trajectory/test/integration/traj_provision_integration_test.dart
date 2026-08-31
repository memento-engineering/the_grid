/// The Stage-1 provision guard: `traj provision` against a REAL running dolt
/// sql-server, driving the runbook's step 2 end to end (stage1-wiring §4).
///
/// What this pins that a unit test cannot: the verb creates the sibling
/// database on a live server, applies the §4 DDL with `dolt_ignore` first,
/// mints a `trajectory` user the SERVER actually accepts, and — the part that
/// matters — that credential can read the log it was granted and is REFUSED
/// by the ledger database beside it. Provisioning nobody has connected with
/// is a plan, not provisioning.
///
/// Hermetic: a temp data dir, an ephemeral port, and a synthetic grid home
/// whose `.grid/.beads/dolt/config.yaml` points at it. Never a real store,
/// and bd's proxy files are neither read nor written — the verb resolves the
/// listener from that config alone.
///
/// PR-gating, and fail-closed on a missing dolt (decision:
/// stage0-guards-gate-prs): a skipped guard is a failed guard.
@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/hermetic_trajectory_server.dart';

void main() {
  late HermeticTrajectoryServer server;
  late Directory gridHome;

  /// The grid home the verb resolves the listener from — the plain layout
  /// (`.grid/.beads/dolt/config.yaml`), written to point at the hermetic
  /// server. No proxy client-info file, no bd pid/lock files: the verb must
  /// need none of them.
  void writeServerConfig() {
    final doltDir = Directory(p.join(gridHome.path, '.grid', '.beads', 'dolt'))
      ..createSync(recursive: true);
    File(p.join(doltDir.path, 'config.yaml')).writeAsStringSync(
      'listener:\n'
      '  host: ${server.host}\n'
      '  port: ${server.port}\n',
    );
  }

  /// The bootstrap credential the runbook's step 1 probes for. Created
  /// server-side by the hermetic admin (which holds GRANT OPTION) and
  /// persisted at its stated home — the same two artifacts step 1b's offline
  /// window produces by hand.
  Future<void> seedGridboot(String password) async {
    final admin = await TrajectoryConnection.connect(server.serverEndpoint);
    try {
      await admin.execute(
        "CREATE USER IF NOT EXISTS '$gridbootUser'@'%' "
        "IDENTIFIED BY '$password'",
      );
      // The server outlives each test's grid home, and CREATE USER IF NOT
      // EXISTS never updates an existing password (measured on dolt 2.2 —
      // the same fact `provisionTrajectoryUser` documents). Without the
      // ALTER, every test after the first authenticates with the FIRST
      // test's secret.
      await admin.execute(
        "ALTER USER '$gridbootUser'@'%' IDENTIFIED BY '$password'",
      );
      await admin.execute("GRANT ALL PRIVILEGES ON *.* TO '$gridbootUser'@'%'");
    } finally {
      await admin.close();
    }
    final secret = File(gridbootSecretPath(gridHome.path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(password);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', secret.path]);
    }
  }

  setUpAll(() async {
    server = await HermeticTrajectoryServer.create();
  });

  tearDownAll(() async {
    await server.dispose();
  });

  setUp(() async {
    gridHome = Directory(
      (await Directory.systemTemp.createTemp(
        'traj_prov_it_',
      )).resolveSymbolicLinksSync(),
    );
    writeServerConfig();
  });

  tearDown(() async {
    if (gridHome.existsSync()) await gridHome.delete(recursive: true);
  });

  test('provisions a fresh home end to end, and the scoped credential reads '
      'the log it was granted', () async {
    await seedGridboot('bootpw-fresh');
    final out = <String>[];
    final err = <String>[];

    final code = await runTrajProvision(
      gridHome: gridHome.path,
      out: out.add,
      err: err.add,
    );

    expect(err, isEmpty, reason: out.join('\n'));
    expect(code, 0);
    final text = out.join('\n');
    expect(text, contains('database: trajectory'));
    expect(text, contains('schema: dolt_ignore registered'));
    expect(text, contains('granted on trajectory.* ONLY'));
    expect(text, contains('trajectory rows = 0'));

    // The service secret landed at its stated home, 0600, and NEVER under
    // .beads (the asserted boundary).
    final secret = File(trajectorySecretPath(gridHome.path));
    expect(secret.existsSync(), isTrue);
    expect(p.split(secret.path), isNot(contains('.beads')));
    if (!Platform.isWindows) {
      expect(secret.statSync().mode & 0x1FF, 0x180);
    }

    // The credential works for real, and the DDL is actually there.
    final service = await TrajectoryConnection.connect(
      TrajectoryEndpoint(
        host: server.host,
        port: server.port,
        user: trajectoryUser,
        password: secret.readAsStringSync().trim(),
        database: 'trajectory',
      ),
    );
    try {
      final ignores = await service.execute('SELECT pattern FROM dolt_ignore');
      expect({
        for (final row in ignores.rows) row['pattern'],
      }, containsAll(<String>['proj_%', 'traj_pulse', 'traj_fence']));
      final rows = await service.execute(
        'SELECT COUNT(*) AS n FROM trajectory',
      );
      expect(rows.rows.single['n'], '0');
    } finally {
      await service.close();
    }
  });

  test('the scoped credential is REFUSED by a sibling database', () async {
    await seedGridboot('bootpw-scope');
    expect(await runTrajProvision(gridHome: gridHome.path, out: (_) {}), 0);

    // Stand a ledger-shaped sibling up beside the log, then try to USE it as
    // the service identity. `trajectory.*` means trajectory.* .
    final admin = await TrajectoryConnection.connect(server.serverEndpoint);
    try {
      await admin.execute('CREATE DATABASE IF NOT EXISTS ledger_lookalike');
    } finally {
      await admin.close();
    }
    final password = File(
      trajectorySecretPath(gridHome.path),
    ).readAsStringSync().trim();
    await expectLater(
      TrajectoryConnection.connect(
        TrajectoryEndpoint(
          host: server.host,
          port: server.port,
          user: trajectoryUser,
          password: password,
          database: 'ledger_lookalike',
        ),
      ),
      throwsA(isA<MySQLServerException>()),
    );
  });

  test('a second run is a no-op that still verifies — and reuses the '
      'secret', () async {
    await seedGridboot('bootpw-idem');
    expect(await runTrajProvision(gridHome: gridHome.path, out: (_) {}), 0);
    final first = File(trajectorySecretPath(gridHome.path)).readAsStringSync();

    final out = <String>[];
    final err = <String>[];
    final code = await runTrajProvision(
      gridHome: gridHome.path,
      out: out.add,
      err: err.add,
    );

    expect(err, isEmpty, reason: out.join('\n'));
    expect(code, 0);
    expect(out.join('\n'), contains('trajectory rows = 0'));
    // Re-minting here would push a password the server never learned and
    // strand the station behind 1045 forever.
    expect(File(trajectorySecretPath(gridHome.path)).readAsStringSync(), first);
  });

  test('the port is re-resolved per connect — a bd-rewritten config is '
      'picked up without a restart', () async {
    await seedGridboot('bootpw-reresolve');
    // Point the config at a dead port, then repair it: a verb that captured
    // the listener once would still be dialling the dead one.
    File(
      p.join(gridHome.path, '.grid', '.beads', 'dolt', 'config.yaml'),
    ).writeAsStringSync('listener:\n  host: 127.0.0.1\n  port: 1\n');
    final err = <String>[];
    expect(
      await runTrajProvision(
        gridHome: gridHome.path,
        out: (_) {},
        err: err.add,
      ),
      1,
    );
    expect(err.join('\n'), isNotEmpty);

    writeServerConfig();
    expect(await runTrajProvision(gridHome: gridHome.path, out: (_) {}), 0);
  });

  test('a home with no bootstrap credential prints the ONE offline window '
      'instead of failing blind', () async {
    final out = <String>[];
    final err = <String>[];
    final code = await runTrajProvision(
      gridHome: gridHome.path,
      out: out.add,
      err: err.add,
    );
    expect(code, 1);
    final text = err.join('\n');
    expect(text, contains('offline window'));
    expect(text, contains('cp -Rc'));
    expect(text, contains('--doltcfg-dir .doltcfg'));
    expect(text, contains("CREATE USER IF NOT EXISTS 'gridboot'@'%'"));
    expect(text, contains('gridboot.secret'));
    // Nothing was created: a refusal must not half-provision.
    expect(File(trajectorySecretPath(gridHome.path)).existsSync(), isFalse);
  });
}
