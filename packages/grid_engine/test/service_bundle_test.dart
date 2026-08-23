import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  test('derive preserves the base bundle and replaces only transport', () {
    final originalTransport = RecordingExplorationTransport();
    final replacementTransport = RecordingExplorationTransport();
    MountEligibilityDecision mountEligibility(Bead bead) =>
        const MountEligibilityDecision.eligible();
    final base = ServiceBundle(
      trustFloor: const TrustFloor(TrustLevel.external),
      transport: originalTransport,
      mountEligibility: mountEligibility,
    );

    final derived = ServiceBundle.derive(base, transport: replacementTransport);

    expect(derived.transport, same(replacementTransport));
    expect(derived.trustFloor, base.trustFloor);
    expect(derived.mountEligibility, same(mountEligibility));
  });
}
