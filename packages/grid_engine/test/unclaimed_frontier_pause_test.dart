import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

const _macos = CapabilityFacts(
  sets: {
    kSystemOs: {'macos'},
    kRadio: {'ble'},
  },
);

const _linuxRequirement = CapabilityFacts(
  sets: {
    kSystemOs: {'linux'},
    kRadio: {'ble'},
  },
);

const _burn = Circuit(
  id: 'burn',
  terminalStepId: 'coordinator',
  steps: [
    CapabilityStep(stepId: 'host', capabilityId: 'burn-host', requires: _macos),
    CapabilityStep(
      stepId: 'follower',
      capabilityId: 'burn-follower',
      requires: _linuxRequirement,
    ),
    CapabilityStep(
      stepId: 'coordinator',
      capabilityId: 'coord',
      dependsOn: {'host', 'follower'},
    ),
  ],
);

List<UnclaimedRequirement> _frontier(SessionPauseState pauseState) =>
    stationUnclaimedFrontier(
      JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [
            Bead(
              id: 'tg-burn',
              issueType: IssueType.task,
              status: BeadStatus.open,
            ),
          ],
          dependencies: const [],
          readyIds: const {'tg-burn'},
          capturedAt: DateTime(2026),
        ),
        sessionsByWorkBead: {
          'tg-burn': SessionProjection(
            workBeadId: 'tg-burn',
            sessionId: 'tgdog-s1',
            pauseState: pauseState,
          ),
        },
      ),
      rootCircuitFor: (_) => _burn,
      registry: RecordingCapabilityRegistry(clock: DateTime(2026)),
      stationFacts: _macos,
    );

void main() {
  test('a paused session broadcasts no unclaimed requirement', () {
    final live = _frontier(SessionPauseState.none);
    expect(live, hasLength(1));
    expect(live.single.step.stepId, 'follower');

    expect(_frontier(SessionPauseState.paused), isEmpty);
    expect(_frontier(SessionPauseState.resumed), hasLength(1));
  });
}
