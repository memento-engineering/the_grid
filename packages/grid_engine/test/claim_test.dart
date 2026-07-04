// The pure D-A3 claim predicate (`sdk/claim.dart`, the honesty-pass D-B5 hook
// #1, `docs/SCRATCH-grid-alignment.md`, 2026-07-03): unclaimedSteps narrows
// the ELIGIBLE frontier (`frontier.dart`) to the CapabilitySteps whose
// declared `requires` the station's own CapabilityFacts do not satisfy by
// containment. Zero I/O — pure value-types only, mirroring
// track_a_frontier_test.dart's style.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

final _now = DateTime(2026);

/// A macOS+BLE station (the burn-host's own machine) — satisfies `host`'s
/// requirement, but not `follower`'s (linux+flutter).
const _stationFacts = CapabilityFacts(
  sets: {
    kSystemOs: {'macos'},
    kRadio: {'ble'},
  },
);

/// The ADR-0011 D6 burn shape: `host` requires macOS+BLE (locally satisfied),
/// `follower` requires linux+flutter+BLE (NOT satisfied by this station),
/// `coordinator` declares no requirement at all and awaits both.
const _burn = Circuit(
  id: 'burn',
  terminalStepId: 'coordinator',
  steps: [
    CapabilityStep(
      stepId: 'host',
      capabilityId: 'burn-host',
      requires: CapabilityFacts(
        sets: {
          kSystemOs: {'macos'},
          kRadio: {'ble'},
        },
      ),
    ),
    CapabilityStep(
      stepId: 'follower',
      capabilityId: 'burn-follower',
      requires: CapabilityFacts(
        sets: {
          kSystemOs: {'linux'},
          kFlutterTarget: {'linux'},
          kRadio: {'ble'},
        },
      ),
    ),
    CapabilityStep(
      stepId: 'coordinator',
      capabilityId: 'coord',
      dependsOn: {'host', 'follower'},
    ),
  ],
);

List<UnclaimedStep> _unclaimed(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath, {
  CapabilityFacts stationFacts = _stationFacts,
  Circuit? Function(String circuitId)? circuitById,
}) => unclaimedSteps(
  circuit,
  cursor,
  nodePath,
  stationFacts: stationFacts,
  circuitById: circuitById ?? (_) => null,
  now: _now,
);

void main() {
  group('unclaimedSteps — the D-A3/D-B5 per-requirement predicate', () {
    test('the Burn: host (macOS+BLE) is claimed locally; follower '
        '(linux+flutter+BLE) is unclaimed', () {
      final unclaimed = _unclaimed(_burn, const {}, 'tg-burn');
      expect(unclaimed, hasLength(1));
      final only = unclaimed.single;
      expect(only.nodePath, 'tg-burn/follower');
      expect(only.stepId, 'follower');
      expect(only.capabilityId, 'burn-follower');
      expect(only.requires, (_burn.steps[1] as CapabilityStep).requires);
    });

    test('a step with NO declared requirement is never unclaimed — even '
        'against a totally empty station profile', () {
      const noReqs = Circuit(
        id: 'x',
        terminalStepId: 'a',
        steps: [CapabilityStep(stepId: 'a', capabilityId: 'a')],
      );
      expect(
        _unclaimed(noReqs, const {}, 'n', stationFacts: const CapabilityFacts()),
        isEmpty,
      );
    });

    test('an EMPTY declared requirement matches vacuously — never unclaimed',
        () {
      const emptyReq = Circuit(
        id: 'x',
        terminalStepId: 'a',
        steps: [
          CapabilityStep(
            stepId: 'a',
            capabilityId: 'a',
            requires: CapabilityFacts(),
          ),
        ],
      );
      expect(
        _unclaimed(emptyReq, const {}, 'n', stationFacts: const CapabilityFacts()),
        isEmpty,
      );
    });

    test('a mismatched requirement on a step that is NOT YET ELIGIBLE never '
        'surfaces — unclaimedSteps is scoped to the frontier, not every step',
        () {
      // Give the (currently ineligible) coordinator a mismatched requirement
      // too, to prove it is excluded for INELIGIBILITY, not by chance.
      const withCoordinatorReq = Circuit(
        id: 'burn',
        terminalStepId: 'coordinator',
        steps: [
          CapabilityStep(stepId: 'host', capabilityId: 'burn-host'),
          CapabilityStep(stepId: 'follower', capabilityId: 'burn-follower'),
          CapabilityStep(
            stepId: 'coordinator',
            capabilityId: 'coord',
            dependsOn: {'host', 'follower'},
            requires: CapabilityFacts(
              sets: {
                kSystemOs: {'windows'},
              },
            ),
          ),
        ],
      );
      // Neither host nor follower are complete yet, so coordinator is withheld
      // by the barrier — its mismatched requirement never reaches the set.
      expect(_unclaimed(withCoordinatorReq, const {}, 'n'), isEmpty);
    });

    test('a satisfied requirement on an eligible step resolves LOCALLY — '
        'never reported as unclaimed', () {
      final unclaimed = _unclaimed(_burn, const {}, 'tg-burn');
      expect(unclaimed.any((u) => u.stepId == 'host'), isFalse);
    });

    test('a mismatched requirement on a nested sub-circuit leaf surfaces with '
        'the correctly nested nodePath', () {
      const inner = Circuit(
        id: 'inner',
        terminalStepId: 'follower',
        steps: [
          CapabilityStep(
            stepId: 'follower',
            capabilityId: 'burn-follower',
            requires: CapabilityFacts(
              sets: {
                kSystemOs: {'linux'},
              },
            ),
          ),
        ],
      );
      const outer = Circuit(
        id: 'outer',
        terminalStepId: 'wrap',
        steps: [SubCircuitStep(stepId: 'wrap', circuitId: 'inner')],
      );
      final registry = {'inner': inner};
      final unclaimed = _unclaimed(
        outer,
        const {},
        'tg-burn',
        circuitById: (id) => registry[id],
      );
      expect(unclaimed, hasLength(1));
      expect(unclaimed.single.nodePath, 'tg-burn/wrap/follower');
    });
  });
}
