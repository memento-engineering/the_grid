// tg-xh5d (`the_grid#capability-edges-are-bd-native-and-link-is-sugar`): the
// PURE reading of bd's native `external:<project>:<capability>` rows — parse,
// admission, and the two config maps that must name the same roster.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

Bead closed(String id, {List<String> labels = const []}) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.closed,
  labels: labels,
);

void main() {
  group('ExternalDepRef', () {
    test('parses the wire form and round-trips it', () {
      final ref = ExternalDepRef.parse('external:power_station:pow-9')!;
      expect(ref.project, 'power_station');
      expect(ref.capability, 'pow-9');
      expect(ref.wire, 'external:power_station:pow-9');
      expect(
        ref,
        const ExternalDepRef(project: 'power_station', capability: 'pow-9'),
      );
    });

    test('a capability may itself carry colons — only the FIRST separator '
        'splits the project off', () {
      final ref = ExternalDepRef.parse('external:p:a:b')!;
      expect(ref.project, 'p');
      expect(ref.capability, 'a:b');
    });

    test('a local id, and every malformed spelling, parse as NOT external', () {
      for (final raw in const [
        'pow-9',
        'external:',
        'external:p',
        'external:p:',
        'external::cap',
        'externals:p:cap',
      ]) {
        expect(ExternalDepRef.parse(raw), isNull, reason: raw);
      }
    });
  });

  group('capability labels', () {
    test('export/provides spell one convention, read back off a label set', () {
      expect(exportLabel('pow-9'), 'export:pow-9');
      expect(providesLabel('pow-9'), 'provides:pow-9');
      const labels = [
        'export:a',
        'provides:b',
        'export:',
        'priority',
        'export:c',
      ];
      expect(exportedCapabilities(labels), ['a', 'c']);
      expect(providedCapabilities(labels), ['b']);
    });

    test(
      'a capability is shipped only by a CLOSED bead carrying provides:',
      () {
        expect(
          capabilityShipped('pow-9', [
            closed('pow-9', labels: const ['provides:pow-9']),
          ]),
          isTrue,
        );
        expect(capabilityShipped('pow-9', [closed('pow-9')]), isFalse);
        expect(
          capabilityShipped('pow-9', [
            bead('pow-9').copyWith(labels: const ['provides:pow-9']),
          ]),
          isFalse,
          reason:
              '`bd ship --force` on an OPEN issue is not a finished blocker',
        );
      },
    );
  });

  group('applyExternalDeps', () {
    const armedRow = BeadDependency(
      issueId: 'tg-1',
      dependsOnId: 'external:power_station:pow-9',
    );

    test('an unshipped capability blocks silently; a shipped one admits', () {
      final blocked = applyExternalDeps(
        candidates: {'tg-1', 'tg-2'},
        dependencies: const [armedRow],
        isArmed: (project) => project == 'power_station',
        isShipped: (_, _) => false,
      );
      expect(blocked.admitted, {'tg-2'});
      expect(blocked.refusals, isEmpty);

      final admitted = applyExternalDeps(
        candidates: {'tg-1', 'tg-2'},
        dependencies: const [armedRow],
        isArmed: (project) => project == 'power_station',
        isShipped: (_, _) => true,
      );
      expect(admitted.admitted, {'tg-1', 'tg-2'});
      expect(admitted.refusals, isEmpty);
    });

    test('an unarmed project BLOCKS and refuses, naming both ends', () {
      final verdict = applyExternalDeps(
        candidates: {'tg-1'},
        dependencies: const [armedRow],
        isArmed: (_) => false,
        isShipped: (_, _) => true,
      );
      expect(verdict.admitted, isEmpty);
      final refusal = verdict.refusals.single;
      expect(refusal.consumerId, 'tg-1');
      expect(refusal.edgeKey, 'tg-1->external:power_station:pow-9');
      final message = refusal.message('the_grid(tg)');
      expect(message, contains('REFUSED'));
      expect(message, contains('tg-1'));
      expect(message, contains('external:power_station:pow-9'));
      expect(message, contains('the_grid(tg)'));
    });

    test(
      'a duplicated row refuses once, and a non-blocking type never does',
      () {
        final verdict = applyExternalDeps(
          candidates: {'tg-1'},
          dependencies: const [
            armedRow,
            armedRow,
            BeadDependency(
              issueId: 'tg-2',
              dependsOnId: 'external:dashboard:d-1',
              type: DependencyType.related,
            ),
          ],
          isArmed: (_) => false,
          isShipped: (_, _) => true,
        );
        expect(verdict.refusals, hasLength(1));
      },
    );

    test('local and raw foreign rows are left entirely alone', () {
      final verdict = applyExternalDeps(
        candidates: {'tg-1'},
        dependencies: const [
          BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-2'),
          BeadDependency(issueId: 'tg-1', dependsOnId: 'pow-9'),
        ],
        isArmed: (_) => false,
        isShipped: (_, _) => false,
      );
      expect(verdict.admitted, {'tg-1'});
      expect(verdict.refusals, isEmpty);
    });

    test('an empty candidate set is returned as-is', () {
      final verdict = applyExternalDeps(
        candidates: const <String>{},
        dependencies: const [armedRow],
        isArmed: (_) => true,
        isShipped: (_, _) => false,
      );
      expect(verdict.admitted, isEmpty);
    });
  });

  group('externalProjectConfigRefusal', () {
    test('is null when bd already knows the project', () {
      expect(
        externalProjectConfigRefusal(
          project: 'power_station',
          configured: const {'power_station', 'genesis'},
          store: '/work/the_grid',
        ),
        isNull,
      );
    });

    test('names the store, the project and what bd does know', () {
      final refusal = externalProjectConfigRefusal(
        project: 'power_station',
        configured: const {'genesis'},
        store: '/work/the_grid',
      )!;
      expect(refusal, contains('/work/the_grid'));
      expect(refusal, contains('power_station'));
      expect(refusal, contains('genesis'));
      expect(refusal, contains('external_projects'));
    });

    test('an unconfigured store reads as <none>, never as an error', () {
      expect(
        externalProjectConfigRefusal(
          project: 'power_station',
          configured: const {},
          store: '/work/the_grid',
        ),
        contains('<none>'),
      );
    });
  });
}
