/// The PURE half of `grid read` — span resolution, capping and the
/// content-addressed dedupe key.
///
/// Records the ruling in
/// `power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`:
/// reading source is a mechanical lookup, so it is a command rather than
/// inference, and a vended command bounds its output, says what it withheld,
/// and may only suppress a repeat it can PROVE unchanged.
///
/// Pure by design (no `dart:io`): every function here takes source text and
/// returns values, so the whole contract is testable without a filesystem.
library;

import 'dart:convert';

/// One 1-based, inclusive line range within a file.
class LineSpan {
  /// Creates the span covering [start]..[end], both 1-based and inclusive.
  const LineSpan(this.start, this.end);

  /// First line, 1-based.
  final int start;

  /// Last line, 1-based and inclusive.
  final int end;

  /// How many lines this span covers.
  int get lines => end - start + 1;

  @override
  bool operator ==(Object other) =>
      other is LineSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start:$end';
}

/// One file's resolved excerpt, before capping.
class SourceSlice {
  /// Creates a slice of [path] covering [span] with [text].
  const SourceSlice({
    required this.path,
    required this.span,
    required this.text,
    required this.totalLines,
  });

  /// The file this slice came from, as the caller named it.
  final String path;

  /// The 1-based inclusive line range.
  final LineSpan span;

  /// The excerpt itself, newline-joined, without a trailing newline.
  final String text;

  /// The file's full line count, so a reader knows what it did not get.
  final int totalLines;

  /// The CONTENT-ADDRESSED identity of this answer.
  ///
  /// Keyed on path, span and a hash of the text — never on the command that
  /// produced it. A build lane edits files underneath the agent, so a
  /// command-string key would serve a stale read while reporting success.
  String get identity =>
      '$path@${span.start}:${span.end}#${contentFingerprint(text)}';
}

/// A deterministic 64-bit FNV-1a fingerprint of [text], as lowercase hex.
///
/// A CHANGE DETECTOR, not a security primitive, which is exactly what the
/// ruling asks for: the question is only ever "is this the same answer I
/// already returned". Deliberately dependency-free — adding `crypto` to the
/// CLI to compare two strings would be its own kind of shortcut.
String contentFingerprint(String text) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;
  for (final byte in utf8.encode(text)) {
    hash = (hash ^ byte) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Splits [source] into lines without a trailing empty element.
List<String> sourceLines(String source) {
  final lines = const LineSplitter().convert(source);
  return lines;
}

/// The span covering the whole of [source].
LineSpan wholeFile(String source) {
  final n = sourceLines(source).length;
  return LineSpan(1, n == 0 ? 0 : n);
}

/// Clamps [span] into [source]'s real extent, or null when it lies outside.
LineSpan? clampSpan(String source, LineSpan span) {
  final n = sourceLines(source).length;
  if (n == 0) return null;
  final start = span.start < 1 ? 1 : span.start;
  final end = span.end > n ? n : span.end;
  if (start > end) return null;
  return LineSpan(start, end);
}

/// Cuts [span] out of [source].
SourceSlice sliceOf(String path, String source, LineSpan span) {
  final lines = sourceLines(source);
  final text = lines.sublist(span.start - 1, span.end).join('\n');
  return SourceSlice(
    path: path,
    span: span,
    text: text,
    totalLines: lines.length,
  );
}

/// The Dart declaration forms [resolveSymbol] recognises, in one pattern.
///
/// Deliberately a DECLARATION scan rather than an analyzer session: resolving
/// one name must not cost a package resolve. It answers "where is this
/// declared" — the question the guessed line range was standing in for — and
/// reports every match rather than guessing which one the caller meant.
RegExp _declarationPattern(String symbol) {
  final n = RegExp.escape(symbol);
  return RegExp(
    // a type-ish declaration: `class Foo`, `sealed class Foo`, `mixin Foo`…
    r'^\s*(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
    r'(?:class|mixin|enum|extension(?:\s+type)?|typedef)\s+'
    '$n'
    r'\b'
    // …or a member/function: `void foo(`, `Foo(` , `T get foo`, `set foo(`
    r'|^\s*(?:@\w+\s+)*(?:static\s+|external\s+|abstract\s+|final\s+|const\s+)*'
    r'(?:[\w<>,\s\?\[\]\.]+\s+)?(?:get\s+|set\s+)?'
    '$n'
    r'\s*[\(<=\{]',
    multiLine: true,
  );
}

/// Every line (1-based) in [source] that DECLARES [symbol].
List<int> declarationLines(String source, String symbol) {
  final lines = sourceLines(source);
  final pattern = _declarationPattern(symbol);
  final hits = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (pattern.hasMatch(lines[i])) hits.add(i + 1);
  }
  return hits;
}

/// The brace-balanced extent of the declaration beginning at [startLine].
///
/// Walks forward counting `{`/`}` outside strings and comments. A declaration
/// with no brace within [lookahead] lines (a `typedef`, a field) returns a
/// small window instead, so the caller always gets something bounded.
LineSpan declarationExtent(
  String source,
  int startLine, {
  int lookahead = 6,
  int fallbackLines = 3,
}) {
  final lines = sourceLines(source);
  if (startLine < 1 || startLine > lines.length) {
    return LineSpan(startLine, startLine);
  }
  var depth = 0;
  var opened = false;
  for (var i = startLine - 1; i < lines.length; i++) {
    final line = _stripNoise(lines[i]);
    for (final rune in line.runes) {
      if (rune == 0x7B) {
        depth++;
        opened = true;
      } else if (rune == 0x7D) {
        depth--;
      } else if (rune == 0x3B && !opened) {
        // A `;` before any brace ENDS a braceless declaration (a typedef, a
        // field, an abstract member). Without this the walk runs on and
        // swallows the NEXT declaration's body, reporting one symbol's extent
        // as its neighbour's.
        return LineSpan(startLine, i + 1);
      }
    }
    if (opened && depth <= 0) return LineSpan(startLine, i + 1);
    if (!opened && (i - (startLine - 1)) >= lookahead) {
      final end = startLine + fallbackLines - 1;
      return LineSpan(startLine, end > lines.length ? lines.length : end);
    }
  }
  return LineSpan(startLine, lines.length);
}

/// Removes line comments and simple string bodies so their braces do not count.
String _stripNoise(String line) {
  final withoutLineComment = line.replaceAll(RegExp(r'//.*$'), '');
  return withoutLineComment
      .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''")
      .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""');
}

/// Resolves [symbol] in [source] to the spans that declare it.
///
/// Empty when the symbol is not declared here — the caller reports that as a
/// miss rather than falling back to dumping the file, which is the behaviour
/// the guessed line range produced.
List<LineSpan> resolveSymbol(String source, String symbol) => [
  for (final line in declarationLines(source, symbol))
    declarationExtent(source, line),
];

/// One slice after the output contract has been applied.
class CappedSlice {
  /// Creates the emitted form of a slice.
  const CappedSlice({
    required this.slice,
    required this.text,
    required this.withheldLines,
    required this.suppressed,
  });

  /// The slice this came from.
  final SourceSlice slice;

  /// The text actually emitted — empty when [suppressed].
  final String text;

  /// Lines withheld by the cap. Zero when the whole slice was emitted.
  final int withheldLines;

  /// Whether this answer was withheld because it was PROVEN unchanged.
  final bool suppressed;

  /// Whether the cap cut this slice.
  bool get truncated => withheldLines > 0;
}

/// The report `grid read` renders.
class ReadReport {
  /// Creates a report over [slices].
  const ReadReport({required this.slices, required this.capBytes});

  /// Every requested slice, in request order.
  final List<CappedSlice> slices;

  /// The byte budget this report was rendered under.
  final int capBytes;

  /// Bytes actually emitted.
  int get emittedBytes =>
      slices.fold(0, (sum, s) => sum + utf8.encode(s.text).length);
}

/// Applies the output contract to [slices] under a shared [capBytes] budget.
///
/// MAX-MIN FAIR SHARE across the set, not per file: a small file is emitted
/// whole and its unused budget flows to the large ones, so asking for five
/// files never starves four of them to dump the first. A slice already in
/// [seenIdentities] is SUPPRESSED rather than re-emitted — permitted only
/// because the identity is content-addressed, so a changed file has a
/// different key and comes back fresh.
ReadReport capSlices(
  List<SourceSlice> slices, {
  required int capBytes,
  Set<String> seenIdentities = const {},
}) {
  final fresh = <SourceSlice>[];
  final suppressed = <String, CappedSlice>{};
  for (final slice in slices) {
    if (seenIdentities.contains(slice.identity)) {
      suppressed[slice.identity] = CappedSlice(
        slice: slice,
        text: '',
        withheldLines: 0,
        suppressed: true,
      );
    } else {
      fresh.add(slice);
    }
  }
  final order = [...fresh]
    ..sort(
      (a, b) =>
          utf8.encode(a.text).length.compareTo(utf8.encode(b.text).length),
    );
  final emitted = <String, CappedSlice>{};
  var remaining = capBytes;
  var left = order.length;
  for (final slice in order) {
    final share = left == 0 ? 0 : remaining ~/ left;
    final bytes = utf8.encode(slice.text);
    if (bytes.length <= share) {
      emitted[slice.identity] = CappedSlice(
        slice: slice,
        text: slice.text,
        withheldLines: 0,
        suppressed: false,
      );
      remaining -= bytes.length;
    } else {
      final lines = slice.text.isEmpty ? <String>[] : slice.text.split('\n');
      final kept = <String>[];
      var used = 0;
      for (final line in lines) {
        final cost = utf8.encode(line).length + 1;
        if (used + cost > share) break;
        kept.add(line);
        used += cost;
      }
      emitted[slice.identity] = CappedSlice(
        slice: slice,
        text: kept.join('\n'),
        withheldLines: lines.length - kept.length,
        suppressed: false,
      );
      remaining -= used;
    }
    left--;
  }
  return ReadReport(
    slices: [
      for (final slice in slices)
        emitted[slice.identity] ?? suppressed[slice.identity]!,
    ],
    capBytes: capBytes,
  );
}

/// Renders [report] as the bounded text a seat reads.
///
/// Every slice carries its path and line anchors so a patch can reference them
/// without a second numbering pass, and every cut says what it withheld and
/// how to ask for it. Silent truncation is the failure this forbids: it
/// produces confident, partial answers.
String renderRead(ReadReport report) {
  final buffer = StringBuffer();
  for (final capped in report.slices) {
    final slice = capped.slice;
    if (capped.suppressed) {
      buffer.writeln(
        '== ${slice.path} ${slice.span} — UNCHANGED since this session '
        'already read it; not re-emitted ==',
      );
      continue;
    }
    buffer.writeln(
      '== ${slice.path} ${slice.span} of ${slice.totalLines} lines ==',
    );
    if (capped.text.isNotEmpty) buffer.writeln(capped.text);
    if (capped.truncated) {
      final shown = slice.span.lines - capped.withheldLines;
      final from = slice.span.start + shown;
      buffer.writeln(
        '… +${capped.withheldLines} more lines withheld by the '
        '${report.capBytes}-byte cap — refine with '
        '--span $from:${slice.span.end}',
      );
    }
  }
  return buffer.toString();
}
