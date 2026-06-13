import 'package:grid_controller/src/models/bead.dart';
import 'package:grid_controller/src/models/bead_status.dart';
import 'package:grid_controller/src/models/dependency_type.dart';
import 'package:grid_controller/src/models/issue_type.dart';
import 'package:grid_controller/src/services/dolt_row_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('beadFromRow', () {
    test('maps a fully-populated row (typedAssoc shape: DateTime + Map)', () {
      final created = DateTime.utc(2026, 6, 11, 6, 1);
      final updated = DateTime.utc(2026, 6, 11, 7, 2);
      final started = DateTime.utc(2026, 6, 11, 6, 30);
      final row = <String, Object?>{
        'id': 'tg-abc',
        'title': 'Wire the reconciler',
        'description': 'desc',
        'design': 'design',
        'acceptance_criteria': 'ac',
        'notes': 'notes',
        'spec_id': 'spec-1',
        'status': 'in_progress',
        'priority': 1,
        'issue_type': 'task',
        'assignee': 'grid',
        'owner': 'nico',
        'estimated_minutes': 45,
        'created_at': created,
        'created_by': 'grid-controller',
        'updated_at': updated,
        'started_at': started,
        'closed_at': null,
        'close_reason': '',
        'closed_by_session': '',
        'due_at': null,
        'defer_until': null,
        'external_ref': 'ext:42',
        'source_system': 'grid',
        'metadata': <String, dynamic>{'k': 'v', 'n': 3},
        'ephemeral': 0,
      };

      final bead = beadFromRow(
        row,
        labels: const ['zeta', 'alpha'],
        dependencyCount: 2,
        dependentCount: 1,
        commentCount: 4,
      );

      expect(bead.id, 'tg-abc');
      expect(bead.title, 'Wire the reconciler');
      expect(bead.specId, 'spec-1');
      expect(bead.status, BeadStatus.inProgress);
      expect(bead.priority, 1);
      expect(bead.issueType, IssueType.task);
      expect(bead.assignee, 'grid');
      expect(bead.owner, 'nico');
      expect(bead.estimatedMinutes, 45);
      expect(bead.createdAt, created);
      expect(bead.updatedAt, updated);
      expect(bead.startedAt, started);
      expect(bead.closedAt, isNull);
      expect(bead.externalRef, 'ext:42');
      expect(bead.sourceSystem, 'grid');
      expect(bead.metadata, {'k': 'v', 'n': 3});
      expect(bead.ephemeral, isFalse);
      expect(bead.dependencyCount, 2);
      expect(bead.dependentCount, 1);
      expect(bead.commentCount, 4);
      // Labels are sorted regardless of input order.
      expect(bead.labels, ['alpha', 'zeta']);
    });

    test('maps the assoc() shape: String timestamps, JSON-string metadata, '
        "ephemeral as '1'", () {
      final row = <String, Object?>{
        'id': 'tg-str',
        'title': 'titled',
        'description': 'd',
        'design': '',
        'acceptance_criteria': '',
        'notes': '',
        'spec_id': '',
        'status': 'closed',
        'priority': '0',
        'issue_type': 'bug',
        'assignee': '',
        'owner': '',
        'estimated_minutes': null,
        'created_at': '2026-06-11 06:01:00',
        'created_by': 'grid-controller',
        'updated_at': '2026-06-11 07:02:00',
        'started_at': null,
        'closed_at': '2026-06-11 08:00:00',
        'close_reason': 'done',
        'closed_by_session': 'sess-9',
        'due_at': null,
        'defer_until': null,
        'external_ref': null,
        'source_system': '',
        'metadata': '{"k":"v","n":3}',
        'ephemeral': '1',
      };

      final bead = beadFromRow(row);

      expect(bead.status, BeadStatus.closed);
      expect(bead.isClosed, isTrue);
      expect(bead.priority, 0);
      expect(bead.issueType, IssueType.bug);
      // MySQL DATETIME is zone-naive; bd stores UTC, so the mapper reads a
      // zoneless string as UTC (matching the bd-CLI path's trailing-Z value).
      expect(bead.createdAt, DateTime.utc(2026, 6, 11, 6, 1));
      expect(bead.closedAt, DateTime.utc(2026, 6, 11, 8));
      expect(bead.closeReason, 'done');
      expect(bead.closedBySession, 'sess-9');
      expect(bead.externalRef, isNull);
      // JSON-string metadata is decoded into a Map.
      expect(bead.metadata, {'k': 'v', 'n': 3});
      // '1' → true.
      expect(bead.ephemeral, isTrue);
      expect(bead.labels, isEmpty);
    });

    test('maps a wisps-table row (A15 pour shape: ephemeral root with '
        'idempotency_key metadata; gate-typed speculative step)', () {
      // The `wisps` table shares every column this mapper reads with `issues`
      // (migrations 0020/0023/0027 + ignored-track is_blocked), so the same
      // mapper serves both halves of the issues ∪ wisps snapshot. A poured
      // convergence wisp root arrives ephemeral='1' with the idempotency key
      // under metadata (the find-before-pour probe surface).
      final root = beadFromRow(<String, Object?>{
        'id': 'tg-wisp-r1',
        'title': 'Convergence wisp iter 1',
        'status': 'open',
        'priority': '1',
        'issue_type': 'epic',
        'created_at': '2026-06-12 06:00:00',
        'metadata': '{"idempotency_key":"converge:tg-root:iter:1"}',
        'ephemeral': '1',
      });
      expect(root.ephemeral, isTrue);
      expect(root.issueType, IssueType.epic);
      expect(root.metadata['idempotency_key'], 'converge:tg-root:iter:1');

      // A speculative step pours as ready-excluded type `gate` with the real
      // type stashed under gc.deferred_* (A15) — and a CLOSED wisp row keeps
      // mapping (snapshot = all statuses; closedWispCount depends on it).
      final step = beadFromRow(<String, Object?>{
        'id': 'tg-wisp-s1',
        'title': 'iterate on tron',
        'status': 'closed',
        'issue_type': 'gate',
        'closed_at': '2026-06-12 07:00:00',
        'metadata': '{"gc.deferred_type":"task"}',
        'ephemeral': '1',
      });
      expect(step.ephemeral, isTrue);
      expect(step.issueType, IssueType.gate);
      expect(step.isClosed, isTrue);
      expect(step.metadata['gc.deferred_type'], 'task');
    });

    test('ephemeral 1 (int) → true', () {
      final bead = beadFromRow(<String, Object?>{'id': 'x', 'ephemeral': 1});
      expect(bead.ephemeral, isTrue);
    });

    test('ephemeral true (bool, typedAssoc TINYINT(1)) → true', () {
      final bead = beadFromRow(<String, Object?>{'id': 'x', 'ephemeral': true});
      expect(bead.ephemeral, isTrue);
    });

    test('null text columns collapse to empty strings; defaults apply', () {
      final bead = beadFromRow(<String, Object?>{
        'id': 'tg-min',
        'title': null,
        'description': null,
        'design': null,
        'acceptance_criteria': null,
        'notes': null,
        'spec_id': null,
        'status': null,
        'issue_type': null,
        'assignee': null,
        'owner': null,
        'created_by': null,
        'close_reason': null,
        'closed_by_session': null,
        'source_system': null,
        'metadata': null,
        'ephemeral': null,
      });

      expect(bead.title, '');
      expect(bead.description, '');
      expect(bead.design, '');
      expect(bead.acceptanceCriteria, '');
      expect(bead.notes, '');
      expect(bead.specId, '');
      expect(bead.assignee, '');
      expect(bead.owner, '');
      expect(bead.createdBy, '');
      expect(bead.sourceSystem, '');
      // Null enum-ish columns fall back to the codec defaults.
      expect(bead.status, BeadStatus.open);
      expect(bead.issueType, IssueType.task);
      expect(bead.priority, 0);
      expect(bead.metadata, isEmpty);
      expect(bead.ephemeral, isFalse);
      expect(bead.externalRef, isNull);
      expect(bead.estimatedMinutes, isNull);
    });

    test(
      'a custom status / custom type passes through unharmed (open set)',
      () {
        final bead = beadFromRow(<String, Object?>{
          'id': 'tg-custom',
          'status': 'convoy-running',
          'issue_type': 'convergence',
        });
        expect(bead.status, const BeadStatus('convoy-running'));
        expect(bead.issueType, IssueType.convergence);
      },
    );

    test('throws when the required id column is missing/null', () {
      expect(
        () => beadFromRow(<String, Object?>{'title': 'no id'}),
        throwsArgumentError,
      );
      expect(
        () => beadFromRow(<String, Object?>{'id': null}),
        throwsArgumentError,
      );
    });

    test('priority as num/double string coerces to int', () {
      expect(
        beadFromRow(<String, Object?>{'id': 'x', 'priority': 2.0}).priority,
        2,
      );
      expect(
        beadFromRow(<String, Object?>{'id': 'x', 'priority': '3'}).priority,
        3,
      );
    });

    group('equivalence with Bead.fromJson', () {
      test('SQL row and the equivalent JSON decode to the same Bead', () {
        // The CLI path decodes this JSON; the SQL path maps the row below.
        final json = <String, dynamic>{
          'id': 'tg-eq',
          'title': 'Equivalence',
          'description': 'body',
          'design': '',
          'acceptance_criteria': 'ac',
          'notes': '',
          'spec_id': 'spec-7',
          'status': 'open',
          'priority': 2,
          'issue_type': 'feature',
          'assignee': 'grid',
          'owner': '',
          'estimated_minutes': 30,
          'created_at': '2026-06-11T06:01:00.000Z',
          'created_by': 'grid-controller',
          'updated_at': '2026-06-11T07:02:00.000Z',
          'started_at': null,
          'closed_at': null,
          'close_reason': '',
          'closed_by_session': '',
          'due_at': null,
          'defer_until': null,
          'external_ref': null,
          'source_system': '',
          'metadata': {'a': 1, 'b': 'two'},
          'labels': ['beta', 'alpha'],
          'ephemeral': false,
          'dependency_count': 1,
          'dependent_count': 0,
          'comment_count': 2,
        };
        final fromCli = Bead.fromJson(json);

        // SQL row: snake_case columns, MySQL datetime strings, ephemeral 0,
        // labels arrive via the labels query (unsorted), counts via dep query.
        final row = <String, Object?>{
          'id': 'tg-eq',
          'title': 'Equivalence',
          'description': 'body',
          'design': '',
          'acceptance_criteria': 'ac',
          'notes': '',
          'spec_id': 'spec-7',
          'status': 'open',
          'priority': 2,
          'issue_type': 'feature',
          'assignee': 'grid',
          'owner': '',
          'estimated_minutes': 30,
          'created_at': '2026-06-11 06:01:00',
          'created_by': 'grid-controller',
          'updated_at': '2026-06-11 07:02:00',
          'started_at': null,
          'closed_at': null,
          'close_reason': '',
          'closed_by_session': '',
          'due_at': null,
          'defer_until': null,
          'external_ref': null,
          'source_system': '',
          'metadata': '{"a":1,"b":"two"}',
          'ephemeral': 0,
        };
        final fromSql = beadFromRow(
          row,
          labels: const ['beta', 'alpha'],
          dependencyCount: 1,
          dependentCount: 0,
          commentCount: 2,
        );

        // The CLI JSON above carries UTC ISO timestamps; align by comparing in
        // UTC, since the SQL datetime string is wall-clock (no zone).
        expect(
          fromSql.copyWith(createdAt: null, updatedAt: null),
          fromCli.copyWith(createdAt: null, updatedAt: null),
        );
        expect(fromSql.createdAt!.toUtc(), fromCli.createdAt!.toUtc());
        expect(fromSql.updatedAt!.toUtc(), fromCli.updatedAt!.toUtc());
        // Labels end up identically sorted on both paths.
        expect(fromSql.labels, fromCli.labels);
        expect(fromSql.labels, ['alpha', 'beta']);
      });
    });
  });

  group('dependencyFromRow', () {
    test('maps a dependencies row (assoc shape)', () {
      final row = <String, Object?>{
        'issue_id': 'tg-a',
        'depends_on_id': 'tg-b',
        'type': 'blocks',
        'created_at': '2026-06-11 06:01:00',
        'created_by': 'grid-controller',
        'metadata': '{"why":"x"}',
        'thread_id': 'thr-1',
      };

      final dep = dependencyFromRow(row);

      expect(dep.issueId, 'tg-a');
      expect(dep.dependsOnId, 'tg-b');
      expect(dep.type, DependencyType.blocks);
      expect(dep.createdAt, DateTime.utc(2026, 6, 11, 6, 1));
      expect(dep.createdBy, 'grid-controller');
      // BeadDependency keeps metadata as the raw JSON string.
      expect(dep.metadata, '{"why":"x"}');
      expect(dep.threadId, 'thr-1');
      expect(dep.edgeKey, 'tg-a tg-b blocks');
    });

    test('defaults: null type → blocks, null metadata → empty string', () {
      final dep = dependencyFromRow(<String, Object?>{
        'issue_id': 'tg-a',
        'depends_on_id': 'tg-b',
        'type': null,
        'created_at': null,
        'created_by': null,
        'metadata': null,
        'thread_id': null,
      });
      expect(dep.type, DependencyType.blocks);
      expect(dep.metadata, '');
      expect(dep.createdBy, '');
      expect(dep.threadId, '');
      expect(dep.createdAt, isNull);
    });

    test(
      'a custom dependency type passes through; blocking predicate holds',
      () {
        final dep = dependencyFromRow(<String, Object?>{
          'issue_id': 'tg-a',
          'depends_on_id': 'tg-b',
          'type': 'parent-child',
        });
        expect(dep.type, DependencyType.parentChild);
        expect(dep.type.affectsBlocking, isTrue);
        expect(dep.type.isBlockingEdge, isFalse);
      },
    );

    test('object-shaped metadata is re-encoded to a stable string', () {
      final dep = dependencyFromRow(<String, Object?>{
        'issue_id': 'tg-a',
        'depends_on_id': 'tg-b',
        'metadata': <String, dynamic>{'k': 'v'},
      });
      expect(dep.metadata, '{"k":"v"}');
    });

    test('throws when a primary-key column is missing', () {
      expect(
        () => dependencyFromRow(<String, Object?>{'issue_id': 'tg-a'}),
        throwsArgumentError,
      );
      expect(
        () => dependencyFromRow(<String, Object?>{'depends_on_id': 'tg-b'}),
        throwsArgumentError,
      );
    });
  });
}
