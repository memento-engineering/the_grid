import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _directBinarySpawn = RegExp(
  r'''Process\.(?:runSync|startSync|run|start)\s*\(\s*(['"])(?:bd|dolt)\1''',
  multiLine: true,
);

List<String> _offlineBinaryViolations(Directory testRoot) {
  final integrationRoot = p.absolute(
    p.normalize(p.join(testRoot.path, 'integration')),
  );
  final violations = <String>[];

  for (final entity in testRoot.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final filePath = p.absolute(p.normalize(entity.path));
    if (p.isWithin(integrationRoot, filePath)) continue;
    if (_directBinarySpawn.hasMatch(entity.readAsStringSync())) {
      violations.add(entity.path);
    }
  }

  return violations..sort();
}

void main() {
  test('offline tests do not launch bd or dolt directly', () {
    final violations = _offlineBinaryViolations(Directory('test'));

    expect(
      violations,
      isEmpty,
      reason:
          'Offline tests must not launch bd or dolt directly:\n'
          '${violations.join('\n')}',
    );
  });
}
