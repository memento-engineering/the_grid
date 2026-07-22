// The composition site must ARM the cross-link LOUD channel. Unwired, a
// cross-repo block still applies but an unresolvable one is enforced in
// SILENCE: work vanishes from the frontier with nothing in the log saying why.
//
// `buildStationWork` cannot be driven to a successful build offline (it
// constructs Dolt-backed controllers), so the WIRE is gated at the source — the
// same structural technique `completion_fence_wiring_test.dart` uses.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('buildStationWork passes the unresolved sink into StationJoinBridge', () {
    final src = File('lib/src/work/work_assembly.dart').readAsStringSync();

    expect(
      src.contains('onUnresolvedCrossLink: unresolvedSink'),
      isTrue,
      reason:
          'buildStationWork must hand StationJoinBridge the same LOUD sink the '
          'FederatedSnapshotSource union gets, so a malformed link bead or an '
          'unobserved `to` target is reported rather than silently blocking.',
    );
    expect(
      src.contains('onUnresolvedExternalDep: unresolvedSink'),
      isTrue,
      reason: 'both cross-store edge sources report through the ONE sink',
    );
  });
}
