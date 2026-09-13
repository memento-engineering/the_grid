import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  test('relay contract and persisted horizon projection', () async {
    final deadline = DateTime.utc(2026, 9, 12, 12);
    final observedAt = deadline.add(const Duration(minutes: 1));
    final observation = RelayObservation(
      sessionId: 'state-session-1',
      workBeadId: 'work-1',
      startedAt: deadline.subtract(const Duration(hours: 24)),
      deadline: deadline,
      observedAt: observedAt,
    );
    expect(observation.copyWith(observedAt: observedAt), observation);

    final observer = _FakeRelayObserver(
      const RelayVerdict.absorb(nextHorizon: Duration(hours: 6)),
    );
    final absorb = await observer.observe(observation);
    final absorbSummary = switch (absorb) {
      RelayAbsorb(:final nextHorizon) => 'absorb:${nextHorizon.inHours}',
      RelayEscalate(:final reason) => 'escalate:$reason',
    };
    expect(absorbSummary, 'absorb:6');

    const escalate = RelayVerdict.escalate(reason: 'operator needed');
    final escalationSummary = switch (escalate) {
      RelayAbsorb(:final nextHorizon) => 'absorb:${nextHorizon.inHours}',
      RelayEscalate(:final reason) => 'escalate:$reason',
    };
    expect(escalationSummary, 'escalate:operator needed');

    final nextAt = DateTime.utc(2026, 9, 13, 3, 4, 5);
    final metadata = <String, String>{
      SessionBeadKeys.workBead: 'work-1',
      ...relayHorizonMetadata(nextAt),
    };
    expect(
      metadata[SessionBeadKeys.relayNextObservationAt],
      '2026-09-13T03:04:05.000Z',
    );

    final projected = projectSession(
      Bead(
        id: 'state-session-1',
        issueType: GridIssueTypes.session,
        metadata: metadata,
      ),
    );
    expect(projected.relayNextObservationAt, nextAt);
    expect(projected.copyWith(relayNextObservationAt: nextAt), projected);

    const flareNames = <String>[
      kRelayAbsentFlare,
      kRelayErrorFlare,
      kRelayTimeoutFlare,
      kRelayCapacityFlare,
      kRelayEscalatedFlare,
    ];
    expect(flareNames, everyElement(startsWith('relay.')));
    expect(kDefaultWorkSessionTimeToLive, const Duration(hours: 24));
    expect(kDefaultRelayObservationTimeout, const Duration(minutes: 5));
  });
}

final class _FakeRelayObserver implements RelayObserver {
  _FakeRelayObserver(this.verdict);

  final RelayVerdict verdict;

  @override
  Future<RelayVerdict> observe(RelayObservation observation) async => verdict;
}
