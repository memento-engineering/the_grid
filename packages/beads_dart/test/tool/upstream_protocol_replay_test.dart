import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

const protocolRoot = String.fromEnvironment('BD_PROTOCOL_ROOT');

void main() {
  group(
    'upstream protocol corpus replay',
    () {
      late Directory corpus;
      late Map<String, dynamic> blobs;

      setUpAll(() {
        corpus = Directory('$protocolRoot/testdata/corpus');
        expect(corpus.existsSync(), isTrue, reason: corpus.path);
        final manifestFile = File('${corpus.path}/manifest.json');
        final decoded = jsonDecode(manifestFile.readAsStringSync());
        expect(decoded, isA<Map<String, dynamic>>());
        final manifest = decoded as Map<String, dynamic>;
        expect(manifest['schema_version'], kBdSchemaVersion);
        expect(manifest['blobs'], isA<Map<String, dynamic>>());
        blobs = manifest['blobs'] as Map<String, dynamic>;
      });

      test('manifest inventory is exact and variants are symmetric', () {
        final declared = blobs.keys.toSet();
        final actual = corpus
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .map(
              (file) => file.path
                  .substring(corpus.path.length + 1)
                  .replaceAll(Platform.pathSeparator, '/')
                  .replaceFirst(RegExp(r'\.json$'), ''),
            )
            .where((key) => key != 'manifest')
            .toSet();
        expect(actual, declared);

        final flatNames = {
          for (final key in declared)
            if (key.startsWith('flat/')) key.substring('flat/'.length),
        };
        final envelopeNames = {
          for (final key in declared)
            if (key.startsWith('envelope/')) key.substring('envelope/'.length),
        };
        expect(flatNames, envelopeNames);
        expect(declared.length, flatNames.length * 2);
      });

      test('every flat and envelope pair decodes to the same value', () {
        final names =
            blobs.keys
                .where((key) => key.startsWith('flat/'))
                .map((key) => key.substring('flat/'.length))
                .toList()
              ..sort();

        for (final name in names) {
          try {
            final flat = BdEnvelope.parseFlat(
              File('${corpus.path}/flat/$name.json').readAsStringSync(),
            );
            final envelope = BdEnvelope.parse(
              File('${corpus.path}/envelope/$name.json').readAsStringSync(),
            );
            expect(flat.schemaVersion, envelope.schemaVersion);
            expect(flat.data, envelope.data, reason: 'corpus key: $name');
          } catch (error, stackTrace) {
            fail('corpus key $name failed replay: $error\n$stackTrace');
          }
        }
      });
    },
    skip: protocolRoot.isEmpty
        ? 'BD_PROTOCOL_ROOT not supplied; A1 supplies it on compatibility rails'
        : false,
  );
}
