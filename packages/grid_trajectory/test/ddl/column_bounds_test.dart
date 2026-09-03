/// The §4 column-width bounds (tg-kzvs): every free-text reason column the DDL
/// declares is ENUMERATED FROM THE DDL — never a hand-copied list — and a
/// 64 KiB value fits every one of them with a visible marker.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

void main() {
  // The receipt's shape: a leg quoting a whole PR payload into its error.
  final oversized = 'x' * (64 * 1024);

  test('the DDL parse is not vacuous: known columns carry known widths', () {
    expect(
      trajectoryColumnWidths['proj_session_head']!['work_terminal_reason'],
      255,
    );
    expect(trajectoryColumnWidths['proj_session_head']!['held_reason'], 512);
    expect(trajectoryColumnWidths['trajectory']!['idem_key_text'], 512);
    expect(trajectoryColumnWidths.keys, contains('proj_effects'));
  });

  test('the bounded set is exactly the *_reason columns of the DDL', () {
    final reasons = {
      for (final entry in trajectoryReasonColumnWidths.entries)
        for (final column in entry.value.keys) '${entry.key}.$column',
    };
    expect(reasons, isNotEmpty);
    expect(reasons, everyElement(endsWith('_reason')));
    expect(
      reasons,
      containsAll([
        'proj_session_head.work_terminal_reason',
        'proj_session_head.held_reason',
        'proj_session_head.unknown_reason',
        'trajectory.unknown_reason',
        'proj_effects.unknown_reason',
      ]),
    );
    // Identity-bearing text is deliberately OUT of scope: its SHA is the key.
    expect(reasons, isNot(contains('trajectory.idem_key_text')));
  });

  group('every free-text reason column the schema declares', () {
    // ENUMERATED, not listed: a reason column added to the DDL is covered here
    // the day it lands.
    for (final table in trajectoryReasonColumnWidths.entries) {
      for (final column in table.value.entries) {
        final name = '${table.key}.${column.key}';
        final width = column.value;

        test('$name bounds a 64 KiB value to $width', () {
          final bounded = boundText(oversized, width);
          expect(bounded.runes.length, width);
          expect(bounded, startsWith('xxxx'));
          expect(bounded, endsWith(']'));
          expect(bounded, contains('truncated from 65536'));
        });

        test('$name passes a fitting value through verbatim', () {
          final fits = 'y' * width;
          expect(boundText(fits, width), fits);
          expect(boundText(fits, width), isNot(contains('truncated')));
        });
      }
    }
  });

  test('truncation is by CODE POINT: no lone surrogate escapes', () {
    final astral = '😀' * 400; // 400 code points, 800 UTF-16 units
    final bounded = boundText(astral, 255);
    expect(bounded.runes.length, 255);
    expect(
      bounded.runes.every((rune) => rune < 0xD800 || rune > 0xDFFF),
      isTrue,
    );
  });

  test('boundReasonColumns shapes only declared reason columns', () {
    final bounded = boundReasonColumns(kSessionHeadTable, {
      'work_terminal_reason': oversized,
      'held_reason': oversized,
      'outcome': 'failed',
      'closed_at': null,
    });
    expect((bounded['work_terminal_reason']! as String).runes.length, 255);
    expect((bounded['held_reason']! as String).runes.length, 512);
    expect(bounded['outcome'], 'failed');
    expect(bounded['closed_at'], isNull);
  });
}
