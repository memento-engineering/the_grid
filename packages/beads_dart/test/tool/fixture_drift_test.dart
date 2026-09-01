import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const forkPatchFixtureSet =
    '2026-09-01-bd-grid-v1.0.5-graph-apply-parent-cycle-skip.1';

Object? fixture(String path) =>
    jsonDecode(File('../../fixtures/upstream/$path').readAsStringSync());

Map<String, Object?> issueMap(Object? value) {
  if (value case final Map<String, Object?> map) {
    if (map.containsKey('id') && map.containsKey('issue_type')) return map;
    for (final child in map.values) {
      try {
        return issueMap(child);
      } on StateError {
        // Keep searching sibling branches.
      }
    }
  } else if (value case final List<Object?> list) {
    for (final child in list) {
      try {
        return issueMap(child);
      } on StateError {
        // Keep searching sibling entries.
      }
    }
  }
  throw StateError('fixture contains no issue map');
}

void main() {
  test('fork graph-apply patch retains the 1.0.5 envelope shape', () {
    for (final file in <String>[
      'tg-list-all-empty.json',
      'tg-statuses.json',
      'tg-types.json',
      'tg-error-stdout.json',
      'fx-session-sample.json',
      'fx-message-sample.json',
      'fx-molecule-sample.json',
      'fx-ready-sample.json',
      'fx-show-sample.json',
    ]) {
      final envelope =
          fixture('$forkPatchFixtureSet/$file')! as Map<String, Object?>;
      expect(envelope['schema_version'], 1, reason: file);
    }
    for (final file in <String>[
      'fx-session-sample.json',
      'fx-message-sample.json',
      'fx-molecule-sample.json',
      'fx-show-sample.json',
    ]) {
      expect(issueMap(fixture('$forkPatchFixtureSet/$file')), isNotEmpty);
    }
  });

  test('show revision drift', () {
    final oldIssue = issueMap(
      fixture('2026-07-10-bd-1.0.5/fx-message-sample.json'),
    );
    final mainIssue = issueMap(
      fixture('2026-08-08-bd-main/fx-show-sample.json'),
    );
    expect(oldIssue, isNot(contains('revision')));
    expect(mainIssue['revision'], isA<int>());
  });

  test('truncated pagination drift', () {
    final oldEnvelope =
        fixture('2026-07-10-bd-1.0.5/fx-ready-sample.json')!
            as Map<String, Object?>;
    final mainEnvelope =
        fixture('2026-08-08-bd-main/fx-ready-sample.json')!
            as Map<String, Object?>;
    expect(oldEnvelope, isNot(contains('pagination')));
    expect(mainEnvelope['pagination'], isA<Map<String, Object?>>());
    expect(oldEnvelope['schema_version'], 1);
    expect(mainEnvelope['schema_version'], 1);
  });
}
