// tg-b3k — the pure rework-round contract + the machine-actionable-gate
// predicate: the ONE definition of the `<bead>#r<N>` key shape, the round cap,
// and the `respec:` asset↔engine token both actuators read.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

SessionProjection _session({
  required Map<String, NodeCursor> cursor,
  required Map<String, OpenGate> openGates,
  int reworkRounds = 0,
}) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-s',
  cursor: cursor,
  openGates: openGates,
  reworkRounds: reworkRounds,
);

void main() {
  group('the round key shape (tg-b3k)', () {
    test('reworkKeyFor authors `<bead>#r<N>`', () {
      expect(reworkKeyFor('tg-1', 2), 'tg-1#r2');
    });

    test(
      'reworkRoundOf is ANCHORED — a bead id that merely PREFIXES another is '
      'never mistaken for one of its rounds',
      () {
        expect(reworkRoundOf('tg-x1j', 'tg-x1j#r3'), 3);
        expect(reworkRoundOf('tg-x1j', 'tg-x1j2#r1'), isNull);
        expect(reworkRoundOf('tg-x1j', 'tg-x1j'), isNull);
        expect(reworkRoundOf('tg-x1j', 'tg-x1j#rX'), isNull);
      },
    );

    test('maxReworkRound takes the highest round, 0 when none is retired', () {
      expect(
        maxReworkRound('tg-1', ['tg-1', 'tg-1#r1', 'tg-1#r3', 'tg-2#r9']),
        3,
      );
      expect(maxReworkRound('tg-1', ['tg-1']), 0);
      expect(maxReworkRound('tg-1', const []), 0);
    });

    test('the cap is 3 (M5 D-4) and both actuators compare it the same way', () {
      expect(kMaxReworkRounds, 3);
    });
  });

  group('the machine-actionable gate predicate (tg-b3k)', () {
    test('isRespecGate matches ONLY the `respec:` prefix (fail-closed)', () {
      expect(isRespecGate('respec: round=1 lane=architecture grade=D'), isTrue);
      expect(isRespecGate('  respec: round=2'), isTrue);
      expect(isRespecGate('needs human sign-off'), isFalse);
      expect(isRespecGate('RESPEC: shouting is not the contract'), isFalse);
      expect(isRespecGate('the spec needs a respec: eventually'), isFalse);
      expect(isRespecGate(''), isFalse);
    });

    test('a `respec:` gate over a GATED node is machine-actionable', () {
      final gate = machineActionableGate(
        _session(
          cursor: const {'tg-1/route': NodeCursor(state: StepState.gated)},
          openGates: const {
            'tg-1/route': OpenGate(
              gateId: 'tgdog-g1',
              nodePath: 'tg-1/route',
              reason: 'respec: round=1',
            ),
          },
        ),
      );
      expect(gate?.gateId, 'tgdog-g1');
    });

    test(
      'a HUMAN gate over a gated node is NOT machine-actionable (the '
      'non-regression fence)',
      () {
        expect(
          machineActionableGate(
            _session(
              cursor: const {'tg-1/route': NodeCursor(state: StepState.gated)},
              openGates: const {
                'tg-1/route': OpenGate(
                  gateId: 'tgdog-g1',
                  nodePath: 'tg-1/route',
                  reason: 'needs human sign-off',
                ),
              },
            ),
          ),
          isNull,
        );
      },
    );

    test('a `respec:` gate over a node that is NOT parked is ignored', () {
      expect(
        machineActionableGate(
          _session(
            cursor: const {'tg-1/route': NodeCursor(state: StepState.running)},
            openGates: const {
              'tg-1/route': OpenGate(
                gateId: 'tgdog-g1',
                nodePath: 'tg-1/route',
                reason: 'respec: round=1',
              ),
            },
          ),
        ),
        isNull,
      );
    });

    test('openGateNodes is DERIVED from openGates (one source of truth)', () {
      final s = _session(
        cursor: const {},
        openGates: const {
          'tg-1/route': OpenGate(gateId: 'tgdog-g1', nodePath: 'tg-1/route'),
        },
      );
      expect(s.openGateNodes, {'tg-1/route'});
    });
  });
}
