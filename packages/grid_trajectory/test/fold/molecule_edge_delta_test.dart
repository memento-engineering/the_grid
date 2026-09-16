import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

void main() {
  TrajectoryEnvelope poured({int seq = 1, Object? edges = const <Object?>[]}) =>
      envelope(
        recordType: 'molecule.poured',
        family: TrajectoryFamily.step,
        seq: seq,
        sessionId: 'session-1',
        round: 3,
        payload: {
          'formula': 'code',
          'graph': {'edges': edges, 'nodes': <Object?>[]},
          'node_count': 0,
          'graph_digest': 'a' * 64,
        },
      );

  test('one pour yields rows only for complete blocks and validates edges', () {
    final delta = moleculeEdgeDeltaFor(
      poured(
        edges: const [
          {'from_path': 'work/b', 'to_path': 'work/a', 'kind': 'blocks'},
          {'from_path': 'work/c', 'to_path': 'work/b', 'kind': 'validates'},
          {'from_path': 'work/d', 'to_path': 'work/c', 'kind': 'parent-child'},
          {'from_path': 'work/e', 'kind': 'blocks'},
          {'from_path': 1, 'to_path': 'work/a', 'kind': 'blocks'},
          'not-an-edge',
        ],
      ),
    )!;

    expect(delta.rows, [
      const MoleculeEdgeRow(
        sessionId: 'session-1',
        round: 3,
        fromPath: 'work/b',
        toPath: 'work/a',
        kind: 'blocks',
      ),
      const MoleculeEdgeRow(
        sessionId: 'session-1',
        round: 3,
        fromPath: 'work/c',
        toPath: 'work/b',
        kind: 'validates',
      ),
    ]);
  });

  test('malformed graph edges produce an empty delta', () {
    expect(moleculeEdgeDeltaFor(poured(edges: 'bad'))!.rows, isEmpty);
    expect(
      moleculeEdgeDeltaFor(
        envelope(
          recordType: 'step.transition',
          family: TrajectoryFamily.step,
          sessionId: 'session-1',
          round: 3,
          stepPath: 'work/a',
          stepRound: 0,
          incarnation: 0,
          payload: const {'state': 'running'},
        ),
      ),
      isNull,
    );
  });

  test('incremental SQL and replay apply the identical row set', () {
    final delta = moleculeEdgeDeltaFor(
      poured(
        edges: const [
          {'from_path': 'work/b', 'to_path': 'work/a', 'kind': 'blocks'},
          {'from_path': 'work/c', 'to_path': 'work/a', 'kind': 'validates'},
        ],
      ),
    )!;
    final sqlRows = {
      for (final statement in moleculeEdgeSqlFor(delta))
        MoleculeEdgeRow(
          sessionId: statement.params['session_id']! as String,
          round: statement.params['round']! as int,
          fromPath: statement.params['from_path']! as String,
          toPath: statement.params['to_path']! as String,
          kind: statement.params['kind']! as String,
        ).key,
    };
    final replayRows = <MoleculeEdgeKey, MoleculeEdgeRow>{};
    applyMoleculeEdgeDelta(replayRows, delta);

    expect(sqlRows, replayRows.keys.toSet());
    for (final statement in moleculeEdgeSqlFor(delta)) {
      expect(statement.sql, startsWith('INSERT INTO proj_step_edges'));
      expect(statement.sql, endsWith('ON DUPLICATE KEY UPDATE kind = :kind'));
    }
  });

  test('repeated pours preserve row count and content', () {
    final delta = moleculeEdgeDeltaFor(
      poured(
        edges: const [
          {'from_path': 'work/b', 'to_path': 'work/a', 'kind': 'blocks'},
        ],
      ),
    )!;
    final rows = <MoleculeEdgeKey, MoleculeEdgeRow>{};
    applyMoleculeEdgeDelta(rows, delta);
    final once = Map<MoleculeEdgeKey, MoleculeEdgeRow>.of(rows);
    applyMoleculeEdgeDelta(rows, delta);
    expect(rows, once);
    expect(rows, hasLength(1));
  });
}
