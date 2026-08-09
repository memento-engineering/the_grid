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
      contains('the awaited pre-tree `GridDelegate.boot` rail (tg-1fa2.4)'),
    );
    expect(
      style,
      contains(
        'The live `GridDelegate` API has `didLaunch`, the awaited pre-tree '
        '`boot` (tg-1fa2.4), and `initGrid` lifecycle rails',
      ),
    );
    // tg-at3r: ONE delegate class — the two-layer split is retired, and
    // "running resident" survives only as a STATE description.
    expect(style, contains('retiring the two-layer delegate split'));
    expect(style, contains("ADR-0000 A45's pinned ordering requires it"));
  });
}
