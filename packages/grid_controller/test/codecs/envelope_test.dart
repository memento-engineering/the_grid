import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  group('BdEnvelope.parse', () {
    test('list-returning command exposes dataList', () {
      final env = BdEnvelope.parse(fixtureText('tg-list-all-empty.json'));
      expect(env.schemaVersion, kBdSchemaVersion);
      expect(env.dataList, isEmpty);
    });

    test('object-returning command exposes dataMap', () {
      final env = BdEnvelope.parse(fixtureText('tg-statuses.json'));
      expect(env.dataMap.containsKey('built_in_statuses'), isTrue);
    });

    test('error envelope (on stdout) is still a valid envelope', () {
      // A3: bd errors arrive enveloped on stdout with schema_version 1.
      final env = BdEnvelope.parse(fixtureText('tg-error-stdout.json'));
      expect(env.schemaVersion, 1);
      expect(env.errorMessage, contains('no issue found'));
    });

    test('malformed JSON throws BdParseException', () {
      expect(
        () => BdEnvelope.parse('{not json'),
        throwsA(isA<BdParseException>()),
      );
    });

    test('missing schema_version throws BdParseException', () {
      expect(
        () => BdEnvelope.parse('{"data": []}'),
        throwsA(isA<BdParseException>()),
      );
    });

    test('wrong schema_version throws BdSchemaDriftException', () {
      expect(
        () => BdEnvelope.parse('{"schema_version": 2, "data": []}'),
        throwsA(
          isA<BdSchemaDriftException>()
              .having((e) => e.found, 'found', 2)
              .having((e) => e.expected, 'expected', 1),
        ),
      );
    });

    test('dataList throws on shape mismatch', () {
      final env = BdEnvelope.parse('{"schema_version": 1, "data": {}}');
      expect(() => env.dataList, throwsA(isA<BdParseException>()));
    });
  });

  group('BdCommandFailed.fromOutput (A3 channel order)', () {
    test('reads error from stdout envelope first', () {
      final fail = BdCommandFailed.fromOutput(
        command: ['bd', 'dep', 'list', 'tg-nonexistent', '--json'],
        exitCode: 1,
        stdout: fixtureText('tg-error-stdout.json'),
        stderr: '',
      );
      expect(fail.message, contains('no issue found'));
      expect(fail.exitCode, 1);
    });

    test('falls back to stderr when stdout has no envelope error', () {
      final fail = BdCommandFailed.fromOutput(
        command: ['bd', 'boom'],
        exitCode: 2,
        stdout: '',
        stderr: 'fatal: kaboom',
      );
      expect(fail.message, 'fatal: kaboom');
    });

    test('falls back to raw stdout when neither has structure', () {
      final fail = BdCommandFailed.fromOutput(
        command: ['bd', 'boom'],
        exitCode: 3,
        stdout: 'plain text failure',
        stderr: '',
      );
      expect(fail.message, 'plain text failure');
    });

    test('synthesizes a message when there is no output at all', () {
      final fail = BdCommandFailed.fromOutput(
        command: ['bd', 'boom'],
        exitCode: 9,
        stdout: '',
        stderr: '',
      );
      expect(fail.message, contains('exited 9'));
    });
  });
}
