import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Pure-logic tests for the session `state` transition table (Track 4) — the
/// Dart port of gc's `state_machine.go:106-144`. Tested before any bd write is
/// wired (predictable-flutter: pure logic before IO).
void main() {
  group('transition table — the legal spine', () {
    test('create: none → start_pending (and ONLY from none)', () {
      expect(
        transition(LifecycleState.none, LifecycleCommand.create),
        LifecycleState.startPending,
      );
      // create is illegal from any real state.
      expect(
        transitionOrNull(LifecycleState.active, LifecycleCommand.create),
        isNull,
      );
    });

    test('spawn: start_pending → spawning', () {
      expect(
        transition(LifecycleState.startPending, LifecycleCommand.spawn),
        LifecycleState.spawning,
      );
    });

    test('activate: spawning → active, and asleep → active (re-activate)', () {
      expect(
        transition(LifecycleState.spawning, LifecycleCommand.activate),
        LifecycleState.active,
      );
      expect(
        transition(LifecycleState.asleep, LifecycleCommand.activate),
        LifecycleState.active,
      );
      // active → active is idempotent-legal (activity on an already-active).
      expect(
        transition(LifecycleState.active, LifecycleCommand.activate),
        LifecycleState.active,
      );
    });

    test('sleep: active → asleep (clean exit / idle)', () {
      expect(
        transition(LifecycleState.active, LifecycleCommand.sleep),
        LifecycleState.asleep,
      );
    });

    test('drain: active → draining', () {
      expect(
        transition(LifecycleState.active, LifecycleCommand.drain),
        LifecycleState.draining,
      );
    });

    test('quarantine: active/asleep → quarantined', () {
      expect(
        transition(LifecycleState.active, LifecycleCommand.quarantine),
        LifecycleState.quarantined,
      );
      expect(
        transition(LifecycleState.asleep, LifecycleCommand.quarantine),
        LifecycleState.quarantined,
      );
    });

    test(
      'restart: asleep/quarantined/draining → spawning (fresh incarnation)',
      () {
        for (final from in [
          LifecycleState.asleep,
          LifecycleState.quarantined,
          LifecycleState.draining,
        ]) {
          expect(
            transition(from, LifecycleCommand.restart),
            LifecycleState.spawning,
            reason: 'restart from ${from.wire}',
          );
        }
      },
    );

    test('close: any non-none state → closed (gc anyState sentinel)', () {
      for (final from in [
        LifecycleState.startPending,
        LifecycleState.spawning,
        LifecycleState.active,
        LifecycleState.asleep,
        LifecycleState.draining,
        LifecycleState.quarantined,
      ]) {
        expect(
          transition(from, LifecycleCommand.close),
          LifecycleState.closed,
          reason: 'close from ${from.wire}',
        );
      }
      // close from none is illegal (nothing to close).
      expect(
        transitionOrNull(LifecycleState.none, LifecycleCommand.close),
        isNull,
      );
    });
  });

  group('illegal transitions fail-closed', () {
    test('throws IllegalLifecycleTransition on a disallowed pair', () {
      // sleep from start_pending is not in the table.
      expect(
        () => transition(LifecycleState.startPending, LifecycleCommand.sleep),
        throwsA(isA<IllegalLifecycleTransition>()),
      );
    });

    test('transitionOrNull returns null instead of throwing', () {
      expect(
        transitionOrNull(LifecycleState.closed, LifecycleCommand.activate),
        isNull,
      );
    });

    test('a closed session accepts no command except idempotent close', () {
      for (final cmd in LifecycleCommand.values) {
        if (cmd == LifecycleCommand.close) {
          // close is anyState→closed; re-closing a closed bead is idempotent
          // (gc treats an already-closed Close as a no-op, manager.go:895-898).
          expect(
            transitionOrNull(LifecycleState.closed, cmd),
            LifecycleState.closed,
          );
          continue;
        }
        expect(
          transitionOrNull(LifecycleState.closed, cmd),
          isNull,
          reason: 'closed should reject ${cmd.name}',
        );
      }
    });
  });

  group('allowedCommands', () {
    test('active offers sleep/drain/quarantine/activate/close, sorted', () {
      expect(allowedCommands(LifecycleState.active), [
        LifecycleCommand.activate,
        LifecycleCommand.close,
        LifecycleCommand.drain,
        LifecycleCommand.quarantine,
        LifecycleCommand.sleep,
      ]);
    });

    test('none offers only create', () {
      expect(allowedCommands(LifecycleState.none), [LifecycleCommand.create]);
    });
  });

  test('LifecycleState round-trips any wire string gc writes', () {
    // A gc state the_grid does not model is preserved verbatim, not dropped.
    const exotic = LifecycleState('detached');
    expect(exotic.wire, 'detached');
    expect(exotic.isTerminal, isFalse);
    expect(LifecycleState.closed.isTerminal, isTrue);
  });
}
