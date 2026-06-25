// Test-only conformance probes for the Wave 4 acceptance suite.
//
// These wrap the REAL kernel collaborators (the JoinedSnapshotNotifier the
// bridge drives, and the SnapshotSource the bridge subscribes to) with thin
// counting shims so an acceptance test can assert the load-bearing
// derailment-invariant-1 facts STRUCTURALLY — "exactly one persistent tree
// listener", "the bridge is the only stream subscriber" — without reaching into
// `@protected` internals (`StateNotifier.hasListeners`) or scraping logs.
//
// Pure-Dart: no live tg/gc/claude/git/network. Reused across the invariant_1
// acceptance test; kept here (not in test/support/engine_fakes.dart) because
// they are conformance instrumentation, not the shared offline fakes.
import 'dart:async';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:state_notifier/state_notifier.dart';

import '../support/engine_fakes.dart';

/// A [JoinedSnapshotNotifier] that counts its LIVE persistent listeners.
///
/// `WorkList` adds a persistent listener (it keeps the [RemoveListener] and
/// only calls it on dispose); the `current` getter and other transient probes
/// add-then-immediately-remove. By incrementing on every `addListener` and
/// decrementing when the returned remover is invoked, [liveListenerCount]
/// reflects exactly the listeners that are still subscribed at the moment it is
/// read — so a test can assert "exactly ONE persistent tree listener after
/// mount" (the sole work-axis observer, `WorkList`).
class CountingJoinedSnapshotNotifier extends JoinedSnapshotNotifier {
  CountingJoinedSnapshotNotifier(super.initial);

  int _live = 0;

  /// The number of listeners currently subscribed (added and not yet removed).
  int get liveListenerCount => _live;

  @override
  RemoveListener addListener(
    void Function(JoinedSnapshot state) listener, {
    bool fireImmediately = true,
  }) {
    _live++;
    var removed = false;
    final remove = super.addListener(listener, fireImmediately: fireImmediately);
    return () {
      if (!removed) {
        removed = true;
        _live--;
      }
      remove();
    };
  }
}

/// A [SnapshotSource] wrapper that counts every `.listen()` on its [snapshots]
/// stream — the probe behind "the bridge is the ONLY subscriber to the
/// SnapshotSources" (no tree node ever subscribes to a `GraphSnapshot` stream;
/// it only receives the injected immutable [JoinedSnapshot] value).
///
/// Delegates [current] + the underlying broadcast stream to an inner
/// [FakeSnapshotSource], so a test pushes through [push] exactly as it would the
/// fake.
class CountingSnapshotSource implements SnapshotSource {
  CountingSnapshotSource([GraphSnapshot? current])
    : _inner = FakeSnapshotSource(current);

  final FakeSnapshotSource _inner;

  /// The number of `.listen()` subscriptions taken on [snapshots].
  int listenCount = 0;

  @override
  Stream<GraphSnapshot> get snapshots {
    listenCount++;
    return _inner.snapshots;
  }

  @override
  GraphSnapshot? get current => _inner.current;

  /// Pushes [snapshot] (updates [current] and emits), like the change-gated
  /// runtime.
  void push(GraphSnapshot snapshot) => _inner.push(snapshot);

  /// Closes the underlying stream (call from an `addTearDown`).
  Future<void> close() => _inner.close();
}
