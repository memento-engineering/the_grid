/// A Go `time.Duration`: a signed 64-bit count of nanoseconds.
///
/// gc encodes `convergence.gate_timeout` with `Duration.String()` and decodes
/// it with `time.ParseDuration` (`EncodeDuration`/`DecodeDuration`,
/// metadata.go:159-174). Dart's `Duration` has microsecond resolution and a
/// different string format, so the codec carries this zero-cost wrapper over
/// the nanosecond count with byte-faithful ports of both directions.
extension type const GoDuration(int nanoseconds) {
  static const GoDuration zero = GoDuration(0);

  /// Port of Go `time.ParseDuration` (returning null instead of an error).
  ///
  /// Grammar: `[-+]?([0-9]*(\.[0-9]*)?[a-z]+)+` with the special case `"0"`
  /// (optionally signed). Units: `ns`, `us`/`µs`/`μs`, `ms`, `s`, `m`, `h`.
  /// No whitespace, no days. Faithful oddities: `"+5s"` parses, `".5s"`
  /// parses (500ms), `"1.5h30m"` parses (multi-component), `"5"` and `"s"`
  /// and `""` do not.
  ///
  /// Known deviations — both confined to Go's unsigned-intermediate ±2⁶³
  /// boundary, which gc never writes:
  ///
  /// * **Total value at exactly ±2⁶³ ns** (~292y): Go round-trips it through
  ///   a uint64; this port returns null.
  /// * **Fraction integer at exactly 2⁶³**: Go's `leadingFraction` commits a
  ///   digit while `x*10 + d ≤ 2⁶³` (go1.26 time/format.go:1594-1600 — the
  ///   post-check `y > 1<<63` freezes only ABOVE 2⁶³, so `y == 2⁶³` commits
  ///   through the uint64). Dart's int64 cannot hold 2⁶³, so this port
  ///   freezes one digit earlier (at `y > 2⁶³−1`). The committed fraction
  ///   then differs by `d/(scale·10) < 10⁻¹⁸` before the float64
  ///   `f·(unit/scale)` conversion — at most 1 ulp through the double math.
  ///   Every go-run-pinned input in go_duration_test.dart (including the
  ///   exact-2⁶³ fraction `"0.9223372036854775808s"` against all units)
  ///   parses identically to go1.26.4.
  static GoDuration? parse(String input) {
    var s = input;
    var neg = false;
    if (s.isNotEmpty && (s.startsWith('-') || s.startsWith('+'))) {
      neg = s.startsWith('-');
      s = s.substring(1);
    }
    // Special case (after sign strip): plain "0" is zero with no unit.
    if (s == '0') return zero;
    if (s.isEmpty) return null;

    var total = 0;
    var i = 0;
    while (i < s.length) {
      // The next character must be [0-9.].
      final first = s.codeUnitAt(i);
      if (!(first == _dot || (first >= _zero && first <= _nine))) return null;

      // Consume [0-9]* (Go leadingInt).
      var v = 0;
      final intStart = i;
      while (i < s.length) {
        final c = s.codeUnitAt(i);
        if (c < _zero || c > _nine) break;
        if (v > _overflowGuard) return null;
        v = v * 10 + (c - _zero);
        if (v < 0) return null;
        i++;
      }
      final pre = i != intStart;

      // Consume (\.[0-9]*)? (Go leadingFraction).
      var f = 0;
      var scale = 1.0;
      var post = false;
      if (i < s.length && s.codeUnitAt(i) == _dot) {
        i++;
        final fracStart = i;
        var overflow = false;
        while (i < s.length) {
          final c = s.codeUnitAt(i);
          if (c < _zero || c > _nine) break;
          i++;
          if (overflow) continue;
          // Go's pre-check (time/format.go:1589): another digit would
          // overflow even before adding it.
          if (f > _overflowGuard) {
            overflow = true;
            continue;
          }
          // Go's post-check (time/format.go:1594-1598, `y > 1<<63`): the
          // candidate digit pushes the fraction integer past int64 max —
          // in Dart it wraps negative. Freeze f AND scale for all later
          // digits WITHOUT committing, exactly like Go's overflow path.
          // (Go alone commits the single value y == 2⁶³ via uint64 — the
          // documented boundary-class deviation above.)
          final next = f * 10 + (c - _zero);
          if (next < 0) {
            overflow = true;
            continue;
          }
          f = next;
          scale *= 10;
        }
        post = i != fracStart;
      }
      if (!pre && !post) return null; // no digits (e.g. ".s")

      // Consume the unit: everything up to the next digit or dot.
      final unitStart = i;
      while (i < s.length) {
        final c = s.codeUnitAt(i);
        if (c == _dot || (c >= _zero && c <= _nine)) break;
        i++;
      }
      if (i == unitStart) return null; // missing unit
      final unit = _unitNanos[s.substring(unitStart, i)];
      if (unit == null) return null; // unknown unit

      if (v > _maxInt64 ~/ unit) return null; // overflow
      v *= unit;
      if (f > 0) {
        // Go: v += uint64(float64(f) * (float64(unit) / scale)).
        v += (f.toDouble() * (unit.toDouble() / scale)).truncate();
        if (v < 0) return null;
      }
      total += v;
      if (total < 0) return null;
    }
    return GoDuration(neg ? -total : total);
  }

  /// Port of Go `Duration.String()` — the exact format gc writes via
  /// `EncodeDuration` (metadata.go:159-161).
  ///
  /// Examples: `0s`, `300ms`, `1.5µs`, `5m0s`, `1h0m0s`, `-1m30s`.
  String encode() {
    // Dart's abs() wraps at min-int64; Go prints this exact string.
    if (nanoseconds == _minInt64) return '-2562047h47m16.854775808s';
    final neg = nanoseconds < 0;
    var u = nanoseconds.abs();
    String out;
    if (u < _nanosPerSecond) {
      if (u == 0) return '0s';
      if (u < 1000) {
        out = '${u}ns';
      } else if (u < 1000000) {
        out = '${u ~/ 1000}${_frac(u % 1000, 3)}µs';
      } else {
        out = '${u ~/ 1000000}${_frac(u % 1000000, 6)}ms';
      }
    } else {
      final frac = _frac(u % _nanosPerSecond, 9);
      u ~/= _nanosPerSecond;
      out = '${u % 60}${frac}s';
      u ~/= 60;
      if (u > 0) {
        out = '${u % 60}m$out';
        u ~/= 60;
        if (u > 0) out = '${u}h$out';
      }
    }
    return neg ? '-$out' : out;
  }

  /// Lossy bridge to Dart's microsecond-resolution [Duration] (truncates
  /// toward zero, like Go's integer division).
  Duration toDuration() => Duration(microseconds: nanoseconds ~/ 1000);

  /// Go `Duration.Milliseconds()` (truncates toward zero).
  int get inMilliseconds => nanoseconds ~/ 1000000;
}

/// Fraction renderer for [GoDuration.encode] (Go `fmtFrac`): pads to [digits],
/// trims trailing zeros, omits the dot when the fraction is zero.
String _frac(int value, int digits) {
  if (value == 0) return '';
  var s = value.toString().padLeft(digits, '0');
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.isEmpty ? '' : '.$s';
}

const _dot = 0x2E;
const _zero = 0x30;
const _nine = 0x39;
const _maxInt64 = 0x7FFFFFFFFFFFFFFF;
const _minInt64 = -0x8000000000000000;
const _overflowGuard = 922337203685477580; // (1<<63)/10, Go's leadingInt guard
const _nanosPerSecond = 1000000000;

/// Go's `unitMap` (time/format.go): nanoseconds per unit token.
const _unitNanos = <String, int>{
  'ns': 1,
  'us': 1000,
  'µs': 1000, // µs (U+00B5 micro sign)
  'μs': 1000, // μs (U+03BC greek small letter mu)
  'ms': 1000000,
  's': 1000000000,
  'm': 60000000000,
  'h': 3600000000000,
};
