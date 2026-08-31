import 'dart:convert';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('traj_cfg_');
  });

  tearDown(() async {
    await home.delete(recursive: true);
  });

  void writeConfig(String relative, {required int port}) {
    final file = File(p.join(home.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      'log_level: info\n'
      'listener:\n'
      '  host: 127.0.0.1\n'
      '  port: $port\n'
      '  max_connections: 100\n',
    );
  }

  test('plain layout: .grid/.beads/dolt/config.yaml wins', () {
    writeConfig('.grid/.beads/dolt/config.yaml', port: 34951);

    final listener = resolveDoltServerListener(home.path);

    expect(listener.host, '127.0.0.1');
    expect(listener.port, 34951);
    expect(listener.configPath, endsWith('dolt/config.yaml'));
  });

  test('proxied layout: the proxy root config.yaml wins over the outer '
      'dolt/config.yaml', () {
    writeConfig('.grid/.beads/dolt/config.yaml', port: 34951);
    writeConfig('.grid/.beads/proxieddb/config.yaml', port: 51156);
    File(
      p.join(home.path, '.grid/.beads/proxied_server_client_info.json'),
    ).writeAsStringSync(jsonEncode({'root_path': 'proxieddb'}));

    final listener = resolveDoltServerListener(home.path);

    expect(listener.port, 51156);
    expect(listener.configPath, contains('proxieddb'));
  });

  test('no config at all fails loudly, naming every path probed', () {
    expect(
      () => resolveDoltServerListener(home.path),
      throwsA(
        isA<TrajectoryConfigException>().having(
          (e) => e.probed.single,
          'probed',
          endsWith(p.join('.beads', 'dolt', 'config.yaml')),
        ),
      ),
    );
  });

  test('a config without a complete listener fails loudly', () {
    final file = File(p.join(home.path, '.grid/.beads/dolt/config.yaml'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('log_level: info\nlistener:\n  host: 127.0.0.1\n');

    expect(
      () => resolveDoltServerListener(home.path),
      throwsA(
        isA<TrajectoryConfigException>().having(
          (e) => e.message,
          'message',
          contains('no complete listener'),
        ),
      ),
    );
  });
}
