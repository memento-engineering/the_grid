import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:beads_dart/src/interactors/graph_sync_interactor.dart';
import 'package:beads_dart/src/reactivity/dirty_signal.dart';
import 'package:test/test.dart';

void main() {
  group('GraphSyncInteractor coalescing + single-flight', () {
    test('start performs exactly one baseline refresh', () {
      fakeAsync((async) {
        var refreshes = 0;
        final signals = StreamController<DirtySignal>.broadcast();
        final interactor = GraphSyncInteractor(
          signals: signals.stream,
          onRefresh: () async => refreshes++,
        );
        interactor.start();
        async.flushMicrotasks();
        expect(refreshes, 1);
      });
    });

    test('a burst within the quiet window collapses to one refresh', () {
      fakeAsync((async) {
        var refreshes = 0;
        final signals = StreamController<DirtySignal>.broadcast();
        final interactor = GraphSyncInteractor(
          signals: signals.stream,
          onRefresh: () async => refreshes++,
          quietPeriod: const Duration(milliseconds: 150),
        );
        interactor.start();
        async.flushMicrotasks();
        expect(refreshes, 1, reason: 'baseline');

        // Three signals, each <150ms apart — the quiet timer keeps resetting.
        signals.add(const DirtySignal(DirtyOrigin.workspaceWatch));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 50));
        signals.add(const DirtySignal(DirtyOrigin.workspaceWatch));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 50));
        signals.add(const DirtySignal(DirtyOrigin.workingSetProbe));
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 149));
        expect(refreshes, 1, reason: 'quiet period has not elapsed');

        async.elapse(const Duration(milliseconds: 2));
        async.flushMicrotasks();
        expect(refreshes, 2, reason: 'exactly one coalesced refresh');
      });
    });

    test('signals during a refresh schedule exactly one follow-up', () {
      fakeAsync((async) {
        var refreshes = 0;
        final signals = StreamController<DirtySignal>.broadcast();
        final interactor = GraphSyncInteractor(
          signals: signals.stream,
          onRefresh: () async {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          },
        );
        interactor.start(); // baseline begins, in flight for 100ms
        async.flushMicrotasks();
        expect(refreshes, 1);
        expect(interactor.stats.refreshing, isTrue);

        // Two signals arrive mid-refresh — should yield ONE follow-up, not two.
        signals.add(const DirtySignal(DirtyOrigin.workspaceWatch));
        async.flushMicrotasks();
        signals.add(const DirtySignal(DirtyOrigin.workingSetProbe));
        async.flushMicrotasks();
        expect(interactor.stats.pendingFollowUp, isTrue);

        async.elapse(const Duration(milliseconds: 100)); // baseline completes
        async.flushMicrotasks();
        expect(refreshes, 2, reason: 'one follow-up runs');

        async.elapse(const Duration(milliseconds: 100)); // follow-up completes
        async.flushMicrotasks();
        expect(refreshes, 2, reason: 'no extra refresh — fully coalesced');
        expect(interactor.stats.refreshing, isFalse);
      });
    });

    test('refreshNow bypasses the quiet period', () {
      fakeAsync((async) {
        var refreshes = 0;
        final signals = StreamController<DirtySignal>.broadcast();
        final interactor = GraphSyncInteractor(
          signals: signals.stream,
          onRefresh: () async => refreshes++,
          quietPeriod: const Duration(seconds: 10),
        );
        interactor.start();
        async.flushMicrotasks();
        expect(refreshes, 1);

        interactor.refreshNow();
        async.flushMicrotasks();
        expect(refreshes, 2, reason: 'immediate, no 10s wait');
      });
    });

    test('a fresh signal after settling triggers a new refresh', () {
      fakeAsync((async) {
        var refreshes = 0;
        final signals = StreamController<DirtySignal>.broadcast();
        final interactor = GraphSyncInteractor(
          signals: signals.stream,
          onRefresh: () async => refreshes++,
          quietPeriod: const Duration(milliseconds: 150),
        );
        interactor.start();
        async.flushMicrotasks();

        signals.add(const DirtySignal(DirtyOrigin.manual));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(refreshes, 2);

        signals.add(const DirtySignal(DirtyOrigin.manual));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(refreshes, 3);
      });
    });

    test('stats track per-origin signal counts', () {
      fakeAsync((async) {
        final signals = StreamController<DirtySignal>.broadcast();
        final interactor = GraphSyncInteractor(
          signals: signals.stream,
          onRefresh: () async {},
        );
        interactor.start();
        async.flushMicrotasks();

        signals.add(const DirtySignal(DirtyOrigin.workspaceWatch));
        signals.add(const DirtySignal(DirtyOrigin.workspaceWatch));
        signals.add(const DirtySignal(DirtyOrigin.workingSetProbe));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        final stats = interactor.stats;
        expect(stats.signalCounts[DirtyOrigin.workspaceWatch], 2);
        expect(stats.signalCounts[DirtyOrigin.workingSetProbe], 1);
        expect(stats.totalSignals, 3);
        expect(stats.refreshCount, greaterThanOrEqualTo(2));
      });
    });
  });
}
