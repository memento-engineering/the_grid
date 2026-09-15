import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:beads_dart/src/reactivity/dirty_signal.dart';
import 'package:beads_dart/src/reactivity/snapshot_reader.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import '../support/reactivity_fakes.dart';

class _ScriptedChangeProbe implements ChangeProbe {
  _ScriptedChangeProbe(this._call);

  final Future<String> Function(int call) _call;
  int calls = 0;

  @override
  Future<String> probe() {
    calls++;
    return _call(calls);
  }
}

void main() {
  group('WorkspaceBeadsWatcher', () {
    test('reacts to breadcrumb files only', () async {
      final fakeEvents = StreamController<WatchEvent>.broadcast();
      final watcher = WorkspaceBeadsWatcher(
        '/ws/.beads',
        watcherFactory: (_) => fakeEvents.stream,
      );
      final signals = <DirtySignal>[];
      final sub = watcher.signals.listen(signals.add);

      fakeEvents.add(WatchEvent(ChangeType.MODIFY, '/ws/.beads/last-touched'));
      fakeEvents.add(WatchEvent(ChangeType.MODIFY, '/ws/.beads/dolt/x.bin'));
      fakeEvents.add(
        WatchEvent(ChangeType.ADD, '/ws/.beads/interactions.jsonl'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(signals, hasLength(2));
      expect(
        signals.every((s) => s.origin == DirtyOrigin.workspaceWatch),
        isTrue,
      );
      await sub.cancel();
      await watcher.dispose();
    });

    test('isBeadsBreadcrumb classifies filenames', () {
      expect(isBeadsBreadcrumb('/x/.beads/last-touched'), isTrue);
      expect(isBeadsBreadcrumb('/x/.beads/hooks.log'), isTrue);
      expect(isBeadsBreadcrumb('/x/.beads/config.yaml'), isFalse);
    });
  });

  group('WorkingSetProbeSource', () {
    test('emits only when the working-set hash changes', () {
      fakeAsync((async) {
        final probe = FakeChangeProbe('h1');
        final source = WorkingSetProbeSource(
          probe,
          interval: const Duration(seconds: 1),
        );
        final signals = <DirtySignal>[];
        source.signals.listen(signals.add);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(signals, isEmpty, reason: 'first probe is the baseline');

        probe.hash = 'h2';
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(signals, hasLength(1));
        expect(signals.single.origin, DirtyOrigin.workingSetProbe);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(signals, hasLength(1), reason: 'unchanged hash → no emit');

        source.dispose();
      });
    });

    test('surfaces persistent probe death every fifth failure', () {
      fakeAsync((async) {
        final probe = FakeChangeProbe('h1')..error = StateError('reaped');
        final source = WorkingSetProbeSource(
          probe,
          interval: const Duration(seconds: 1),
        );
        final signals = <DirtySignal>[];
        source.signals.listen(signals.add);

        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(signals, isEmpty);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(signals, hasLength(1));
        expect(signals.single.origin, DirtyOrigin.workingSetProbe);
        expect(signals.single.detail, startsWith('probe-dead:'));

        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(signals, hasLength(1));

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(signals, hasLength(2));
        expect(signals.last.detail, startsWith('probe-dead:'));
        source.dispose();
      });
    });

    test('success resets failures and later hash change emits normally', () {
      fakeAsync((async) {
        final probe = FakeChangeProbe('h1');
        final source = WorkingSetProbeSource(
          probe,
          interval: const Duration(seconds: 1),
        );
        final signals = <DirtySignal>[];
        source.signals.listen(signals.add);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        probe.error = StateError('first outage');
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        probe.error = null;
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        probe.error = StateError('second outage');
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(signals, isEmpty);

        probe.error = null;
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        probe.hash = 'h2';
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(signals, hasLength(1));
        expect(signals.single.origin, DirtyOrigin.workingSetProbe);
        expect(signals.single.detail, 'h2');
        source.dispose();
      });
    });

    test(
      'disposal during an in-flight changed probe emits nothing and does not throw',
      () {
        fakeAsync((async) {
          final signals = <DirtySignal>[];
          final uncaught = <Object>[];
          late Completer<String> heldChange;
          late _ScriptedChangeProbe probe;
          late WorkingSetProbeSource source;
          runZonedGuarded(() {
            heldChange = Completer<String>();
            probe = _ScriptedChangeProbe((call) {
              return switch (call) {
                1 => Future.value('h1'),
                2 => heldChange.future,
                _ => Future.error(StateError('unexpected probe call $call')),
              };
            });
            source = WorkingSetProbeSource(
              probe,
              interval: const Duration(seconds: 1),
            );
            source.signals.listen(signals.add);
          }, (error, _) => uncaught.add(error));

          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          expect(probe.calls, 1);
          expect(signals, isEmpty, reason: 'first probe is the baseline');

          async.elapse(const Duration(seconds: 1));
          expect(probe.calls, 2);
          source.dispose();
          heldChange.complete('h2');
          async.flushMicrotasks();

          expect(signals, isEmpty);
          expect(uncaught, isEmpty);
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(probe.calls, 2, reason: 'dispose cancels later timer calls');
          expect(uncaught, isEmpty);
        });
      },
    );

    test(
      'disposal during an in-flight fifth failure emits nothing and does not throw',
      () {
        fakeAsync((async) {
          final signals = <DirtySignal>[];
          final uncaught = <Object>[];
          late Completer<String> heldFailure;
          late _ScriptedChangeProbe probe;
          late WorkingSetProbeSource source;
          runZonedGuarded(() {
            heldFailure = Completer<String>();
            probe = _ScriptedChangeProbe((call) {
              if (call < 5) {
                return Future.error(StateError('probe failure $call'));
              }
              if (call == 5) return heldFailure.future;
              return Future.error(StateError('unexpected probe call $call'));
            });
            source = WorkingSetProbeSource(
              probe,
              interval: const Duration(seconds: 1),
            );
            source.signals.listen(signals.add);
          }, (error, _) => uncaught.add(error));

          async.elapse(const Duration(seconds: 4));
          async.flushMicrotasks();
          expect(probe.calls, 4);
          expect(signals, isEmpty);

          async.elapse(const Duration(seconds: 1));
          expect(probe.calls, 5);
          source.dispose();
          heldFailure.completeError(StateError('probe failure 5'));
          async.flushMicrotasks();

          expect(signals, isEmpty);
          expect(uncaught, isEmpty);
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(probe.calls, 5, reason: 'dispose cancels later timer calls');
          expect(uncaught, isEmpty);
        });
      },
    );
  });

  group('PollingTickerSource', () {
    test('emits unconditionally each interval', () {
      fakeAsync((async) {
        final source = PollingTickerSource(
          interval: const Duration(seconds: 5),
        );
        final signals = <DirtySignal>[];
        source.signals.listen(signals.add);
        async.elapse(const Duration(seconds: 16));
        async.flushMicrotasks();
        expect(signals, hasLength(3));
        expect(signals.first.origin, DirtyOrigin.pollTicker);
        source.dispose();
      });
    });
  });

  group('ManualDirtySource', () {
    test('trigger emits a manual signal', () async {
      final source = ManualDirtySource();
      final signals = <DirtySignal>[];
      final sub = source.signals.listen(signals.add);
      source.trigger(detail: 'requery');
      await Future<void>.delayed(Duration.zero);
      expect(signals.single.origin, DirtyOrigin.manual);
      expect(signals.single.detail, 'requery');
      await sub.cancel();
      await source.dispose();
    });
  });
}
