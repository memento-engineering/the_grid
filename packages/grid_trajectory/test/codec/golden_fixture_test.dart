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

  Map<String, Object?> read(File file) =>
      (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();

  ({String type, int version}) keyOf(File file) {
    final match = RegExp(
      r'^(.+)\.v(\d+)\.json$',
    ).firstMatch(file.uri.pathSegments.last)!;
    return (type: match.group(1)!, version: int.parse(match.group(2)!));
  }

  // Rule 2 lets ONE type carry several live versions at once (the I1 gen_ai
  // rename: verify.usage.telemetry v1 + v2). So the bijection is stated per
  // type — the exact registered version SET must be the exact fixture set —
  // rather than as a flat key comparison that would read a second version as
  // a stray file.
  test('every type ships a fixture for exactly its registered version set', () {
    Map<String, Set<int>> versionsPerType(Iterable<(String, int)> keys) {
      final byType = <String, Set<int>>{};
      for (final (type, version) in keys) {
        (byType[type] ??= <int>{}).add(version);
      }
      return byType;
    }

    final fixtures = versionsPerType(
      fixtureFiles.map((file) {
        final key = keyOf(file);
        return (key.type, key.version);
      }),
    );
    expect(fixtures, equals(versionsPerType(TrajectoryCodec.decoders.keys)));
    // No duplicate files hiding inside a set comparison.
    expect(fixtureFiles, hasLength(TrajectoryCodec.decoders.length));
  });

  for (final file in fixtureFiles) {
    final name = file.uri.pathSegments.last;
    test('round-trips $name through the registry', () {
      final fixture = read(file);
      final decoded = TrajectoryCodec.decode(envelopeFor(fixture));

      // Registry dispatch: a golden fixture must reach its typed decoder.
      expect(
        decoded,
        isNot(isA<OpaqueRecord>()),
        reason: (decoded is OpaqueRecord) ? decoded.decodeFailure : null,
      );
      expect(decoded.recordType, fixture['record_type']);
      expect(decoded.family.wire, fixture['family']);

      // A superseded version's fixture decodes through its KEPT decoder into
      // the CURRENT class (§2.6 rule 2 — the log is never migrated), so the
      // class encodes the current version, not the fixture's. Encode fidelity
      // is asserted against the current version's own fixture below.
      final isCurrent = decoded.typeVersion == fixture['type_version'];

      if (isCurrent) {
        // Decode → encode fidelity, both halves of the row.
        expect(
          jsonDecode(jsonEncode(decoded.payloadToJson())),
          equals(fixture['payload']),
        );
      } else {
        final current = read(
          File(
            '${fixtureDir.path}/${keyOf(file).type}'
            '.v${decoded.typeVersion}.json',
          ),
        );
        // The kept decoder maps the old key names onto the same fields: the
        // legacy row re-encodes as the CURRENT payload, value for value.
        expect(
          jsonDecode(jsonEncode(decoded.payloadToJson())),
          equals(current['payload']),
        );
      }

      // Identity is version-independent: the envelope correlation and the §5
      // grammar (text and hash) are pinned by every fixture, current or kept.
      expect(
        jsonDecode(jsonEncode(decoded.correlationToJson())),
        equals(fixture['envelope']),
      );
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
