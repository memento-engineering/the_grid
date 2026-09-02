import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const forkPatchFixtureSet =
    '2026-09-01-bd-grid-v1.0.5-graph-apply-parent-cycle-skip.1';
const rcFixtureSet = '2026-09-02-bd-1.3.0-rc.1';
const mainFixtureSet = '2026-08-08-bd-main';

/// The nine enveloped JSON captures every set carries.
const capturedEnvelopes = <String>[
  'tg-list-all-empty.json',
  'tg-statuses.json',
  'tg-types.json',
  'tg-error-stdout.json',
  'fx-session-sample.json',
  'fx-message-sample.json',
  'fx-molecule-sample.json',
  'fx-ready-sample.json',
  'fx-show-sample.json',
];

/// Every wire key `Bead.fromJson` decodes (`lib/src/models/bead.dart`). A key
/// in this set that the 2026-08-08 capture carried and the rc capture does not
/// is a REMOVED/RENAMED decoded field — the loud, non-additive drift alarm.
const beadWireKeys = <String>{
  'id',
  'title',
  'description',
  'design',
  'acceptance_criteria',
  'notes',
  'spec_id',
  'status',
  'priority',
  'issue_type',
  'assignee',
  'owner',
  'estimated_minutes',
  'created_at',
  'created_by',
  'updated_at',
  'started_at',
  'closed_at',
  'close_reason',
  'closed_by_session',
  'due_at',
  'defer_until',
  'external_ref',
  'source_system',
  'metadata',
  'labels',
  'ephemeral',
  'dependency_count',
  'dependent_count',
  'comment_count',
};

/// `owner` is populated from the capture host's git identity. The rc capture
/// pins HOME to a throwaway root so no identity — and no operator email —
/// reaches the bytes, so its absence is a capture-environment fact, not
/// upstream drift.
const seedDrivenAbsences = <String>{'owner'};

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

/// The union of issue-object keys across a set's issue-bearing captures.
Set<String> issueKeyUnion(String set) {
  final keys = <String>{};
  for (final file in const [
    'fx-session-sample.json',
    'fx-message-sample.json',
    'fx-molecule-sample.json',
    'fx-ready-sample.json',
    'fx-show-sample.json',
  ]) {
    final data = (fixture('$set/$file')! as Map<String, Object?>)['data'];
    if (data case final List<Object?> list) {
      for (final item in list) {
        if (item case final Map<String, Object?> map) keys.addAll(map.keys);
      }
    }
  }
  for (final line in const LineSplitter().convert(
    File(
      '../../fixtures/upstream/$set/fx-export-sample.jsonl',
    ).readAsStringSync(),
  )) {
    if (line.trim().isEmpty) continue;
    keys.addAll((jsonDecode(line) as Map<String, Object?>).keys);
  }
  return keys;
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

  test('rc.1 keeps envelope schema_version 1 everywhere', () {
    for (final file in capturedEnvelopes) {
      final envelope = fixture('$rcFixtureSet/$file')! as Map<String, Object?>;
      expect(envelope['schema_version'], 1, reason: file);
    }
  });

  test('rc.1 removes no Bead-decoded wire key', () {
    final removed = issueKeyUnion(mainFixtureSet)
        .intersection(beadWireKeys)
        .difference(issueKeyUnion(rcFixtureSet))
        .difference(seedDrivenAbsences);
    expect(
      removed,
      isEmpty,
      reason:
          'bd 1.3.0-rc.1 dropped decoded wire key(s) $removed — a NON-additive '
          'delta. Fix the decoder before any store moves (D-BD1 release rail).',
    );
  });

  test('rc.1 adds close_reason and nothing else', () {
    final added = issueKeyUnion(
      rcFixtureSet,
    ).difference(issueKeyUnion(mainFixtureSet));
    expect(added, {'close_reason'});
    final session = issueMap(fixture('$rcFixtureSet/fx-session-sample.json'));
    expect(session['status'], 'closed');
    expect(session['close_reason'], 'Closed');
    final mainSession = issueMap(
      fixture('$mainFixtureSet/fx-session-sample.json'),
    );
    expect(mainSession, isNot(contains('close_reason')));
  });

  test('rc.1 widens revision from a JSON number to a JSON string', () {
    expect(
      issueMap(fixture('$mainFixtureSet/fx-show-sample.json'))['revision'],
      isA<int>(),
    );
    expect(
      issueMap(fixture('$rcFixtureSet/fx-show-sample.json'))['revision'],
      isA<String>(),
      reason:
          'rc.1 emits revision as a decimal string; beads_dart decodes no '
          'revision field, so this is a pinned fixture-level delta.',
    );
  });

  test('rc.1 stores --set-metadata values as typed JSON scalars', () {
    final rc = issueMap(fixture('$rcFixtureSet/fx-show-sample.json'));
    final metadata = rc['metadata']! as Map<String, Object?>;
    expect(metadata['attempt'], isA<int>());
    expect(metadata['flag'], isA<bool>());
    expect(metadata.containsKey('nothing'), isTrue);
    expect(metadata['nothing'], isNull);
    expect(metadata['name'], isA<String>());
    final main = issueMap(fixture('$mainFixtureSet/fx-show-sample.json'));
    expect(
      (main['metadata']! as Map<String, Object?>).values,
      everyElement(isA<String>()),
      reason: 'pre-1.3 --set-metadata values are string-forced',
    );
  });

  test('rc.1 changes the not-found error text but not the envelope keys', () {
    final mainError =
        (fixture('$mainFixtureSet/tg-error-stdout.json')!
                as Map<String, Object?>)['data']!
            as Map<String, Object?>;
    final rcError =
        (fixture('$rcFixtureSet/tg-error-stdout.json')!
                as Map<String, Object?>)['data']!
            as Map<String, Object?>;
    expect(rcError.keys, mainError.keys);
    expect(mainError['error'], 'not found: issue tg-nonexistent');
    expect(rcError['error'], contains('no issue found matching'));
  });

  test('rc.1 README records the deltas the byte set cannot witness', () {
    final readme = File(
      '../../fixtures/upstream/$rcFixtureSet/README.md',
    ).readAsStringSync();
    expect(readme, contains('v1.3.0-rc.1'));
    expect(readme, contains('9c6a69ec12350959ec8c495c74eeb02902d629b6'));
    for (final delta in const [
      'hint',
      'RFC3339Nano',
      'labels on proxied create/update envelopes',
      'MIXED shapes',
      'no longer cascades',
      'owner is ABSENT',
    ]) {
      expect(readme, contains(delta), reason: delta);
    }
  });
}
