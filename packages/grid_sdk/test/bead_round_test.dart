import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  Bead work({Map<String, dynamic> metadata = const {}}) => Bead(
    id: 'tg-1',
    title: 'ship it',
    status: BeadStatus.inProgress,
    metadata: metadata,
  );

  Bead session(String id, String key) => Bead(
    id: id,
    issueType: GridIssueTypes.session,
    metadata: {SessionBeadKeys.workBead: key},
  );

  test('finds one live session and derives round from retired keys', () {
    final result = projectRoundContext(
      workBead: work(
        metadata: const {WorkBeadKeys.validationPlan: 'dart test'},
      ),
      stateBeads: [
        session('session-live', 'tg-1'),
        session('session-r1', 'tg-1#r1'),
        session('session-r2', 'tg-1#r2'),
      ],
    );

    expect(result, isA<BeadRoundFound>());
    final found = result as BeadRoundFound;
    expect(found.sessionId, 'session-live');
    expect(found.round, 3);
    expect(found.validationPlan, 'dart test');
  });

  test('no live session is a typed no-round outcome naming the bead', () {
    final result =
        projectRoundContext(
              workBead: work(),
              stateBeads: [session('session-r1', 'tg-1#r1')],
            )
            as BeadRoundAbsent;

    expect(result.beadId, 'tg-1');
    expect(result.reason, contains('tg-1'));
    expect(result.validationPlan, isNull);
  });

  test('multiple live sessions are a typed no-round outcome', () {
    final result =
        projectRoundContext(
              workBead: work(),
              stateBeads: [
                session('session-a', 'tg-1'),
                session('session-b', 'tg-1'),
              ],
            )
            as BeadRoundAbsent;

    expect(result.reason, contains('2 sessions'));
  });

  test('void keys never spend a round ordinal', () {
    final result =
        projectRoundContext(
              workBead: work(),
              stateBeads: [
                session('session-live', 'tg-1'),
                session('session-void', 'tg-1#void-session-old'),
              ],
            )
            as BeadRoundFound;

    expect(result.round, 1);
  });

  test('blank validation plan decodes as absent', () {
    final result =
        projectRoundContext(
              workBead: work(
                metadata: const {WorkBeadKeys.validationPlan: '   '},
              ),
              stateBeads: [session('session-live', 'tg-1')],
            )
            as BeadRoundFound;

    expect(result.validationPlan, isNull);
  });
}
