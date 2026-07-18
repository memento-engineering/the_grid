import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

/// Tests for the single bd write chokepoint (Track 4; ADR-0006 Decision 2).
///
/// The heart is the fail-closed safety: a write whose target rig is WRONG or
/// ABSENT is refused before any `bd` call, and every allowed write carries
/// `--actor grid-controller`, merges metadata, and never calls `bd show` or any
/// SQL.
Bead _step(
  String id, {
  String sessionId = 'tgdog-sess1',
  String path = 'tgdog-work/build',
  BeadStatus status = BeadStatus.open,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  title: 'step build',
  issueType: IssueType.step,
  status: status,
  metadata: {
    StationBeadWriter.rigKey: 'tgdog',
    StationBeadWriter.stepSessionKey: sessionId,
    StationBeadWriter.stepPathKey: path,
    'grid.step.stepId': 'build',
    'grid.step.capability': 'build',
    'grid.step.kind': 'job',
    ...metadata,
  },
);

Bead _molecule(String id, {String sessionId = 'tgdog-sess1'}) => Bead(
  id: id,
  issueType: IssueType.molecule,
  status: BeadStatus.open,
  metadata: {
    StationBeadWriter.rigKey: 'tgdog',
    StationBeadWriter.moleculeSessionKey: sessionId,
  },
);

void main() {
  late RecordingBdRunner runner;
  late BdCliService bd;
  late List<String> refusals;

  // The shared rig allow-set seed (A35): exactly {tgdog}.
  BeadOwnershipPredicate predicate() => BeadOwnershipPredicate({'tgdog'});

  StationBeadWriter writer() => StationBeadWriter(
    bd: bd,
    ownership: predicate(),
    onRefusal: refusals.add,
  );

  setUp(() {
    runner = RecordingBdRunner(createdId: 'tgdog-sess1');
    bd = BdCliService(runner);
    refusals = <String>[];
  });

  group('the fail-closed refusal (the key safety test)', () {
    test('update on a bead whose id prefix is NOT owned is refused', () async {
      // gascity-owned bead — the_grid must never mutate it.
      await expectLater(
        writer().update('gascity-conv7', metadata: {'state': 'active'}),
        throwsA(isA<OwnershipRefused>()),
      );
      // NOT ONE bd call was issued (refused before the wire).
      expect(runner.calls, isEmpty);
      // It logged loudly.
      expect(refusals, hasLength(1));
      expect(refusals.single, contains('not in the owned allow-set'));
    });

    test(
      'update on a bead with NO rig prefix at all is refused (absent rig)',
      () async {
        await expectLater(
          writer().update('noprefixbead', metadata: {'state': 'active'}),
          throwsA(
            isA<OwnershipRefused>().having((e) => e.substation, 'rig', isNull),
          ),
        );
        expect(runner.calls, isEmpty);
      },
    );

    test(
      'createSession with a non-owned rig is refused before any bd create',
      () async {
        await expectLater(
          writer().createSession(
            substation: 'gascity',
            title: 'x',
            workBeadId: 'gascity-99',
          ),
          throwsA(
            isA<OwnershipRefused>().having(
              (e) => e.operation,
              'operation',
              'create',
            ),
          ),
        );
        expect(runner.calls, isEmpty);
      },
    );

    test('close and delete on a non-owned bead are refused', () async {
      await expectLater(
        writer().close('gascity-conv7'),
        throwsA(isA<OwnershipRefused>()),
      );
      await expectLater(
        writer().delete('gascity-conv7'),
        throwsA(isA<OwnershipRefused>()),
      );
      expect(runner.calls, isEmpty);
    });

    test(
      'a wrong allow-set seed (not tgdog) refuses the_grid\'s own rig too',
      () async {
        // belt-and-suspenders: the predicate is the only authority; if seeded
        // with the wrong rig, even a tgdog-prefixed bead is refused.
        final w = StationBeadWriter(
          bd: bd,
          ownership: BeadOwnershipPredicate({'someotherrig'}),
          onRefusal: refusals.add,
        );
        await expectLater(
          w.update('tgdog-sess1', metadata: {'state': 'active'}),
          throwsA(isA<OwnershipRefused>()),
        );
        expect(runner.calls, isEmpty);
      },
    );
  });

  group('allowed writes — bd-only, --actor grid-controller, merge, no show', () {
    test('createSession mints + stamps the owned rig FROM BIRTH', () async {
      final id = await writer().createSession(
        substation: 'tgdog',
        title: 'session for tgdog-work1',
        workBeadId: 'tgdog-work1',
        metadata: {'state': 'start_pending'},
      );
      expect(id, 'tgdog-sess1');

      // 1) a `bd create --json --actor grid-controller --type session …`.
      final creates = runner.callsFor('create');
      expect(creates, hasLength(1));
      expect(creates.single, containsAllInOrder(['create', '--json']));
      expect(creates.single, containsAllInOrder(['--type', 'session']));

      // 2) immediately followed by the rig-stamping `update --metadata`.
      final updates = runner.callsFor('update');
      expect(updates, hasLength(1));
      final stamped =
          jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
      // The rig marker is present from birth — the chokepoint can assert it on
      // every later write.
      expect(stamped['rig'], 'tgdog');
      expect(stamped['work_bead'], 'tgdog-work1');
      expect(stamped['state'], 'start_pending');

      // Safety invariants.
      expect(runner.everyMutationHasActor, isTrue);
      expect(runner.neverCalledShow, isTrue);
    });

    test(
      'update issues exactly one `bd update --metadata <json>` (merge)',
      () async {
        await writer().update('tgdog-sess1', metadata: {'state': 'active'});
        final updates = runner.callsFor('update');
        expect(updates, hasLength(1));
        expect(updates.single, containsAllInOrder(['update', 'tgdog-sess1']));
        // metadata is a single merged JSON object (bd merges named keys).
        final meta =
            jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
        expect(meta, {'state': 'active'});
        expect(runner.everyMutationHasActor, isTrue);
      },
    );

    test('close issues `bd close <id> --reason`', () async {
      await writer().close('tgdog-sess1', reason: 'session ended');
      final closes = runner.callsFor('close');
      expect(closes, hasLength(1));
      expect(closes.single, containsAllInOrder(['close', 'tgdog-sess1']));
      expect(closes.single, containsAllInOrder(['--reason', 'session ended']));
      expect(closes.single, containsAllInOrder(['--actor', 'grid-controller']));
    });

    test(
      'an owned-rig-MARKER bead (no owned prefix) is still writable',
      () async {
        // The metadata.rig axis: a bead whose id prefix is unknown but whose
        // metadata declares the owned rig in the SAME write is owned.
        await writer().update(
          'xyz-1',
          metadata: {'rig': 'tgdog', 'state': 'active'},
        );
        expect(runner.callsFor('update'), hasLength(1));
        expect(refusals, isEmpty);
      },
    );

    test(
      'batch refuses the whole transaction if ANY line is non-owned',
      () async {
        await expectLater(
          writer().batch([
            (id: 'tgdog-sess1', line: 'close tgdog-sess1'),
            (id: 'gascity-9', line: 'close gascity-9'),
          ]),
          throwsA(isA<OwnershipRefused>()),
        );
        // No batch was sent (the unowned target poisons the one transaction).
        expect(runner.callsFor('batch'), isEmpty);
      },
    );
  });

  group('capture-only session lifecycle stamps (FT-1, tg-pez)', () {
    final clock = DateTime.utc(2026, 7, 2, 9, 30);
    StationBeadWriter clockedWriter() => StationBeadWriter(
      bd: bd,
      ownership: predicate(),
      onRefusal: refusals.add,
      clock: () => clock,
    );

    test('createSession stamps started_at (ISO-8601 UTC) in the birth merge — '
        'no extra write', () async {
      await clockedWriter().createSession(
        substation: 'tgdog',
        title: 'x',
        workBeadId: 'tgdog-work1',
      );
      // The stamp rides the SAME single birth update (rig + work_bead + started_at).
      expect(runner.callsFor('update'), hasLength(1));
      final birth =
          jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
      expect(birth['started_at'], '2026-07-02T09:30:00.000Z');
      expect(birth['rig'], 'tgdog');
    });

    test('a caller-supplied started_at overrides the default (spawn metadata '
        'wins)', () async {
      await clockedWriter().createSession(
        substation: 'tgdog',
        title: 'x',
        workBeadId: 'tgdog-work1',
        metadata: {'started_at': 'CALLER'},
      );
      final birth =
          jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
      expect(birth['started_at'], 'CALLER');
    });

    test('close stamps closed_at (ISO-8601 UTC) BEFORE the bd close (one '
        'serialized chain link)', () async {
      await clockedWriter().close('tgdog-sess1', reason: 'done');
      // The closed_at merge update.
      final meta =
          jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
      expect(meta['closed_at'], '2026-07-02T09:30:00.000Z');
      // …then exactly one `bd close`.
      expect(runner.callsFor('close'), hasLength(1));
      // Ordering: the stamp update precedes the close on the wire.
      final updateIdx = runner.calls.indexWhere((c) => c.first == 'update');
      final closeIdx = runner.calls.indexWhere((c) => c.first == 'close');
      expect(updateIdx >= 0 && updateIdx < closeIdx, isTrue);
      // Still bd-only, --actor, never show.
      expect(runner.everyMutationHasActor, isTrue);
      expect(runner.neverCalledShow, isTrue);
    });

    test('close on a NON-owned bead is still refused before any stamp', () async {
      await expectLater(
        clockedWriter().close('gascity-conv7'),
        throwsA(isA<OwnershipRefused>()),
      );
      // Fail-closed: neither the closed_at stamp nor the close reached the wire.
      expect(runner.calls, isEmpty);
    });
  });

  test('requireSubstationMarker demands BOTH prefix and metadata.rig', () {
    final strict = BeadOwnershipPredicate({
      'tgdog',
    }, requireSubstationMarker: true);
    // prefix owned but no marker → not owned.
    expect(strict.ownsTarget(id: 'tgdog-1'), isFalse);
    // both present → owned.
    expect(
      strict.ownsTarget(id: 'tgdog-1', metadata: {'rig': 'tgdog'}),
      isTrue,
    );
  });

  group('molecule step successors (A52 Ratified)', () {
    test(
      'createStepSuccessor mints one step bead and one supersedes edge',
      () async {
        runner.nextCreatedId = 'tgdog-step-new';
        final id = await writer().createStepSuccessor(
          substation: 'tgdog',
          priorStep: _step(
            'tgdog-step-old',
            metadata: {
              StationBeadWriter.stepStateKey: 'complete',
              StationBeadWriter.stepStartedAtKey: 'old-start',
              StationBeadWriter.stepFinishedAtKey: 'old-finish',
              StationBeadWriter.stepDurationMsKey: '42',
              StationBeadWriter.stepFailureReasonKey: 'old failure',
              'grid.result.tgdog-work/build.grade': 'F',
            },
          ),
          currentDepth: 1,
          maxDepth: 3,
        );

        expect(id, 'tgdog-step-new');
        expect(runner.callsFor('export'), hasLength(1));
        final creates = runner.callsFor('create');
        expect(creates, hasLength(1));
        expect(creates.single, containsAllInOrder(['--type', 'step']));
        final metadata =
            jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
        expect(metadata[StationBeadWriter.rigKey], 'tgdog');
        expect(metadata[StationBeadWriter.stepPathKey], 'tgdog-work/build');
        expect(metadata[StationBeadWriter.stepStateKey], 'pending');
        expect(metadata, isNot(contains(StationBeadWriter.stepStartedAtKey)));
        expect(metadata, isNot(contains(StationBeadWriter.stepFinishedAtKey)));
        expect(metadata, isNot(contains(StationBeadWriter.stepDurationMsKey)));
        expect(
          metadata,
          isNot(contains(StationBeadWriter.stepFailureReasonKey)),
        );
        expect(metadata.keys, isNot(contains(startsWith('grid.result.'))));

        final deps = runner.callsFor('dep');
        expect(deps, hasLength(1));
        expect(
          deps.single,
          containsAllInOrder([
            'dep',
            'add',
            'tgdog-step-new',
            'tgdog-step-old',
            '--type',
            'supersedes',
          ]),
        );
      },
    );

    test('createStepSuccessor dedups an existing open successor', () async {
      const dep = BeadDependency(
        issueId: 'tgdog-step-existing',
        dependsOnId: 'tgdog-step-old',
        type: DependencyType.supersedes,
      );
      runner.exportBeads = [
        _step('tgdog-step-old'),
        _step('tgdog-step-existing'),
      ];
      runner.exportDependencies = const [dep];

      final id = await writer().createStepSuccessor(
        substation: 'tgdog',
        priorStep: _step('tgdog-step-old'),
        currentDepth: 1,
        maxDepth: 3,
      );

      expect(id, 'tgdog-step-existing');
      expect(runner.callsFor('export'), hasLength(1));
      expect(runner.callsFor('create'), isEmpty);
      expect(runner.callsFor('dep'), isEmpty);
    });

    test('createStepSuccessor refuses at the cap before mutation', () async {
      await expectLater(
        writer().createStepSuccessor(
          substation: 'tgdog',
          priorStep: _step('tgdog-step-old'),
          currentDepth: 3,
          maxDepth: 3,
        ),
        throwsA(isA<StateError>()),
      );
      expect(runner.calls, isEmpty);
    });

    test(
      'reapMolecule batches root beads plus open successor chain closes',
      () async {
        const dep1 = BeadDependency(
          issueId: 'tgdog-step-r1',
          dependsOnId: 'tgdog-step-old',
          type: DependencyType.supersedes,
        );
        const dep2 = BeadDependency(
          issueId: 'tgdog-step-r2',
          dependsOnId: 'tgdog-step-r1',
          type: DependencyType.supersedes,
        );
        runner.exportBeads = [
          _molecule('tgdog-mol'),
          _step('tgdog-step-old'),
          _step(
            'tgdog-step-r1',
            metadata: {StationBeadWriter.stepSessionKey: ''},
          ),
          _step(
            'tgdog-step-r2',
            metadata: {StationBeadWriter.stepSessionKey: ''},
          ),
          _step(
            'tgdog-step-closed',
            status: BeadStatus.closed,
            metadata: {StationBeadWriter.stepSessionKey: ''},
          ),
        ];
        runner.exportDependencies = const [dep1, dep2];

        await writer().reapMolecule(sessionId: 'tgdog-sess1');

        final batches = runner.callsFor('batch');
        expect(batches, hasLength(1));
        final script = runner.stdins[runner.calls.indexOf(batches.single)]!;
        expect(
          script.split('\n'),
          unorderedEquals([
            'close tgdog-mol',
            'close tgdog-step-old',
            'close tgdog-step-r1',
            'close tgdog-step-r2',
          ]),
        );
      },
    );
  });
}
