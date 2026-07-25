import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const allowedRuntimeDependencies = <String>{
  'flutter',
  'freezed_annotation',
  'grid_diagnostics_contract',
  'state_notifier',
};

const forbiddenImports = <String>{
  'package:grid_engine/',
  'package:beads_dart/',
  'package:devtools_extensions/',
  'package:vm_service/',
  'package:http/',
  'package:web_socket_channel/',
  'dart:io',
};

void main() {
  test('runtime dependencies are exactly transport-neutral dependencies', () {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final dependencyStart = lines.indexOf('dependencies:');
    final devDependencyStart = lines.indexOf('dev_dependencies:');
    final dependencies = <String>{};
    for (final line in lines.sublist(dependencyStart + 1, devDependencyStart)) {
      final match = RegExp(r'^  ([a-zA-Z0-9_]+):').firstMatch(line);
      if (match != null) dependencies.add(match.group(1)!);
    }
    expect(dependencies, allowedRuntimeDependencies);
    expect(
      dependencies,
      isNot(
        containsAll(<String>{
          'grid_engine',
          'beads_dart',
          'devtools_extensions',
          'vm_service',
          'http',
          'web_socket_channel',
        }),
      ),
    );
  });

  test('library imports no engine or transport implementation', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = entity.readAsStringSync();
      for (final forbidden in forbiddenImports) {
        if (contents.contains(forbidden)) {
          violations.add('${entity.path}: $forbidden');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('public barrel exports the five cockpit views', () {
    final library = File('lib/grid_cockpit_ui.dart').readAsStringSync();
    expect(library, contains("export 'src/views/circuit_pipeline_view.dart';"));
    expect(library, contains("export 'src/views/cost_tile.dart';"));
    expect(
      library,
      contains("export 'src/views/diagnostics_inspector_view.dart';"),
    );
    expect(library, contains("export 'src/views/station_overview_view.dart';"));
    expect(library, contains("export 'src/views/work_list_view.dart';"));
    expect(library, isNot(contains("export 'src/views/notifier_view.dart';")));
  });
}
