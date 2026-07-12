/// The sustained-wedge monitor (tg-jwh) — the station's own stuck-detector.
///
/// It latches WHEN a stall began, and only calls it a [Wedged] once the stall
/// has held continuously for [WedgeMonitor.threshold]. The escalation is a FLARE
/// (ADR-0008 D9: a NON-BLOCKING signal emitted at a transition — never a gate,
/// which would halt the loop) through the reserved emit-only
/// [ExplorationTransport] (D-8), the SAME sink `session.mintFailed` /
/// `gate.rearmFailed` / `work.throttled` already use. It fires on the RISING
/// EDGE — exactly once per episode, never once per poll — which is what makes it
/// LOUD and NOT the spammy per-poll gate-open signal.
///
/// It owns its own re-arming one-shot Timer through the injected
/// `scheduleTimer` seam (the same seam `StationDriver` carries), because a
/// WEDGED station emits no flushes: a flush-driven check could never fire the
/// alarm it exists for. It adds NO subscription: it reads the producer-side
/// snapshot through the injected `latest` getter (derailment-invariant 1 /
/// ADR-0008 D-H rule 2 — `StationJoinBridge.latest` is what the bridge last
/// PUSHED, not a sync read of the notifier's reactive state).
library;

import 'dart:async';

import '../domain/joined_snapshot.dart';
import '../domain/wedge.dart';
import '../sdk/capability.dart';

/// Samples the station's forward progress on a timer and flares a SUSTAINED
/// stall exactly once per episode. Owned + driven by `StationDriver`.
class WedgeMonitor {
  /// Creates a monitor over the producer-side [latest] join.
  ///
  /// [transport] is the emit-only observability sink (D-8): null — the default,
  /// and the posture of every engine flare today until the live arm adapts one —
  /// means the state is still computed and still served on the status surface,
  /// it just flares to nobody. The ENGINE holds no opinion about what a sink
  /// DOES with a flare (ADR-0007 §1); it only emits.
  WedgeMonitor({
    required JoinedSnapshot Function() latest,
    this.threshold = kDefaultWedgeThreshold,
    this.pollInterval = kDefaultWedgePollInterval,
    ExplorationTransport? transport,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? scheduleTimer,
  }) : _latest = latest,
       _transport = transport,
       _clock = clock ?? DateTime.now,
       _scheduleTimer = scheduleTimer ?? Timer.new;

  /// How long a stall must hold continuously before it is a WEDGE.
  final Duration threshold;

  /// How often the station re-samples itself.
  final Duration pollInterval;

  final JoinedSnapshot Function() _latest;
  final ExplorationTransport? _transport;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _scheduleTimer;

  WedgeState _state = kNotWedged;
  DateTime? _stalledSince;
  Timer? _timer;
  bool _disposed = false;

  /// The station's current wedge state — a plain derived VALUE (not a mirror of
  /// reactive state behind a sync accessor): the status view reads it fresh per
  /// request.
  WedgeState get state => _state;

  /// Takes the baseline sample. Idempotent — [poll] is the whole loop.
  void start() => poll();

  /// Samples once, advances the latch, and re-arms the timer IFF the station is
  /// currently stalled. Called by the timer, by [start], and by
  /// `StationDriver.afterFlush` (a flush is what detects the ENTRY into a stall;
  /// the timer is what carries that stall through TIME once flushes stop).
  ///
  /// A FLOWING station schedules nothing: the timer exists only to watch a stall
  /// ripen, so a healthy grid arms no wall clock at all (and a station with a
  /// scheduled restart is `cooling`, hence never stalled — the backoff timer and
  /// this one are mutually exclusive by construction).
  void poll() {
    if (_disposed) return;
    final now = _clock();
    final sample = sampleWedge(_latest(), now: now);

    if (!sample.isStalled) {
      final wasWedged = _state.isWedged;
      _stalledSince = null;
      _state = Flowing(sample: sample);
      _cancelTimer();
      // The FALLING edge, once: a station that was never wedged says nothing.
      if (wasWedged) _flare(kUnwedgedFlare, since: null, sample: sample);
      return;
    }

    // The latch: an explicit null-check, never a `??=`-cache of a dependency
    // (ADR-0008 D-H rule 1).
    var since = _stalledSince;
    if (since == null) {
      since = now;
      _stalledSince = now;
    }
    // Watch this stall through time — a WEDGED station emits no flushes, so the
    // alarm can never be flush-driven.
    _armIfIdle();
    if (now.difference(since) < threshold) {
      _state = Stalling(since: since, sample: sample);
      return;
    }
    final wasWedged = _state.isWedged;
    _state = Wedged(since: since, sample: sample);
    // The RISING EDGE only: a wedged station polled 20 more times flares ONCE,
    // not 20 times (LOUD, never spammy — the whole point of tg-jwh).
    if (!wasWedged) _flare(kWedgedFlare, since: since, sample: sample);
  }

  /// Emits the fire-and-continue flare (D9) through the emit-only transport. A
  /// throwing transport NEVER breaks the poll — the same swallow convention as
  /// `WorkList._reportThrottled` and `SessionScope._flareMint`.
  void _flare(String name, {DateTime? since, required WedgeSample sample}) {
    try {
      _transport?.flare(name, {
        if (since != null) 'since': since.toIso8601String(),
        'reason': sample.reason,
        'live': '${sample.live}',
        'running': '${sample.running}',
        'gated': '${sample.gated}',
        'cooling': '${sample.cooling}',
      });
    } catch (_) {
      // A throwing transport never breaks the station's own poll — swallow.
    }
  }

  void _armIfIdle() {
    if (_timer != null) return;
    _timer = _scheduleTimer(pollInterval, _tick);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    _timer = null;
    if (_disposed) return;
    // `poll` re-arms while the stall holds, and lets the timer lapse once the
    // grid is flowing again.
    poll();
  }

  /// Cancels the poll timer. Idempotent.
  void dispose() {
    _disposed = true;
    _cancelTimer();
  }
}
