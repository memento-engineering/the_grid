// tg-nsj: discoverWorkspaces over N LOCAL beads workspaces (D-F4) — hermetic
// temp `.beads/` dirs, no network, no `bd` process. Mirrors the
// `BeadsWorkspace.discover` hermetic-temp-dir pattern (beads_dart's own
// `beads_workspace_test.dart`).
import 'dart:io';

import 'package:grid_cli/src/station_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('discoverWorkspaces (hermetic temp dirs)', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('grid_ws_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String makeStore(String name) {
      final dir = Directory(p.join(tmp.path, name))..createSync();
      Directory(p.join(dir.path, '.beads')).createSync();
      return dir.path;
    }

    test('N named workspaces resolve into a Map keyed by substation id (the '
        'office-grid example: tg + butane_flutter + dash)', () {
      final tg = makeStore('tg');
      final butane = makeStore('butane_flutter');
      final dash = makeStore('dash');

      final ws = discoverWorkspaces(
        workspaces: {'tg': tg, 'butane_flutter': butane, 'dash': dash},
      );

      expect(ws.work.keys, {'tg', 'butane_flutter', 'dash'});
      expect(ws.work['tg']!.root, tg);
      expect(ws.work['butane_flutter']!.root, butane);
      expect(ws.work['dash']!.root, dash);
      expect(ws.state, isNull);
    });

    test('a named workspace that resolves to no `.beads/` throws a '
        'StationRefusal naming the substation', () {
      expect(
        () => discoverWorkspaces(
          workspaces: {'dash': p.join(tmp.path, 'nowhere')},
        ),
        throwsA(
          isA<StationRefusal>().having(
            (r) => r.message,
            'message',
            allOf(contains('"dash"'), contains('--workspace')),
          ),
        ),
      );
    });

    test('a --state-workspace that resolves to no `.beads/` throws a '
        'StationRefusal', () {
      final tg = makeStore('tg');
      expect(
        () => discoverWorkspaces(
          workspaces: {'tg': tg},
          stateWorkspacePath: p.join(tmp.path, 'nowhere'),
        ),
        throwsA(
          isA<StationRefusal>().having(
            (r) => r.message,
            'message',
            contains('--state-workspace'),
          ),
        ),
      );
    });

    test('a --state-workspace that DOES resolve is returned as state', () {
      final tg = makeStore('tg');
      final state = makeStore('tgdog');
      final ws = discoverWorkspaces(
        workspaces: {'tg': tg},
        stateWorkspacePath: state,
      );
      expect(ws.state, isNotNull);
      expect(ws.state!.root, state);
    });
  });
}
