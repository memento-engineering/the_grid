import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('projectSession (the read half of the contract)', () {
    test('projects work-bead linkage, the per-node cursor, identity, terminal',
        () {
      final session = Bead(
        id: 'tgdog-9a',
        issueType: IssueType.session,
        status: BeadStatus.open,
        metadata: const {
          'rig': 'tgdog',
          'work_bead': 'genesis-7r9',
          'grid.cursor.genesis-7r9/agent.state': 'complete',
          // The legacy scalar identity fence (kept for the restart reconciler).
          'pgid': '4242',
          'pid': '4243',
          'token': 'deadbeef',
        },
      );

      final p = projectSession(session);
      expect(p.workBeadId, 'genesis-7r9');
      expect(p.sessionId, 'tgdog-9a');
      expect(p.cursor['genesis-7r9/agent']!.state, StepState.complete);
      expect(p.isTerminal, isFalse);
      expect(p.pgid, 4242);
      expect(p.pid, 4243);
      expect(p.token, 'deadbeef');
    });

    test('a freshly minted session (no cursor keys) projects an empty cursor',
        () {
      final session = Bead(
        id: 'tgdog-1',
        issueType: IssueType.session,
        metadata: const {'work_bead': 'genesis-q8h'},
      );
      final p = projectSession(session);
      expect(p.cursor, isEmpty);
      expect(p.pgid, isNull);
      expect(p.token, isNull);
    });

    test('a closed session bead is terminal (the unmount signal)', () {
      final session = Bead(
        id: 'tgdog-2',
        issueType: IssueType.session,
        status: BeadStatus.closed,
        metadata: const {
          'work_bead': 'genesis-q8h',
          'grid.cursor.genesis-q8h/land.state': 'complete',
        },
      );
      final p = projectSession(session);
      expect(p.isTerminal, isTrue);
      expect(p.cursor['genesis-q8h/land']!.state, StepState.complete);
    });
  });

  group('write payloads (the write half of the contract)', () {
    test('startedIdentityMetadata stringifies the scalar pgid/pid/token fence',
        () {
      expect(
        startedIdentityMetadata(pgid: 7, pid: 8, token: 'cafe'),
        {'pgid': '7', 'pid': '8', 'token': 'cafe'},
      );
    });

    test('nodeResultMetadata namespaces the payload under grid.result.; a '
        'null/empty payload writes nothing', () {
      expect(
        nodeResultMetadata('genesis-7r9/land', {'pr_url': 'https://x/pull/3'}),
        {'grid.result.genesis-7r9/land.pr_url': 'https://x/pull/3'},
      );
      expect(nodeResultMetadata('genesis-7r9/land', null), isEmpty);
      expect(nodeResultMetadata('genesis-7r9/land', const {}), isEmpty);
    });

    test('operatorRulingMetadata (tg-i08) stamps grade + operator-ruling '
        'transport + rationale under grid.result.<lane>, round-trippable by the '
        'route\'s sibling read', () {
      final ruling = operatorRulingMetadata(
        'tg-1/review/test-coverage',
        grade: 'A',
        rationale: 'critic cd\'d; verdict was A — transport-F false gate',
      );
      expect(ruling, {
        'grid.result.tg-1/review/test-coverage.grade': 'A',
        'grid.result.tg-1/review/test-coverage.transport': 'operator-ruling',
        'grid.result.tg-1/review/test-coverage.rationale':
            'critic cd\'d; verdict was A — transport-F false gate',
      });
      expect(kOperatorRulingTransport, 'operator-ruling');
      // The route re-reads it through projectCircuitResults → resultOf().
      final session = Bead(
        id: 'tgdog-9',
        issueType: IssueType.session,
        metadata: <String, dynamic>{'work_bead': 'tg-1', ...ruling},
      );
      final results = projectCircuitResults(session);
      expect(results['tg-1/review/test-coverage']!['grade'], 'A');
      expect(
        results['tg-1/review/test-coverage']!['transport'],
        'operator-ruling',
      );
    });

    test('a grid.result.* key is DISJOINT from the cursor namespace — the '
        'projection ignores it (no misread as cursor state)', () {
      final merged = <String, dynamic>{
        'work_bead': 'genesis-7r9',
        ...nodeStateMetadata('genesis-7r9/land', StepState.complete),
        ...nodeResultMetadata('genesis-7r9/land', {'pr_url': 'https://x/pull/9'}),
      };
      final session = Bead(
        id: 'tgdog-9',
        issueType: IssueType.session,
        metadata: merged,
      );
      final p = projectSession(session);
      // The cursor reads the state; the result key is NOT projected as a node.
      expect(p.cursor['genesis-7r9/land']!.state, StepState.complete);
      expect(p.cursor.keys, ['genesis-7r9/land']);
    });

    test('round-trip: a per-node cursor write then projection reads it back', () {
      // Simulate the chokepoint merge of a node cursor write onto a minted
      // session (the disjoint-key, merge-safe write of D-1/D-3).
      final merged = <String, dynamic>{
        'rig': 'tgdog',
        'work_bead': 'genesis-7r9',
        ...nodeStateMetadata('genesis-7r9/agent', StepState.complete),
        ...nodeFailedMetadata('genesis-7r9/verify', restartCount: 2),
        ...startedIdentityMetadata(pgid: 99, pid: 100, token: 'fade'),
      };
      final session = Bead(
        id: 'tgdog-3',
        issueType: IssueType.session,
        metadata: merged,
      );
      final p = projectSession(session);
      expect(p.cursor['genesis-7r9/agent']!.state, StepState.complete);
      expect(p.cursor['genesis-7r9/verify']!.state, StepState.failed);
      expect(p.cursor['genesis-7r9/verify']!.restartCount, 2);
      expect(p.pgid, 99);
      expect(p.token, 'fade');
      expect(p.workBeadId, 'genesis-7r9');
    });
  });
}
