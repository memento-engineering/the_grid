import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('SubstationWork is the single live molecule mint-mode composition', () {
    final src = File('lib/src/work/station_work.dart').readAsStringSync();

    expect(
      src.contains('this.circuitMintMode = CircuitMintMode.molecule'),
      isTrue,
      reason: 'plain SubstationWork must be the one molecule live arm',
    );
    expect(
      src.contains('circuitMintMode: circuitMintMode'),
      isTrue,
      reason: 'SubstationConfig must receive the composition value',
    );
  });
}
