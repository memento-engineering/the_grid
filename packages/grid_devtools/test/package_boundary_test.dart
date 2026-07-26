import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime imports stay outside controller and beads packages', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = entity.readAsStringSync();
      if (contents.contains('package:grid_controller/') ||
          contents.contains('package:beads_dart/') ||
          contents.contains('package:grid_cli/') ||
          contents.contains("import 'dart:io'") ||
          contents.contains('import "dart:io"')) {
        violations.add(entity.path);
      }
    }
    expect(violations, isEmpty);
  });
}
