import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/scripted_db.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('traj_prov_');
  });

  tearDown(() async {
    await home.delete(recursive: true);
  });

  test('creates the user and grants on trajectory.* ONLY; secret lands under '
      '.grid/trajectory/ at 0600', () async {
    final db = ScriptedDb();

    final credential = await provisionTrajectoryUser(db, gridHome: home.path);

    final create = db.matching('CREATE USER').single;
    expect(create.sql, contains("IF NOT EXISTS 'trajectory'@'%'"));
    final grant = db.matching('GRANT').single;
    expect(grant.sql, contains('ON trajectory.*'));
    expect(grant.sql, isNot(contains('*.*')));

    expect(
      credential.secretPath,
      p.join(home.path, '.grid', 'trajectory', 'trajectory.secret'),
    );
    final secret = File(credential.secretPath);
    expect(secret.readAsStringSync(), credential.password);
    expect(credential.password, hasLength(40));
    if (!Platform.isWindows) {
      expect(secret.statSync().mode & 0x1FF, 0x180); // rw-------
    }
  });

  test('an existing secret is reused, never re-minted', () async {
    final first = await provisionTrajectoryUser(
      ScriptedDb(),
      gridHome: home.path,
    );
    final second = await provisionTrajectoryUser(
      ScriptedDb(),
      gridHome: home.path,
    );
    expect(second.password, first.password);
  });

  test('a grid home resolving under .beads is refused', () async {
    await expectLater(
      provisionTrajectoryUser(
        ScriptedDb(),
        gridHome: p.join(home.path, '.beads', 'nested'),
      ),
      throwsArgumentError,
    );
  });
}
