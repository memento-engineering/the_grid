/// Wedge detection (tg-jwh): the station's own answer to "is the grid stuck?".
///
/// A grid is WEDGED when it has live sessions but NONE of them is in an active
/// stage — every one parked at a gate, or otherwise not moving — SUSTAINED past
/// a threshold. It is DISTINCT from a routine gate-open: one gate with work
/// still flowing elsewhere is [WedgeState.flowing]; a momentary between-stages
/// gap is [Stalling]; only a sustained TOTAL stall is [Wedged], and only that
/// flares (`station.wedged`, ADR-0008 D9's flare primitive).
///
/// The derivation is PURE and STATION-SIDE: it reads the producer-side
/// [JoinedSnapshot] the join bridge last pushed (never a pipeline subscription —
/// ADR-0007 §6.1 derailment-invariant 1), so the status surface reports a value
/// the station already computed and no watcher re-derives it from raw sessions.
///
/// NOT in scope (and NOT a wedge): a station with ready work but ZERO live
/// sessions — a dead mint already flares `session.mintFailed`/
/// `session.mintExhausted` (tg-6nf), and a governor-throttled backlog already
/// flares `work.throttled` and never becomes live (A43).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../molecule/molecule_codec.dart' show projectMoleculeCursor;
import '../sdk/circuit.dart';
import '../sdk/cursor.dart' show NodeCursor;
import 'joined_snapshot.dart';

part 'wedge.freezed.dart';

/// The default sustain window before a stall is called a WEDGE — long enough
/// that no legitimate transition trips it (the supervised-restart backoff caps
/// at 60s; a `Rewind` verdict's wave re-keys within a microtask flush — A47),
/// short enough that the governor is pulled in within a poll or two rather than
/// whenever a human happens to look.
const kDefaultWedgeThreshold = Duration(minutes: 10);

/// The default cadence the station re-samples its own forward progress at.
const kDefaultWedgePollInterval = Duration(seconds: 30);

/// The flare emitted ONCE on the rising edge of a wedge episode (ADR-0008 D9 —
/// a non-blocking signal, never a gate: a flare-as-gate would wrongly halt the
/// loop). Named like its siblings `session.mintFailed` / `work.throttled`.
const kWedgedFlare = 'station.wedged';

/// The flare emitted ONCE on the falling edge — forward progress resumed.
const kUnwedgedFlare = 'station.unwedged';

/// One instantaneous, pure count of the station's forward progress, taken over
/// the LIVE (non-terminal) sessions of a [JoinedSnapshot].
@freezed
abstract class WedgeSample with _$WedgeSample {
  /// Creates a sample.
  const factory WedgeSample({
    /// Live (non-terminal) sessions.
    @Default(0) int live,

    /// Live sessions with at least one node in [StepState.running] — the ONLY
    /// evidence of an active stage. [StepState.ready] does NOT count: it is a
    /// POSITIVE TERMINAL (a daemon signalled up, its dep satisfied), so a
    /// session whose sole non-terminal node is a `ready` daemon with nothing
    /// downstream mounting is genuinely not advancing.
    @Default(0) int running,

    /// Live sessions parked at a gate (>=1 node [StepState.gated]) with no
    /// running node.
    @Default(0) int gated,

    /// Live sessions with a failed node whose `cooldownUntil` is still in the
    /// FUTURE — a supervised restart is SCHEDULED (ADR-0008 D7's restorable
    /// backoff), so the grid IS making forward progress.
    @Default(0) int cooling,
  }) = _WedgeSample;

  const WedgeSample._();

  /// The wedge predicate: work is live, nothing is in an active stage, and
  /// nothing is scheduled to restart.
  bool get isStalled => live > 0 && running == 0 && cooling == 0;

  /// The human-readable escalation reason carried on the wire and in the flare.
  String get reason {
    if (live == 0) return 'no live session';
    if (!isStalled) return '$running of $live live session(s) running';
    if (gated > 0) {
      final parked = gated == live ? 'ALL $live' : '$gated of $live';
      return '$parked live session(s) parked at a gate; 0 running, 0 cooling '
          'down — no forward progress';
    }
    return '$live live session(s); 0 running, 0 gated, 0 cooling down — no '
        'session is in an active stage';
  }

  /// The counts as they ride the status surface's wedge block.
  Map<String, Object?> toJson() => <String, Object?>{
    'live': live,
    'running': running,
    'gated': gated,
    'cooling': cooling,
  };
}

/// The station's sustained wedge state — a freezed SEALED union, so a
/// consumer's dispatch is exhaustive (ADR-0001 Decision 1).
@freezed
sealed class WedgeState with _$WedgeState {
  /// Work is flowing (or there is no live work at all) — never an alarm.
  const factory WedgeState.flowing({required WedgeSample sample}) = Flowing;

  /// Stalled, but NOT yet past the threshold — a normal between-stages gap
  /// looks exactly like this and must never flare. [Stalling.since] is when the
  /// stall began.
  const factory WedgeState.stalling({
    required DateTime since,
    required WedgeSample sample,
  }) = Stalling;

  /// WEDGED — stalled continuously for at least the threshold. The LOUD state.
  const factory WedgeState.wedged({
    required DateTime since,
    required WedgeSample sample,
  }) = Wedged;

  const WedgeState._();

  /// True only in the [Wedged] arm — the single boolean the status surface
  /// reports.
  bool get isWedged => this is Wedged;

  /// The wire shape the status surface serializes under its top-level wedge key.
  /// Hand-written (no `part '*.g.dart'`): freezed's union codec would inject a
  /// `runtimeType` discriminator the RS-4 wire must not carry.
  Map<String, Object?> toJson() => switch (this) {
    Flowing(:final sample) => _json(wedged: false, since: null, sample: sample),
    Stalling(:final since, :final sample) => _json(
      wedged: false,
      since: since,
      sample: sample,
    ),
    Wedged(:final since, :final sample) => _json(
      wedged: true,
      since: since,
      sample: sample,
    ),
  };

  Map<String, Object?> _json({
    required bool wedged,
    required DateTime? since,
    required WedgeSample sample,
  }) => <String, Object?>{
    'wedged': wedged,
    'since': since?.toIso8601String(),
    'reason': sample.reason,
    ...sample.toJson(),
  };
}

/// The all-zero sample — no live session at all.
const kNoWedgeSample = WedgeSample();

/// The never-alarming default: what a status built WITHOUT a work runtime
/// reports, so a status surface can never raise a phantom alarm.
const kNotWedged = Flowing(sample: kNoWedgeSample);

/// Counts the station's forward progress over [snapshot]'s LIVE sessions — pure,
/// allocation-light, no I/O. [now] fences the cooling-down check.
///
/// A molecule session (`SessionProjection.isMolecule`) contributes through its
/// own `type=step` beads, projected via [projectMoleculeCursor] over the
/// per-session bucket the join already carries
/// (`SessionProjection.moleculeBeads` — the SAME snapshot the caller holds,
/// A39: no new read). The projection keeps only the ACTIVE incarnation per
/// path (A52 supersedes chains), so a stale superseded step still stamped
/// `running` can never mask a molecule stall.
///
/// A NON-molecule live session — only a HISTORICAL flat one can exist since
/// tg-eli phase 2 retired the flat model — counts `live` but contributes NO
/// nodes (its `grid.cursor.*` keys no longer project). That is honest: the
/// engine cannot drive it, so it genuinely is not advancing, and a store
/// holding one can ripen into a visible stall instead of a silent wedge.
WedgeSample sampleWedge(JoinedSnapshot snapshot, {required DateTime now}) {
  var live = 0;
  var running = 0;
  var gated = 0;
  var cooling = 0;
  for (final session in snapshot.sessionsByWorkBead.values) {
    if (session.isTerminal) continue;
    live++;
    // The model split is the EXPLICIT discriminator, never inferred from the
    // buckets (`DESIGN-tg-pm6.md` §12): a molecule pour that crashed before
    // its first step bead landed still samples down the molecule arm (an
    // empty cursor — a stall that can honestly ripen). A non-molecule (legacy
    // flat) session contributes no nodes at all — see the function doc.
    final nodes = session.isMolecule
        ? projectMoleculeCursor(
            session.moleculeBeads,
            dependencies: session.moleculeDependencies,
          ).cursor.values
        : const <NodeCursor>[];
    var isRunning = false;
    var isGated = false;
    var isCooling = false;
    for (final node in nodes) {
      switch (node.state) {
        case StepState.running:
          isRunning = true;
        case StepState.gated:
          isGated = true;
        case StepState.failed:
          final until = node.cooldownUntil;
          if (until != null && until.isAfter(now)) isCooling = true;
        // `pending` covers the A47 rewind wave (a `Rewind` writes state=pending
        // then the tree re-keys and re-mounts within a microtask flush — far
        // under the threshold, so it can never false-alarm). `ready`/`complete`
        // are POSITIVE TERMINALS, not active stages.
        case StepState.pending || StepState.ready || StepState.complete:
          break;
      }
    }
    if (isRunning) running++;
    if (isCooling) cooling++;
    if (isGated && !isRunning) gated++;
  }
  return WedgeSample(
    live: live,
    running: running,
    gated: gated,
    cooling: cooling,
  );
}
