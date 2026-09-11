import 'dart:convert';

import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

const String _source = '''
class Alpha {
  int value = 0;

  void go() {
    print('{ not a brace }');
  }
}

typedef Beta = void Function();

class Gamma {
  const Gamma();
}
''';

void main() {
  group('symbol resolution', () {
    test('finds a class and its brace-balanced extent', () {
      final spans = resolveSymbol(_source, 'Alpha');
      expect(spans, hasLength(1));
      expect(spans.single.start, 1);
      // Ends on the class's closing brace, not the method's.
      expect(spans.single.end, 7);
    });

    test('braces inside strings and comments do not unbalance the walk', () {
      final spans = resolveSymbol(_source, 'go');
      expect(spans, hasLength(1));
      expect(spans.single.lines, greaterThan(1));
      final text = sliceOf('x.dart', _source, spans.single).text;
      expect(text, contains('not a brace'));
      expect(text.trimRight(), endsWith('}'));
    });

    test('a braceless declaration falls back to a bounded window', () {
      final spans = resolveSymbol(_source, 'Beta');
      expect(spans, hasLength(1));
      expect(spans.single.lines, lessThanOrEqualTo(3));
    });

    test('an undeclared symbol resolves to nothing, never the whole file', () {
      expect(resolveSymbol(_source, 'Missing'), isEmpty);
    });
  });

  group('the output contract', () {
    test('a slice under the cap is emitted whole with no marker', () {
      final slice = sliceOf('a.dart', _source, const LineSpan(1, 2));
      final report = capSlices([slice], capBytes: 10000);
      expect(report.slices.single.truncated, isFalse);
      expect(renderRead(report), isNot(contains('withheld')));
    });

    test('a cut slice names what it withheld and how to ask for it', () {
      final slice = sliceOf('a.dart', _source, const LineSpan(1, 7));
      final report = capSlices([slice], capBytes: 20);
      final capped = report.slices.single;
      expect(capped.truncated, isTrue);
      final rendered = renderRead(report);
      expect(rendered, contains('more lines withheld'));
      expect(rendered, contains('--span'));
    });

    test('the budget is shared max-min fair, never first-come', () {
      final small = sliceOf('small.dart', 'a\nb\n', const LineSpan(1, 2));
      final large = sliceOf('large.dart', _source, const LineSpan(1, 13));
      final report = capSlices([large, small], capBytes: 60);
      final renderedSmall = report.slices.firstWhere(
        (s) => s.slice.path == 'small.dart',
      );
      // The small file survives whole even though the large one was requested
      // first and would otherwise have eaten the budget.
      expect(renderedSmall.truncated, isFalse);
      expect(renderedSmall.text, contains('a'));
    });

    test('emitted bytes never exceed the cap', () {
      final slices = [
        sliceOf('a.dart', _source, const LineSpan(1, 13)),
        sliceOf('b.dart', _source, const LineSpan(1, 13)),
      ];
      final report = capSlices(slices, capBytes: 120);
      expect(report.emittedBytes, lessThanOrEqualTo(120));
    });
  });

  group('content-addressed identity', () {
    test('identity changes when the text changes', () {
      final before = sliceOf('a.dart', _source, const LineSpan(1, 2));
      final after = sliceOf(
        'a.dart',
        _source.replaceFirst('int value = 0;', 'int value = 1;'),
        const LineSpan(1, 2),
      );
      expect(before.span, after.span);
      expect(before.identity, isNot(after.identity));
    });

    test('a known identity is suppressed, not re-emitted', () {
      final slice = sliceOf('a.dart', _source, const LineSpan(1, 2));
      final report = capSlices(
        [slice],
        capBytes: 10000,
        seenIdentities: {slice.identity},
      );
      expect(report.slices.single.suppressed, isTrue);
      expect(report.slices.single.text, isEmpty);
      expect(renderRead(report), contains('UNCHANGED'));
    });

    test('an EDITED file is re-emitted despite the same path and span', () {
      final before = sliceOf('a.dart', _source, const LineSpan(1, 2));
      final edited = sliceOf(
        'a.dart',
        _source.replaceFirst('int value = 0;', 'int value = 1;'),
        const LineSpan(1, 2),
      );
      final report = capSlices(
        [edited],
        capBytes: 10000,
        seenIdentities: {before.identity},
      );
      expect(
        report.slices.single.suppressed,
        isFalse,
        reason: 'suppression keys on the answer, never on path+span alone',
      );
    });

    test('the fingerprint is deterministic and utf8-aware', () {
      expect(contentFingerprint('é'), contentFingerprint('é'));
      expect(contentFingerprint('a'), isNot(contentFingerprint('b')));
      expect(utf8.encode('é').length, 2);
    });
  });

  group('span parsing', () {
    test('accepts a well-formed range', () {
      expect(parseSpan('3:9'), const LineSpan(3, 9));
    });

    test('refuses a reversed, zero or malformed range', () {
      expect(parseSpan('9:3'), isNull);
      expect(parseSpan('0:3'), isNull);
      expect(parseSpan('3'), isNull);
      expect(parseSpan('a:b'), isNull);
    });
  });
}
