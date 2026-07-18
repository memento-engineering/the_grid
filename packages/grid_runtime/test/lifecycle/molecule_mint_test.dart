import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

/// Tests for `StationBeadWriter.createMolecule`/`reapMolecule`
/// (`DESIGN-tg-pm6.md` R6) — the chokepoint mint that pours a molecule's
/// `type=molecule`/`type=step` graph as ONE `bd create --graph` transaction,
/// and its session-close collection counterpart. Offline: a recording
/// BdRunner, no live `bd`, no grid_engine import (this chokepoint stays
/// domain-free — the wire keys it reads/writes are kept wire-compatible with
/// `MoleculeCircuitKeys`/`MoleculeStepKeys` by string literal, never by
/// import).
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

  /// A minimal 2-node molecule plan: a `root` circuit bead parented onto the
  /// owning session, plus one `root.step-a` step bead nested under it —
  /// shaped like `instantiateMolecule`'s own output, without importing it.
  GraphApplyPlan planFor(String sessionId) => GraphApplyPlan(
    commitMessage: 'grid molecule kCodeCircuit @ tgdog-work1/tgdog-sess1',
    nodes: [
      GraphNode(
        key: 'root',
        title: 'circuit kCodeCircuit',
        type: IssueType.molecule.wire,
        parentId: sessionId,
        metadata: {
          'grid.circuit.formula': 'kCodeCircuit',
          'grid.circuit.session': sessionId,
        },
      ),
      GraphNode(
        key: 'root.step-a',
        title: 'step step-a',
        type: IssueType.step.wire,
        metadata: {
          'grid.step.id': 'step-a',
          'grid.step.capability': 'code',
          'grid.step.path': 'root.step-a',
          'grid.step.session': sessionId,
        },
      ),
    ],
    edges: const [
      GraphEdge(fromKey: 'root.step-a', toKey: 'root', type: 'parent-child'),
    ],
  );

  setUp(() {
    runner = RecordingBdRunner(createdId: 'tgdog-sess1')
      ..graphApplyIds = {'root': 'tgdog-mol1', 'root.step-a': 'tgdog-step1'};
    bd = BdCliService(runner);
    refusals = <String>[];
  });

  group('createMolecule — one pour, one Dolt transaction', () {
    test(
      'pours the plan as ONE `bd create --graph` invocation with NO --ephemeral',
      () async {
        final ids = await writer().createMolecule(
          planFor('tgdog-sess1'),
          substation: 'tgdog',
          sessionId: 'tgdog-sess1',
        );

        expect(ids, {'root': 'tgdog-mol1', 'root.step-a': 'tgdog-step1'});

        // Exactly ONE graph-apply pour — never a per-node create loop.
        expect(runner.graphApplyCalls, hasLength(1));
        final argv = runner.graphApplyCalls.single;
        expect(argv, containsAllInOrder(['create', '--graph']));
        expect(argv, contains('--json'));
        expect(argv, containsAllInOrder(['--actor', 'grid-controller']));
        // PERSISTENT (Decided item 1): never a wisp.
        expect(argv, isNot(contains('--ephemeral')));

        // The dedup probe reads the store BEFORE pouring, but no OTHER bd
        // call happened besides that read + the one pour.
        expect(runner.callsFor('export'), hasLength(1));
        expect(runner.calls, hasLength(2));
      },
    );

    test('fail-closed: a molecule targeting a NON-owned substation is refused '
        'before any bd call', () async {
      await expectLater(
        writer().createMolecule(
          planFor('gascity-sess1'),
          substation: 'gascity',
          sessionId: 'gascity-sess1',
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
      expect(refusals, hasLength(1));
    });

    test(
      'fail-closed: a node parented onto a FOREIGN existing bead poisons the '
      'whole pour even though the substation itself is owned',
      () async {
        final plan = GraphApplyPlan(
          commitMessage: 'grid molecule x',
          nodes: [
            GraphNode(
              key: 'root',
              title: 'circuit x',
              type: IssueType.molecule.wire,
              // Owned substation, but parented onto a FOREIGN session.
              parentId: 'gascity-sess9',
            ),
            const GraphNode(
              key: 'root.step-a',
              title: 'step step-a',
              type: 'step',
            ),
          ],
        );

        await expectLater(
          writer().createMolecule(
            plan,
            substation: 'tgdog',
            sessionId: 'tgdog-sess1',
          ),
          throwsA(isA<OwnershipRefused>()),
        );
        // NOT ONE bd call was issued — refused before the wire.
        expect(runner.calls, isEmpty);
      },
    );

    test('refuses an empty plan before touching bd', () async {
      await expectLater(
        writer().createMolecule(
          const GraphApplyPlan(commitMessage: 'empty'),
          substation: 'tgdog',
          sessionId: 'tgdog-sess1',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(runner.calls, isEmpty);
    });

    test(
      'mint-dedup: an OPEN molecule bead already stamped with this session — '
      're-entry pours NOTHING and returns an empty map',
      () async {
        runner.exportBeads = [
          Bead(
            id: 'tgdog-mol1',
            title: 'circuit kCodeCircuit',
            issueType: IssueType.molecule,
            status: BeadStatus.open,
            metadata: const {
              'grid.circuit.session': 'tgdog-sess1',
              'grid.circuit.formula': 'kCodeCircuit',
            },
          ),
        ];

        final ids = await writer().createMolecule(
          planFor('tgdog-sess1'),
          substation: 'tgdog',
          sessionId: 'tgdog-sess1',
        );

        expect(ids, isEmpty);
        expect(runner.graphApplyCalls, isEmpty);
      },
    );

    test('mint-dedup also keys on an OPEN `type=step` bead for the session '
        '(not just the molecule root)', () async {
      runner.exportBeads = [
        Bead(
          id: 'tgdog-step1',
          title: 'step step-a',
          issueType: IssueType.step,
          status: BeadStatus.open,
          metadata: const {'grid.step.session': 'tgdog-sess1'},
        ),
      ];

      final ids = await writer().createMolecule(
        planFor('tgdog-sess1'),
        substation: 'tgdog',
        sessionId: 'tgdog-sess1',
      );

      expect(ids, isEmpty);
      expect(runner.graphApplyCalls, isEmpty);
    });

    test(
      'mint-dedup does NOT fire for a DIFFERENT session\'s beads — pours fresh',
      () async {
        runner.exportBeads = [
          Bead(
            id: 'tgdog-molOther',
            title: 'circuit other',
            issueType: IssueType.molecule,
            status: BeadStatus.open,
            metadata: const {'grid.circuit.session': 'tgdog-OTHER-session'},
          ),
        ];

        final ids = await writer().createMolecule(
          planFor('tgdog-sess1'),
          substation: 'tgdog',
          sessionId: 'tgdog-sess1',
        );

        expect(ids, isNotEmpty);
        expect(runner.graphApplyCalls, hasLength(1));
      },
    );

    test(
      'mint-dedup ignores a CLOSED molecule bead (open-only, mirrors the gate '
      'precedent) — pours fresh',
      () async {
        runner.exportBeads = [
          Bead(
            id: 'tgdog-mol1',
            title: 'circuit kCodeCircuit',
            issueType: IssueType.molecule,
            status: BeadStatus.closed,
            metadata: const {'grid.circuit.session': 'tgdog-sess1'},
          ),
        ];

        final ids = await writer().createMolecule(
          planFor('tgdog-sess1'),
          substation: 'tgdog',
          sessionId: 'tgdog-sess1',
        );

        expect(ids, isNotEmpty);
        expect(runner.graphApplyCalls, hasLength(1));
      },
    );
  });

  group('reapMolecule — closes exactly the molecule set, nothing else', () {
    test(
      'closes every OPEN molecule/step bead stamped with the session via ONE '
      '`bd batch`, excluding closed beads, foreign sessions, and other types',
      () async {
        runner.exportBeads = [
          // In scope: OPEN molecule + step for THIS session.
          Bead(
            id: 'tgdog-mol1',
            title: 'circuit',
            issueType: IssueType.molecule,
            status: BeadStatus.open,
            metadata: const {'grid.circuit.session': 'tgdog-sess1'},
          ),
          Bead(
            id: 'tgdog-step1',
            title: 'step',
            issueType: IssueType.step,
            status: BeadStatus.open,
            metadata: const {'grid.step.session': 'tgdog-sess1'},
          ),
          // Out of scope: already closed.
          Bead(
            id: 'tgdog-step2',
            title: 'step (already closed)',
            issueType: IssueType.step,
            status: BeadStatus.closed,
            metadata: const {'grid.step.session': 'tgdog-sess1'},
          ),
          // Out of scope: a DIFFERENT session.
          Bead(
            id: 'tgdog-step3',
            title: 'step (other session)',
            issueType: IssueType.step,
            status: BeadStatus.open,
            metadata: const {'grid.step.session': 'tgdog-OTHER-session'},
          ),
          // Out of scope: right session key, wrong bead type.
          Bead(
            id: 'tgdog-gate1',
            title: 'gate',
            issueType: IssueType.gate,
            status: BeadStatus.open,
            metadata: const {'grid.step.session': 'tgdog-sess1'},
          ),
        ];

        await writer().reapMolecule(sessionId: 'tgdog-sess1');

        final batches = runner.callsFor('batch');
        expect(batches, hasLength(1));
        final script = runner.stdins[runner.calls.indexOf(batches.single)]!;
        final lines = script.split('\n');
        expect(
          lines,
          unorderedEquals(['close tgdog-mol1', 'close tgdog-step1']),
        );
        expect(runner.everyMutationHasActor, isTrue);
        expect(runner.neverCalledShow, isTrue);
      },
    );

    test(
      'no matching beads is a silent no-op — no `bd batch` at all',
      () async {
        runner.exportBeads = [
          Bead(
            id: 'tgdog-step9',
            title: 'unrelated',
            issueType: IssueType.step,
            status: BeadStatus.open,
            metadata: const {'grid.step.session': 'tgdog-OTHER-session'},
          ),
        ];

        await writer().reapMolecule(sessionId: 'tgdog-sess1');

        expect(runner.callsFor('batch'), isEmpty);
        expect(runner.calls, hasLength(1)); // just the export scan
      },
    );

    test('an empty store reaps nothing', () async {
      await writer().reapMolecule(sessionId: 'tgdog-sess1');
      expect(runner.callsFor('batch'), isEmpty);
    });

    test(
      'fail-closed: a matched bead with a FOREIGN id prefix refuses the whole '
      'reap batch (defense in depth — never reached in practice, since '
      'createMolecule only ever mints owned ids)',
      () async {
        runner.exportBeads = [
          Bead(
            id: 'gascity-step1',
            title:
                'step (foreign prefix, same session key by construction bug)',
            issueType: IssueType.step,
            status: BeadStatus.open,
            metadata: const {'grid.step.session': 'tgdog-sess1'},
          ),
        ];

        await expectLater(
          writer().reapMolecule(sessionId: 'tgdog-sess1'),
          throwsA(isA<OwnershipRefused>()),
        );
        expect(runner.callsFor('batch'), isEmpty);
      },
    );
  });
}
