/// `traj provision` — the first-boot runbook's step 2, made a verb
/// (stage1-wiring §4).
///
/// Provisioning happens **against the RUNNING state-store server over SQL**.
/// That is the whole point: M1 measured that a sibling database is invisible
/// to bd on an 18 GB live store, so the trajectory database can be created
/// without the offline window everything else in this area would need. The
/// one destructive alternative — stopping bd's child server — is step 1b's
/// exception and lives in the runbook, not in this verb.
///
/// Four rules this verb keeps, all of them load-bearing:
///
///   1. **Never touch bd's proxy files.** No pid file, no lock file, no
///      secret under `.beads/` is read or written here. The listener is
///      resolved from the server's own `config.yaml`
///      (`resolveDoltServerListener`), and the only files written live under
///      `<gridHome>/.grid/trajectory/`.
///   2. **The listener is re-resolved per connect**, never captured once (§4's
///      reconnect rule): bd rewrites the child server's port on its own
///      terms, and a pinned port re-dials a dead listener forever.
///   3. **`dolt_ignore` registration FIRST**, then the §4 DDL verbatim —
///      `applyTrajectorySchema`'s own STEP 0, which must run before any table
///      exists to be committed (probe T3).
///   4. **`trajectory.*` ONLY.** The service credential is granted on the
///      sibling database and refused by the ledger database; the bootstrap
///      credential (`gridboot`, `GRANT ALL ON *.*`) never leaves
///      `.grid/trajectory/gridboot.secret` (§4 step 1, r2 minor 15).
///
/// Idempotent and re-runnable by construction: every step is `IF NOT EXISTS`
/// or a reuse-the-existing-secret path, so a second run on a provisioned home
/// is a no-op that still verifies.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../connect/server_config.dart';
import '../connect/trajectory_connection.dart';
import '../connect/trajectory_db.dart';
import '../ddl/trajectory_provisioning.dart';
import '../ddl/trajectory_schema.dart';
import 'traj_flags.dart';
import 'trajectory_reader.dart' show trajectoryDatabaseName;

/// The bootstrap SQL identity the runbook's step 1 probes for. It is NOT the
/// service credential: it holds `GRANT ALL ON *.*` and exists only so the
/// sibling database and the scoped user can be created at all.
const String gridbootUser = 'gridboot';

/// The bootstrap secret's stated home (§4 step 1, r2 minor 15) — beside the
/// service secret, mode 0600, never under `.beads/`.
String gridbootSecretPath(String gridHome) =>
    p.join(gridHome, '.grid', 'trajectory', 'gridboot.secret');

/// How the verb opens a SQL session; injected so the guard suite can drive a
/// hermetic server and a unit test can script statements without a socket.
typedef ProvisionConnect =
    Future<TrajectoryDb> Function(TrajectoryEndpoint endpoint);

/// How the verb finds the listener; injected for the same reason. Production
/// is [resolveDoltServerListener], called ONCE PER CONNECT.
typedef ListenerResolver = DoltServerListener Function(String gridHome);

Future<TrajectoryDb> _defaultConnect(TrajectoryEndpoint endpoint) =>
    TrajectoryConnection.connect(endpoint);

/// The verb.
class TrajProvisionCommand extends Command<int> {
  TrajProvisionCommand({ProvisionConnect? connect, ListenerResolver? resolve})
    : _connect = connect ?? _defaultConnect,
      _resolve = resolve ?? resolveDoltServerListener {
    addGridHomeOption(argParser);
  }

  final ProvisionConnect _connect;
  final ListenerResolver _resolve;

  @override
  final String name = 'provision';

  @override
  final String description =
      'Create the trajectory database, apply the §4 schema, and provision the '
      'scoped SQL user — against the RUNNING state-store server, idempotently.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln(
        'traj provision: unexpected argument "${argResults!.rest.first}".',
      );
      return 64;
    }
    final gridHome = gridHomeFrom(argResults!, stderr.writeln, 'provision');
    if (gridHome == null) return 64;
    return runTrajProvision(
      gridHome: gridHome,
      connect: _connect,
      resolve: _resolve,
    );
  }
}

/// Runs the runbook's step 2 and prints what it did.
///
/// Exits 0 on a provisioned (or already-provisioned) home; 1 on any refusal,
/// with the §4 step-1b offline window spelled out when the refusal is the
/// missing bootstrap credential — the one case where the operator's next
/// action is a documented procedure rather than a retry.
Future<int> runTrajProvision({
  required String gridHome,
  ProvisionConnect connect = _defaultConnect,
  ListenerResolver resolve = resolveDoltServerListener,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final void Function(String) write = out ?? stdout.writeln;
  final void Function(String) writeErr = err ?? stderr.writeln;
  write('traj provision — first-boot runbook step 2 (stage1-wiring §4)');

  final bootSecret = File(gridbootSecretPath(gridHome));
  if (!bootSecret.existsSync()) {
    writeErr(
      'traj provision: no bootstrap credential at ${bootSecret.path} — this '
      'is the ONE offline window (§4 step 1b).',
    );
    _writeOfflineWindow(writeErr, gridHome);
    return 1;
  }
  final bootPassword = bootSecret.readAsStringSync().trim();
  if (bootPassword.isEmpty) {
    writeErr('traj provision: empty bootstrap secret: ${bootSecret.path}');
    return 1;
  }

  // Resolved HERE and again below: two connects, two resolutions. bd rewrites
  // the port on its own terms (§4's reconnect rule), and a value captured once
  // is a value that goes stale between them.
  TrajectoryEndpoint endpoint({required String? database}) {
    final listener = resolve(gridHome);
    return TrajectoryEndpoint(
      host: listener.host,
      port: listener.port,
      user: gridbootUser,
      password: bootPassword,
      database: database,
    );
  }

  TrajectoryCredential credential;
  try {
    // 1 — CREATE DATABASE, on a SERVER-level session (no database selected,
    // so no branch to pin).
    final server = await connect(endpoint(database: null));
    try {
      await createTrajectoryDatabase(server);
      write('  database: $trajectoryDatabaseName (create if not exists) — ok');
    } finally {
      await server.close();
    }

    // 2 — the §4 DDL, dolt_ignore FIRST, as the bootstrap identity: the
    // scoped user does not exist yet, and DDL is not its job anyway.
    final schemaConn = await connect(
      endpoint(database: trajectoryDatabaseName),
    );
    try {
      await applyTrajectorySchema(schemaConn);
      write('  schema: dolt_ignore registered, §4 DDL applied — ok');
    } finally {
      await schemaConn.close();
    }

    // 3 — the scoped credential, on a fresh server-level session.
    final grantConn = await connect(endpoint(database: null));
    try {
      credential = await provisionTrajectoryUser(grantConn, gridHome: gridHome);
      write(
        '  user: ${credential.user}@% granted on '
        '$trajectoryDatabaseName.* ONLY; secret at ${credential.secretPath} '
        '(0600)',
      );
    } finally {
      await grantConn.close();
    }
  } on Object catch (error) {
    writeErr('traj provision: $error');
    return 1;
  }

  // 4 — verify AS THE SERVICE CREDENTIAL. Provisioning that has not been used
  // once by the identity that will use it is not provisioning, it is a plan.
  try {
    final listener = resolve(gridHome);
    final verify = await connect(
      TrajectoryEndpoint(
        host: listener.host,
        port: listener.port,
        user: credential.user,
        password: credential.password,
        database: trajectoryDatabaseName,
      ),
    );
    try {
      // The log table shares the database's name; the session is already
      // USEing the database, so this is the table (§4 step 2.4 verbatim).
      final rows = await verify.execute('SELECT COUNT(*) AS n FROM trajectory');
      final count = rows.rows.isEmpty ? null : rows.rows.first['n'];
      write(
        '  verify: connected as ${credential.user}; trajectory rows = '
        '${count ?? 'unknown'}',
      );
    } finally {
      await verify.close();
    }
  } on Object catch (error) {
    writeErr(
      'traj provision: the scoped credential could not read the database it '
      'was just granted — $error',
    );
    return 1;
  }

  write(
    '  next: `up --trajectory` runs belt-verify over the empty log, then '
    'claims epoch 1 (§4 step 3 — nothing to do by hand).',
  );
  return 0;
}

/// §4 step 1b, printed verbatim so the operator never has to reconstruct the
/// procedure from memory. Appendix A's stop/start playbook is named rather
/// than paraphrased: it is the standing dolt-server-kill playbook and it lives
/// in the runbook doc.
void _writeOfflineWindow(void Function(String) write, String gridHome) {
  final beads = p.join(gridHome, '.grid', '.beads');
  write('  1. pre-flight snapshot: cp -Rc "$beads" "$beads.bak"');
  write('  2. station down; verify the lock released');
  write(
    '  3. stop bd\'s proxy, then SIGTERM the dolt child server, then clear '
    "bd's proxy pid/lock files (runbook Appendix A steps 1-2)",
  );
  write('  4. from inside "$beads/dolt/", with the --doltcfg-dir discipline:');
  write(
    '       dolt --doltcfg-dir .doltcfg sql -q "CREATE USER IF NOT EXISTS '
    "'$gridbootUser'@'%' IDENTIFIED BY '<secret>'; GRANT ALL ON *.* TO "
    "'$gridbootUser'@'%';\"",
  );
  write(
    '     writing <secret> to ${gridbootSecretPath(gridHome)} (0600) in the '
    'same step',
  );
  write(
    '  5. restart the store (runbook Appendix A step 4), then re-run this '
    'verb. One window, ever, per home.',
  );
}
