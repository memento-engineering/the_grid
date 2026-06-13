import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'runtime_fakes.dart';

/// A reusable multi-tick SHADOW REPLAY harness (M2 Track I): drives a
/// [ShadowRuntime] across an ordered list of [GraphSnapshot]s — gc's actual
/// convergence advance, tick by tick — and collects the divergence reports the
/// shadow emits, so a golden can assert the_grid's predicted transitions match
/// (AGREE) or do not match (DIVERGE) what gc actually did.
///
/// ## The correctness rule, encoded HERE (load-bearing)
///
/// [ShadowRuntime] reduces a `BeadClosed` against `_source.current` and resolves
/// `active_wisp` from `_source.convergences`. So the snapshot the source holds
/// when a wisp-closure event is emitted MUST be the PRE-transition tick — the
/// state in which that wisp is still the loop's `active_wisp`. A harness that
/// bulk-emits, or that sets the final snapshot before emitting the closure that
/// precedes it, produces a FALSE golden (the reducer would read post-transition
/// metadata and predict the wrong transition, or fail to map the closure at
/// all). This harness therefore drives ONE transition per tick:
///
///   for each adjacent (prev, next):
///     1. setSnapshot(prev)                 — the source now holds prev;
///     2. diffSnapshots(prev, next)         — the real changes gc made;
///     3. emit each derived GraphEvent      — the shadow reduces/observes them
///        AGAINST prev (the pre-transition state — the active_wisp is still
///        live for a BeadClosed; the BeadUpdated carries before=prev/after=next
///        so observedGcCommand can infer gc's command);
///     4. pump the event queue to idle;
///     5. setSnapshot(next)                 — advance for the next tick.
///
/// Emitting the diff events while the source still holds `prev` is exactly the
/// live ordering: the_grid observes the change diff BEFORE the next baseline
/// snapshot lands (the watcher lag this package pins elsewhere). The closure
/// prediction is computed against `prev`; gc's command is inferred from the
/// `BeadUpdated(before: prev-bead, after: next-bead)` the diff produced.
class ShadowReplayHarness {
  /// Builds the harness with its own source/shadow wired together. The source
  /// starts holding [snapshots] `.first` (the baseline); [run] advances it.
  factory ShadowReplayHarness.over(List<GraphSnapshot> snapshots) {
    assert(snapshots.isNotEmpty, 'need at least one snapshot');
    final source = FakeConvergenceSource(snapshots.first);
    final shadow = ShadowRuntime(source: source);
    return ShadowReplayHarness._(snapshots, source, shadow);
  }

  ShadowReplayHarness._(this.snapshots, this.source, this.shadow);

  final List<GraphSnapshot> snapshots;
  final FakeConvergenceSource source;
  final ShadowRuntime shadow;

  /// Per-tick record of what was emitted and the report (if any) the tick
  /// produced — the golden's inspection surface.
  final List<ReplayTick> ticks = [];

  /// Drives the full sequence and returns the collected divergence reports, in
  /// order. Disposes the shadow at the end.
  Future<List<DivergenceReport>> run() async {
    shadow.start();
    for (var i = 0; i + 1 < snapshots.length; i++) {
      final prev = snapshots[i];
      final next = snapshots[i + 1];

      // (1) the source holds the PRE-transition tick.
      source.setSnapshot(prev);

      // (2) the real changes gc made between the two ticks.
      final events = diffSnapshots(prev, next);

      // Snapshot how many reports exist before this tick so we can attribute
      // any NEW report to it.
      final reportsBefore = shadow.reports.length;

      // (3) feed each derived event to the shadow, AGAINST prev.
      for (final event in events) {
        source.emit(event);
        // (4) pump to idle after each so the reduce/observe completes against
        // the still-current `prev` snapshot before the next event.
        await pumpEventQueue();
      }

      final newReports = shadow.reports.sublist(reportsBefore);
      ticks.add(ReplayTick(index: i, events: events, reports: newReports));

      // (5) advance the baseline for the next tick.
      source.setSnapshot(next);
    }
    await shadow.dispose();
    return shadow.reports;
  }
}

/// What one replay tick emitted and the divergence report(s) it produced.
class ReplayTick {
  ReplayTick({
    required this.index,
    required this.events,
    required this.reports,
  });

  /// The 0-based adjacent-pair index (tick i covers snapshots[i] → [i+1]).
  final int index;

  /// The diff events gc's change produced for this tick.
  final List<GraphEvent> events;

  /// Divergence reports the shadow emitted during this tick (usually 0 or 1).
  final List<DivergenceReport> reports;

  /// True when this tick produced a report flagged diverged.
  bool get diverged => reports.any((r) => r.diverged);

  /// True when this tick produced no report at all (quiet — gc made no
  /// command-shaped write, or the change was not convergence traffic).
  bool get quiet => reports.isEmpty;
}
