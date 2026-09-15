import 'dart:convert';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';
import '../support/scripted_reader.dart';

void main() {
  TrajectoryEnvelope poured({int seq = 1}) => envelope(
    recordType: 'molecule.poured',
    family: TrajectoryFamily.step,
    seq: seq,
    sessionId: 'session-1',
    round: 2,
    payload: {
      'formula': 'code',
      'graph': {
        'edges': const [
          {'from_path': 'work/b', 'to_path': 'work/a', 'kind': 'blocks'},
        ],
        'nodes': const ['work/a', 'work/b'],
      },
      'node_count': 2,
      'graph_digest': 'a' * 64,
    },
  );

  TrajectoryEnvelope transition({int seq = 2}) => envelope(
    recordType: 'step.transition',
    family: TrajectoryFamily.step,
    seq: seq,
    sessionId: 'session-1',
    round: 2,
    stepPath: 'work/a',
    stepRound: 0,
    incarnation: 0,
    payload: const {'state': 'running'},
  );

  List<Map<String, String?>> asRows(Iterable<TrajectoryEnvelope> records) => [
    for (final record in records)
      {
        for (final entry in record.toJson().entries)
          entry.key: entry.key == 'payload'
              ? jsonEncode(entry.value)
              : entry.value?.toString(),
      },
  ];

  test('declares version one and consumes only molecule.poured v1', () {
    expect(moleculeEdgeFoldVersion, 1);
    expect(moleculeEdgeProjection, 'step_edges');
    expect(moleculeEdgeFoldConsumes, {'molecule.poured': (1, 1)});
  });

  test('folds pours, counts every other step pair, and scans all families', () {
    final result = foldMoleculeEdges([
      transition(seq: 3),
      poured(seq: 2),
      envelope(
        recordType: 'molecule.poured',
        family: TrajectoryFamily.step,
        typeVersion: 2,
        seq: 4,
        sessionId: 'session-1',
        round: 2,
      ),
      envelope(
        recordType: 'attempt.note',
        family: TrajectoryFamily.attempt,
        seq: 9,
        sessionId: 'session-1',
        payload: const {'body': 'x', 'channel': 'ops', 'note_ordinal': 1},
      ),
    ]);
    expect(result.rows.values, [
      const MoleculeEdgeRow(
        sessionId: 'session-1',
        round: 2,
        fromPath: 'work/b',
        toPath: 'work/a',
        kind: 'blocks',
      ),
    ]);
    expect(result.skipped, {'step.transition@v1': 1, 'molecule.poured@v2': 1});
    expect(result.appliedSeq, 9);
  });

  test(
    'replay rewrites rows and its own proj_meta in one transaction',
    () async {
      final db = ScriptedDb();
      db.on(
        'SELECT * FROM trajectory',
        respond: (_) => SqlResult(rows: asRows([poured(), transition()])),
      );
      final result = await replayMoleculeEdges(
        db,
        clock: () => DateTime.utc(2026, 9, 14, 12),
      );

      expect(result.rows, hasLength(1));
      expect(db.matching('DELETE FROM proj_step_edges'), hasLength(1));
      expect(db.matching('INSERT INTO proj_step_edges'), hasLength(1));
      final meta = db.matching('INSERT INTO proj_meta').single;
      expect(meta.params!['projection'], moleculeEdgeProjection);
      expect(meta.params!['fold_version'], moleculeEdgeFoldVersion);
      expect(meta.params!['applied_seq'], 2);
      expect(meta.params!['skipped'], '{"step.transition@v1":1}');
      final sql = db.log.map((call) => call.sql).toList(growable: false);
      final begin = sql.indexOf('START TRANSACTION');
      final commit = sql.indexOf('COMMIT');
      expect(begin, isNonNegative);
      expect(commit, greaterThan(begin));
      expect(
        sql.indexOf('DELETE FROM proj_step_edges'),
        inInclusiveRange(begin, commit),
      );
    },
  );

  test('a replay write failure rolls back and rethrows', () async {
    final db = ScriptedDb();
    db
      ..on(
        'SELECT * FROM trajectory',
        respond: (_) => SqlResult(rows: asRows([poured()])),
      )
      ..on('INSERT INTO proj_step_edges', throwing: StateError('boom'));
    await expectLater(replayMoleculeEdges(db), throwsStateError);
    expect(db.matching('ROLLBACK'), hasLength(1));
    expect(db.matching('COMMIT'), isEmpty);
  });
}
