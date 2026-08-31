/// §2.4 obligation 4 — stuck-obligation accounting (schema §5's N-failure
/// rule), read off the tick's own pass telemetry.
///
/// Schema §5: "a repair that fails read-back `N=5` consecutive ticks appends
/// `attempt.note(channel='obligation-stuck')` and flares for the operator; the
/// obligation stays open (it is keyed on external state, so it cannot silently
/// vanish)". This is that accountant, and it is deliberately NOT an
/// [ObligationQuery]: it keys on the TICK's refusal history, not on a
/// projection, so it consumes passes instead of rows.
///
/// It rides the queue path (the recorder's [StationTrajectoryRecorder.obligationStuckNoted])
/// rather than the tick's fenced append, because a note is accounting, not a
/// repair: it heals nothing, and appending it inside the pass that produced the
/// refusal would make the pass's own progress count report a repair it did not
/// make.
///
/// **What counts as a failure at Stage 1.** No Stage-1 obligation writes bd
/// (§2.4), so "fails read-back" has no ledger half yet; what an obligation CAN
/// accrue is a refusal — its SQL or repair threw, or its append came back
/// refused. Those are exactly [TrajectoryTickPass.refusals], counted per
/// obligation name. A pass in which an obligation is refusal-free resets its
/// streak; the streak is consecutive by construction.
library;

import 'package:grid_trajectory/grid_trajectory.dart';

import 'station_trajectory_recorder.dart';

/// Schema §5's N.
const int kStuckObligationThreshold = 5;

/// The note's subject when a refusal names no session — which is the norm: an
/// obligation's SQL or repair fails wholesale, for no one session. The station
/// is the honest subject, and the shape keeps the note's `note:<subject>:<n>`
/// key well-formed and greppable.
String stationNoteSubject(String station) => 'station:$station';

/// Counts consecutive refusing passes per obligation and files the note.
class StuckObligationAccountant {
  StuckObligationAccountant({
    required StationTrajectoryRecorder recorder,
    required String station,
    this.threshold = kStuckObligationThreshold,
    void Function(String name, Map<String, String> data)? onFlare,
  }) : _recorder = recorder,
       _station = station,
       _onFlare = onFlare;

  final StationTrajectoryRecorder _recorder;
  final String _station;
  final void Function(String name, Map<String, String> data)? _onFlare;

  /// The N of schema §5's N-consecutive-failure rule.
  final int threshold;

  /// obligation name → consecutive refusing passes.
  final Map<String, int> _streaks = <String, int>{};

  /// A read for the `/status` trajectory block: what is currently streaking,
  /// and how far.
  Map<String, int> get streaks => Map<String, int>.unmodifiable(_streaks);

  /// Consumes one pass — the tick's `onPass` sink. Never throws: this is
  /// telemetry consumption on the tick's own loop, and the tick's swallow
  /// convention holds here too.
  void observe(TrajectoryTickPass pass) {
    // A pass that never ran (fenced out, halted, busy, disposed) is not
    // evidence about any obligation: it ran none of them. Streaks are held,
    // not advanced and not reset.
    if (!pass.ran) return;
    final refusedBy = <String, List<TickRefusal>>{};
    for (final refusal in pass.refusals) {
      (refusedBy[refusal.query] ??= []).add(refusal);
    }
    // Reset every obligation that ran clean this pass — including ones that
    // have never refused (a no-op on an absent streak).
    for (final name in _streaks.keys.toList()) {
      if (!refusedBy.containsKey(name)) _streaks.remove(name);
    }
    for (final entry in refusedBy.entries) {
      final streak = (_streaks[entry.key] ?? 0) + 1;
      _streaks[entry.key] = streak;
      if (streak < threshold) continue;
      _file(entry.key, streak, entry.value);
      // The obligation stays OPEN (it is keyed on external state); only the
      // streak resets, so a still-stuck obligation files again after another
      // N passes rather than once per pass forever.
      _streaks.remove(entry.key);
    }
  }

  void _file(String obligation, int streak, List<TickRefusal> refusals) {
    final reasons = refusals
        .map((refusal) => refusal.reason)
        .toSet()
        .join('; ');
    _recorder.obligationStuckNoted(
      sessionId: stationNoteSubject(_station),
      body:
          'obligation "$obligation" refused $streak consecutive ticks '
          '(threshold $threshold); the obligation stays open. Last reasons: '
          '$reasons',
    );
    _flare('trajectory.obligationStuck', {
      'obligation': obligation,
      'streak': '$streak',
      'threshold': '$threshold',
      'reason': reasons,
    });
  }

  void _flare(String name, Map<String, String> data) {
    try {
      _onFlare?.call(name, data);
    } on Object {
      // Emit-only: a throwing transport never breaks the accounting.
    }
  }
}
