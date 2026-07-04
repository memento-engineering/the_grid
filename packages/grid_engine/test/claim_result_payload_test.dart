// The durable claim-recording contract (D-B5 hook #4, the honesty-pass,
// 2026-07-03): leaseGrantToResultPayload / leaseGrantFromResultPayload bridge
// a granted LeaseGrant into the generic step-result payload the EXISTING
// StationBeadWriter chokepoint already persists (ResultKeys, ADR-0006 D3) —
// NO new write path. Pure value-types only.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('leaseGrantToResultPayload / leaseGrantFromResultPayload', () {
    test('round-trips the load-bearing claim fields (leaseId/station/'
        'fencingToken/kind)', () {
      const grant = LeaseGrant(
        leaseId: 'lease-42',
        station: 'linux-dashboard.local',
        ttlSeconds: 60,
        fencingToken: 7,
        heartbeatSeconds: 10,
        kind: 'burn-follower',
      );
      final payload = leaseGrantToResultPayload(grant);
      // Every value is a plain string (the ResultKeys/StationBeadWriter
      // contract — Map<String, String>).
      expect(payload, {
        'leaseId': 'lease-42',
        'claimedBy': 'linux-dashboard.local',
        'fencingToken': '7',
        'kind': 'burn-follower',
      });

      final back = leaseGrantFromResultPayload(payload);
      expect(back, isNotNull);
      expect(back!.leaseId, grant.leaseId);
      expect(back.station, grant.station);
      expect(back.fencingToken, grant.fencingToken);
      expect(back.kind, grant.kind);
      // The renewal cadence is deliberately NOT part of the durable record —
      // a consumer re-leases for it, never reads it from history.
      expect(back.ttlSeconds, 0);
      expect(back.heartbeatSeconds, 0);
    });

    test('a payload missing ANY load-bearing field reads back null (never a '
        'half-populated grant)', () {
      expect(leaseGrantFromResultPayload(const {}), isNull);
      expect(
        leaseGrantFromResultPayload(const {'leaseId': 'x', 'claimedBy': 'y'}),
        isNull,
        reason: 'fencingToken missing',
      );
    });

    test('an unrecorded kind defaults to kDefaultKind on read-back (mirrors '
        'LeaseGrant.fromJson\'s own default)', () {
      final back = leaseGrantFromResultPayload(const {
        'leaseId': 'lease-1',
        'claimedBy': 'peer.local',
        'fencingToken': '1',
      });
      expect(back!.kind, kDefaultKind);
    });

    test('rides the SAME disjoint result namespace every other step result '
        'does — merges without collision alongside nodeResultMetadata', () {
      const grant = LeaseGrant(
        leaseId: 'lease-9',
        station: 'peer.local',
        ttlSeconds: 30,
        fencingToken: 2,
      );
      final merged = nodeResultMetadata(
        'tg-burn/follower',
        leaseGrantToResultPayload(grant),
      );
      expect(merged, {
        'grid.result.tg-burn/follower.leaseId': 'lease-9',
        'grid.result.tg-burn/follower.claimedBy': 'peer.local',
        'grid.result.tg-burn/follower.fencingToken': '2',
        'grid.result.tg-burn/follower.kind': kDefaultKind,
      });
    });
  });
}
