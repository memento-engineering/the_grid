/// Byte-faithful ports of the Go scalar codecs gc uses for convergence
/// metadata (`gascity/internal/convergence/metadata.go:140-156` and
/// `handler.go:799-803`).
library;

/// Exactly Go's `unicode.IsSpace` set: the Latin-1 fast path
/// (`\t \n \v \f \r` space, U+0085 NEL, U+00A0 NBSP) plus the Unicode
/// space categories Zs (U+1680, U+2000–U+200A, U+202F, U+205F, U+3000),
/// Zl (U+2028) and Zp (U+2029).
///
/// Notably **excluded**: U+FEFF (BOM) and U+200B (zero-width space) — both
/// category Cf, not space in Go. Dart's `String.trim()` strips the BOM "for
/// historical reasons", which is why [goTrimSpace] exists at all.
///
/// All members are BMP non-surrogate code points, so comparing UTF-16 code
/// units directly is exact.
bool _isGoSpace(int codeUnit) => switch (codeUnit) {
  0x09 || 0x0A || 0x0B || 0x0C || 0x0D || 0x20 => true, // ASCII fast path
  0x85 || 0xA0 => true, // NEL, NBSP
  0x1680 => true, // OGHAM SPACE MARK (Zs)
  >= 0x2000 && <= 0x200A => true, // EN QUAD … HAIR SPACE (Zs)
  0x2028 || 0x2029 => true, // LINE/PARAGRAPH SEPARATOR (Zl/Zp)
  0x202F || 0x205F || 0x3000 => true, // NNBSP, MMSP, IDEOGRAPHIC SPACE (Zs)
  _ => false,
};

/// Port of Go `strings.TrimSpace`.
///
/// **Not** `String.trim()`: Dart's trim strips U+FEFF (BOM) and Go's
/// `unicode.IsSpace` does not, so the two disagree on BOM-bearing input.
/// That difference is outcome-bearing for `Verdict.normalize` — a
/// `"\uFEFFapprove"` agent verdict must read `block` (unknown string), not
/// `approve`, because the verdict gates the gate path's iterate-vs-terminate
/// branch (handler.go:317-324). Differentially pinned against go1.26.4
/// (`strings.TrimSpace("\uFEFFapprove")` keeps the BOM); see
/// go_scalars_test.dart.
String goTrimSpace(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && _isGoSpace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isGoSpace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}

final _goIntPattern = RegExp(r'^[+-]?[0-9]+$');

/// Port of Go `strconv.Atoi` returning null instead of `(0, false)`.
///
/// Go's Atoi accepts an optional leading `+`/`-` sign followed by decimal
/// digits only — **no** surrounding whitespace, no `0x` prefix, no
/// underscores. Dart's `int.tryParse` accepts both whitespace and `0x`, so
/// the input is validated against Go's grammar first. Out-of-int64-range
/// values return null (Atoi's `ErrRange` → `(0, false)` via `DecodeInt`).
///
/// Oddities preserved: `+5` → 5, `-0` → 0, `007` → 7.
int? goAtoi(String s) {
  if (!_goIntPattern.hasMatch(s)) return null;
  // Dart VM ints are int64; tryParse returns null when the value overflows.
  return int.tryParse(s);
}

/// Port of `convergence.DecodeInt` (metadata.go:147-156): empty string and
/// invalid integers both read as "no value" in gc; the codec layer separates
/// the two (absent vs malformed), and this helper reproduces the collapsed
/// Go read for callers that need it.
int? goDecodeInt(String s) {
  if (s.isEmpty) return null;
  return goAtoi(s);
}

/// Port of `convergence.EncodeInt` (metadata.go:141-143): `strconv.Itoa`.
String goEncodeInt(int n) => n.toString();

/// Encodes a bool the way gc writes `convergence.gate_truncated`
/// (handler.go:799-803): `"true"` when set, the **empty string** (not
/// `"false"`) when not.
String goEncodeBool({required bool value}) => value ? 'true' : '';

/// Reads a bool the way gc replays `convergence.gate_truncated`
/// (handler.go:298): strict equality with `"true"`; anything else is false.
bool goDecodeBool(Object? raw) => raw == 'true';
