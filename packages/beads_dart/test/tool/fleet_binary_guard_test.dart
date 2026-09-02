import 'dart:io';

import 'package:test/test.dart';

import '../support/fleet_binary_guard.dart';

void main() {
  group('the pure verdict', () {
    test('a matching stamp runs the test', () {
      expect(
        foreignBinaryReason(
          storeStamp: 'HEAD-a45199a',
          binaryVersion: 'HEAD-a45199a',
        ),
        isNull,
      );
    });

    test('a foreign binary skips with the pinned reason', () {
      expect(
        foreignBinaryReason(
          storeStamp: 'HEAD-a45199a',
          binaryVersion: '1.3.0-rc.1',
        ),
        kForeignBinaryReason,
      );
      expect(
        kForeignBinaryReason,
        "binary under test differs from the store's writer; live equivalence "
        'runs only under the fleet binary',
      );
    });

    test('an absent bd or an unstamped store skips too', () {
      expect(
        foreignBinaryReason(storeStamp: 'HEAD-a45199a', binaryVersion: null),
        kForeignBinaryReason,
      );
      expect(
        foreignBinaryReason(storeStamp: null, binaryVersion: 'HEAD-a45199a'),
        kUnstampedStoreReason,
      );
      expect(
        foreignBinaryReason(storeStamp: '  ', binaryVersion: 'x'),
        kUnstampedStoreReason,
      );
    });
  });

  test('bdVersionOnPath parses the first token or refuses', () {
    expect(bdVersionOnPath(executable: 'definitely-not-a-real-binary'), isNull);
  });

  test('both live tests guard before they read an endpoint', () {
    for (final path in const [
      'test/integration/sql_cli_equivalence_test.dart',
      'test/integration/cross_workspace_probe_test.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final guard = source.indexOf('skippedForForeignBinary(ws)');
      final endpoint = source.indexOf('ws?.endpoint');
      expect(guard, greaterThan(0), reason: '$path does not guard');
      expect(
        guard,
        lessThan(endpoint),
        reason: '$path resolves an endpoint before guarding',
      );
    }
  });

  test('run.sh keeps its two-argument form (no invoker-selected mode)', () {
    final runner = File(
      '../../tool/bd_compatibility/run.sh',
    ).readAsStringSync();
    expect(runner, contains(r'[[ $# -eq 2 ]]'));
    expect(runner, isNot(contains(r'$3')));
    expect(
      runner,
      contains('usage: run.sh <upstream-checkout> <absolute-bd-executable>'),
    );
  });
}
