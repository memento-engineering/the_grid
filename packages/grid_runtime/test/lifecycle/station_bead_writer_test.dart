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
  issueType: GridIssueTypes.step,
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
  issueType: GridIssueTypes.molecule,
  status: BeadStatus.open,
  metadata: {
    StationBeadWriter.rigKey: 'tgdog',
    StationBeadWriter.moleculeSessionKey: sessionId,
  },
);

Bead _session(String id, {String workBeadId = 'tg-1'}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {StationBeadWriter.rigKey: 'tgdog', 'work_bead': workBeadId},
);

Bead _attempt(String id, {String workBeadId = 'tg-1'}) => Bead(
  id: id,
  issueType: GridIssueTypes.mountAttempt,
  status: BeadStatus.open,
  metadata: {
    StationBeadWriter.rigKey: 'tgdog',
    StationBeadWriter.mountAttemptWorkBeadKey: workBeadId,
    StationBeadWriter.mountAttemptCountKey: '1',
  },
);

void main() {
  late RecordingBdRunner runner;
  late BdCliService bd;
  late List<String> refusals;
  late List<({String name, Map<String, String> data})> flares;

  // The shared rig allow-set seed (A35): exactly {tgdog}.
  BeadOwnershipPredicate predicate() => BeadOwnershipPredicate({'tgdog'});

  StationBeadWriter writer({
    void Function(String, Map<String, String>)? onFlare,
  }) => StationBeadWriter(
    bd: bd,
    reader: runner,
    ownership: predicate(),
    onRefusal: refusals.add,
    onFlare: onFlare ?? (name, data) => flares.add((name: name, data: data)),
  );

  setUp(() {
    BdCliService.resetGuardedWriteCapabilityForTesting();
    runner = RecordingBdRunner(createdId: 'tgdog-sess1');
    bd = BdCliService(runner);
    refusals = <String>[];
    flares = <({String name, Map<String, String> data})>[];
  });

  group('guarded write capability', () {
    test('unsupported guards are omitted and flared once', () async {
      runner = RecordingBdRunner(guardedWriteHelp: 'Flags:\n  --actor string');
      bd = BdCliService(runner);
      runner.exportBeads = const [
        Bead(
          id: 'tgdog-one',
          status: BeadStatus.open,
          metadata: {
            StationBeadWriter.specAuthorKey: StationBeadWriter.specifyAuthor,
          },
        ),
        Bead(
          id: 'tgdog-two',
          status: BeadStatus.open,
          metadata: {
            StationBeadWriter.specAuthorKey: StationBeadWriter.specifyAuthor,
          },
        ),
      ];

      await writer().clearSpecifyAuthoredSpec('tgdog-one');
      await writer().clearSpecifyAuthoredSpec('tgdog-two');

      final updates = runner
          .callsFor('update')
          .where((call) => !call.contains('--help'));
      expect(updates.every((args) => !args.contains('--if-assignee')), isTrue);
      expect(updates.every((args) => !args.contains('--if-status')), isTrue);
      final receipts = flares
          .where((flare) => flare.name == 'bd.guardedWriteDegraded')
          .toList();
      expect(receipts, hasLength(1));
      expect(receipts.single.data, {
        'missingCapability': '--if-assignee,--if-status',
        'safetyDropped': 'compare-and-swap defence in depth',
        'primarySafety': 'StationBeadWriter single-writer chokepoint preserved',
      });
    });

    test('flare sink failure does not block degraded mutation', () async {
      runner = RecordingBdRunner(guardedWriteHelp: 'Flags:\n  --actor string');
      bd = BdCliService(runner);
      runner.exportBeads = const [
        Bead(
          id: 'tgdog-one',
          status: BeadStatus.open,
          metadata: {
            StationBeadWriter.specAuthorKey: StationBeadWriter.specifyAuthor,
          },
        ),
      ];

      await writer(
        onFlare: (_, __) => throw StateError('sink down'),
      ).clearSpecifyAuthoredSpec('tgdog-one');

      expect(runner.callsFor('update'), hasLength(1));
    });
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
      'clearSpecifyAuthoredSpec refuses a non-owned bead before bd update',
      () async {
        await expectLater(
          writer().clearSpecifyAuthoredSpec('gascity-work1'),
          throwsA(isA<OwnershipRefused>()),
        );
        expect(runner.calls, isEmpty);
        expect(refusals, hasLength(1));
        expect(refusals.single, contains('not in the owned allow-set'));
      },
    );

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

    test('strict refusal reports the full hyphenated owned prefix', () async {
      final strictWriter = StationBeadWriter(
        bd: bd,
        reader: runner,
        ownership: BeadOwnershipPredicate({
          'swift-infer',
        }, requireSubstationMarker: true),
        onRefusal: refusals.add,
      );

      await expectLater(
        strictWriter.update('swift-infer-097', metadata: {'state': 'active'}),
        throwsA(
          isA<OwnershipRefused>().having(
            (e) => e.substation,
            'substation',
            'swift-infer',
          ),
        ),
      );
      expect(refusals.single, contains('swift-infer'));
      expect(runner.calls, isEmpty);
    });

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
          reader: runner,
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
    test('link writes use the chokepoint actor', () async {
      runner.nextCreatedId = 'tgdog-link1';
      final id = await writer().createLink(
        substation: 'tgdog',
        from: 'tg-work1',
        to: 'pow-work2',
        reason: 'waits for power',
        actor: 'specify',
      );

      expect(id, 'tgdog-link1');
      expect(
        runner.callsFor('create').single,
        containsAllInOrder(['--type', 'link']),
      );
      final metadata =
          jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
      expect(metadata, {
        'rig': 'tgdog',
        'grid.link.from': 'tg-work1',
        'grid.link.to': 'pow-work2',
        'grid.link.type': 'blocks',
        'grid.link.reason': 'waits for power',
        'grid.link.actor': 'specify',
      });
      await writer().close('tgdog-link1', reason: 'dependency cleared');
      expect(
        runner.callsFor('close').single,
        containsAllInOrder([
          'close',
          'tgdog-link1',
          '--reason',
          'dependency cleared',
        ]),
      );
      expect(runner.everyMutationHasActor, isTrue);
    });

    test(
      'createLink refuses an unowned state prefix before any call',
      () async {
        await expectLater(
          writer().createLink(
            substation: 'houston',
            from: 'tg-work1',
            to: 'pow-work2',
            reason: 'waits',
            actor: 'specify',
          ),
          throwsA(isA<OwnershipRefused>()),
        );
        expect(runner.calls, isEmpty);
      },
    );

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
      expect(flares.single.name, 'session.minted');
      expect(flares.single.data['sessionId'], 'tgdog-sess1');
      expect(flares.single.data['workBeadId'], 'tgdog-work1');

      // Safety invariants.
      expect(runner.everyMutationHasActor, isTrue);
      expect(runner.neverCalledShow, isTrue);
    });

    test('update issues exactly one atomic metadata merge', () async {
      await writer().update('tgdog-sess1', metadata: {'state': 'active'});
      final updates = runner.callsFor('update');
      expect(updates, hasLength(1));
      expect(updates.single, containsAllInOrder(['update', 'tgdog-sess1']));
      expect(
        updates.single,
        containsAllInOrder(['--set-metadata', 'state=active']),
      );
      expect(updates.single, isNot(contains('--metadata')));
      final meta =
          jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
      expect(meta, {'state': 'active'});
      expect(runner.everyMutationHasActor, isTrue);
    });

    test(
      'writeOperatorText routes description through guarded service',
      () async {
        await writer().writeOperatorText(
          'tgdog-work1',
          field: OperatorBeadTextField.description,
          content: 'operator description',
          append: false,
        );

        expect(runner.callsFor('update'), hasLength(1));
        expect(
          runner.callsFor('update').single,
          containsAllInOrder(['--body-file', '-']),
        );
        expect(runner.stdins.single, 'operator description');
      },
    );

    test(
      'ADR-0006 D2 / ADR-0001 D5: appendNotes update issues no bd show',
      () async {
        await writer().update(
          'tgdog-sess1',
          metadata: const {'state': 'active'},
          appendNotes: 'operator finding',
        );

        expect(runner.calls, hasLength(1));
        expect(runner.calls.single.first, 'update');
        expect(
          runner.calls.single,
          containsAllInOrder(['--append-notes', 'operator finding']),
        );
        expect(runner.neverCalledShow, isTrue);
      },
    );

    test(
      'writeSpecifyAuthoredSpec stamps fields and provenance atomically',
      () async {
        await writer().writeSpecifyAuthoredSpec(
          'tgdog-work1',
          design: 'a design',
          acceptanceCriteria: 'the acceptance',
        );

        final updates = runner.callsFor('update');
        expect(updates, hasLength(1));
        expect(updates.single, containsAllInOrder(['--design-file', '-']));
        expect(runner.stdins.single, 'a design');
        expect(
          updates.single,
          containsAllInOrder(['--acceptance', 'the acceptance']),
        );
        expect(
          jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>,
          {StationBeadWriter.specAuthorKey: StationBeadWriter.specifyAuthor},
        );
        expect(runner.everyMutationHasActor, isTrue);
        expect(runner.calls, hasLength(1));
        expect(runner.calls.single.first, 'update');
        expect(runner.neverCalledShow, isTrue);
      },
    );

    test('clearSpecifyAuthoredSpec clears and unmarks a marked spec', () async {
      runner.exportBeads = const [
        Bead(
          id: 'tgdog-work1',
          status: BeadStatus.open,
          assignee: StationBeadWriter.specifyAuthor,
          metadata: {
            StationBeadWriter.specAuthorKey: StationBeadWriter.specifyAuthor,
          },
        ),
      ];

      await writer().clearSpecifyAuthoredSpec('tgdog-work1');

      expect(runner.callsFor('export'), isEmpty);
      final updates = runner.callsFor('update');
      final mutation = updates.singleWhere((call) => !call.contains('--help'));
      expect(mutation, containsAllInOrder(['update', 'tgdog-work1']));
      expect(mutation, containsAllInOrder(['--if-assignee', 'specify']));
      expect(mutation, containsAllInOrder(['--if-status', 'open']));
      expect(mutation, containsAllInOrder(['--design-file', '-']));
      expect(runner.stdins.last, '');
      expect(mutation, containsAllInOrder(['--acceptance', '']));
      expect(
        mutation,
        containsAllInOrder([
          '--unset-metadata',
          StationBeadWriter.specAuthorKey,
        ]),
      );
      expect(mutation, isNot(contains('--description')));
      expect(mutation, isNot(contains('--notes')));
      expect(mutation, isNot(contains('--append-notes')));
      expect(runner.everyMutationHasActor, isTrue);
      expect(runner.neverCalledShow, isTrue);
      expect(refusals, isEmpty);
    });

    test('guard mismatch surfaces a typed ownership refusal once', () async {
      const guardMismatchEnvelope =
          '{"schema_version":1,"data":{"error":"guard mismatch",'
          '"guard_mismatch":true}}';
      runner = _GuardMismatchRunner(guardMismatchEnvelope);
      bd = BdCliService(runner);

      await expectLater(
        writer().update(
          'tgdog-work1',
          metadata: const {'state': 'active'},
          ifAssignee: 'specify',
          ifStatus: BeadStatus.open,
        ),
        throwsA(
          isA<OwnershipGuardRefused>()
              .having((error) => error.operation, 'operation', 'update')
              .having((error) => error.targetId, 'targetId', 'tgdog-work1')
              .having((error) => error.cause, 'cause', isA<BdGuardMismatch>()),
        ),
      );
      expect(runner.calls, hasLength(2));
      expect(runner.calls.first, ['update', '--help']);
      expect(
        runner.calls.last,
        containsAll(<String>['--if-assignee', '--if-status']),
      );
      expect(refusals, hasLength(1));
    });

    test(
      'clearSpecifyAuthoredSpec preserves and flares an unmarked spec',
      () async {
        runner.exportBeads = const [
          Bead(
            id: 'tgdog-work1',
            design: 'operator design',
            acceptanceCriteria: 'operator acceptance',
          ),
        ];

        await writer().clearSpecifyAuthoredSpec('tgdog-work1');

        expect(runner.callsFor('export'), isEmpty);
        expect(runner.callsFor('update'), isEmpty);
        expect(flares, hasLength(1));
        expect(flares.single.name, 'rework.specPreserved');
        expect(flares.single.data, {'beadId': 'tgdog-work1'});
        expect(runner.neverCalledShow, isTrue);
      },
    );

    test('a throwing preservation flare does not fail rework', () async {
      runner.exportBeads = const [Bead(id: 'tgdog-work1')];

      await writer(
        onFlare: (_, __) => throw StateError('sink unavailable'),
      ).clearSpecifyAuthoredSpec('tgdog-work1');

      expect(runner.callsFor('export'), isEmpty);
      expect(runner.callsFor('update'), isEmpty);
      expect(runner.neverCalledShow, isTrue);
    });

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
      reader: runner,
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
              StationBeadWriter.stepCrumbKey:
                  'tgdog-work1/tgdog-sess1/tgdog-mol1/tgdog-step-old',
              StationBeadWriter.stepStateKey: 'complete',
              StationBeadWriter.stepStartedAtKey: 'old-start',
              StationBeadWriter.stepFinishedAtKey: 'old-finish',
              StationBeadWriter.stepDurationMsKey: '42',
              StationBeadWriter.stepFailureReasonKey: 'old failure',
              'grid.result.tgdog-work/build.grade': 'F',
            },
          ),
          spentRounds: 1,
          maxRounds: 3,
        );

        expect(id, 'tgdog-step-new');
        expect(runner.callsFor('export'), isEmpty);
        final creates = runner.callsFor('create');
        expect(creates, hasLength(1));
        expect(creates.single, containsAllInOrder(['--type', 'step']));
        final metadata =
            jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
        expect(metadata[StationBeadWriter.rigKey], 'tgdog');
        expect(metadata[StationBeadWriter.stepPathKey], 'tgdog-work/build');
        expect(
          metadata[StationBeadWriter.stepCrumbKey],
          'tgdog-work1/tgdog-sess1/tgdog-mol1/tgdog-step-new',
        );
        expect(
          metadata[StationBeadWriter.stepCrumbKey],
          isNot(contains('tgdog-step-old')),
        );
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

    test(
      'tg-q3q0 (deep): the supersedes edge lands BEFORE the metadata that '
      'makes the successor selectable — a snapshot between the writes used '
      'to see an edge-less pending step at the same path (depth 0), freezing '
      'grid.round at the old value and blinding the edge-keyed dedup probe',
      () async {
        runner.nextCreatedId = 'tgdog-step-new';
        await writer().createStepSuccessor(
          substation: 'tgdog',
          priorStep: _step(
            'tgdog-step-old',
            metadata: {
              StationBeadWriter.stepCrumbKey:
                  'tgdog-work1/tgdog-sess1/tgdog-mol1/tgdog-step-old',
              StationBeadWriter.stepStateKey: 'complete',
            },
          ),
          spentRounds: 1,
          maxRounds: 3,
        );
        final depIndex = runner.calls.indexWhere((c) => c.first == 'dep');
        final updateIndex = runner.calls.indexWhere((c) => c.first == 'update');
        expect(depIndex, isNot(-1));
        expect(updateIndex, isNot(-1));
        expect(
          depIndex,
          lessThan(updateIndex),
          reason:
              'the half-minted successor must stay inert (no path '
              'metadata) until its supersedes edge exists',
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
        spentRounds: 1,
        maxRounds: 3,
      );

      expect(id, 'tgdog-step-existing');
      expect(runner.callsFor('export'), isEmpty);
      expect(runner.callsFor('create'), isEmpty);
      expect(runner.callsFor('dep'), isEmpty);
    });

    test(
      'createStepSuccessor refuses spent verdict cap before mutation',
      () async {
        await expectLater(
          writer().createStepSuccessor(
            substation: 'tgdog',
            priorStep: _step('tgdog-step-old'),
            spentRounds: 3,
            maxRounds: 3,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'rework verdict cap reached (3/3)',
            ),
          ),
        );
        expect(runner.calls, isEmpty);
      },
    );

    test(
      'createStepSuccessor allows deep structural history below verdict cap',
      () async {
        runner.nextCreatedId = 'tgdog-step-new';
        final id = await writer().createStepSuccessor(
          substation: 'tgdog',
          priorStep: _step('tgdog-step-old'),
          spentRounds: 0,
          maxRounds: 3,
        );
        expect(id, 'tgdog-step-new');
        expect(runner.callsFor('create'), hasLength(1));
        expect(runner.callsFor('dep'), hasLength(1));
      },
    );

    test(
      'reapMolecule orders sibling blockers before their route join and root',
      () async {
        runner.exportBeads = [
          _session('tgdog-sess1'),
          _attempt('tgdog-att1'),
          _molecule('tgdog-mol'),
          _molecule('tgdog-prereq'),
          _step('tgdog-code'),
          _step('tgdog-decision'),
          _step('tgdog-route'),
        ];
        runner.exportDependencies = const [
          BeadDependency(
            issueId: 'tgdog-code',
            dependsOnId: 'tgdog-prereq',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-route',
            dependsOnId: 'tgdog-code',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-route',
            dependsOnId: 'tgdog-decision',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-code',
            dependsOnId: 'tgdog-mol',
            type: DependencyType.parentChild,
          ),
          BeadDependency(
            issueId: 'tgdog-decision',
            dependsOnId: 'tgdog-mol',
            type: DependencyType.parentChild,
          ),
          BeadDependency(
            issueId: 'tgdog-route',
            dependsOnId: 'tgdog-mol',
            type: DependencyType.parentChild,
          ),
        ];

        await writer().reapMolecule(sessionId: 'tgdog-sess1');

        final batch = runner.callsFor('batch').single;
        final script = runner.stdins[runner.calls.indexOf(batch)]!;
        expect(
          script.split('\n'),
          orderedEquals([
            'close tgdog-att1',
            'close tgdog-decision',
            'close tgdog-prereq',
            'close tgdog-code',
            'close tgdog-route',
            'close tgdog-mol',
          ]),
        );
        expect(runner.callsFor('dep'), hasLength(1));
      },
    );

    test(
      'reapMolecule degrades to per-bead closes when the store refuses batch '
      '(proxied-server mode) — the tg-ehht 9,389-orphan mechanism',
      () async {
        final proxied = _ProxiedBatchRunner(createdId: 'tgdog-sess1');
        proxied.exportBeads = [
          _session('tgdog-sess1'),
          _attempt('tgdog-att1'),
          _molecule('tgdog-mol'),
          _molecule('tgdog-prereq'),
          _step('tgdog-code'),
          _step('tgdog-decision'),
          _step('tgdog-route'),
        ];
        proxied.exportDependencies = const [
          BeadDependency(
            issueId: 'tgdog-code',
            dependsOnId: 'tgdog-prereq',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-route',
            dependsOnId: 'tgdog-code',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-route',
            dependsOnId: 'tgdog-decision',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-code',
            dependsOnId: 'tgdog-mol',
            type: DependencyType.parentChild,
          ),
          BeadDependency(
            issueId: 'tgdog-decision',
            dependsOnId: 'tgdog-mol',
            type: DependencyType.parentChild,
          ),
          BeadDependency(
            issueId: 'tgdog-route',
            dependsOnId: 'tgdog-mol',
            type: DependencyType.parentChild,
          ),
        ];
        final w = StationBeadWriter(
          bd: BdCliService(proxied),
          reader: proxied,
          ownership: BeadOwnershipPredicate(const {'tgdog'}),
        );

        await w.reapMolecule(sessionId: 'tgdog-sess1');

        expect(proxied.callsFor('batch'), hasLength(1), reason: 'tried first');
        final closes = proxied
            .callsFor('close')
            .map((c) => c[1])
            .toList(growable: false);
        expect(
          closes,
          orderedEquals([
            'tgdog-att1',
            'tgdog-decision',
            'tgdog-prereq',
            'tgdog-code',
            'tgdog-route',
            'tgdog-mol',
          ]),
          reason:
              'the proxied fallback must preserve the dependency-aware order, '
              'including a molecule-ranked blocker before a step-ranked issue',
        );
      },
    );

    test('reapMolecule refuses a dependency cycle before mutation', () async {
      runner.exportBeads = [
        _session('tgdog-sess1'),
        _attempt('tgdog-att1'),
        _molecule('tgdog-mol'),
        _step('tgdog-step-a'),
        _step('tgdog-step-b'),
      ];
      runner.exportDependencies = const [
        BeadDependency(
          issueId: 'tgdog-step-a',
          dependsOnId: 'tgdog-step-b',
          type: DependencyType.blocks,
        ),
        BeadDependency(
          issueId: 'tgdog-step-b',
          dependsOnId: 'tgdog-step-a',
          type: DependencyType.blocks,
        ),
      ];

      await expectLater(
        writer().reapMolecule(sessionId: 'tgdog-sess1'),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                startsWith('molecule reap dependency cycle:'),
              )
              .having(
                (error) => error.message,
                'step a',
                contains('tgdog-step-a'),
              )
              .having(
                (error) => error.message,
                'step b',
                contains('tgdog-step-b'),
              ),
        ),
      );
      expect(runner.callsFor('batch'), isEmpty);
      expect(runner.callsFor('close'), isEmpty);
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
          orderedEquals([
            'close tgdog-step-old',
            'close tgdog-step-r1',
            'close tgdog-step-r2',
            'close tgdog-mol',
          ]),
          reason:
              'an unforced batch must close every step leaf before its '
              'molecule root or bd rolls back the transaction',
        );
      },
    );
  });

  group('metadataOf — the molecule StepMetadataReader (tg-h4u, R3)', () {
    test("returns the bead's string metadata via the snapshot read — and NEVER "
        'calls bd show (ADR-0006 Decision 2 / ADR-0001 Decision 5)', () async {
      runner.exportBeads = [
        _step(
          'tgdog-step-1',
          metadata: {
            'grid.lease.pgid': '4242',
            'grid.lease.pid': '4343',
            'grid.lease.token': 'tok-abc',
          },
        ),
      ];

      final metadata = await writer().metadataOf('tgdog-step-1');

      expect(metadata, isNotNull);
      expect(metadata!['grid.lease.pgid'], '4242');
      expect(metadata['grid.lease.pid'], '4343');
      expect(metadata['grid.lease.token'], 'tok-abc');
      expect(metadata[StationBeadWriter.stepSessionKey], 'tgdog-sess1');
      expect(runner.callsFor('export'), isEmpty);
      expect(runner.neverCalledShow, isTrue);
    });

    test(
      'an absent bead reads as null — not adoptable, never a crash',
      () async {
        runner.exportBeads = [_step('tgdog-step-1')];
        expect(await writer().metadataOf('tgdog-step-9'), isNull);
      },
    );

    test('an empty store reads as null', () async {
      runner.exportBeads = const [];
      expect(await writer().metadataOf('tgdog-step-1'), isNull);
    });
  });
}

final class _GuardMismatchRunner extends RecordingBdRunner {
  _GuardMismatchRunner(this.envelope);

  final String envelope;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    await super.run(args, timeout: timeout, stdin: stdin);
    return BdResult(exitCode: 13, stdout: envelope, stderr: '');
  }
}

/// A [RecordingBdRunner] whose `batch` refuses like a proxied-server store.
final class _ProxiedBatchRunner extends RecordingBdRunner {
  _ProxiedBatchRunner({required super.createdId});

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    if (args.isNotEmpty && args.first == 'batch') {
      calls.add(List<String>.unmodifiable(args));
      stdins.add(stdin);
      return Future.value(
        const BdResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Error: batch is not supported in proxied-server mode',
        ),
      );
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}
