// §2.6 rule 4: every type version ships a golden JSON fixture with a
// round-trip test; CI diffs fixtures. The checked-in files are the oracle —
// a payload-shape change without a type_version bump (and its NEW fixture
// file) fails here.

import 'dart:convert';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/fixture_support.dart';

void main() {
  final fixtureDir = Directory('test/fixtures');
  final fixtureFiles =
      fixtureDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test(
    'every registered (record_type, type_version) has exactly one fixture',
    () {
      final fixtureKeys = fixtureFiles.map((file) {
        final name = file.uri.pathSegments.last;
        final match = RegExp(r'^(.+)\.v(\d+)\.json$').firstMatch(name)!;
        return (match.group(1)!, int.parse(match.group(2)!));
      }).toSet();
      expect(fixtureKeys, equals(TrajectoryCodec.decoders.keys.toSet()));
      expect(fixtureFiles, hasLength(TrajectoryCodec.decoders.length));
    },
  );

  for (final file in fixtureFiles) {
    final name = file.uri.pathSegments.last;
    test('round-trips $name through the registry', () {
      final fixture = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, Object?>();
      final decoded = TrajectoryCodec.decode(envelopeFor(fixture));

      // Registry dispatch: a golden fixture must reach its typed decoder.
      expect(
        decoded,
        isNot(isA<OpaqueRecord>()),
        reason: (decoded is OpaqueRecord) ? decoded.decodeFailure : null,
      );
      expect(decoded.recordType, fixture['record_type']);
      expect(decoded.typeVersion, fixture['type_version']);
      expect(decoded.family.wire, fixture['family']);

      // Decode → encode fidelity, both halves of the row.
      expect(
        jsonDecode(jsonEncode(decoded.payloadToJson())),
        equals(fixture['payload']),
      );
      expect(
        jsonDecode(jsonEncode(decoded.correlationToJson())),
        equals(fixture['envelope']),
      );

      // The §5 grammar builder is pinned by the golden key, text and hash.
      expect(decoded.idemKeyText(fixtureContext), fixture['idem_key_text']);
      expect(decoded.idemKey(fixtureContext), fixture['idem_key']);
    });
  }

  group('rule 3 — replay never throws', () {
    TrajectoryEnvelope envelope({
      required String recordType,
      int typeVersion = 1,
      Map<String, Object?> payload = const {},
    }) => TrajectoryEnvelope(
      recordId: '01FIXTURE0000000000000RECD',
      idemKey: 'x' * 64,
      idemKeyText: 'opaque-probe',
      family: TrajectoryFamily.attempt,
      recordType: recordType,
      typeVersion: typeVersion,
      occurredAt: DateTime.utc(2026, 8, 31, 12),
      recordedAt: DateTime.utc(2026, 8, 31, 12),
      station: 'lunar',
      authorityId: 'lunar/7',
      bootEpoch: 7,
      source: 'fixture',
      payload: payload,
    );

    test('an unregistered record_type decodes to OpaqueRecord', () {
      final decoded = TrajectoryCodec.decode(
        envelope(recordType: 'attempt.unheard_of'),
      );
      expect(decoded, isA<OpaqueRecord>());
      expect((decoded as OpaqueRecord).decodeFailure, isNull);
    });

    test('a future type_version of a known type decodes to OpaqueRecord', () {
      final decoded = TrajectoryCodec.decode(
        envelope(recordType: 'attempt.note', typeVersion: 99),
      );
      expect(decoded, isA<OpaqueRecord>());
      expect((decoded as OpaqueRecord).decodeFailure, isNull);
    });

    test('a malformed payload of a known pair decodes to OpaqueRecord with '
        'the failure recorded', () {
      final decoded = TrajectoryCodec.decode(
        envelope(recordType: 'attempt.note', payload: {'body': 42}),
      );
      expect(decoded, isA<OpaqueRecord>());
      final opaque = decoded as OpaqueRecord;
      expect(opaque.decodeFailure, isNotNull);
      expect(opaque.rawPayload, equals({'body': 42}));
    });
  });
}
