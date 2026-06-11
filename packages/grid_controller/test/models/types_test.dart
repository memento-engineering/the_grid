import 'package:grid_controller/grid_controller.dart';
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
    test('core vs custom classification', () {
      expect(IssueType.task.isCore, isTrue);
      expect(IssueType.molecule.isCore, isFalse);
    });

    test('infra types are the list-hidden set (A5)', () {
      expect(IssueType.agent.isInfra, isTrue);
      expect(IssueType.rig.isInfra, isTrue);
      expect(IssueType.role.isInfra, isTrue);
      expect(IssueType.session.isInfra, isFalse);
      expect(IssueType.molecule.isInfra, isFalse);
    });

    test('custom-types fixture is fully covered by named constants', () {
      final env = BdEnvelope.parse(fixtureText('tg-types.json'));
      final customNames = (env.dataMap['custom_types']! as List)
          .cast<String>()
          .toSet();
      const known = <IssueType>[
        IssueType.agent,
        IssueType.convergence,
        IssueType.convoy,
        IssueType.event,
        IssueType.gate,
        IssueType.mergeRequest,
        IssueType.message,
        IssueType.molecule,
        IssueType.rig,
        IssueType.role,
        IssueType.session,
        IssueType.spec,
        IssueType.step,
      ];
      expect(known.map((t) => t.wire).toSet(), customNames);
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
