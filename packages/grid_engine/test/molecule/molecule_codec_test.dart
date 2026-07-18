// R1 — the molecule schema + codec + instantiateMolecule (cook's role).
//
// `stepBeadMetadata` / `projectMoleculeCursor` mirror the flat model's
// `nodeCursorMetadata` / `projectCircuitCursor` (session_bead_test.dart); this
// file is deliberately structured the same way so the two codecs stay
// comparable at a glance. `instantiateMolecule` is a pure compile step (cook's
// role) — no I/O, no Fakes needed.
//
// DESIGN-tg-pm6.md §4 / §14. Zero I/O.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/molecule_codec.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:test/test.dart';

Bead _stepBead(
  String id,
  String nodePath, {
  Map<String, String> extra = const {},
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.step,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {MoleculeStepKeys.path: nodePath, ...extra},
);

// --- the kCodeCircuit-shaped fixture (mirrors rewind_arm_test.dart's style) --
//
// `harnessPeripheral` is a SubCircuitStep nested under the root `code` circuit
// (recursion); `critic-correctness`/`critic-security` are a same-capability
// swarm (Decided item 4) that each validate `build` (the validates
// convention); `land` is the terminal, gated on the whole fan-out.

const _harnessPeripheral = Circuit(
  id: 'harness-peripheral',
  terminalStepId: 'launch',
  steps: [
    CapabilityStep(stepId: 'prep', capabilityId: 'prep'),
    CapabilityStep(
      stepId: 'launch',
      capabilityId: 'launch',
      kind: StepKind.daemon,
      dependsOn: {'prep'},
    ),
  ],
);

const _codeCircuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'build'),
    SubCircuitStep(
      stepId: 'harnessPeripheral',
      circuitId: 'harness-peripheral',
      dependsOn: {'build'},
    ),
    CapabilityStep(
      stepId: 'critic-correctness',
      capabilityId: 'critic',
      dependsOn: {'build'},
      params: {kSwarmParam: 'committee', kValidatesParam: 'build'},
    ),
    CapabilityStep(
      stepId: 'critic-security',
      capabilityId: 'critic',
      dependsOn: {'build'},
      params: {kSwarmParam: 'committee', kValidatesParam: 'build'},
    ),
    CapabilityStep(
      stepId: 'land',
      capabilityId: 'land',
      dependsOn: {'critic-correctness', 'critic-security', 'harnessPeripheral'},
    ),
  ],
);

Circuit? _circuitById(String id) => switch (id) {
  'harness-peripheral' => _harnessPeripheral,
  _ => null,
};

void main() {
  group('stepBeadMetadata (the write half — mirrors nodeCursorMetadata)', () {
    test('writes state + restartCount always; omits null optionals', () {
      final meta = stepBeadMetadata(const NodeCursor(state: StepState.running));
      expect(meta, {
        MoleculeStepKeys.state: 'running',
        MoleculeStepKeys.restartCount: '0',
      });
    });

    test('writes every set field with the right key + UTC ISO date', () {
      final meta = stepBeadMetadata(
        NodeCursor(
          state: StepState.failed,
          restartCount: 2,
          cooldownUntil: DateTime.utc(2026, 6, 27, 12),
          startedAt: DateTime.utc(2026, 6, 27, 11),
          finishedAt: DateTime.utc(2026, 6, 27, 11, 30),
          durationMs: 1800000,
          failureReason: 'boom',
        ),
      );
      expect(meta[MoleculeStepKeys.state], 'failed');
      expect(meta[MoleculeStepKeys.restartCount], '2');
      expect(meta[MoleculeStepKeys.cooldownUntil], '2026-06-27T12:00:00.000Z');
      expect(meta[MoleculeStepKeys.startedAt], '2026-06-27T11:00:00.000Z');
      expect(meta[MoleculeStepKeys.finishedAt], '2026-06-27T11:30:00.000Z');
      expect(meta[MoleculeStepKeys.durationMs], '1800000');
      expect(meta[MoleculeStepKeys.failureReason], 'boom');
    });

    test(
      'never writes a pgid/pid/token key — those ride LeaseKeys (R3), never this codec',
      () {
        final meta = stepBeadMetadata(
          const NodeCursor(
            state: StepState.running,
            pgid: 42,
            pid: 43,
            token: 'tok',
          ),
        );
        expect(meta.keys, isNot(contains(LeaseKeys.pgid)));
        expect(meta.keys, isNot(contains(LeaseKeys.pid)));
        expect(meta.keys, isNot(contains(LeaseKeys.token)));
        for (final key in meta.keys) {
          expect(key.startsWith(LeaseKeys.prefix), isFalse, reason: key);
        }
      },
    );

    test(
      'never writes a rewindCount key (Decided item 7: derived, never persisted)',
      () {
        final meta = stepBeadMetadata(
          const NodeCursor(state: StepState.pending),
        );
        expect(meta.keys, isNot(contains(contains('rewindCount'))));
      },
    );
  });

  group('projectMoleculeCursor (the read half — mirrors projectCircuitCursor)', () {
    test(
      'golden round-trip: stepBeadMetadata -> projectMoleculeCursor recovers '
      'the original NodeCursor exactly',
      () {
        const nodePath = 'tg-1/build';
        final original = NodeCursor(
          state: StepState.failed,
          restartCount: 2,
          cooldownUntil: DateTime.utc(2026, 7, 1),
          startedAt: DateTime.utc(2026, 7, 1, 11),
          finishedAt: DateTime.utc(2026, 7, 1, 11, 5),
          durationMs: 300000,
          failureReason: 'boom',
        );
        final bead = _stepBead(
          'tgdog-step-9',
          nodePath,
          extra: stepBeadMetadata(original),
        );
        final projected = projectMoleculeCursor([bead]);
        expect(projected.cursor[nodePath], original);
        expect(projected.beadIdByNodePath[nodePath], 'tgdog-step-9');
      },
    );

    test(
      'a fresh step bead (no fine state key) falls back to bd status: open -> pending',
      () {
        final bead = _stepBead('s1', 'tg-1/build');
        expect(
          projectMoleculeCursor([bead]).cursor['tg-1/build']!.state,
          StepState.pending,
        );
      },
    );

    test('a fresh step bead falls back to bd status: closed -> complete', () {
      final bead = _stepBead('s1', 'tg-1/build', closed: true);
      expect(
        projectMoleculeCursor([bead]).cursor['tg-1/build']!.state,
        StepState.complete,
      );
    });

    test(
      'every StepState round-trips through the fine-state key (no fallback engaged)',
      () {
        for (final s in StepState.values) {
          final bead = _stepBead(
            's',
            'p',
            extra: stepBeadMetadata(NodeCursor(state: s)),
          );
          expect(projectMoleculeCursor([bead]).cursor['p']!.state, s);
        }
      },
    );

    test(
      'a non-step bead (a molecule bead) never contributes a cursor entry',
      () {
        final molecule = Bead(
          id: 'tgdog-mol-1',
          issueType: IssueType.molecule,
          metadata: {
            MoleculeCircuitKeys.formula: 'code',
            MoleculeCircuitKeys.session: 'tgdog-sess-1',
          },
        );
        final projected = projectMoleculeCursor([molecule]);
        expect(projected.cursor, isEmpty);
        expect(projected.beadIdByNodePath, isEmpty);
      },
    );

    test(
      'a step bead missing MoleculeStepKeys.path is skipped, not thrown (malformed, fail-closed)',
      () {
        final bead = Bead(
          id: 's-broken',
          issueType: IssueType.step,
          metadata: {MoleculeStepKeys.state: 'running'},
        );
        expect(() => projectMoleculeCursor([bead]), returnsNormally);
        expect(projectMoleculeCursor([bead]).cursor, isEmpty);
      },
    );

    test(
      'disjoint step beads project independently (separate beads, not disjoint keys — '
      'the molecule model trades the flat model\'s merge-isolation story for bead-isolation)',
      () {
        final a = _stepBead(
          'a',
          'n/x',
          extra: stepBeadMetadata(const NodeCursor(state: StepState.complete)),
        );
        final b = _stepBead(
          'b',
          'n/y',
          extra: stepBeadMetadata(const NodeCursor(state: StepState.running)),
        );
        final cursor = projectMoleculeCursor([a, b]).cursor;
        expect(cursor['n/x']!.state, StepState.complete);
        expect(cursor['n/y']!.state, StepState.running);
      },
    );

    test('supersedes chain selects the active step bead for a path', () {
      final prior = _stepBead(
        's0',
        'tg-1/build',
        extra: stepBeadMetadata(const NodeCursor(state: StepState.complete)),
      );
      final successor = _stepBead(
        's1',
        'tg-1/build',
        extra: stepBeadMetadata(const NodeCursor(state: StepState.pending)),
      );
      const deps = [
        BeadDependency(
          issueId: 's1',
          dependsOnId: 's0',
          type: DependencyType.supersedes,
        ),
      ];

      final active = activeStepBeadsByPath([prior, successor], deps);
      expect(active['tg-1/build']!.id, 's1');
      expect(supersedesDepthByStepId([prior, successor], deps), {
        's0': 0,
        's1': 1,
      });
      expect(supersedesDepthByPath([prior, successor], deps), {
        'tg-1/build': 1,
      });

      final projected = projectMoleculeCursor([
        prior,
        successor,
      ], dependencies: deps);
      expect(projected.beadIdByNodePath['tg-1/build'], 's1');
      expect(projected.cursor['tg-1/build']!.state, StepState.pending);
    });

    test('supersedes depth is monotonic across successor beads', () {
      final a = _stepBead('s0', 'tg-1/build');
      final b = _stepBead('s1', 'tg-1/build');
      final c = _stepBead('s2', 'tg-1/build');
      const deps = [
        BeadDependency(
          issueId: 's1',
          dependsOnId: 's0',
          type: DependencyType.supersedes,
        ),
        BeadDependency(
          issueId: 's2',
          dependsOnId: 's1',
          type: DependencyType.supersedes,
        ),
      ];

      expect(supersedesDepthByStepId([a, b, c], deps), {
        's0': 0,
        's1': 1,
        's2': 2,
      });
      expect(activeStepBeadsByPath([a, b, c], deps)['tg-1/build']!.id, 's2');
      expect(supersedesDepthByPath([a, b, c], deps), {'tg-1/build': 2});
    });

    test(
      'projected rewindCount is always 0 — R4 layers the derived generation in memory only',
      () {
        final bead = _stepBead(
          's1',
          'tg-1/build',
          extra: stepBeadMetadata(const NodeCursor(state: StepState.complete)),
        );
        expect(
          projectMoleculeCursor([bead]).cursor['tg-1/build']!.rewindCount,
          0,
        );
      },
    );
  });

  group(
    'structural — the codec never reads grid.lease.* (R3 boundary, item 5)',
    () {
      test(
        'lease keys on a step bead have zero effect on the projected cursor',
        () {
          final withLease = _stepBead(
            's1',
            'tg-1/build',
            extra: {
              ...stepBeadMetadata(const NodeCursor(state: StepState.running)),
              LeaseKeys.pgid: '111',
              LeaseKeys.pid: '222',
              LeaseKeys.token: 'tok',
            },
          );
          final withoutLease = _stepBead(
            's1',
            'tg-1/build',
            extra: stepBeadMetadata(const NodeCursor(state: StepState.running)),
          );
          expect(
            projectMoleculeCursor([withLease]).cursor,
            projectMoleculeCursor([withoutLease]).cursor,
          );
          final node = projectMoleculeCursor([withLease]).cursor['tg-1/build']!;
          expect(node.pgid, isNull);
          expect(node.pid, isNull);
          expect(node.token, isNull);
        },
      );
    },
  );

  group(
    'structural — no durable key the derivation reads carries prose (pow-hf2)',
    () {
      test(
        'every StepState wire value is a bare identifier, never a sentence',
        () {
          for (final s in StepState.values) {
            final meta = stepBeadMetadata(NodeCursor(state: s));
            expect(meta[MoleculeStepKeys.state], s.name);
            expect(s.name, isNot(contains(' ')));
          }
        },
      );

      test(
        'an unrecognised/prose state value never gates as itself — the coarse-status '
        'fallback wins instead of accepting arbitrary text as state',
        () {
          final bead = _stepBead(
            's1',
            'tg-1/build',
            extra: {MoleculeStepKeys.state: 'the build looks fine to me'},
          );
          expect(
            projectMoleculeCursor([bead]).cursor['tg-1/build']!.state,
            StepState.pending,
          );
        },
      );

      test(
        'failureReason IS prose but is capture-only: it never substitutes for the '
        'gating state field',
        () {
          final bead = _stepBead(
            's1',
            'tg-1/build',
            extra: {
              MoleculeStepKeys.failureReason: 'boom, everything is on fire',
            },
          );
          final node = projectMoleculeCursor([bead]).cursor['tg-1/build']!;
          expect(
            node.state,
            StepState.pending,
          ); // coarse-status fallback, not failed
          expect(node.failureReason, 'boom, everything is on fire');
        },
      );
    },
  );

  group("instantiateMolecule (cook's role — the pure compile step)", () {
    const sessionId = 'tgdog-sess-1';
    const nodePath = 'tg-42';
    final root = BeadPathKey(['genesis-7r9', sessionId]);

    late GraphApplyPlan plan;

    setUp(() {
      plan = instantiateMolecule(
        _codeCircuit,
        sessionId: sessionId,
        root: root,
        nodePath: nodePath,
        circuitById: _circuitById,
      );
    });

    test(
      'golden node set: one molecule/step GraphNode per circuit node, incl. recursion',
      () {
        final byKey = {for (final n in plan.nodes) n.key: n};
        expect(byKey.keys.toSet(), {
          'tg-42',
          'tg-42/build',
          'tg-42/harnessPeripheral',
          'tg-42/harnessPeripheral/prep',
          'tg-42/harnessPeripheral/launch',
          'tg-42/critic-correctness',
          'tg-42/critic-security',
          'tg-42/land',
        });

        expect(byKey['tg-42']!.type, IssueType.molecule.wire);
        expect(byKey['tg-42']!.metadata[MoleculeCircuitKeys.formula], 'code');
        expect(
          byKey['tg-42']!.metadata[MoleculeCircuitKeys.session],
          sessionId,
        );

        expect(byKey['tg-42/harnessPeripheral']!.type, IssueType.molecule.wire);
        expect(
          byKey['tg-42/harnessPeripheral']!.metadata[MoleculeCircuitKeys
              .formula],
          'harness-peripheral',
        );

        expect(byKey['tg-42/build']!.type, IssueType.step.wire);
        expect(
          byKey['tg-42/build']!.metadata[MoleculeStepKeys.stepId],
          'build',
        );
        expect(
          byKey['tg-42/build']!.metadata[MoleculeStepKeys.capability],
          'build',
        );
        expect(byKey['tg-42/build']!.metadata[MoleculeStepKeys.kind], 'job');
        expect(
          byKey['tg-42/build']!.metadata[MoleculeStepKeys.path],
          'tg-42/build',
        );
        expect(
          byKey['tg-42/build']!.metadata[MoleculeStepKeys.session],
          sessionId,
        );
        expect(
          byKey['tg-42/build']!.metadata.containsKey(MoleculeStepKeys.swarm),
          isFalse,
        );

        expect(
          byKey['tg-42/harnessPeripheral/launch']!.metadata[MoleculeStepKeys
              .kind],
          'daemon',
        );
      },
    );

    test(
      'the crumb key is NEVER stamped by this pure compile step (a later, post-pour rung stamps it)',
      () {
        for (final node in plan.nodes) {
          expect(node.metadata.containsKey(MoleculeCircuitKeys.crumb), isFalse);
          expect(node.metadata.containsKey(MoleculeStepKeys.crumb), isFalse);
        }
      },
    );

    test(
      'a swarm of same-capability critics yields DISTINCT sibling step ids (item 4)',
      () {
        final critics = plan.nodes
            .where((n) => n.metadata[MoleculeStepKeys.capability] == 'critic')
            .toList();
        expect(critics.length, 2);
        expect(
          critics.map((n) => n.metadata[MoleculeStepKeys.stepId]).toSet(),
          {'critic-correctness', 'critic-security'},
        );
        expect(critics.map((n) => n.key).toSet().length, 2);
        for (final critic in critics) {
          expect(critic.metadata[MoleculeStepKeys.swarm], 'committee');
        }
      },
    );

    test('golden edge set: parent-child nesting + blocks barriers + the validates-convention '
        'edge, incl. recursion resolving through the nested terminal step', () {
      final actual = plan.edges
          .map((e) => (e.fromKey, e.toKey, e.type))
          .toSet();
      final expected = <(String, String, String)>{
        // parent-child nesting (Native structure: session→molecule, molecule→step,
        // molecule→sub-molecule).
        ('tg-42/build', 'tg-42', DependencyType.parentChild.wire),
        ('tg-42/harnessPeripheral', 'tg-42', DependencyType.parentChild.wire),
        (
          'tg-42/harnessPeripheral/prep',
          'tg-42/harnessPeripheral',
          DependencyType.parentChild.wire,
        ),
        (
          'tg-42/harnessPeripheral/launch',
          'tg-42/harnessPeripheral',
          DependencyType.parentChild.wire,
        ),
        ('tg-42/critic-correctness', 'tg-42', DependencyType.parentChild.wire),
        ('tg-42/critic-security', 'tg-42', DependencyType.parentChild.wire),
        ('tg-42/land', 'tg-42', DependencyType.parentChild.wire),
        // dependsOn barriers.
        ('tg-42/harnessPeripheral', 'tg-42/build', DependencyType.blocks.wire),
        (
          'tg-42/harnessPeripheral/launch',
          'tg-42/harnessPeripheral/prep',
          DependencyType.blocks.wire,
        ),
        ('tg-42/critic-correctness', 'tg-42/build', DependencyType.blocks.wire),
        ('tg-42/critic-security', 'tg-42/build', DependencyType.blocks.wire),
        // land's SubCircuitStep dep resolves through the nested TERMINAL step
        // (harnessPeripheral's own terminalStepId, 'launch') — the exact path
        // sdk/frontier.dart's depTerminalPath would compute for depsSatisfied.
        ('tg-42/land', 'tg-42/critic-correctness', DependencyType.blocks.wire),
        ('tg-42/land', 'tg-42/critic-security', DependencyType.blocks.wire),
        (
          'tg-42/land',
          'tg-42/harnessPeripheral/launch',
          DependencyType.blocks.wire,
        ),
        // the validates-convention edge (params[kValidatesParam] -> 'build').
        (
          'tg-42/critic-correctness',
          'tg-42/build',
          DependencyType.validates.wire,
        ),
        ('tg-42/critic-security', 'tg-42/build', DependencyType.validates.wire),
      };
      expect(actual, expected);
    });

    test(
      'the root molecule parents onto the EXISTING session bead via parentId; a nested '
      'molecule parents ONLY through the parentChild edge, never parentId',
      () {
        final byKey = {for (final n in plan.nodes) n.key: n};
        expect(byKey['tg-42']!.parentId, sessionId);
        expect(byKey['tg-42']!.parentKey, isNull);
        expect(byKey['tg-42/harnessPeripheral']!.parentId, isNull);
        expect(byKey['tg-42/build']!.parentId, isNull);
      },
    );

    test(
      'commitMessage carries the circuit id and the root breadcrumb (audit trail)',
      () {
        expect(plan.commitMessage, contains('code'));
        expect(plan.commitMessage, contains(root.canonical));
      },
    );

    test(
      'never mints a grid.cursor.* or rewindCount key anywhere in the plan — the molecule '
      'model has no flat-cursor key AT ALL, and rewindCount is derived, never persisted',
      () {
        for (final node in plan.nodes) {
          for (final key in node.metadata.keys) {
            expect(key.startsWith('grid.cursor.'), isFalse, reason: key);
            expect(key, isNot(contains('rewindCount')));
            expect(key.startsWith(LeaseKeys.prefix), isFalse, reason: key);
          }
        }
      },
    );
  });

  group('instantiateMolecule — fail-closed on a dangling reference', () {
    const sessionId = 'tgdog-sess-1';
    final root = BeadPathKey([sessionId]);

    test('a dangling SubCircuitStep circuitId mints nothing for that step', () {
      const circuit = Circuit(
        id: 'broken',
        terminalStepId: 'ghost',
        steps: [SubCircuitStep(stepId: 'ghost', circuitId: 'does-not-exist')],
      );
      final plan = instantiateMolecule(
        circuit,
        sessionId: sessionId,
        root: root,
        nodePath: 'tg-9',
        circuitById: (_) => null,
      );
      expect(plan.nodes.map((n) => n.key), ['tg-9']);
      expect(plan.edges, isEmpty);
    });

    test(
      'a dangling dependsOn/validates target mints no edge, only the parent-child one',
      () {
        const circuit = Circuit(
          id: 'lonely',
          terminalStepId: 'x',
          steps: [
            CapabilityStep(
              stepId: 'x',
              capabilityId: 'x',
              dependsOn: {'ghost'},
              params: {kValidatesParam: 'also-ghost'},
            ),
          ],
        );
        final plan = instantiateMolecule(
          circuit,
          sessionId: sessionId,
          root: root,
          nodePath: 'tg-9',
          circuitById: null,
        );
        expect(plan.edges.length, 1);
        expect(plan.edges.single.type, DependencyType.parentChild.wire);
      },
    );

    test(
      'a null circuitById resolver defaults to resolving nothing (never throws)',
      () {
        const circuit = Circuit(
          id: 'solo',
          terminalStepId: 'x',
          steps: [CapabilityStep(stepId: 'x', capabilityId: 'x')],
        );
        expect(
          () => instantiateMolecule(
            circuit,
            sessionId: sessionId,
            root: root,
            nodePath: 'tg-1',
          ),
          returnsNormally,
        );
      },
    );
  });
}
