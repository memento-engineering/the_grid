import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  group('BeadStatus', () {
    test('built-in category mapping mirrors upstream', () {
      expect(BeadStatus.open.category, StatusCategory.active);
      expect(BeadStatus.inProgress.category, StatusCategory.wip);
      expect(BeadStatus.blocked.category, StatusCategory.wip);
      expect(BeadStatus.hooked.category, StatusCategory.wip);
      expect(BeadStatus.closed.category, StatusCategory.done);
      expect(BeadStatus.deferred.category, StatusCategory.frozen);
      expect(BeadStatus.pinned.category, StatusCategory.frozen);
    });

    test('custom status decodes without throwing (open-set behavior)', () {
      const custom = BeadStatus('triaging');
      expect(custom.category, StatusCategory.unspecified);
      expect(custom.isBuiltIn, isFalse);
      expect(custom.isClosed, isFalse);
    });

    test('value equality via underlying string', () {
      expect(const BeadStatus('open'), BeadStatus.open);
      final deduped = <BeadStatus>{}
        ..add(BeadStatus.open)
        ..add(BeadStatus('open'.toString()));
      expect(deduped, hasLength(1));
    });

    test('the seven built-ins match the statuses fixture', () {
      final env = BdEnvelope.parse(fixtureText('tg-statuses.json'));
      final names = [
        for (final s in (env.dataMap['built_in_statuses']! as List))
          (s as Map<String, dynamic>)['name'] as String,
      ];
      expect(BeadStatus.builtIns.map((s) => s.wire).toSet(), names.toSet());
    });
  });

  group('IssueType', () {
    test('contains exactly the nine upstream built-ins', () {
      expect(
        IssueType.coreTypes.map((type) => type.wire).toSet(),
        equals({
          'task',
          'bug',
          'feature',
          'chore',
          'epic',
          'decision',
          'spike',
          'story',
          'milestone',
        }),
      );
      for (final type in IssueType.coreTypes) {
        expect(type.isCore, isTrue, reason: type.wire);
      }
      expect(const IssueType('molecule').isCore, isFalse);
      expect(const IssueType('unknown-custom').isCore, isFalse);
    });

    test('preserves workspace-specific values', () {
      const type = IssueType('workspace-specific');
      expect(type.wire, 'workspace-specific');
    });
  });

  group('DependencyType', () {
    test('affectsBlocking matches upstream AffectsReadyWork', () {
      for (final t in [
        DependencyType.blocks,
        DependencyType.parentChild,
        DependencyType.conditionalBlocks,
        DependencyType.waitsFor,
      ]) {
        expect(t.affectsBlocking, isTrue, reason: t.wire);
      }
      expect(DependencyType.related.affectsBlocking, isFalse);
      expect(DependencyType.tracks.affectsBlocking, isFalse);
    });

    test('isBlockingEdge excludes parent-child', () {
      expect(DependencyType.blocks.isBlockingEdge, isTrue);
      expect(DependencyType.conditionalBlocks.isBlockingEdge, isTrue);
      expect(DependencyType.waitsFor.isBlockingEdge, isTrue);
      expect(DependencyType.parentChild.isBlockingEdge, isFalse);
    });
  });
}
