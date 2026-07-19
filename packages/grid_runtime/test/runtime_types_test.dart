import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeConfig', () {
    test(
      'defaults: long-lived, empty args/env, no startup hint, no deadline',
      () {
        const cfg = RuntimeConfig(workDir: '/w', command: 'claude');
        expect(cfg.lifecycle, Lifecycle.longLived);
        expect(cfg.args, isEmpty);
        expect(cfg.env, isEmpty);
        expect(cfg.startupHint, isNull);
        expect(cfg.deadline, isNull);
      },
    );

    test('value equality includes the per-spawn deadline', () {
      const a = RuntimeConfig(
        workDir: '/w',
        command: 'claude',
        args: ['-p'],
        deadline: Duration(minutes: 20),
      );
      const b = RuntimeConfig(
        workDir: '/w',
        command: 'claude',
        args: ['-p'],
        deadline: Duration(minutes: 20),
      );
      expect(a, equals(b));
      expect(
        a.copyWith(deadline: const Duration(minutes: 21)),
        isNot(equals(b)),
      );
    });
  });

  group('RuntimeCapabilities', () {
    test(
      'subprocess preset is honest: liveness+output, no attach/activity',
      () {
        const caps = RuntimeCapabilities.subprocess;
        expect(caps.detectsLiveness, isTrue);
        expect(caps.streamsOutput, isTrue);
        expect(caps.supportsAttach, isFalse);
        expect(caps.detectsActivity, isFalse);
      },
    );
  });

  group('RuntimeEvent (sealed union)', () {
    test('shared name getter demuxes every variant', () {
      final events = <RuntimeEvent>[
        const RuntimeEvent.sessionStarted(
          name: 's1',
          pid: 1,
          pgid: 2,
          deadline: Duration(minutes: 20),
        ),
        const RuntimeEvent.exited(name: 's2', exitCode: 0),
        const RuntimeEvent.died(name: 's3'),
        const RuntimeEvent.respawned(name: 's4', epoch: 2),
        const RuntimeEvent.activityChanged(name: 's5', active: true),
      ];
      expect(events.map((e) => e.name), ['s1', 's2', 's3', 's4', 's5']);
      final started = events.whereType<SessionStarted>().single;
      expect(started.deadline, const Duration(minutes: 20));
    });

    test('exhaustive switch covers all five variants', () {
      String describe(RuntimeEvent e) => switch (e) {
        SessionStarted(:final pid) => 'started:$pid',
        Exited(:final exitCode) => 'exited:$exitCode',
        Died(:final reason) => 'died:$reason',
        Respawned(:final epoch) => 'respawned:$epoch',
        ActivityChanged(:final active) => 'activity:$active',
      };

      expect(
        describe(const RuntimeEvent.exited(name: 's', exitCode: 7)),
        'exited:7',
      );
      expect(
        describe(const RuntimeEvent.died(name: 's', reason: 'vanished')),
        'died:vanished',
      );
    });
  });
}
