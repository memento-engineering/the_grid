import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

SessionProjection _open({
  SessionPauseState pauseState = SessionPauseState.none,
}) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-s1',
  pauseState: pauseState,
);

void main() {
  group('sessionDispositionOf on the pause axis', () {
    test('an open paused session blocks the mount', () {
      final disposition = sessionDispositionOf(
        _open(pauseState: SessionPauseState.paused),
      );
      expect(disposition, isA<PausedSession>());
      expect(disposition.blocksMount, isTrue);
      expect((disposition as PausedSession).reason, contains('grid resume'));
    });

    test('an open resumed session is live again', () {
      final disposition = sessionDispositionOf(
        _open(pauseState: SessionPauseState.resumed),
      );
      expect(disposition, isA<LiveSession>());
      expect(disposition.blocksMount, isFalse);
    });

    test('a never-paused open session remains live', () {
      expect(sessionDispositionOf(_open()), isA<LiveSession>());
    });

    test('a terminal session ignores a stale paused marker', () {
      const done = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-s1',
        isTerminal: true,
        completed: true,
        pauseState: SessionPauseState.paused,
      );
      expect(sessionDispositionOf(done), isA<DoneSession>());
      const held = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-s1',
        isTerminal: true,
        humanHeld: true,
        pauseState: SessionPauseState.paused,
      );
      expect(sessionDispositionOf(held), isA<HeldSession>());
    });
  });

  group('projectSession reads the pause axis', () {
    Bead session(Map<String, String> extra) => Bead(
      id: 'tgdog-s1',
      issueType: GridIssueTypes.session,
      metadata: {'work_bead': 'tg-1', ...extra},
    );

    test('known values round-trip and unknown values default to none', () {
      expect(
        projectSession(session(const {})).pauseState,
        SessionPauseState.none,
      );
      expect(
        projectSession(
          session(const {'grid.session.pause_state': 'paused'}),
        ).pauseState,
        SessionPauseState.paused,
      );
      expect(
        projectSession(
          session(const {'grid.session.pause_state': 'resumed'}),
        ).pauseState,
        SessionPauseState.resumed,
      );
      expect(
        projectSession(
          session(const {'grid.session.pause_state': 'unknown'}),
        ).pauseState,
        SessionPauseState.none,
      );
    });
  });

  group('the preserved cursor resumes near its prior frontier', () {
    const circuit = Circuit(
      id: 'code',
      terminalStepId: 'land',
      steps: [
        CapabilityStep(stepId: 'specify', capabilityId: 'agent'),
        CapabilityStep(
          stepId: 'build',
          capabilityId: 'agent',
          dependsOn: {'specify'},
        ),
        CapabilityStep(
          stepId: 'land',
          capabilityId: 'land',
          dependsOn: {'build'},
        ),
      ],
    );

    test('a build-stage pause resumes at build without rerunning specify', () {
      const preserved = <String, NodeCursor>{
        'specify': NodeCursor(state: StepState.complete),
        'build': NodeCursor(state: StepState.running),
      };
      final frontier = eligibleSteps(
        circuit,
        preserved,
        '',
        circuitById: (_) => null,
        now: DateTime(2026),
      ).map((step) => step.stepId).toList();
      expect(frontier, ['build']);
      expect(frontier, isNot(contains('specify')));
    });

    test('an empty cursor starts at specify', () {
      final frontier = eligibleSteps(
        circuit,
        const {},
        '',
        circuitById: (_) => null,
        now: DateTime(2026),
      ).map((step) => step.stepId).toList();
      expect(frontier, ['specify']);
    });
  });
}
