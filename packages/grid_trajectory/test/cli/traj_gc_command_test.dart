/// `traj gc` — tg-3o6b item 2: reclamation as an OPERATOR action under the
/// gridboot credential, with the service grant left exactly as ratified.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

void main() {
  late Directory home;
  late ScriptedDb db;
  late List<TrajectoryEndpoint> dialed;
  late List<String> out;
  late List<String> err;

  DoltServerListener resolve(String gridHome) => const DoltServerListener(
    host: '127.0.0.1',
    port: 3307,
    configPath: '/dev/null',
  );

  void seedGridboot(String secret) {
    final file = File(gridbootSecretPath(home.path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(secret);
  }

  Future<int> gc() => runTrajGc(
    gridHome: home.path,
    connect: (endpoint) async {
      dialed.add(endpoint);
      return db;
    },
    resolve: resolve,
    out: out.add,
    err: err.add,
  );

  setUp(() {
    home = Directory.systemTemp.createTempSync('traj-gc-');
    db = ScriptedDb();
    dialed = [];
    out = [];
    err = [];
  });

  tearDown(() => home.deleteSync(recursive: true));

  test('collects as GRIDBOOT on the trajectory database, and closes', () async {
    seedGridboot('boot-pw\n');
    expect(await gc(), 0);
    expect(db.log.single.sql, 'CALL DOLT_GC()');
    expect(dialed.single.user, gridbootUser);
    expect(dialed.single.password, 'boot-pw');
    expect(dialed.single.database, 'trajectory');
    expect(dialed.single.port, 3307);
    expect(db.closed, isTrue);
    expect(out.join('\n'), contains('collected:'));
  });

  test('never reads the SERVICE secret — the scoped grant is not the '
      'credential and is never widened', () async {
    seedGridboot('boot-pw');
    File(trajectorySecretPath(home.path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('service-pw');
    expect(await gc(), 0);
    expect(dialed.single.password, isNot('service-pw'));
    expect(db.matching('GRANT'), isEmpty);
    expect(db.matching('CREATE USER'), isEmpty);
  });

  test('a home without the bootstrap credential is refused, pointing at the '
      'ONE offline window — never at a wider grant', () async {
    expect(await gc(), 1);
    expect(err.join('\n'), contains('gridboot.secret'));
    expect(err.join('\n'), contains('step-1b'));
    expect(err.join('\n'), contains('trajectory.* only'));
    expect(dialed, isEmpty);
  });

  test('an empty bootstrap secret refuses without dialing', () async {
    seedGridboot('   \n');
    expect(await gc(), 1);
    expect(err.join('\n'), contains('empty bootstrap secret'));
    expect(dialed, isEmpty);
  });

  test(
    'a denied gridboot names the missing GRANT rather than retrying',
    () async {
      seedGridboot('boot-pw');
      db.on(
        'CALL DOLT_GC()',
        throwing: MySQLServerException(
          "command denied to user 'gridboot'@'%'",
          1105,
        ),
      );
      expect(await gc(), 1);
      expect(err.join('\n'), contains('GRANT ALL ON *.*'));
      expect(db.closed, isTrue, reason: 'the session closes on the error path');
    },
  );

  test(
    'the grid home is required and a positional is a usage refusal',
    () async {
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(
          TrajGcCommand(connect: (_) async => ScriptedDb(), resolve: resolve),
        );
      expect(await runner.run(['gc']), 64);
      expect(
        await runner.run(['gc', 'stray', '--state-workspace', '/tmp']),
        64,
      );
    },
  );
}
