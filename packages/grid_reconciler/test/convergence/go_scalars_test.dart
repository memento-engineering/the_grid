import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

/// Differential pins for the Go scalar ports. The goTrimSpace table was
/// executed against go1.26.4 `strings.TrimSpace` on 2026-06-12; every row
/// records the Go result verbatim.
void main() {
  group('goTrimSpace (Go strings.TrimSpace / unicode.IsSpace)', () {
    test('trims the full Go space set from both ends', () {
      // Latin-1 fast path: \t \n \v \f \r space, NEL, NBSP.
      expect(goTrimSpace('\t\n\v\f\r x \r\f\v\n\t'), 'x');
      expect(goTrimSpace('\u0085x\u0085'), 'x'); // NEL
      expect(goTrimSpace('\u00A0x\u00A0'), 'x'); // NBSP
      // Zs beyond Latin-1.
      expect(goTrimSpace('\u1680x'), 'x'); // OGHAM SPACE MARK
      expect(goTrimSpace('\u2000\u2001\u2009\u200Ax'), 'x'); // EN QUAD…HAIR
      expect(goTrimSpace('\u202Fx\u205F'), 'x'); // NNBSP, MMSP
      expect(goTrimSpace('\u3000x\u3000'), 'x'); // IDEOGRAPHIC SPACE
      // Zl/Zp.
      expect(goTrimSpace('\u2028x\u2029'), 'x');
    });

    test('does NOT trim U+FEFF (BOM) or U+200B (ZWSP) — the exact '
        'String.trim() divergence (both are Cf, not Go space)', () {
      // go1.26.4: strings.TrimSpace("\uFEFFapprove") keeps the BOM.
      expect(goTrimSpace('\uFEFFapprove'), '\uFEFFapprove');
      expect(goTrimSpace('approve\uFEFF'), 'approve\uFEFF');
      expect(goTrimSpace('\u200Bapprove'), '\u200Bapprove');
      // Dart's trim strips the BOM — the divergence this port closes.
      expect('\uFEFFapprove'.trim(), 'approve');
    });

    test('interior whitespace is untouched; empty and all-space collapse', () {
      expect(goTrimSpace('a b'), 'a b');
      expect(goTrimSpace(''), '');
      expect(goTrimSpace(' \u3000\t'), '');
    });
  });

  group('case-mapping platform pins (Verdict.normalize residual)', () {
    test('the Dart VM toLowerCase is the SIMPLE mapping, matching Go '
        'strings.ToLower on outcome-relevant runes', () {
      // If any of these break, the platform's case mapping changed and
      // Verdict.normalize's lowercase residual analysis must be redone.
      expect('İ'.toLowerCase(), 'i'); // U+0130: simple → i (Go agrees)
      expect('ß'.toUpperCase(), 'ß'); // full mapping would yield SS
      expect(
        '\u212AELVIN'.toLowerCase(),
        'kelvin',
      ); // Kelvin sign → k, both mappings
      expect('ΣAΣ'.toLowerCase(), 'σaσ'); // no final-sigma context rule
    });
  });
}
