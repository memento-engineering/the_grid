import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const allowedRuntimeDependencies = <String>{
  'flutter',
  'freezed_annotation',
  'genesis_foundation',
  'grid_cockpit_ui',
  'grid_diagnostics_contract',
  'web_socket_channel',
};

const forbiddenText = <String>{
  'dart:io',
  'package:vm_service/',
  'package:dtd/',
  'package:devtools_extensions/',
  'package:multicast_dns/',
  'package:bonsoir/',
  'package:nsd/',
  'grid_cockpit_contract',
};

const forbiddenPackages = <String>{
  'vm_service',
  'dtd',
  'devtools_extensions',
  'multicast_dns',
  'bonsoir',
  'nsd',
  'grid_cockpit_contract',
};

void main() {
  test('runtime dependencies are exactly the shared client boundary', () {
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

  test('library remains browser safe and contains no retired contracts', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = entity.readAsStringSync();
      for (final forbidden in forbiddenText) {
        if (contents.contains(forbidden)) {
          violations.add('${entity.path}: $forbidden');
        }
      }
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final forbidden in forbiddenText) {
      if (pubspec.contains(forbidden)) {
        violations.add('pubspec.yaml: $forbidden');
      }
    }
    for (final package in forbiddenPackages) {
      if (pubspec.contains('\n  $package:')) {
        violations.add('pubspec.yaml: $package');
      }
    }
    expect(violations, isEmpty);
  });
}
