/// The DERIVED transport is fold-only — a writer that reaches for it is refused
/// LOUDLY at construction, like `envelope` before it.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

VerifyVerdictRecorded build(VerdictTransport transport) =>
    VerifyVerdictRecorded(
      sessionId: 's1',
      round: 1,
      stepPath: 'review/coherence',
      stepRound: 1,
      incarnation: 1,
      headShaAtRecord: 'a' * 40,
      lane: 'coherence',
      rubricVersion: 'v1',
      grade: 'A',
      rationale: 'because',
      transport: transport,
      pinnedHeadSha: 'a' * 40,
      shaDrift: false,
    );

void main() {
  test('an artifact verdict builds', () {
    expect(
      build(VerdictTransport.artifact).transport,
      VerdictTransport.artifact,
    );
  });

  test('a DERIVED step.transition verdict is refused on the wire', () {
    expect(() => build(VerdictTransport.stepTransition), throwsArgumentError);
  });

  test('the recovered transport stays refused too', () {
    expect(() => build(VerdictTransport.envelope), throwsArgumentError);
  });
}
