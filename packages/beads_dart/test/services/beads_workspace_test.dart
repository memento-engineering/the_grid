import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('BeadsWorkspace.discover (hermetic temp dirs)', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('grid_ws_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeBeads(Map<String, String> files) {
      final beads = Directory(p.join(tmp.path, '.beads'))..createSync();
      files.forEach((name, content) {
        File(p.join(beads.path, name)).writeAsStringSync(content);
      });
    }

    test('server mode resolves an endpoint from the dolt pack config', () {
      // Lay down a city root with the gc dolt-config.yaml.
      final cityRoot = Directory(p.join(tmp.path, 'city'))..createSync();
      final packDir = Directory(
        p.join(cityRoot.path, '.gc', 'runtime', 'packs', 'dolt'),
      )..createSync(recursive: true);
      File(p.join(packDir.path, 'dolt-config.yaml')).writeAsStringSync('''
listener:
  port: 34947
  host: 0.0.0.0
''');
      writeBeads({
        'metadata.json':
            '{"dolt_mode":"server","dolt_database":"tg","backend":"dolt"}',
        '.env': 'GT_ROOT=${cityRoot.path}\n',
      });

      final ws = BeadsWorkspace.discover(
        start: tmp.path,
        env: {'GC_DOLT_PASSWORD': 'secret', 'GC_DOLT_USER': 'grid'},
      );
      expect(ws, isNotNull);
      expect(ws!.mode, DoltMode.server);
      expect(ws.database, 'tg');
      expect(ws.endpoint, isNotNull);
      expect(ws.endpoint!.host, '127.0.0.1'); // 0.0.0.0 → loopback for clients
      expect(ws.endpoint!.port, 34947);
      expect(ws.endpoint!.user, 'grid');
      expect(ws.endpoint!.hasCredential, isTrue);
    });

    test('direct mode yields a null endpoint (bd CLI fallback)', () {
      writeBeads({
        'metadata.json': '{"dolt_mode":"direct","dolt_database":"tg"}',
      });
      final ws = BeadsWorkspace.discover(start: tmp.path, env: const {});
      expect(ws, isNotNull);
      expect(ws!.mode, DoltMode.direct);
      expect(ws.endpoint, isNull);
    });

    test(
      'missing credential resolves an endpoint with hasCredential false',
      () {
        final cityRoot = Directory(p.join(tmp.path, 'city'))..createSync();
        final packDir = Directory(
          p.join(cityRoot.path, '.gc', 'runtime', 'packs', 'dolt'),
        )..createSync(recursive: true);
        File(
          p.join(packDir.path, 'dolt-config.yaml'),
        ).writeAsStringSync('listener:\n  port: 34947\n  host: 0.0.0.0\n');
        writeBeads({
          'metadata.json': '{"dolt_mode":"server","dolt_database":"tg"}',
          '.env': 'GT_ROOT=${cityRoot.path}\n',
        });
        final ws = BeadsWorkspace.discover(start: tmp.path, env: const {});
        expect(ws!.endpoint, isNotNull);
        expect(ws.endpoint!.user, 'root');
        expect(ws.endpoint!.hasCredential, isFalse);
      },
    );

    test('returns null when no .beads/ exists anywhere up-tree', () {
      final isolated = Directory.systemTemp.createTempSync('grid_none_');
      addTearDown(() => isolated.deleteSync(recursive: true));
      expect(BeadsWorkspace.discover(start: isolated.path), isNull);
    });
  });
}
