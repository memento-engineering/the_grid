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

GraphSnapshot snapshot(
  Iterable<Bead> beads, {
  Iterable<BeadDependency> dependencies = const [],
  Iterable<String> readyIds = const [],
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: dependencies,
  readyIds: readyIds,
  capturedAt: DateTime.utc(2026, 9, 18),
);

Bead stamped(String id) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.open,
  metadata: const {kEligibilityApprovalKey: '2026-09-18T00:00:00Z'},
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

    test('a capability is shipped by a bead that is not named after it — the '
        'FAN-IN form', () {
      expect(
        capabilityShipped('release-gate', [
          closed('pow-9', labels: const ['provides:release-gate']),
        ]),
        isTrue,
      );
    });

    test(
      'unshipped capabilities are the exports with no matching provides',
      () {
        expect(
          unshippedCapabilities(const [
            'export:a',
            'provides:a',
            'export:b',
            'provides:c',
          ]),
          ['b'],
        );
      },
    );

    test('unshippedExports is the CLOSED beads still owing a bd ship', () {
      final owed = unshippedExports([
        closed('pow-1', labels: const ['export:pow-1']),
        closed('pow-2', labels: const ['export:pow-2', 'provides:pow-2']),
        closed('pow-3', labels: const ['export:pow-3', 'export:release-gate']),
        closed('pow-4'),
        bead('pow-5').copyWith(labels: const ['export:pow-5']),
      ]);
      expect(owed, {
        'pow-1': ['pow-1'],
        'pow-3': ['pow-3', 'release-gate'],
      });
    });
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

  group('healableExternalDepTargets', () {
    const row = BeadDependency(
      issueId: 'tg-1',
      dependsOnId: 'external:power_station:pow-9',
    );

    Map<String, GraphSnapshot> federation({
      required BeadDependency dependency,
      Iterable<Bead> powerBeads = const [],
      bool includePower = true,
    }) => {
      'the_grid': snapshot([stamped('tg-1')], dependencies: [dependency]),
      if (includePower) 'power_station': snapshot(powerBeads),
    };

    test('classifies only an exact CLOSED unlabelled core target', () {
      expect(
        healableExternalDepTargets(
          federation(dependency: row, powerBeads: [closed('pow-9')]),
        ),
        const [ExternalDepRef(project: 'power_station', capability: 'pow-9')],
      );

      final excluded = <String, Map<String, GraphSnapshot>>{
        'missing project': federation(dependency: row, includePower: false),
        'absent exact id': federation(
          dependency: row,
          powerBeads: [closed('pow-other')],
        ),
        'named capability': federation(
          dependency: const BeadDependency(
            issueId: 'tg-1',
            dependsOnId: 'external:power_station:release-gate',
          ),
          powerBeads: [
            closed('pow-container', labels: const ['export:release-gate']),
          ],
        ),
        'open target': federation(dependency: row, powerBeads: [bead('pow-9')]),
        'non-core target': federation(
          dependency: row,
          powerBeads: const [
            Bead(
              id: 'pow-9',
              issueType: IssueType('session'),
              status: BeadStatus.closed,
            ),
          ],
        ),
        'provided target': federation(
          dependency: row,
          powerBeads: [
            closed('pow-9', labels: const ['provides:pow-9']),
          ],
        ),
        'non-blocking row': federation(
          dependency: const BeadDependency(
            issueId: 'tg-1',
            dependsOnId: 'external:power_station:pow-9',
            type: DependencyType.related,
          ),
          powerBeads: [closed('pow-9')],
        ),
      };
      for (final entry in excluded.entries) {
        expect(
          healableExternalDepTargets(entry.value),
          isEmpty,
          reason: entry.key,
        );
      }
    });

    test('deduplicates multiple consumers and returns lexical wire order', () {
      final grid = snapshot(
        [stamped('tg-1'), stamped('tg-2')],
        dependencies: const [
          BeadDependency(issueId: 'tg-1', dependsOnId: 'external:zeta:z-1'),
          BeadDependency(issueId: 'tg-1', dependsOnId: 'external:alpha:a-1'),
          BeadDependency(issueId: 'tg-2', dependsOnId: 'external:alpha:a-1'),
        ],
      );
      expect(
        healableExternalDepTargets({
          'the_grid': grid,
          'zeta': snapshot([closed('z-1')]),
          'alpha': snapshot([closed('a-1')]),
        }),
        const [
          ExternalDepRef(project: 'alpha', capability: 'a-1'),
          ExternalDepRef(project: 'zeta', capability: 'z-1'),
        ],
      );
    });
  });

  group('externalDepOpenTargetClause', () {
    MountEligibilityDecision evaluate({
      required Bead consumer,
      required List<BeadDependency> dependencies,
      required List<Bead> targets,
    }) {
      final graph = snapshot([
        consumer,
        ...targets,
      ], dependencies: dependencies);
      return externalDepOpenTargetClause(graph)(consumer);
    }

    test('refuses only stamped blocking rows with an exact OPEN target', () {
      const row = BeadDependency(
        issueId: 'tg-1',
        dependsOnId: 'external:power_station:pow-9',
      );
      final approved = stamped('tg-1');

      expect(
        evaluate(
          consumer: bead('tg-1'),
          dependencies: const [row],
          targets: [bead('pow-9')],
        ),
        const MountEligibilityDecision.eligible(),
        reason: 'unstamped',
      );
      expect(
        evaluate(
          consumer: approved,
          dependencies: const [
            BeadDependency(
              issueId: 'tg-1',
              dependsOnId: 'external:power_station:pow-9',
              type: DependencyType.related,
            ),
          ],
          targets: [bead('pow-9')],
        ),
        const MountEligibilityDecision.eligible(),
        reason: 'non-blocking',
      );
      expect(
        evaluate(
          consumer: approved,
          dependencies: const [row],
          targets: [bead('pow-9').copyWith(status: BeadStatus.inProgress)],
        ),
        const MountEligibilityDecision.eligible(),
        reason: 'the visibility clause is intentionally exact-OPEN',
      );

      final graph = snapshot(
        [approved, bead('pow-9')],
        dependencies: const [row],
      );
      expect(
        externalDepOpenTargetClause(graph)(approved),
        const MountEligibilityDecision.refused(
          clause: 'external-unshipped: power_station:pow-9 (target open)',
        ),
      );
      expect(hasStampedOpenExternalTargetHold(graph, approved), isTrue);
    });

    test('orders multiple exact open targets lexically', () {
      final consumer = stamped('tg-1');
      expect(
        evaluate(
          consumer: consumer,
          dependencies: const [
            BeadDependency(issueId: 'tg-1', dependsOnId: 'external:zeta:z-1'),
            BeadDependency(issueId: 'tg-1', dependsOnId: 'external:alpha:a-1'),
          ],
          targets: [bead('z-1'), bead('a-1')],
        ),
        const MountEligibilityDecision.refused(
          clause: 'external-unshipped: alpha:a-1 (target open)',
        ),
      );
    });

    test('absent named and CLOSED targets are eligible at this clause', () {
      final consumer = stamped('tg-1');
      for (final targets in <List<Bead>>[
        [
          closed('pow-container', labels: const ['export:release-gate']),
        ],
        [closed('pow-9')],
        [
          closed('pow-9', labels: const ['provides:pow-9']),
        ],
      ]) {
        final capability = targets.single.id == 'pow-container'
            ? 'release-gate'
            : 'pow-9';
        expect(
          evaluate(
            consumer: consumer,
            dependencies: [
              BeadDependency(
                issueId: 'tg-1',
                dependsOnId: 'external:power_station:$capability',
              ),
            ],
            targets: targets,
          ),
          const MountEligibilityDecision.eligible(),
        );
      }
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

    test('names the effective-config surface and every configured project', () {
      final refusal = externalProjectConfigRefusal(
        project: 'power_station',
        configured: const {'swift_infer', 'genesis'},
        store: '/work/the_grid',
      )!;
      expect(refusal, contains('/work/the_grid'));
      expect(refusal, contains('external_projects.power_station'));
      expect(refusal, contains('Configured: genesis, swift_infer'));
      expect(refusal, contains('bd config show --json'));
    });

    test('an unconfigured store names the project, surface, and <none>', () {
      final refusal = externalProjectConfigRefusal(
        project: 'power_station',
        configured: const {},
        store: '/work/the_grid',
      )!;
      expect(refusal, contains('/work/the_grid'));
      expect(refusal, contains('external_projects.power_station'));
      expect(refusal, contains('bd config show --json'));
      expect(refusal, contains('Configured: <none>'));
    });
  });
}
