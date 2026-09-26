/// Wedge detection (tg-jwh): the station's own answer to "is the grid stuck?".
///
/// A grid is WEDGED when it has live sessions but NONE of them is in an active
/// stage — every one parked at a gate, or otherwise not moving — SUSTAINED past
/// a threshold. It is DISTINCT from a routine gate-open: one gate with work
/// still flowing elsewhere is [WedgeState.flowing]; a momentary between-stages
/// gap is [Stalling]; only a sustained TOTAL stall is [Wedged], and only that
/// flares (`station.wedged` on entry and `station.wedgeChanged` when its count
/// tuple changes, ADR-0008 D9's flare primitive).
///
/// The derivation is PURE and STATION-SIDE: it reads the producer-side
/// [JoinedSnapshot] the join bridge last pushed (never a pipeline subscription —
/// ADR-0007 §6.1 derailment-invariant 1), so the status surface reports a value
/// the station already computed and no watcher re-derives it from raw sessions.
///
/// NOT in scope (and NOT a wedge): a station with ready work but ZERO live
/// sessions. Wedge remains a station-wide live-session forward-progress
/// signal. Pre-session create failures are independently visible through
/// `session.mintFailed` / `session.mintExhausted` and StationControl's
/// `work.mintFailedScopes` plus `perSubstation[].mintFailedScopes` counts; the
/// zero-live interval after a retryable molecule-pour void is observed by
/// `SessionScope`'s per-attempt `session.moleculePourStalled` watchdog until the
/// authority re-provides a replacement grant. That scope-local watchdog also
/// names an empty-projection episode directly, while this sampler continues to
/// count the same live session in the station aggregate. The two layers share
/// a sustained/rising-edge shape but not ownership: neither watchdog starts a
/// retry, and only the authority owns re-admission timing. A
/// governor-throttled backlog already flares `work.throttled` and never becomes
/// live (A43).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../molecule/molecule_codec.dart' show projectMoleculeCursor;
import '../sdk/circuit.dart';
import '../sdk/cursor.dart' show NodeCursor;
import 'joined_snapshot.dart';
import 'session_bead.dart' show SessionPauseState;
import 'session_projection.dart';
import 'step_cursor_read.dart' show effectiveStepCursor;

part 'wedge.freezed.dart';

/// ONE live session's forward-progress classification — the per-session half
/// of [sampleWedge], shared with the work axis so "this session drives
/// nothing" means the same thing on the admission pass as it does on the
/// station wedge (tg-t4k9; `the_grid#pause-is-a-non-terminal-blocking-
/// disposition` asks the wedge sampler and the mount boundary to apply one
/// definition of live work).
typedef LiveSessionActivity = ({bool running, bool gated, bool cooling});

/// Classifies [session]'s ACTIVE step incarnations (the same read
/// [sampleWedge] makes) into running / gated / cooling. [now] fences the
/// cooling-down check. A non-molecule session has no nodes and reads as none
/// of the three.
LiveSessionActivity liveSessionActivityOf(
  SessionProjection session, {
  required DateTime now,
}) {
  final beadCursor = session.isMolecule
      ? projectMoleculeCursor(
          session.moleculeBeads,
          dependencies: session.moleculeDependencies,
        ).cursor
      : null;
  final nodes = beadCursor == null
      ? const <NodeCursor>[]
      : effectiveStepCursor(
          session,
          siteCursor: beadCursor,
          beadCursor: beadCursor,
        ).values;
  var running = false;
  var gated = false;
  var cooling = false;
  for (final node in nodes) {
    switch (node.state) {
      case StepState.running:
        running = true;
      case StepState.gated:
        gated = true;
      case StepState.failed:
        final until = node.cooldownUntil;
        if (until != null && until.isAfter(now)) cooling = true;
      // `pending` covers the A47 rewind wave (a `Rewind` writes state=pending
      // then the tree re-keys and re-mounts within a microtask flush — far
      // under the threshold, so it can never false-alarm). `ready`/`complete`
      // are POSITIVE TERMINALS, not active stages.
      case StepState.pending || StepState.ready || StepState.complete:
        break;
    }
  }
  return (running: running, gated: gated, cooling: cooling);
}

/// True when [session] is live and unpaused yet DRIVES NOTHING: no running
/// step, no cooling-down failure, and no gate — durable or cursor-derived —
/// parking it. This is the per-session condition the work axis watches after
/// an adoption (tg-t4k9 AC-3): a session that holds its mount slot and reads
/// as quiet. A gated session is parked by design and is NOT idle here, and a
/// paused one occupies no slot to begin with.
bool isIdleLiveSession(SessionProjection session, {required DateTime now}) {
  if (session.isTerminal) return false;
  if (session.pauseState == SessionPauseState.paused) return false;
  if (session.openGateBeadCount > 0) return false;
  final activity = liveSessionActivityOf(session, now: now);
  return !activity.running && !activity.gated && !activity.cooling;
}

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

/// The flare emitted once when the progress-count tuple changes inside one
/// sustained wedge episode. [kWedgedFlare] remains the episode's rising edge;
/// this signal makes later growth or contraction actionable without counting
/// it as another episode.
const kWedgeChangedFlare = 'station.wedgeChanged';

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

    /// Live sessions deliberately parked by an operator. They remain visible
    /// as durable, non-terminal store rows but are not currently driveable.
    @Default(0) int paused,

    /// Live sessions with at least one node in [StepState.running] — the ONLY
    /// evidence of an active stage. [StepState.ready] does NOT count: it is a
    /// POSITIVE TERMINAL (a daemon signalled up, its dep satisfied), so a
    /// session whose sole non-terminal node is a `ready` daemon with nothing
    /// downstream mounting is genuinely not advancing.
    @Default(0) int running,

    /// Exact OPEN gate-bead count from the joined state store. Historical or
    /// synthetic projections with no joined gate evidence contribute a
    /// one-per-session cursor fallback when gated and not running.
    @Default(0) int gated,

    /// Live sessions with a failed node whose `cooldownUntil` is still in the
    /// FUTURE — a supervised restart is SCHEDULED (ADR-0008 D7's restorable
    /// backoff), so the grid IS making forward progress.
    @Default(0) int cooling,

    /// Sorted ids of live sessions with neither a running node nor a future
    /// cooldown. Null ids from synthetic projections are omitted.
    @Default(<String>[]) List<String> frozenSessionIds,
  }) = _WedgeSample;

  const WedgeSample._();

  /// Live sessions the station may currently drive.
  int get active => live - paused;

  /// The wedge predicate: work is live, nothing is in an active stage, and
  /// nothing is scheduled to restart.
  bool get isStalled => active > 0 && running == 0 && cooling == 0;

  /// The human-readable escalation reason carried on the wire and in the flare.
  String get reason {
    if (live == 0) return 'no live session';
    if (active == 0) {
      return 'all $live live session(s) operator-paused; 0 active';
    }
    if (!isStalled) {
      return '$running of $active active session(s) running '
          '($live live, $paused paused)';
    }
    if (gated > 0) {
      return '$gated open gate bead(s) across $active active session(s) leave '
          'work parked at a gate; 0 running, 0 cooling down — no forward '
          'progress';
    }
    return '$active active session(s) ($live live, $paused paused); 0 running, '
        '0 gated, 0 cooling down — no session is in an active stage';
  }

  /// The counts as they ride the status surface's wedge block.
  Map<String, Object?> toJson() => <String, Object?>{
    'live': live,
    'paused': paused,
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
  var paused = 0;
  var running = 0;
  var gated = 0;
  var cooling = 0;
  final frozenSessionIds = <String>[];
  for (final session in snapshot.sessionsByWorkBead.values) {
    // Terminal disposition wins over every stale marker and contributes no
    // live state-store fact.
    if (session.isTerminal) continue;

    live++;
    // Durable gate beads are counted exactly, before the driveability split.
    // A paused row is still live and may still own open gate state.
    gated += session.openGateBeadCount;
    if (session.pauseState == SessionPauseState.paused) {
      paused++;
      continue;
    }
    // The model split is the EXPLICIT discriminator, never inferred from the
    // buckets (`DESIGN-tg-pm6.md` §12): a molecule pour that crashed before
    // its first step bead landed still samples down the molecule arm (an
    // empty cursor — a stall that can honestly ripen). A non-molecule (legacy
    // flat) session contributes no nodes at all — see the function doc.
    // CONSUMER 2 of the step dual read (cut-wiring C4). Unlike the frontier,
    // this site's today-read IS the bead recompute, so adoption here is the
    // pure read swap the design describes: with the step axis unengaged the
    // helper hands back that same projection, unchanged and un-copied.
    final (running: isRunning, gated: isGated, cooling: isCooling) =
        liveSessionActivityOf(session, now: now);
    if (isRunning) running++;
    if (isCooling) cooling++;
    // Synthetic and historical projections may carry only cursor evidence.
    // Preserve that fallback, but never add it on top of exact joined gate
    // evidence.
    if (session.openGateBeadCount == 0 && isGated && !isRunning) gated++;
    final sessionId = session.sessionId;
    if (!isRunning && !isCooling && sessionId != null) {
      frozenSessionIds.add(sessionId);
    }
  }
  frozenSessionIds.sort();
  return WedgeSample(
    live: live,
    paused: paused,
    running: running,
    gated: gated,
    cooling: cooling,
    frozenSessionIds: frozenSessionIds,
  );
}
