/// Regenerates the golden fixtures under `test/fixtures/` from the sample
/// records — a DELIBERATE act: a diff in the output is a payload-schema
/// change, and a breaking one must mint `type_version + 1` (a NEW fixture
/// file) instead of rewriting an existing one (§2.6 rules 2/4).
///
/// Run from the package root: `dart run tool/regenerate_fixtures.dart`.
///
/// It writes one file per SAMPLE record, at that record's CURRENT
/// `type_version`, and therefore never touches a superseded version's
/// fixture — `verify.usage.telemetry.v1.json` survives every regeneration by
/// construction, which is exactly rule 2's "old decoders are kept forever"
/// expressed in the golden suite. A kept fixture is edited by nobody.
library;

import 'dart:convert';
import 'dart:io';

import '../test/support/fixture_support.dart';

void main() {
  final directory = Directory('test/fixtures');
  directory.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  for (final record in sampleRecords()) {
    final file = File(
      '${directory.path}/${record.recordType}.v${record.typeVersion}.json',
    );
    file.writeAsStringSync('${encoder.convert(fixtureFor(record))}\n');
    stdout.writeln('wrote ${file.path}');
  }
}
