import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// Decodes the first record from a `{schema_version, data: [...]}` fixture.
Bead _firstBead(String fixture) {
  final env = BdEnvelope.parse(fixtureText(fixture));
  return Bead.fromJson(env.dataList.first);
}

void main() {
  group('Bead.fromJson against pinned fixtures', () {
    test('session bead decodes core + snake_case fields', () {
      final bead = _firstBead('hq-session-sample.json');
      expect(bead.id, 'ga-dvt2');
      expect(bead.issueType, IssueType.session);
      expect(bead.status, BeadStatus.closed);
      expect(bead.isClosed, isTrue);
      expect(bead.status.category, StatusCategory.done);
      expect(bead.closeReason, contains('session drained'));
      expect(bead.closedAt, isNotNull);
      // metadata is an arbitrary JSON object, preserved verbatim.
      expect(bead.metadata['agent_name'], 'lenny/pack.critique-1');
    });

    test('message bead decodes labels, ephemeral, assignee', () {
      final bead = _firstBead('hq-message-sample.json');
      expect(bead.issueType, IssueType.message);
      expect(bead.assignee, 'mayor');
      expect(bead.ephemeral, isTrue);
      expect(bead.labels, contains('thread:thread-067ce293d2d4'));
      expect(bead.metadata['from'], 'controller');
    });

    test('molecule bead decodes', () {
      final bead = _firstBead('hq-molecule-sample.json');
      expect(bead.issueType, IssueType.molecule);
      expect(bead.title, 'mol-dog-stale-db');
    });

    test('export record decodes comments + counts', () {
      final records = fixtureJsonl('hq-export-sample.jsonl');
      final bead = Bead.fromJson(records.first);
      expect(bead.id, 'ga-bdzf');
      expect(bead.issueType, IssueType.bug);
      expect(bead.priority, 0);
      expect(bead.commentCount, 3);
      expect(bead.comments, hasLength(3));
      expect(bead.comments.first.author, 'Nico Spencer');
    });

    test('all 25 export records round-trip without throwing', () {
      final records = fixtureJsonl('hq-export-sample.jsonl');
      expect(records, hasLength(25));
      for (final record in records) {
        final bead = Bead.fromJson(record);
        expect(bead.id, isNotEmpty);
        // toJson is total (no throw) and preserves id + status wire form.
        final json = bead.toJson();
        expect(json['id'], bead.id);
        expect(json['status'], bead.status.wire);
        expect(json['issue_type'], bead.issueType.wire);
      }
    });
  });

  group('Bead value semantics', () {
    test('two beads with equal fields are == (the diff primitive)', () {
      final records = fixtureJsonl('hq-export-sample.jsonl');
      final a = Bead.fromJson(records.first);
      final b = Bead.fromJson(records.first);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith changing a field breaks equality', () {
      final bead = _firstBead('hq-message-sample.json');
      expect(bead.copyWith(priority: 99), isNot(equals(bead)));
    });

    test('deep equality on metadata map', () {
      const a = Bead(id: 'x', metadata: {'k': 'v'});
      const b = Bead(id: 'x', metadata: {'k': 'v'});
      expect(a, equals(b));
      expect(a.copyWith(metadata: const {'k': 'w'}), isNot(equals(a)));
    });
  });

  group('defaults', () {
    test('minimal bead applies safe defaults', () {
      const bead = Bead(id: 'tg-1');
      expect(bead.status, BeadStatus.open);
      expect(bead.issueType, IssueType.task);
      expect(bead.priority, 0);
      expect(bead.labels, isEmpty);
      expect(bead.ephemeral, isFalse);
    });
  });
}
