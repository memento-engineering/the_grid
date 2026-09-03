// tg-mspw — the composition site must hand the union BOTH identity axes.
// Unwired, `_sources.keys` holds NAMES only and every production id (`tg-…`,
// `pow-…`) resolves to nothing: a foreign dep row is neither refused nor
// reported, and the LOUD guarantee is unbacked.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('assembleStationWork passes every member prefix into the union', () {
    final src = File('lib/src/work/work_assembly.dart').readAsStringSync();

    expect(
      src.contains('memberPrefixes:'),
      isTrue,
      reason:
          'FederatedSnapshotSource must receive each member prefix, not just '
          'the name-keyed member map.',
    );
    expect(
      src.contains('s.name: s.prefix'),
      isTrue,
      reason:
          'the prefixes must come from the SubstationWorkSpec identity axes '
          'the allow-set already uses.',
    );
  });
}
