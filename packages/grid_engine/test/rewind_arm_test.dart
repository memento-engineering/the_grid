// tg-o90 — StepOutcome.Rewind: routing as a first-class engine primitive.
//
// MIGRATED (tg-eli phase 2 — the molecule-only removal): the flat write
// cascade a `Rewind` verdict used to drive (`_persistRewind` — flip the
// named sibling + its transitive dependents + the rewinding node itself back
// to `pending` with a bumped `rewindCount`, so the sub-DAG re-runs VIRGIN
// inside the SAME session) is DELETED along with the flat cursor model. On
// the molecule-only engine, backward motion is DERIVED (a step's incarnation
// is which link of its own `DependencyType.supersedes` chain is ACTIVE — A52
// Ratified, `molecule_codec.dart`'s `supersedesDepthByStepId`), never
// PERSISTED as a `rewindCount` key (Decided item 7) and never actuated by a
// circuit step's own verdict. So a `CapabilityHost` that receives an
// `AllocationRewound` report on the molecule path is, by construction, a
// MIS-COMPOSITION — `CapabilityHostState._persistRewindReport` routes it to
// a supervised FAILURE, unconditionally, regardless of the named stepIds or
// reason (`capability_host.dart`'s exact, hardcoded message). This is the
// PRE-EXISTING molecule behavior (unchanged by this wave — the flat write
// cascade retired, leaving this refusal as the ONLY behavior); this file
// migrates every scenario to assert THAT, deleting the flat re-run / re-key /
// rework-cap-belt assertions that rode the retired cascade (none of those
// mechanics exist on the molecule engine — the cap belt for an actual rework
// ROUND lives in `SessionScope`/`live_frontier.dart`'s supersedes-chain-depth
// derivation, an entirely different mechanism this lane does not own).
//
// `test/molecule/host_molecule_targeting_test.dart` already proves the single
// canonical case ("AllocationRewound is DEAD CODE on the molecule path");
// this file's job is narrower — pin every VARIANT of the report's payload
// (a real sibling name, an unknown step id, an empty stepIds set) to the
// SAME refusal (nothing about the payload changes the outcome any more), plus
// the surviving FENCE (an `Escalate` still parks, untouched by this rung) and
// the SDK-level allocation mapping (`RouteAllocation` → `AllocationRewound`,
// unaffected by the Host-side change).
//
// Zero I/O: fakes + the recording chokepoint.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The circuit the mounted `route` node belongs to (`StepMount.circuit` — the
/// graph a Rewind would (formerly) resolve its siblings against).
const _specReview = Circuit(
  id: 'spec_review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'specify', capabilityId: 'specify'),
    CapabilityStep(
      stepId: 'critic',
      capabilityId: 'critic',
      dependsOn: {'specify'},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'critic'},
    ),
  ],
);

const _stepBeadId = 'tgdog-step1';

/// The step bead id [InheritedCircuit.beadIdByNodePath] resolves the mounted
/// route node to — every host in this file writes here (R5b).
final _moleculeCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
  beadIdByNodePath: const {'tg-1/spec_review/route': _stepBeadId},
  cursor: const {},
);

/// A bare-mounted REAL CapabilityHost over [capability] at the spec circuit's
/// `route` node, ambient to an [InheritedCircuit] (R2) — the shape the
/// refusal / fence cases need (no join, no SessionScope; just the host's own
/// actuation writing through the chokepoint to its OWN step bead).
({TreeOwner owner, Fakes fakes}) _bareRoute(
  Capability capability, {
  NodeCursor node = const NodeCursor(),
  EscalationHandler? escalation,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: DateTime(2026)),
        child: InheritedSeed<ServiceBundle>(
          value: ServiceBundle(escalation: escalation),
          child: InheritedSeed<InheritedCircuit>(
            value: _moleculeCircuit,
            child: InheritedSeed<SiblingView>(
              value: const SiblingView(),
              child: CapabilityHost(
                capability: capability,
                mount: StepMount(
                  step: const CapabilityStep(
                    stepId: 'route',
                    capabilityId: 'route',
                  ),
                  nodePath: 'tg-1/spec_review/route',
                  circuit: _specReview,
                  circuitPath: 'tg-1/spec_review',
                  session: const SessionHandle('tgdog-s'),
                  node: node,
                  key: ValueKey(
                    'tg-1/spec_review/route#${node.restartCount}.'
                    '${node.rewindCount}',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

void main() {
  group(
    'tg-o90 — AllocationRewound is DEAD CODE on the molecule engine: EVERY '
    'variant of the report routes to the SAME supervised failure on the '
    "step's OWN bead",
    () {
      for (final scenario in [
        (
          name: 'a real sibling name',
          verdict: const Rewind({'specify'}, 'RESPEC: acceptance not '
              'falsifiable'),
        ),
        (
          name: 'an UNKNOWN step id',
          verdict: const Rewind({'nope'}, 'typo'),
        ),
        (name: 'an EMPTY stepIds set', verdict: const Rewind({}, 'oops')),
      ]) {
        test(
          '${scenario.name}: state=failed on the step bead, restartCount '
          'bumped, no gate bead, no grid.cursor.* key anywhere — the payload '
          'never changes the outcome',
          () async {
            final h = _bareRoute(FixedRouteCapability(scenario.verdict));
            addTearDown(() {
              h.owner.dispose();
              unawaited(h.fakes.provider.close());
            });
            await _pump();

            final updates = h.fakes.runner.callsFor('update');
            expect(updates, hasLength(1));
            expect(
              updates.single[1],
              _stepBeadId,
              reason: 'the write targets the STEP bead, never the session bead',
            );
            final meta = h.fakes.runner.metadataOfUpdate(0);
            expect(meta[MoleculeStepKeys.state], 'failed');
            expect(meta[MoleculeStepKeys.restartCount], '1');
            expect(
              meta[MoleculeStepKeys.failureReason],
              contains('backward motion is derived'),
            );
            expect(
              meta.keys,
              isNot(contains('grid.step.rewindCount')),
              reason: 'the molecule schema never persists rewindCount (item 7)',
            );
            expect(
              meta.keys.where((k) => k.startsWith('grid.cursor.')),
              isEmpty,
            );
            expect(
              h.fakes.runner.callsFor('create'),
              isEmpty,
              reason: 'no gate bead — a refusal is a FAILURE, never a park',
            );
          },
        );
      }
    },
  );

  group('tg-o90 — the FENCE: an Escalate from the SAME circuit still parks '
      'exactly as before, untouched by the rewind removal', () {
    test('an Escalate writes gated on the step bead + mints a real gate bead '
        '(the M5 D-7 default HumanGate — no handler bound)', () async {
      final h = _bareRoute(
        const FixedRouteCapability(Escalate('human ultimatum')),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      // TWO chokepoint `update`s: (1) the `state=gated` cursor write on the
      // step bead (R5b) and (2) `createGate`'s own metadata stamp on the
      // freshly minted gate bead (unchanged — still keyed to the OWNING
      // SESSION, an orthogonal concern to R5b's write-target fork).
      final updates = h.fakes.runner.callsFor('update');
      expect(updates, hasLength(2));
      expect(updates.first[1], _stepBeadId);
      expect(h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.state], 'gated');

      final creates = h.fakes.runner.callsFor('create');
      expect(creates, hasLength(1));
      expect(creates.single, containsAllInOrder(['--type', 'gate']));
      final gateStamp = h.fakes.runner.metadataOfUpdate(1);
      expect(gateStamp['blocks'], 'tgdog-s');
      expect(gateStamp['node'], 'tg-1/spec_review/route');

      // The park is NOT a rewind: no axis bumped, no rewindCount key.
      expect(
        h.fakes.runner.metadataOfUpdate(0).keys,
        isNot(contains('grid.step.rewindCount')),
      );
    });
  });

  group('tg-o90 — the allocation layer maps a Rewind to a DISTINCT report '
      '(SDK-level; unaffected by the Host-side molecule refusal)', () {
    test('RouteAllocation reports AllocationRewound (never Escalated/Failed)',
        () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final alloc = RouteAllocation(
        const FixedRouteCapability(Rewind({'specify'}, 'respec')),
        AllocationContext(
          treeContext: FakeTreeContext(),
          args: stepArgs('tg-1/spec_review/route'),
          transport: provider,
          address: const AllocationAddress('tgdog-s', 'tg-1/spec_review/route'),
          env: const {},
          sink: reports.add,
        ),
      );
      await alloc.startOrAdopt();

      expect(reports, hasLength(1));
      final report = reports.single;
      expect(report, isA<AllocationRewound>());
      expect((report as AllocationRewound).stepIds, {'specify'});
      expect(report.reason, 'respec');
    });
  });
}
