import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('STYLE.md codifies the ratified tree-composition rules', () {
    final style = File('../../docs/STYLE.md').readAsStringSync();

    for (final heading in [
      '## 1. `build*` describes synchronously',
      '## 2. Provider ownership follows construction',
      '## 3. Availability is observed, including absence',
      '## 4. No provider is universal',
      '## 5. Boot is an assembly ratchet',
    ]) {
      expect(style, contains(heading), reason: heading);
    }

    expect(
      style,
      contains('The async `buildStationWork` name is pending `tg-1fa2.3`'),
    );
    expect(
      style,
      contains(
        'The live `GridDelegate` API has `didLaunch` and `initGrid` '
        'lifecycle rails; it does not yet have `GridDelegate.boot`.',
      ),
    );
    expect(style, contains("ADR-0000 A45's pinned ordering requires it"));
  });
}
