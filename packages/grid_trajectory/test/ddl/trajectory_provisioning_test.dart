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

  test(
    'an existing secret is reused, never re-minted — and never ALTERed',
    () async {
      final first = await provisionTrajectoryUser(
        ScriptedDb(),
        gridHome: home.path,
      );
      final reuse = ScriptedDb();
      final second = await provisionTrajectoryUser(reuse, gridHome: home.path);
      expect(second.password, first.password);
      expect(reuse.matching('ALTER USER'), isEmpty);
    },
  );

  test(
    'a LOST secret is repaired: the fresh mint is pushed server-side via '
    'ALTER USER (CREATE USER IF NOT EXISTS never updates a password)',
    () async {
      final first = await provisionTrajectoryUser(
        ScriptedDb(),
        gridHome: home.path,
      );
      File(first.secretPath).deleteSync();

      final db = ScriptedDb();
      final second = await provisionTrajectoryUser(db, gridHome: home.path);

      expect(second.password, isNot(first.password));
      final alter = db.matching('ALTER USER').single;
      expect(alter.sql, contains("'trajectory'@'%'"));
      expect(alter.sql, contains(second.password));
      expect(File(second.secretPath).readAsStringSync(), second.password);
      if (!Platform.isWindows) {
        expect(File(second.secretPath).statSync().mode & 0x1FF, 0x180);
      }
    },
  );

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
