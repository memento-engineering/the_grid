import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

TrajectoryEnvelope _envelope(TrajectoryRecord record) {
  final instant = DateTime.utc(2026);
  return TrajectoryEnvelope.fromJson({
    'record_id': '01JMOLECULEEDGEMIRROR00001',
    'idem_key': 'edge'.padRight(64, 'e'),
    'idem_key_text': 'edge-mirror',
    'family': record.family.wire,
    'record_type': record.recordType,
    'type_version': record.typeVersion,
    'occurred_at': instant.toIso8601String(),
    'recorded_at': instant.toIso8601String(),
    'station': 'station-1',
    'authority_id': 'station-1/1',
    'boot_epoch': 1,
    'provenance': TrajectoryProvenance.observed.wire,
    'source': 'test',
    'payload': record.payloadToJson(),
    ...record.correlationToJson(),
  });
}

void main() {
  test('edge mirror seeds, publishes, evicts, and latches health', () {
    final mirror = MoleculeEdgeMirror();
    var notifications = 0;
    mirror.addListener((_) => notifications += 1, fireImmediately: false);
    mirror.seed(
      rows: const [
        MoleculeEdgeRow(
          sessionId: 'session-1',
          round: 0,
          fromPath: 'work/verify',
          toPath: 'work/build',
          kind: 'blocks',
        ),
      ],
      seededAt: DateTime.utc(2026),
      stale: false,
    );
    expect(mirror.snapshot.health, TrajectorySnapshotHealth.live);
    expect(mirror.snapshot.bySessionId('session-1'), hasLength(1));
    expect(notifications, 1);

    expect(mirror.latchCompromised(), isTrue);
    expect(mirror.snapshot.health, TrajectorySnapshotHealth.compromised);
    expect(mirror.evictClosedSessions({'session-1'}), 1);
    expect(mirror.snapshot.bySessionId('session-1'), isEmpty);
  });

  test('post-ACK pour applies and a reseed replaces the edge set', () {
    final mirror = MoleculeEdgeMirror()
      ..seed(rows: const [], seededAt: DateTime.utc(2026), stale: false);
    const poured = MoleculePoured(
      sessionId: 'session-1',
      round: 0,
      formula: 'code',
      graph: {
        'nodes': <Object?>[],
        'edges': [
          {
            'from_path': 'work/verify',
            'to_path': 'work/build',
            'kind': 'validates',
          },
        ],
      },
      nodeCount: 0,
      graphDigest:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    mirror.applyAppended(_envelope(poured), seq: 1, decoded: poured);
    expect(mirror.snapshot.bySessionId('session-1'), hasLength(1));

    mirror.reseed(rows: const [], seededAt: DateTime.utc(2026, 1, 2));
    expect(mirror.snapshot.bySessionId('session-1'), isEmpty);
    expect(mirror.snapshot.health, TrajectorySnapshotHealth.live);
  });

  test('persisted edge kinds outside blocks and validates fail loudly', () {
    expect(
      () => MoleculeEdgeRow.fromSqlRow(const {
        'session_id': 'session-1',
        'round': 0,
        'from_path': 'work/a',
        'to_path': 'work/b',
        'kind': 'supersedes',
      }),
      throwsStateError,
    );
  });
}
