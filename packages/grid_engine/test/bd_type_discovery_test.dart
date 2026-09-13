// The bd `types --json` read every TYPE-SCOPED bd read is narrowed by. A
// scoped read refuses an unregistered type outright, so the type set is
// DISCOVERED from the store rather than assumed.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  test('configured type names accept omitted and mixed entry shapes', () {
    expect(configuredBdTypeNames(const <String, dynamic>{}), isEmpty);
    expect(
      configuredBdTypeNames(const <String, dynamic>{
        'custom_types': [
          'agent',
          {'name': 'step'},
        ],
      }),
      {'agent', 'step'},
    );
  });

  test('every named field is read, so core and custom types merge', () {
    expect(
      configuredBdTypeNames(
        const <String, dynamic>{
          'core_types': [
            {'name': 'task'},
          ],
          'custom_types': ['session'],
        },
        fields: const ['core_types', 'custom_types'],
      ),
      {'task', 'session'},
    );
  });

  test('configured type names refuse malformed present groups', () {
    expect(
      () => configuredBdTypeNames(const {'custom_types': 'agent'}),
      throwsA(isA<BdParseException>()),
    );
    expect(
      () => configuredBdTypeNames(const {
        'custom_types': [<String, dynamic>{}],
      }),
      throwsA(isA<BdParseException>()),
    );
  });
}
