/// grid_cli's ledger half of the §9 shadow seam: the session-bead → view
/// projection (markers from `projectSession`, round from the `#rN` key
/// shape), the reader over the injected fetch, and the factory's graceful
/// degrade on a home with no ledger.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart'
    show
        BdException,
        Bead,
        BeadDependency,
        BeadStatus,
        DependencyType,
        IssueType;
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_trajectory/grid_trajectory.dart'
    show
        AttemptLifecycleShadow,
        CompositeShadow,
        LegacyStepView,
        MountOrdinalShadow,
        ShadowCompare,
        StepTransitionShadow,
        SubjectRecords;
import 'package:test/test.dart';

Bead sessionBead({
  String id = 'tranquility-1',
  String workBead = 'tg-9abc',
  BeadStatus status = BeadStatus.open,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  issueType: const IssueType('session'),
  status: status,
  metadata: {'work_bead': workBead, ...metadata},
);

Bead stepBead({
  String id = 'tranquility-step-1',
  BeadStatus status = BeadStatus.open,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  issueType: const IssueType('step'),
  status: status,
  metadata: metadata,
);

Bead mountAttemptBead({
  String id = 'tranquility-attempt-1',
  required String workBead,
  required String count,
}) => Bead(
  id: id,
  issueType: const IssueType('mount-attempt'),
  status: BeadStatus.open,
  metadata: {'grid.attempt.work_bead': workBead, 'grid.attempt.count': count},
);

void main() {
  group('legacySessionViewOf', () {
    test('a live bare-key session: open, no round, no markers', () {
      final view = legacySessionViewOf(sessionBead());
      expect(view.sessionId, 'tranquility-1');
      expect(view.workBeadId, 'tg-9abc');
      expect(view.closed, isFalse);
      expect(view.completed, isFalse);
      expect(view.held, isFalse);
      expect(view.voided, isFalse);
      expect(view.round, isNull);
    });

    test('a completed close carries the grid.outcome marker', () {
      final view = legacySessionViewOf(
        sessionBead(
          status: BeadStatus.closed,
          metadata: const {'grid.outcome': 'complete'},
        ),
      );
      expect(view.closed, isTrue);
      expect(view.completed, isTrue);
    });

    test('the #rN retired key strips to the base id and names the round', () {
      final view = legacySessionViewOf(sessionBead(workBead: 'tg-9abc#r2'));
      expect(view.workBeadId, 'tg-9abc');
      expect(view.round, 2);
      expect(view.voided, isFalse);
    });

    test('the #void- dead key strips and flags voided, never a round', () {
      final view = legacySessionViewOf(
        sessionBead(workBead: 'tg-9abc#void-tranquility-0'),
      );
      expect(view.workBeadId, 'tg-9abc');
      expect(view.voided, isTrue);
      expect(view.round, isNull);
    });

    test('human markers project held + the diagnostic reason', () {
      final escalated = legacySessionViewOf(
        sessionBead(
          status: BeadStatus.closed,
          metadata: const {
            'grid.escalation': 'true',
            'grid.escalation_reason': 'breaker exhausted',
          },
        ),
      );
      expect(escalated.held, isTrue);
      expect(escalated.heldReason, 'breaker exhausted');

      final declined = legacySessionViewOf(
        sessionBead(
          status: BeadStatus.closed,
          metadata: const {
            'grid.rework_declined': 'true',
            'grid.rework_declined_reason': 'orphaned at a gate',
          },
        ),
      );
      expect(declined.held, isTrue);
      expect(declined.heldReason, 'orphaned at a gate');
    });
  });

  group('BdLegacySessionReader', () {
    test('returns the view for a matching bead, null otherwise', () async {
      final reader = BdLegacySessionReader(
        (ids) async => [sessionBead(id: ids.single)],
      );
      final view = await reader.sessionView('tranquility-1');
      expect(view!.workBeadId, 'tg-9abc');

      final empty = BdLegacySessionReader((ids) async => const []);
      expect(await empty.sessionView('tranquility-2'), isNull);
    });
  });

  group('legacyShadowCompareFor', () {
    test(
      'a home with no ledger degrades: nothing comparable, with a reason',
      () async {
        final home = Directory.systemTemp.createTempSync('traj_legacy_');
        addTearDown(() => home.deleteSync(recursive: true));
        final ShadowCompare shadow = await legacyShadowCompareFor(home.path);
        expect(shadow, isA<LegacyStoreUnavailableShadow>());
        expect(shadow.comparableFields, isEmpty);
        expect(shadow.unavailableReason, contains('no grid state store'));
        final result = await shadow.compare(
          sessionId: 's',
          records: const SubjectRecords(records: []),
        );
        expect(result.mismatches, isEmpty);
        // A degrade is not an incomplete READ — it is "no oracle here at all",
        // which the verb reports through unavailableReason instead.
        expect(result.isIncomplete, isFalse);
      },
    );

    test(
      'a seeded state-store layout arms the real Family-1 comparator',
      () async {
        final home = Directory.systemTemp.createTempSync('traj_legacy_');
        addTearDown(() => home.deleteSync(recursive: true));
        // The exact-root layout the resident verbs open: <home>/.grid/.beads,
        // with the store metadata that makes it a well-formed workspace.
        Directory('${home.path}/.grid/.beads').createSync(recursive: true);
        File(
          '${home.path}/.grid/.beads/metadata.json',
        ).writeAsStringSync('{"dolt_mode": "direct"}');
        final shadow = await legacyShadowCompareFor(home.path);
        // Stage 1 shadows three lanes over three different oracles; the verb
        // takes one strategy, so they arrive composed.
        expect(shadow, isA<CompositeShadow>());
        final lanes = (shadow as CompositeShadow).lanes;
        expect(lanes.map((lane) => lane.runtimeType), [
          AttemptLifecycleShadow,
          StepTransitionShadow,
          MountOrdinalShadow,
        ]);
        expect(
          shadow.comparableFields,
          containsAll(<String>['status', 'step_state', 'legacy_attempt_count']),
        );
      },
    );
  });

  group('legacyStepViewOf', () {
    test('projects the path, the fine state, and the cooldown', () {
      final view = legacyStepViewOf(
        stepBead(
          metadata: const {
            'grid.step.path': 'build',
            'grid.step.state': 'failed',
            'grid.step.cooldownUntil': '2026-08-31T10:15:30.000Z',
          },
        ),
      );
      expect(view!.stepPath, 'build');
      expect(view.state, 'failed');
      expect(view.cooldownUntil, DateTime.utc(2026, 8, 31, 10, 15, 30));
    });

    test("a step with no fine state carries null — never bd's coarse "
        'axis', () {
      final view = legacyStepViewOf(
        stepBead(metadata: const {'grid.step.path': 'build'}),
      );
      expect(view!.state, isNull);
      expect(view.cooldownUntil, isNull);
    });

    test('a bead with no node path is not projectable — nothing to join '
        'on', () {
      expect(legacyStepViewOf(stepBead()), isNull);
    });
  });

  group('BdLegacyStepReader', () {
    test('projects every step bead the fetch yields', () async {
      final reader = BdLegacyStepReader(
        (session) async => [
          stepBead(
            metadata: {
              'grid.step.session': session,
              'grid.step.path': 'build',
              'grid.step.state': 'running',
            },
          ),
          stepBead(metadata: const {'grid.step.state': 'running'}),
        ],
      );
      final views = await reader.stepViews('tranquility-1');
      // The path-less bead is dropped, not guessed at.
      expect(views.map((view) => view.stepPath), ['build']);
      // No session fetch: every view is shadow-era.
      expect(views.single.cutDiscipline, isFalse);
    });

    // tg-ul2v: the lane can only classify a retired legacy carrier when it
    // knows the session ran under cut — and it learns that from the SESSION
    // bead's own stamp, read through grid_engine's `sessionDisciplineOf`.
    Future<List<LegacyStepView>> viewsFor(
      Map<String, dynamic> sessionMetadata, {
      bool throws = false,
    }) => BdLegacyStepReader(
      (session) async => [
        stepBead(
          metadata: {
            'grid.step.session': session,
            'grid.step.path': 'build',
            'grid.step.state': 'pending',
          },
        ),
      ],
      sessionFetch: (ids) async {
        if (throws) {
          throw BdException.fromOutput(
            command: const ['show', 'tranquility-1'],
            exitCode: 1,
            stdout: '',
            stderr: 'bd show failed',
          );
        }
        return [
          sessionBead(
            id: 'tranquility-OTHER',
            metadata: const {'grid.session.discipline': 'cut'},
          ),
          sessionBead(metadata: sessionMetadata),
        ];
      },
    ).stepViews('tranquility-1');

    test('a CUT-stamped session marks every one of its step views', () async {
      final views = await viewsFor(const {'grid.session.discipline': 'cut'});
      expect(views.single.cutDiscipline, isTrue);
    });

    test('an unstamped or shadow session, or an unreadable one, is '
        'shadow-era — never classified on a guess', () async {
      expect((await viewsFor(const {})).single.cutDiscipline, isFalse);
      expect(
        (await viewsFor(const {
          'grid.session.discipline': 'shadow',
        })).single.cutDiscipline,
        isFalse,
      );
      expect(
        (await viewsFor(const {
          'grid.session.discipline': 'cut',
        }, throws: true)).single.cutDiscipline,
        isFalse,
      );
    });
  });

  group('BdLegacyMountAttemptReader', () {
    test('reads grid.attempt.count for the joined work bead', () async {
      final reader = BdLegacyMountAttemptReader(
        (workBeadId) async => [
          mountAttemptBead(workBead: workBeadId, count: '2'),
        ],
      );
      expect(await reader.attemptCount('tg-9abc'), 2);
    });

    test('a record for ANOTHER work bead never answers this join', () async {
      final reader = BdLegacyMountAttemptReader(
        (_) async => [mountAttemptBead(workBead: 'tg-OTHER', count: '9')],
      );
      expect(await reader.attemptCount('tg-9abc'), isNull);
    });

    test('no record is null — a first-try mount, not a zero', () async {
      final reader = BdLegacyMountAttemptReader((_) async => const []);
      expect(await reader.attemptCount('tg-9abc'), isNull);
    });
  });

  group('BdLegacyG2Reader', () {
    final oldBuild = stepBead(
      id: 'step-old',
      metadata: const {
        'grid.step.session': 'tranquility-1',
        'grid.step.path': 'build',
      },
    );
    final newBuild = stepBead(
      id: 'step-new',
      metadata: const {
        'grid.step.session': 'tranquility-1',
        'grid.step.path': 'build',
      },
    );
    final verify = stepBead(
      id: 'step-verify',
      metadata: const {
        'grid.step.session': 'tranquility-1',
        'grid.step.path': 'verify',
      },
    );
    final dependencies = <BeadDependency>[
      const BeadDependency(
        issueId: 'step-new',
        dependsOnId: 'step-old',
        type: DependencyType.supersedes,
      ),
      const BeadDependency(
        issueId: 'step-new',
        dependsOnId: 'step-verify',
        type: DependencyType.blocks,
      ),
    ];
    final reader = BdLegacyG2Reader.fromFetch(
      (_) async =>
          (beads: [oldBuild, newBuild, verify], dependencies: dependencies),
    );

    test('normalizes the legacy semantic graph', () async {
      final graph = await reader.graphView('tranquility-1');
      expect(graph!.nodes, {'build', 'verify'});
      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.fromPath, 'build');
      expect(graph.edges.single.toPath, 'verify');
      expect(graph.edges.single.kind, 'blocks');
    });

    test('normalizes successor relationship and depth', () async {
      final successors = await reader.successorViews('tranquility-1');
      expect(successors, hasLength(1));
      expect(successors.single.stepPath, 'build');
      expect(successors.single.supersedesId, 'step-old');
      expect(successors.single.depth, 1);
    });
  });
}
