/// The mechanics/vocabulary import boundary, enforced at the source level.
///
/// Decision: `docs/decisions/2026-08-31-grid-trajectory-leaf-package.md`,
/// "Long-term direction". A standalone agent-trajectory ledger tool is of real
/// long-term interest but extraction is DEFERRED until a second consumer
/// exists; the commitment kept in the meantime is this one — the MECHANICS
/// (`lib/src/append/**`, `lib/src/connect/**`, and the provisioning half of
/// `lib/src/ddl/**`) never reference the concrete record vocabulary. They
/// operate on `TrajectoryRecord`, `TrajectoryEnvelope`, the promoted envelope
/// columns, interface properties on the sealed base, and handed-in values.
///
/// Three prohibitions, each derived from the sources rather than hard-coded so
/// a NEW record type is covered the day it lands:
///
///   1. no import of the `codec/records/` vocabulary,
///   2. no concrete record-type class name,
///   3. no `record_type` literal and no idem-key grammar builder.
///
/// The check runs over source with COMMENTS STRIPPED: prose may explain the
/// rule (and the mechanics' own doc comments do), while code may not reach
/// through it. Do not add an entry to the carve-out to make a violation pass —
/// put the fact on the sealed base as an interface property instead, which is
/// how `isTerminal` / `isSettling` / `forcesDoltCommitBoundary` /
/// `grantBeltIssuerType` came to exist.
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/fixture_support.dart';

/// Source with comments removed and string literals intact — the boundary is
/// about what the code DOES, and a record type smuggled in as a SQL literal
/// counts exactly as much as one named as a class.
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final rest = source.length - i;
    if (rest >= 2 && source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (rest >= 2 && source.startsWith('/*', i)) {
      var depth = 1;
      i += 2;
      while (i < source.length && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      continue;
    }
    // A string literal: copy it verbatim, comment markers inside included.
    final raw = source[i] == 'r' && rest >= 2 && _isQuote(source[i + 1]);
    final quoteAt = raw ? i + 1 : i;
    if (quoteAt < source.length && _isQuote(source[quoteAt])) {
      final quote = source[quoteAt];
      final triple = source.startsWith(quote * 3, quoteAt);
      final delimiter = triple ? quote * 3 : quote;
      final start = i;
      i = quoteAt + delimiter.length;
      while (i < source.length) {
        if (!raw && source[i] == r'\') {
          i += 2;
          continue;
        }
        if (source.startsWith(delimiter, i)) {
          i += delimiter.length;
          break;
        }
        i++;
      }
      out.write(source.substring(start, i));
      continue;
    }
    out.write(source[i]);
    i++;
  }
  return out.toString();
}

bool _isQuote(String character) => character == "'" || character == '"';

List<File> _dartFilesIn(String path) =>
    Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  // `lib/src/ddl/trajectory_schema.dart` is the one carve-out, and it is the
  // carve-out the decision anticipates: the §4 DDL IS the vocabulary DDL —
  // ck_terminal, ck_provision, ck_grant and ck_grant_link promote record-type
  // names into CHECK constraints on purpose (§2.6 rule 6), which is the
  // grid-owned half the decision's "grid_trajectory IS the store" paragraph
  // is about. `trajectory_provisioning.dart` (SQL user + secret) is pure
  // mechanics and stays in scope.
  const vocabularyDdl = 'trajectory_schema.dart';

  final mechanics = [
    ..._dartFilesIn('lib/src/append'),
    ..._dartFilesIn('lib/src/connect'),
    ..._dartFilesIn(
      'lib/src/ddl',
    ).where((file) => !file.path.endsWith(vocabularyDdl)),
  ];

  // Derived, not listed: every concrete record class the part files declare.
  final recordClasses = _dartFilesIn('lib/src/codec/records')
      .expand(
        (file) => RegExp(
          r'\bfinal class (\w+) extends ',
        ).allMatches(file.readAsStringSync()).map((match) => match.group(1)!),
      )
      .toSet();

  final recordTypes = TrajectoryCodec.decoders.keys
      .map((key) => key.$1)
      .toSet();

  // Every §5 grammar row's leading token, e.g. `terminal:` / `usage:`. A
  // string literal opening with one is a grammar builder, wherever it sits.
  final grammarPrefixes = sampleRecords()
      .map((record) => record.idemKeyText(fixtureContext))
      .where((text) => text.contains(':'))
      .map((text) => text.substring(0, text.indexOf(':') + 1))
      .toSet();

  test('the derived vocabulary is non-empty (the checks below are not '
      'vacuous)', () {
    expect(mechanics, isNotEmpty);
    expect(recordClasses, contains('AttemptTerminal'));
    expect(recordClasses.length, greaterThan(40));
    expect(recordTypes, contains('attempt.terminal'));
    expect(recordTypes.length, greaterThan(40));
    expect(grammarPrefixes, contains('terminal:'));
  });

  test('the ddl carve-out is exactly the vocabulary DDL', () {
    // A new file under lib/src/ddl/ must be classified deliberately: either
    // it is mechanics (in scope above) or it is vocabulary (named here).
    expect(
      _dartFilesIn(
        'lib/src/ddl',
      ).map((file) => file.uri.pathSegments.last).toSet(),
      {'trajectory_provisioning.dart', vocabularyDdl},
    );
  });

  for (final file in mechanics) {
    final relative = file.path.replaceFirst(RegExp(r'^.*/lib/'), 'lib/');
    final code = stripComments(file.readAsStringSync());

    test('$relative imports no record vocabulary', () {
      expect(
        RegExp(r'''import\s+['"][^'"]*codec/records/''').hasMatch(code),
        isFalse,
        reason:
            '$relative reaches into codec/records/; the mechanics see the '
            'sealed base only',
      );
    });

    test('$relative names no concrete record class', () {
      for (final className in recordClasses) {
        expect(
          RegExp('\\b$className\\b').hasMatch(code),
          isFalse,
          reason:
              '$relative names the concrete record type $className. Put the '
              'fact on TrajectoryRecord as an interface property (see '
              'isTerminal / isSettling / forcesDoltCommitBoundary / '
              'grantBeltIssuerType) and read it off the base instead.',
        );
      }
    });

    test('$relative dispatches on no record_type and builds no idem-key '
        'grammar', () {
      for (final recordType in recordTypes) {
        expect(
          code.contains(recordType),
          isFalse,
          reason:
              "$relative spells the record type '$recordType'. A record_type "
              'literal is the vocabulary in string clothing — hand the value '
              'in from the record (grantBeltIssuerType is the worked '
              'example).',
        );
      }
      for (final prefix in grammarPrefixes) {
        expect(
          RegExp('''['"]${RegExp.escape(prefix)}''').hasMatch(code),
          isFalse,
          reason:
              '$relative opens a string literal with the §5 grammar prefix '
              "'$prefix'. The grammar belongs to the record types; the "
              'mechanics call idemKeyText/idemKey on the base.',
        );
      }
    });
  }
}
