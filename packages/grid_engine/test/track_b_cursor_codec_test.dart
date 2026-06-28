// Track B — the per-node reentrant cursor codec (D-3): the shared contract.
//
// FLAT, merge-safe `grid.cursor.{nodePath}.{field}` keys on the_grid's OWN
// session bead round-trip a FormulaCursor; disjoint nodes never collide; the
// codec boundary (rig/work_bead) is untouched, and a stray legacy `grid.phase`
// key is simply ignored.
//
// ADR-0008 D4 / M4-P1 Track B. Zero I/O — pure codec.
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

Bead _sessionBead(Map<String, dynamic> metadata, {bool closed = false}) => Bead(
  id: 'tgdog-sess1',
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: metadata,
);

void main() {
  group('Track B — nodeCursorMetadata (the flat write)', () {
    test('writes state + restartCount always; omits null optionals', () {
      final meta = nodeCursorMetadata(
        'tg-1/agent',
        const NodeCursor(state: StepState.running),
      );
      expect(meta, {
        'grid.cursor.tg-1/agent.state': 'running',
        'grid.cursor.tg-1/agent.restartCount': '0',
      });
    });

    test('writes every set field with the right key + ISO date', () {
      final meta = nodeCursorMetadata(
        'b/harnessPeripheral/launch',
        NodeCursor(
          state: StepState.ready,
          pgid: 4242,
          pid: 4243,
          token: 'tok-x',
          restartCount: 2,
          cooldownUntil: DateTime.utc(2026, 6, 27, 12),
          logOffset: 99,
        ),
      );
      expect(meta['grid.cursor.b/harnessPeripheral/launch.state'], 'ready');
      expect(meta['grid.cursor.b/harnessPeripheral/launch.pgid'], '4242');
      expect(meta['grid.cursor.b/harnessPeripheral/launch.pid'], '4243');
      expect(meta['grid.cursor.b/harnessPeripheral/launch.token'], 'tok-x');
      expect(meta['grid.cursor.b/harnessPeripheral/launch.restartCount'], '2');
      expect(
        meta['grid.cursor.b/harnessPeripheral/launch.cooldownUntil'],
        '2026-06-27T12:00:00.000Z',
      );
      expect(meta['grid.cursor.b/harnessPeripheral/launch.logOffset'], '99');
    });
  });

  group('Track B — projectFormulaCursor (the read)', () {
    test('round-trips a multi-node cursor through metadata', () {
      final cursor = <String, NodeCursor>{
        'b/build': const NodeCursor(state: StepState.complete),
        'b/launch': NodeCursor(
          state: StepState.ready,
          pgid: 7,
          pid: 8,
          token: 't',
          restartCount: 1,
          cooldownUntil: DateTime.utc(2026),
          logOffset: 5,
        ),
      };
      final metadata = <String, dynamic>{
        for (final e in cursor.entries) ...nodeCursorMetadata(e.key, e.value),
      };
      expect(projectFormulaCursor(_sessionBead(metadata)), cursor);
    });

    test('disjoint nodes merge without collision (D-1/D-3 safety)', () {
      // Two leaf hosts writing DIFFERENT nodes — their flat keys never overlap,
      // so a metadata merge keeps both (the disjoint-key half of invariant 2).
      final a = nodeCursorMetadata('n/x', const NodeCursor(state: StepState.complete));
      final b = nodeCursorMetadata('n/y', const NodeCursor(state: StepState.running));
      final merged = <String, dynamic>{...a, ...b};
      final cursor = projectFormulaCursor(_sessionBead(merged));
      expect(cursor['n/x']!.state, StepState.complete);
      expect(cursor['n/y']!.state, StepState.running);
    });

    test('every StepState name round-trips; unknown → pending', () {
      for (final s in StepState.values) {
        final meta = nodeCursorMetadata('p', NodeCursor(state: s));
        expect(projectFormulaCursor(_sessionBead(meta))['p']!.state, s);
      }
      final bogus = projectFormulaCursor(
        _sessionBead(const {'grid.cursor.p.state': 'nonsense'}),
      );
      expect(bogus['p']!.state, StepState.pending);
    });

    test('numeric metadata read back as num (not String) still parses', () {
      // bd export can surface numbers as JSON numbers; the codec coerces.
      final cursor = projectFormulaCursor(
        _sessionBead(const {
          'grid.cursor.p.state': 'running',
          'grid.cursor.p.pgid': 4242, // a num, not a string
          'grid.cursor.p.restartCount': 3,
        }),
      );
      expect(cursor['p']!.pgid, 4242);
      expect(cursor['p']!.restartCount, 3);
    });

    test('a malformed cursor key (no field segment) is skipped, not thrown', () {
      final cursor = projectFormulaCursor(
        _sessionBead(const {
          'grid.cursor.': 'x', // no path, no field
          'grid.cursor.justpath': 'y', // no field separator
          'grid.cursor.p.state': 'complete',
        }),
      );
      expect(cursor.keys, ['p']);
    });
  });

  group('Track B — codec boundary untouched (A37 / the law)', () {
    test('projectFormulaCursor ignores rig/work_bead/grid.phase keys', () {
      final cursor = projectFormulaCursor(
        _sessionBead(const {
          'rig': 'tgdog',
          'work_bead': 'tg-1',
          'grid.phase': 'verify',
          'pgid': '999',
          'grid.cursor.tg-1/agent.state': 'complete',
        }),
      );
      expect(cursor.keys, ['tg-1/agent']);
      expect(cursor['tg-1/agent']!.state, StepState.complete);
    });

    test('projectSession reads the per-node cursor; a legacy grid.phase is '
        'ignored', () {
      final session = projectSession(
        _sessionBead(const {
          'work_bead': 'tg-1',
          'rig': 'tgdog',
          'grid.phase': 'verify', // a legacy key — now IGNORED by the projection
          'grid.cursor.tg-1/agent.state': 'complete', // the per-node cursor
        }),
      );
      expect(session.workBeadId, 'tg-1');
      expect(session.cursor['tg-1/agent']!.state, StepState.complete);
      expect(session.isTerminal, isFalse);
    });

    test('a closed session bead is terminal (status-driven, unchanged)', () {
      final session = projectSession(
        _sessionBead(const {'work_bead': 'tg-1', 'rig': 'tgdog'}, closed: true),
      );
      expect(session.isTerminal, isTrue);
      expect(session.cursor, isEmpty);
    });
  });
}
