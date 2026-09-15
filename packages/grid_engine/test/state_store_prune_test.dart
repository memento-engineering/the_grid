import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 14, 12);
  const age = Duration(days: 3);
  final old = DateTime.utc(2026, 9, 10, 11);
  final cutoff = DateTime.utc(2026, 9, 11, 12);
  final young = DateTime.utc(2026, 9, 12);

  group('planStateStorePrune age and cutoff', () {
    for (final invalid in [Duration.zero, const Duration(microseconds: -1)]) {
      test('refuses non-positive age $invalid', () {
        expect(
          () => planStateStorePrune(
            state: _snapshot(),
            work: _snapshot(),
            age: invalid,
            now: now,
          ),
          throwsArgumentError,
        );
      });
    }

    test('selects strictly older graphs but protects cutoff-equal graphs', () {
      final state = _snapshot(
        beads: [
          _session('s-old', workKey: 'w-old', closedAt: old),
          _molecule('m-old', sessionId: 's-old', closedAt: old),
          _step('z-old', sessionId: 's-old', closedAt: old),
          _session('s-equal', workKey: 'w-equal', closedAt: cutoff),
          _molecule('m-equal', sessionId: 's-equal', closedAt: old),
          _step('z-equal', sessionId: 's-equal', closedAt: old),
        ],
      );
      final work = _snapshot(
        beads: [_closedWork('w-old'), _closedWork('w-equal')],
      );

      final plan = planStateStorePrune(
        state: state,
        work: work,
        age: age,
        now: now,
      );

      expect(plan.targetIds, ['m-old', 's-old', 'z-old']);
      expect(plan.protectedIds, ['m-equal', 's-equal', 'z-equal']);
    });
  });

  group('planStateStorePrune work exposure', () {
    test('accepts a closed directly-linked work bead', () {
      final plan = _planFor(
        now: now,
        old: old,
        workKey: 'work-direct',
        workBeads: [_closedWork('work-direct')],
      );

      expect(plan.targetIds, ['m', 's', 'z']);
      expect(plan.protectedIds, isEmpty);
    });

    test('accepts a closed base bead for an exact rework-round key', () {
      final plan = _planFor(
        now: now,
        old: old,
        workKey: reworkKeyFor('work-base', 2),
        workBeads: [_closedWork('work-base')],
      );

      expect(plan.targetIds, ['m', 's', 'z']);
    });

    test('accepts its own exact void key without the detached base bead', () {
      final plan = _planFor(
        now: now,
        old: old,
        workKey: voidKeyFor('work-gone', 's'),
      );

      expect(plan.targetIds, ['m', 's', 'z']);
    });

    for (final malformed in [
      '',
      '#void-s',
      'work#void-other',
      'work#void-s-extra',
      'work#r0-extra',
    ]) {
      test('protects malformed or empty work key "$malformed"', () {
        final plan = _planFor(now: now, old: old, workKey: malformed);

        expect(plan.targetIds, isEmpty);
        expect(plan.protectedIds, ['m', 's', 'z']);
      });
    }

    test('protects an absent or non-string work key', () {
      for (final metadata in <Map<String, dynamic>>[
        const {},
        const {SessionBeadKeys.workBead: 7},
      ]) {
        final state = _snapshot(
          beads: [
            _bead(
              's',
              type: GridIssueTypes.session,
              closedAt: old,
              metadata: metadata,
            ),
          ],
        );

        final plan = planStateStorePrune(
          state: state,
          work: _snapshot(),
          age: age,
          now: now,
        );

        expect(plan.targetIds, isEmpty);
        expect(plan.protectedIds, ['s']);
      }
    });

    test('protects direct and rework links whose work bead is open', () {
      for (final workKey in ['work', reworkKeyFor('work', 1)]) {
        final plan = _planFor(
          now: now,
          old: old,
          workKey: workKey,
          workBeads: [_openWork('work')],
        );

        expect(plan.targetIds, isEmpty);
      }
    });

    test('protects a missing direct work bead', () {
      final plan = _planFor(now: now, old: old, workKey: 'missing');

      expect(plan.targetIds, isEmpty);
      expect(plan.protectedIds, ['m', 's', 'z']);
    });
  });

  group('planStateStorePrune graph completeness', () {
    test('protects open, young, timeless, or ephemeral graph members', () {
      final unsafeChildren = <Bead>[
        _step('child', sessionId: 's', closedAt: old, closed: false),
        _step('child', sessionId: 's', closedAt: young),
        _step('child', sessionId: 's'),
        _step('child', sessionId: 's', closedAt: old, ephemeral: true),
      ];

      for (final child in unsafeChildren) {
        final state = _snapshot(
          beads: [
            _session('s', workKey: 'work', closedAt: old),
            _molecule('m', sessionId: 's', closedAt: old),
            child,
          ],
        );
        final plan = planStateStorePrune(
          state: state,
          work: _snapshot(beads: [_closedWork('work')]),
          age: age,
          now: now,
        );

        expect(plan.targetIds, isEmpty, reason: '${child.toJson()}');
        expect(plan.protectedIds, ['child', 'm', 's']);
      }
    });

    test('protects open, timeless, or ephemeral session roots', () {
      final unsafeSessions = <Bead>[
        _session('s', workKey: 'work', closedAt: old, closed: false),
        _session('s', workKey: 'work'),
        _session('s', workKey: 'work', closedAt: old, ephemeral: true),
      ];

      for (final session in unsafeSessions) {
        final plan = planStateStorePrune(
          state: _snapshot(beads: [session]),
          work: _snapshot(beads: [_closedWork('work')]),
          age: age,
          now: now,
        );

        expect(plan.targetIds, isEmpty);
        expect(plan.protectedIds, ['s']);
      }
    });

    test('collects only matching molecule and step children', () {
      final state = _snapshot(
        beads: [
          _session('s', workKey: 'work', closedAt: old),
          _molecule('m', sessionId: 's', closedAt: old),
          _step('z', sessionId: 's', closedAt: old),
          _molecule('other-m', sessionId: 'other', closedAt: old),
          _step('other-z', sessionId: 'other', closedAt: old),
          _bead(
            'task-with-session-key',
            type: IssueType.task,
            closedAt: old,
            metadata: {MoleculeStepKeys.session: 's'},
          ),
        ],
      );

      final plan = planStateStorePrune(
        state: state,
        work: _snapshot(beads: [_closedWork('work')]),
        age: age,
        now: now,
      );

      expect(plan.targetIds, ['m', 's', 'z']);
      expect(plan.protectedIds, [
        'other-m',
        'other-z',
        'task-with-session-key',
      ]);
    });

    test(
      'protects gates, cursor and lock records, mount attempts, and edges',
      () {
        final state = _snapshot(
          beads: [
            _session('s', workKey: 'work', closedAt: old),
            _molecule('m', sessionId: 's', closedAt: old),
            _step('z', sessionId: 's', closedAt: old),
            _bead('gate', type: GridIssueTypes.gate, closedAt: old),
            _bead('cursor', type: const IssueType('cursor'), closedAt: old),
            _bead('lock', type: const IssueType('lock'), closedAt: old),
            _bead('attempt', type: GridIssueTypes.mountAttempt, closedAt: old),
            _bead('unrelated', type: IssueType.chore, closedAt: old),
          ],
          dependencies: const [
            BeadDependency(issueId: 'z', dependsOnId: 'gate'),
            BeadDependency(issueId: 'unrelated', dependsOnId: 'm'),
            BeadDependency(issueId: 'm', dependsOnId: 'cursor'),
          ],
        );

        final plan = planStateStorePrune(
          state: state,
          work: _snapshot(beads: [_closedWork('work')]),
          age: age,
          now: now,
        );

        expect(plan.targetIds, ['m', 's', 'z']);
        expect(plan.protectedIds, [
          'attempt',
          'cursor',
          'gate',
          'lock',
          'unrelated',
        ]);
      },
    );
  });

  test('StateStorePrunePlan copies, sorts, and freezes both id lists', () {
    final targets = ['z', 'a'];
    final protected = ['y', 'b'];

    final plan = StateStorePrunePlan(
      targetIds: targets,
      protectedIds: protected,
    );
    targets.add('later');
    protected.clear();

    expect(plan.targetIds, ['a', 'z']);
    expect(plan.protectedIds, ['b', 'y']);
    expect(() => plan.targetIds.add('no'), throwsUnsupportedError);
    expect(() => plan.protectedIds.remove('b'), throwsUnsupportedError);
  });
}

StateStorePrunePlan _planFor({
  required DateTime now,
  required DateTime old,
  required String workKey,
  List<Bead> workBeads = const [],
}) => planStateStorePrune(
  state: _snapshot(
    beads: [
      _session('s', workKey: workKey, closedAt: old),
      _molecule('m', sessionId: 's', closedAt: old),
      _step('z', sessionId: 's', closedAt: old),
    ],
  ),
  work: _snapshot(beads: workBeads),
  age: const Duration(days: 3),
  now: now,
);

GraphSnapshot _snapshot({
  List<Bead> beads = const [],
  List<BeadDependency> dependencies = const [],
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: dependencies,
  readyIds: const [],
  capturedAt: DateTime.utc(2026, 9, 14),
);

Bead _session(
  String id, {
  required String workKey,
  DateTime? closedAt,
  bool closed = true,
  bool ephemeral = false,
}) => _bead(
  id,
  type: GridIssueTypes.session,
  closedAt: closedAt,
  closed: closed,
  ephemeral: ephemeral,
  metadata: {SessionBeadKeys.workBead: workKey},
);

Bead _molecule(
  String id, {
  required String sessionId,
  DateTime? closedAt,
  bool closed = true,
  bool ephemeral = false,
}) => _bead(
  id,
  type: GridIssueTypes.molecule,
  closedAt: closedAt,
  closed: closed,
  ephemeral: ephemeral,
  metadata: {MoleculeCircuitKeys.session: sessionId},
);

Bead _step(
  String id, {
  required String sessionId,
  DateTime? closedAt,
  bool closed = true,
  bool ephemeral = false,
}) => _bead(
  id,
  type: GridIssueTypes.step,
  closedAt: closedAt,
  closed: closed,
  ephemeral: ephemeral,
  metadata: {MoleculeStepKeys.session: sessionId},
);

Bead _closedWork(String id) => _bead(id, closedAt: DateTime.utc(2026, 9, 1));

Bead _openWork(String id) => _bead(id, closed: false);

Bead _bead(
  String id, {
  IssueType type = IssueType.task,
  DateTime? closedAt,
  bool closed = true,
  bool ephemeral = false,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  issueType: type,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  closedAt: closedAt,
  ephemeral: ephemeral,
  metadata: metadata,
);
