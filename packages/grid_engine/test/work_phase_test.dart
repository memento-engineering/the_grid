import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('WorkPhase.capId', () {
    test('maps each phase to its capability id', () {
      expect(WorkPhase.implement.capId, 'agent');
      expect(WorkPhase.verify.capId, 'verify');
      expect(WorkPhase.land.capId, 'land');
    });
  });

  group('phaseOf (the A40 JOIN)', () {
    final bead = _bead('tg-1');

    test('no session cursor ⇒ implement (a fresh agent)', () {
      expect(phaseOf(bead, null), WorkPhase.implement);
    });

    test('a session cursor ⇒ its phase', () {
      expect(
        phaseOf(bead, const SessionProjection(workBeadId: 'tg-1', phase: WorkPhase.verify)),
        WorkPhase.verify,
      );
      expect(
        phaseOf(bead, const SessionProjection(workBeadId: 'tg-1', phase: WorkPhase.land)),
        WorkPhase.land,
      );
    });
  });
}

Bead _bead(String id) => Bead(id: id);
