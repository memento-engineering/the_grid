import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _directBinarySpawn = RegExp(
  r'''Process\.(?:runSync|startSync|run|start)\s*\(\s*(['"])(?:bd|dolt)\1''',
  multiLine: true,
);

const _processRunToken = 'Process.run';
const _directBdSpawnFixture =
    '''
import 'dart:io';

Future<void> main() async {
  await $_processRunToken('bd', const <String>[]);
}
''';

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

  group('_offlineBinaryViolations', () {
    late Directory testRoot;

    setUp(() {
      testRoot = Directory.systemTemp.createTempSync(
        'offline_binary_boundary_test.',
      );
    });

    tearDown(() {
      testRoot.deleteSync(recursive: true);
    });

    test('flags a direct bd spawn outside integration', () {
      final fixture = File(p.join(testRoot.path, 'direct_bd_spawn_test.dart'))
        ..writeAsStringSync(_directBdSpawnFixture);

      expect(_offlineBinaryViolations(testRoot), <String>[fixture.path]);
    });

    test('ignores a direct bd spawn under integration', () {
      final integrationRoot = Directory(p.join(testRoot.path, 'integration'))
        ..createSync();
      File(
        p.join(integrationRoot.path, 'direct_bd_spawn_test.dart'),
      ).writeAsStringSync(_directBdSpawnFixture);

      expect(_offlineBinaryViolations(testRoot), isEmpty);
    });
  });
}
