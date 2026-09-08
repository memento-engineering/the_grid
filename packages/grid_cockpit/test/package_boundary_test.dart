import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const allowedRuntimeDependencies = <String>{
  'flutter',
  'freezed_annotation',
  'grid_cockpit_ui',
  'grid_diagnostics_contract',
  'grid_station_client',
};

const forbiddenText = <String>{
  'package:vm_service/',
  'package:dtd/',
  'package:devtools_extensions/',
  'dart:html',
  'package:web/',
  'package:multicast_dns/',
  'package:bonsoir/',
  'package:nsd/',
  'grid_cockpit_contract',
};

const forbiddenPackages = <String>{
  'vm_service',
  'dtd',
  'devtools_extensions',
  'web',
  'multicast_dns',
  'bonsoir',
  'nsd',
  'grid_cockpit_contract',
};

void main() {
  test('runtime dependencies are exactly the desktop cockpit boundary', () {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final dependencyStart = lines.indexOf('dependencies:');
    final devDependencyStart = lines.indexOf('dev_dependencies:');
    final dependencies = <String>{};
    for (final line in lines.sublist(dependencyStart + 1, devDependencyStart)) {
      final match = RegExp(r'^  ([a-zA-Z0-9_]+):').firstMatch(line);
      if (match != null) dependencies.add(match.group(1)!);
    }
    expect(dependencies, allowedRuntimeDependencies);
  });

  test('only the current-directory adapter imports dart:io', () {
    final ioImports = <String>[];
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = entity.readAsStringSync();
      if (contents.contains("import 'dart:io';") ||
          contents.contains('import "dart:io";')) {
        ioImports.add(entity.path);
      }
      for (final forbidden in forbiddenText) {
        if (contents.contains(forbidden)) {
          violations.add('${entity.path}: $forbidden');
        }
      }
      if (contents.contains('print(')) violations.add('${entity.path}: print');
    }

    expect(ioImports, ['lib/src/current_directory_station_discovery.dart']);
    expect(violations, isEmpty);
  });

  test(
    'pubspec excludes browser, tooling, discovery, and retired packages',
    () {
      final contents = File('pubspec.yaml').readAsStringSync();
      for (final forbidden in forbiddenText) {
        expect(contents, isNot(contains(forbidden)));
      }
      for (final package in forbiddenPackages) {
        expect(contents, isNot(contains('\n  $package:')));
      }
    },
  );

  test('both macOS targets disable the application sandbox', () {
    for (final path in <String>[
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final contents = File(path).readAsStringSync();
      expect(
        contents,
        contains('<key>com.apple.security.app-sandbox</key>\n\t<false/>'),
      );
    }
  });
}
