import 'dart:async';

/// Per-bead serial execution — the single-writer-per-convergence-bead guarantee
/// (ADR-0003 invariant 7; handler-9step §1).
///
/// gc enforces invariant 7 structurally: startup reconcile and every tick /
/// operator command run on **one** controller event loop, so two
/// `HandleWispClosed`/operator/recovery calls for the same root bead can never
/// interleave (handler.go:143-145; reconcile.go §1.4 / §12). The grid is
/// event-driven and concurrent, so it must reconstruct that serialization
/// itself: this queue runs tasks for the **same** bead strictly in arrival
/// order (a per-bead mutex / FIFO), while tasks for **different** beads proceed
/// concurrently.
///
/// Each bead owns a tail [Future]; [run] chains the next task behind the
/// current tail and installs the chain as the new tail. A task's own error
/// never poisons the chain — the tail is the task's completion regardless of
/// outcome, so one failed cycle does not wedge the bead (the deferred
/// live-error contract retries the same closure next cycle, ADR-0000 A25 / the
/// invariants make replay safe).
class PerBeadQueue {
  /// The in-flight tail per bead id. Absent ⇒ the bead is idle.
  final Map<String, Future<void>> _tails = {};

  /// Enqueues [task] for [beadId], returning its result. Tasks for the same
  /// [beadId] run one at a time in call order; tasks for different beads do
  /// not block each other.
  Future<T> run<T>(String beadId, Future<T> Function() task) {
    final prior = _tails[beadId] ?? Future<void>.value();
    final completer = Completer<T>();

    // The new tail completes when THIS task settles (success or error) — never
    // before, so the next same-bead task waits for it, and never propagates the
    // error into the chain (the chain is a plain `whenComplete`, not `then`).
    final chained = prior.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    _tails[beadId] = chained;
    // Drop the tail when this task was the last one queued, so idle beads do
    // not leak a retained Future.
    unawaited(
      chained.whenComplete(() {
        if (identical(_tails[beadId], chained)) _tails.remove(beadId);
      }),
    );
    return completer.future;
  }

  /// Whether [beadId] currently has a queued/in-flight task.
  bool isBusy(String beadId) => _tails.containsKey(beadId);

  /// The set of beads with queued/in-flight work (for diagnostics/tests).
  Iterable<String> get busyBeads => _tails.keys;

  /// Completes when all currently-queued work has drained. New work enqueued
  /// after this call is not awaited.
  Future<void> idle() => Future.wait(_tails.values.toList());
}
