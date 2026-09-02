import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

void main() {
  test('both shapes of one key compare equal to the writer string', () {
    for (final entry in <String, List<Object?>>{
      'attempt': <Object?>['3', 3],
      'flag': <Object?>['true', true],
      'ratio': <Object?>['1.5', 1.5],
      'nothing': <Object?>['null', null],
      'name': <Object?>['alpha', 'alpha'],
    }.entries) {
      final expected = entry.value.first! as String;
      for (final stored in entry.value) {
        expect(
          metadataEntryEquals(
            <String, dynamic>{entry.key: stored},
            entry.key,
            expected,
          ),
          isTrue,
          reason: '${entry.key} stored as $stored',
        );
      }
    }
  });

  test('an absent key never matches, and a mismatch stays false', () {
    expect(
      metadataEntryEquals(const <String, dynamic>{}, 'attempt', 'null'),
      isFalse,
    );
    expect(
      metadataEntryEquals(
        const <String, dynamic>{'attempt': 4},
        'attempt',
        '3',
      ),
      isFalse,
    );
  });

  test("metadataScalarText renders the SQL leg's JSON_UNQUOTE text", () {
    expect(metadataScalarText('alpha'), 'alpha');
    expect(metadataScalarText(3), '3');
    expect(metadataScalarText(true), 'true');
    expect(metadataScalarText(null), 'null');
  });
}
