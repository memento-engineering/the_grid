import 'dart:io';

import 'package:test/test.dart';

Directory _workspaceRoot() {
  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth += 1) {
    if (File(
      '${directory.path}/packages/grid_engine/pubspec.yaml',
    ).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('could not locate the_grid workspace root');
}

Iterable<File> _dartFiles(Directory root) => root
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

void main() {
  test('G2 foundation preserves package, emitter, and inert-default fences', () {
    final workspace = _workspaceRoot();
    final anchors = <String>[
      'packages/grid_engine/lib/src/molecule/molecule_codec.dart',
      'packages/grid_runtime/lib/src/trajectory/canonical_molecule_graph.dart',
      'packages/grid_trajectory/lib/src/codec/records/step_records.dart',
      'packages/grid_sdk/lib/src/trajectory/trajectory_config.dart',
    ];
    for (final anchor in anchors) {
      expect(
        File('${workspace.path}/$anchor').existsSync(),
        isTrue,
        reason: 'source guard anchor must exist: $anchor',
      );
    }

    final engineLib = Directory('${workspace.path}/packages/grid_engine/lib');
    final runtimeLib = Directory('${workspace.path}/packages/grid_runtime/lib');
    final enginePackage = Directory('${workspace.path}/packages/grid_engine');
    final packageRoot = Directory('${workspace.path}/packages');
    expect(engineLib.existsSync(), isTrue);
    expect(runtimeLib.existsSync(), isTrue);
    expect(enginePackage.existsSync(), isTrue);
    expect(packageRoot.existsSync(), isTrue);

    final engineLibraries = _dartFiles(engineLib).toList(growable: false);
    expect(engineLibraries, isNotEmpty);
    final trajectoryImport = RegExp(
      r'''import\s+['"]package:grid_trajectory''',
    );
    for (final file in engineLibraries) {
      expect(
        file.readAsStringSync(),
        isNot(matches(trajectoryImport)),
        reason:
            'grid_engine reaches trajectory only through grid_runtime: ${file.path}',
      );
    }

    final pouredConstructor = ['Molecule', 'Poured', r'\s*\('].join();
    final supersededConstructor = ['Step', 'Superseded', r'\s*\('].join();
    final forbiddenEmitter = RegExp(
      '($pouredConstructor|$supersededConstructor)',
    );
    final engineEmitterScope = _dartFiles(
      enginePackage,
    ).toList(growable: false);
    expect(engineEmitterScope, isNotEmpty);
    for (final file in engineEmitterScope) {
      expect(
        file.readAsStringSync(),
        isNot(matches(forbiddenEmitter)),
        reason: 'grid_engine never constructs trajectory records: ${file.path}',
      );
    }

    final recorderPath =
        '${workspace.path}/packages/grid_runtime/lib/src/trajectory/'
        'station_trajectory_recorder.dart';
    for (final file in _dartFiles(runtimeLib)) {
      final source = file.readAsStringSync();
      if (file.path == recorderPath) {
        expect(RegExp(pouredConstructor).allMatches(source), hasLength(1));
        expect(RegExp(supersededConstructor).allMatches(source), hasLength(1));
      } else {
        expect(
          source,
          isNot(matches(forbiddenEmitter)),
          reason:
              'only the station recorder constructs G2 records: ${file.path}',
        );
      }
    }

    final nonOffDefault = RegExp(
      r'=\s*(?:G2Posture|G2EmissionMode)\.(?:shadow|cut)\b',
    );
    final productionLibraries = <File>[
      for (final package in packageRoot.listSync().whereType<Directory>())
        if (Directory('${package.path}/lib').existsSync())
          ..._dartFiles(Directory('${package.path}/lib')),
    ];
    expect(productionLibraries, isNotEmpty);
    for (final file in productionLibraries) {
      expect(
        file.readAsStringSync(),
        isNot(matches(nonOffDefault)),
        reason: 'G2 production defaults remain off: ${file.path}',
      );
    }
  });
}
