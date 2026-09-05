import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

WedgeSample _sample(SessionPauseState pauseState) => sampleWedge(
  JoinedSnapshot(
    graph: GraphSnapshot.fromParts(
      beads: [
        Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open),
      ],
      dependencies: const [],
      readyIds: const {'tg-1'},
      capturedAt: DateTime.utc(2026, 7, 19, 10),
    ),
    sessionsByWorkBead: {
      'tg-1': SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-s1',
        pauseState: pauseState,
      ),
    },
  ),
  now: DateTime.utc(2026, 7, 19, 10),
);

void main() {
  test('a paused session is not counted live', () {
    final live = _sample(SessionPauseState.none);
    expect(live.live, 1);
    expect(live.isStalled, isTrue);

    final paused = _sample(SessionPauseState.paused);
    expect(paused.live, 0);
    expect(paused.isStalled, isFalse);

    expect(_sample(SessionPauseState.resumed).live, 1);
  });
}
