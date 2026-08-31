/// Provisioning for the trajectory service's write-capable SQL user.
///
/// The trajectory-direct-sql-scope decision, made mechanical: a NEW
/// credential, granted on `trajectory.*` ONLY — never `*.*`, never the ledger
/// database — and its secret lives under the grid home's `.grid/trajectory/`
/// (mode 0600), NEVER under `.beads/` (bd's proxy secret files are bd's; the
/// read-only `beads_dart` secret is never widened or reused).
library;

import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../connect/trajectory_db.dart';

/// The SQL user this package provisions and connects as.
const String trajectoryUser = 'trajectory';

/// Where [provisionTrajectoryUser] persists the secret. The read path resolves
/// the same file, so the two can never drift onto different conventions.
String trajectorySecretPath(String gridHome) =>
    p.join(gridHome, '.grid', 'trajectory', 'trajectory.secret');

/// The provisioned identity plus where its secret persists.
@immutable
class TrajectoryCredential {
  const TrajectoryCredential({
    required this.user,
    required this.password,
    required this.secretPath,
  });

  final String user;
  final String password;
  final String secretPath;
}

/// Idempotently provisions the `trajectory` SQL user on [serverConn] (a
/// server-level session) and persists its secret under
/// `<gridHome>/.grid/trajectory/trajectory.secret`.
///
/// An existing secret is reused (re-boots re-grant, never re-mint), so the
/// user's server-side password and the on-disk secret cannot drift apart
/// through this path.
Future<TrajectoryCredential> provisionTrajectoryUser(
  TrajectoryDb serverConn, {
  required String gridHome,
  String user = trajectoryUser,
}) async {
  final secretFile = File(trajectorySecretPath(gridHome));
  final secretDir = p.dirname(secretFile.path);
  if (p.split(secretDir).contains('.beads')) {
    throw ArgumentError.value(
      gridHome,
      'gridHome',
      'the trajectory secret must never live under .beads',
    );
  }

  final String password;
  var minted = false;
  if (secretFile.existsSync()) {
    password = secretFile.readAsStringSync().trim();
    if (password.isEmpty) {
      throw StateError('empty trajectory secret: ${secretFile.path}');
    }
  } else {
    password = _mintPassword();
    minted = true;
    Directory(secretDir).createSync(recursive: true);
    secretFile.writeAsStringSync(password, flush: true);
    await _chmod600(secretFile.path);
  }

  // Wildcard host: dolt's auto root@localhost cannot authenticate over the
  // 127.0.0.1 TCP address the client dials (hermetic_dolt_server precedent).
  await serverConn.execute(
    "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$password'",
  );
  // A lost secret must be repairable: CREATE USER IF NOT EXISTS never
  // updates an existing user's password (measured on dolt 2.2), so a
  // re-minted secret would otherwise strand the station behind 1045 forever.
  // ALTER USER re-aligns the server to the fresh secret; on the fresh-user
  // path it is a same-value no-op.
  if (minted) {
    await serverConn.execute(
      "ALTER USER '$user'@'%' IDENTIFIED BY '$password'",
    );
  }
  // trajectory.* only — the scope IS the decision; widening it to *.* would
  // hand this credential the ledger database.
  await serverConn.execute(
    "GRANT ALL PRIVILEGES ON trajectory.* TO '$user'@'%'",
  );

  return TrajectoryCredential(
    user: user,
    password: password,
    secretPath: secretFile.path,
  );
}

/// 40 chars of URL-safe alphanumerics from a CSPRNG — quote-free by
/// construction so the CREATE USER literal cannot be malformed.
String _mintPassword() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes(
    List.generate(
      40,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ),
  );
}

Future<void> _chmod600(String path) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['600', path]);
  if (result.exitCode != 0) {
    throw StateError('chmod 600 $path failed: ${result.stderr}');
  }
}
