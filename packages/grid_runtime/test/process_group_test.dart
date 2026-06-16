import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// A recording fake of the OS process-group seam (Fakes, not mocks): it records
/// every signal sent and reports programmed liveness so the SIGTERM→grace→
/// SIGKILL escalation and the unsafe-pgid guard are tested offline.
class FakeProcessGroupController implements ProcessGroupController {
  FakeProcessGroupController({
    this.ownGroupId = 99999,
    this.dieAfterTermSignals,
  });

  /// The caller's own group — the self-group guard input.
  final int ownGroupId;

  /// When set, [processAlive] flips to false after this many SIGTERMs are seen
  /// (the group obeyed SIGTERM within the grace window). When null, the group
  /// only dies after a SIGKILL.
  final int? dieAfterTermSignals;

  final List<(int pgid, ProcessSignal signal)> signals = [];
  int _termCount = 0;
  bool _killed = false;

  @override
  Future<int?> resolvePgid(int pid) async => pid; // identity for tests

  @override
  bool processAlive(int pid) {
    if (_killed) return false;
    if (dieAfterTermSignals != null && _termCount >= dieAfterTermSignals!) {
      return false;
    }
    return true;
  }

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    if (signal == ProcessSignal.sigterm) _termCount++;
    if (signal == ProcessSignal.sigkill) _killed = true;
    return true;
  }

  @override
  int currentGroupId() => ownGroupId;
}

void main() {
  group('terminateGroup escalation', () {
    test('SIGTERM alone when the group exits within grace', () async {
      final ctl = FakeProcessGroupController(dieAfterTermSignals: 1);

      final result = await terminateGroup(
        controller: ctl,
        pgid: 4242,
        leaderPid: 4242,
        grace: const Duration(seconds: 1),
        pollPeriod: const Duration(milliseconds: 5),
      );

      expect(result, GroupTerminateResult.exitedOnTerm);
      expect(
        ctl.signals.map((s) => s.$2),
        equals([ProcessSignal.sigterm]),
        reason: 'no SIGKILL when SIGTERM sufficed',
      );
      expect(ctl.signals.first.$1, 4242, reason: 'signalled the whole group');
    });

    test('escalates to SIGKILL when the group survives grace', () async {
      final ctl = FakeProcessGroupController(); // never dies on TERM

      final result = await terminateGroup(
        controller: ctl,
        pgid: 4242,
        leaderPid: 4242,
        grace: const Duration(milliseconds: 30),
        pollPeriod: const Duration(milliseconds: 5),
      );

      expect(result, GroupTerminateResult.killed);
      expect(
        ctl.signals.map((s) => s.$2),
        containsAllInOrder([ProcessSignal.sigterm, ProcessSignal.sigkill]),
      );
    });

    test('refuses an unsafe pgid (<= 1) and sends NO signal', () async {
      final ctl = FakeProcessGroupController();

      final result = await terminateGroup(
        controller: ctl,
        pgid: 1,
        leaderPid: 1234,
      );

      expect(result, GroupTerminateResult.refusedUnsafe);
      expect(ctl.signals, isEmpty);
    });

    test('refuses the caller\'s OWN group and sends NO signal', () async {
      final ctl = FakeProcessGroupController(ownGroupId: 555);

      final result = await terminateGroup(
        controller: ctl,
        pgid: 555,
        leaderPid: 1234,
      );

      expect(result, GroupTerminateResult.refusedUnsafe);
      expect(ctl.signals, isEmpty);
    });

    test('alreadyGone when the leader is dead before we start', () async {
      final ctl = _DeadController();

      final result = await terminateGroup(
        controller: ctl,
        pgid: 4242,
        leaderPid: 4242,
      );

      expect(result, GroupTerminateResult.alreadyGone);
      expect(ctl.signals, isEmpty);
    });
  });
}

class _DeadController extends FakeProcessGroupController {
  @override
  bool processAlive(int pid) => false;
}
