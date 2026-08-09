import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void seed(String root, {String body = '{"dolt_mode":"embedded"}'}) {
  final beads = Directory(p.join(root, '.beads'))..createSync(recursive: true);
  File(p.join(beads.path, 'metadata.json')).writeAsStringSync(body);
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('resident-state-'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('missing and empty roots are usage refusals', () {
    for (final value in [null, '', '  ']) {
      final result = resolveStateWorkspace(
        stationName: 'lunar',
        verb: 'status',
        stateWorkspacePath: value,
      );
      expect(result, isA<StateWorkspaceRefusal>());
      expect((result as StateWorkspaceRefusal).code, 64);
      expect(result.message, startsWith('lunar status:'));
    }
  });

  test('absent and ancestor-only stores refuse at the exact root', () {
    seed(temp.path);
    final child = Directory(p.join(temp.path, 'child'))..createSync();
    for (final home in [temp.path, child.path]) {
      final result = resolveStateWorkspace(
        stationName: 'lunar',
        verb: 'down',
        stateWorkspacePath: home,
      );
      expect(result, isA<StateWorkspaceRefusal>());
      expect((result as StateWorkspaceRefusal).code, 1);
      expect(result.message, startsWith('lunar down:'));
    }
  });

  test('malformed exact state store refuses with the caller prefix', () {
    seed(p.join(temp.path, '.grid'), body: '{not-json');

    final result = resolveStateWorkspace(
      stationName: 'lunar',
      verb: 'status',
      stateWorkspacePath: temp.path,
    );

    expect(result, isA<StateWorkspaceRefusal>());
    final refusal = result as StateWorkspaceRefusal;
    expect(refusal.code, 1);
    expect(refusal.message, startsWith('lunar status:'));
    expect(
      refusal.message,
      contains('could not open the exact grid state store'),
    );
  });

  test('exact state store returns canonical home and workspace', () {
    seed(p.join(temp.path, '.grid'));
    final result = resolveStateWorkspace(
      stationName: 'lunar',
      verb: 'status',
      stateWorkspacePath: '${temp.path}/.',
    );
    expect(result, isA<StateWorkspaceFound>());
    final found = result as StateWorkspaceFound;
    expect(found.home, p.canonicalize(temp.path));
    expect(found.workspace.root, p.join(temp.path, '.grid'));
  });

  test('helper delegates probing to the existing opener', () {
    final source = File('lib/src/state_workspace.dart').readAsStringSync();
    expect(source, isNot(contains('metadata.json')));
    expect(source, isNot(contains('BeadsWorkspace.discover')));
    expect(source, contains('openStateStore'));
  });
}
