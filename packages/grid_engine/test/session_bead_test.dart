import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('projectSession (the read half of the contract)', () {
    test('projects work-bead linkage, cursor, identity, and terminal', () {
      final session = Bead(
        id: 'tgdog-9a',
        issueType: IssueType.session,
        status: BeadStatus.open,
        metadata: const {
          'rig': 'tgdog',
          'work_bead': 'genesis-7r9',
          'grid.phase': 'verify',
          'pgid': '4242',
          'pid': '4243',
          'token': 'deadbeef',
        },
      );

      final p = projectSession(session);
      expect(p.workBeadId, 'genesis-7r9');
      expect(p.sessionId, 'tgdog-9a');
      expect(p.phase, WorkPhase.verify);
      expect(p.isTerminal, isFalse);
      expect(p.pgid, 4242);
      expect(p.pid, 4243);
      expect(p.token, 'deadbeef');
    });

    test('a freshly minted session (no cursor) projects implement', () {
      final session = Bead(
        id: 'tgdog-1',
        issueType: IssueType.session,
        metadata: const {'work_bead': 'genesis-q8h'},
      );
      final p = projectSession(session);
      expect(p.phase, WorkPhase.implement);
      expect(p.pgid, isNull);
      expect(p.token, isNull);
    });

    test('a closed session bead is terminal (the unmount signal)', () {
      final session = Bead(
        id: 'tgdog-2',
        issueType: IssueType.session,
        status: BeadStatus.closed,
        metadata: const {'work_bead': 'genesis-q8h', 'grid.phase': 'land'},
      );
      final p = projectSession(session);
      expect(p.isTerminal, isTrue);
      expect(p.phase, WorkPhase.land);
    });
  });

  group('write payloads (the write half of the contract)', () {
    test('phaseCursorMetadata uses the WorkPhase name', () {
      expect(phaseCursorMetadata(WorkPhase.implement), {'grid.phase': 'implement'});
      expect(phaseCursorMetadata(WorkPhase.verify), {'grid.phase': 'verify'});
      expect(phaseCursorMetadata(WorkPhase.land), {'grid.phase': 'land'});
    });

    test('startedIdentityMetadata stringifies pgid/pid/token', () {
      expect(
        startedIdentityMetadata(pgid: 7, pid: 8, token: 'cafe'),
        {'pgid': '7', 'pid': '8', 'token': 'cafe'},
      );
    });

    test('round-trip: a cursor write then projection reads it back', () {
      // Simulate the chokepoint merge of a cursor write onto a minted session.
      final merged = <String, dynamic>{
        'rig': 'tgdog',
        'work_bead': 'genesis-7r9',
        ...phaseCursorMetadata(WorkPhase.land),
        ...startedIdentityMetadata(pgid: 99, pid: 100, token: 'fade'),
      };
      final session = Bead(
        id: 'tgdog-3',
        issueType: IssueType.session,
        metadata: merged,
      );
      final p = projectSession(session);
      expect(p.phase, WorkPhase.land);
      expect(p.pgid, 99);
      expect(p.token, 'fade');
      expect(p.workBeadId, 'genesis-7r9');
    });
  });
}
