/// THE DUAL READ, session axis — the pure half (cut-wiring §0.3, chunk C2).
///
/// Everything here is a total function or a plain accumulator over values the
/// caller already holds: the LEGACY [SessionProjection] the join projected
/// from the state store, and the pre-fetched [SessionHeadView] the harness
/// mirrored out of P1. Nothing awaits, nothing reads a store, nothing writes
/// one. The bridge and the restart reconciler both call in here so the two
/// read paths cannot drift.
///
/// Three rules do the load-bearing work, and each exists because a verified
/// fail-open was found without it:
///
///   * **THE OVERLAY IDENTITY RULE** (r5 — J9-B1) — the merge input is always
///     `snapshot.bySessionId(legacy.sessionId)`, NEVER a `byWorkBead` winner.
///     The legacy join keys ONE projection per base work bead while P1 keeps
///     every round's row under the immutable base key, so a winner-rule row
///     could otherwise splice a SIBLING session's terminal onto a live one.
///   * **MONOTONIC TERMINALITY** (r3 — F-B4; r8 — V2-B2) — every terminal
///     writes bd FIRST and appends after, fire-and-forget, so a real window
///     exists where legacy says terminal and P1 still says open. The overlay
///     never demotes a terminal-family fact; that shape is `terminalLag`, and
///     it is HEALED (`terminal-reconcile`) before it is ever escalated.
///   * **THE RECONSTRUCTED SUPPRESSOR** (r5/r7 — J8-B1, V1-B2) — a head whose
///     terminal is reconstructed TESTIMONY serves pure legacy and is
///     adjudicated, never counted as a divergence. A reconstructed outcome is
///     fold bookkeeping; it was never decision state.
///
/// C2 built and certified the overlay here and served nothing; C3 SERVES it
/// under `dualRead: primary` — the same functions, the same three rules, now
/// spliced into the sessions map by the join. Under `observe` this file still
/// only ever COUNTS, and the flip back is one config line because wave 1
/// retires nothing: legacy stays fully written underneath either way.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'session_projection.dart';
import 'trajectory_views.dart';

/// The dual-read posture (cut-wiring C2's config line).
///
/// [off] is THE ROLLBACK, and it is stated first because the rollback claim is
/// only true of a posture that actually disarms everything wave 1 added: no
/// comparator pass, no mirror push subscriptions on the join bridge, and none
/// of the new OBSERVER APPENDS (the `terminal-reconcile` heal, the
/// teardown-replay close, the durable round summaries). `off` is
/// byte-identical to pre-cut mainline on every surface the station reads OR
/// writes.
///
/// [observe] compares and counts; the sessions map is pure legacy, but the
/// observer appends and the mirror-driven re-join cadence ARE armed — that is
/// C2's scope, and the soak runs here. [primary] additionally SERVES
/// [sessionProjectionOverlay] — C3's flip, one line, and instantly revertible
/// because legacy is still fully written either way.
enum DualReadMode { off, observe, primary }

/// The heal grace on a `terminalLag` entry (r8 — V2-B2): three tick intervals,
/// an order of magnitude past the post-ACK apply window, so a NORMAL terminal's
/// transit through bd-first/append-later can never trigger anything.
const Duration kTerminalLagHealGrace = Duration(seconds: 90);

/// The symmetric escalation grace on a `retirementLag` entry (r9, aligned with
/// FINAL Q5): the re-key lands before the successor mint's `roundRetired`, and
/// past this the retire-close's record must have dropped.
const Duration kRetirementLagGrace = Duration(seconds: 90);

/// The `attempt.note` channel the durable round evidence rides (§0.4).
const String kDualReadRoundSummaryChannel = 'dual-read-round-summary';

/// The flare a served-tuple mismatch raises. Axis-tagged, because C4 adds a
/// step axis under the same name.
const String kDualReadDivergenceFlare = 'trajectory.dualReadDivergence';

/// The flare a breadcrumbless teardown replay raises (r5): a missing record is
/// a VISIBLE lag; a minted-id record would be an immutable lie that `revert`
/// cannot remove and every `traj replay` reproduces.
const String kReconstructedTerminalSkippedFlare =
    'trajectory.reconstructedTerminalSkipped';

// ── the overlay (§0.3's corrected field set) ──────────────────────────────

/// P1's facts about one head, DERIVED into the legacy vocabulary — the only
/// shape either side of the comparison is ever expressed in (§0.3: "compares
/// the DERIVED tuple … never raw column-vs-stamp").
///
/// The mapping is §0.3's outcome table, verbatim:
///
/// | P1 state                      | isTerminal | completed | humanHeld |
/// |---|---|---|---|
/// | `status='open'`               | false | false | `held` |
/// | `outcome='escalated'`         | true  | false | true  |
/// | `outcome ∈ {succeeded, settled}` | true | true | false |
/// | `outcome='lost'`              | true  | false | false |
/// | `outcome ∈ {failed, cancelled}` | true | false | false |
/// | `outcome='unknown'`           | true  | false | true — FAIL-CLOSED |
///
/// The `unknown` row is the fail-closed choice (FINAL Q3): never voided, never
/// done. The settlement obligation heals the outcome; until it does, a human
/// owns the round.
@immutable
final class SessionHeadFacts {
  const SessionHeadFacts({
    required this.isTerminal,
    required this.completed,
    required this.humanHeld,
    required this.closedAt,
  });

  final bool isTerminal;
  final bool completed;
  final bool humanHeld;
  final DateTime? closedAt;
}

/// Derives [head] into the legacy vocabulary — the table above.
SessionHeadFacts sessionHeadFactsOf(SessionHeadView head) {
  if (head.isOpen) {
    // The decline's fold twin: `AttemptReworkDeclined` sets `held` on an OPEN
    // row and `_declineRework` closes nothing, so an open held row is `live`
    // on BOTH sides (r3 — F-m4). The marker only becomes decision-bearing at
    // terminality, and the tuple still compares it.
    return SessionHeadFacts(
      isTerminal: false,
      completed: false,
      humanHeld: head.held,
      closedAt: head.closedAt,
    );
  }
  final outcome = head.outcome;
  return SessionHeadFacts(
    isTerminal: true,
    completed:
        outcome == SessionHeadOutcome.succeeded ||
        outcome == SessionHeadOutcome.settled,
    // `escalated` carries the hold in the OUTCOME (the fold sets no `held`
    // column there — the mapping recovers what legacy derives from the
    // `grid.escalation` stamp); `unknown` is held FAIL-CLOSED.
    humanHeld:
        head.held ||
        outcome == SessionHeadOutcome.escalated ||
        outcome == SessionHeadOutcome.unknown,
    closedAt: head.closedAt,
  );
}

/// The legacy projection's own facts in the same three-field shape.
SessionHeadFacts legacyFactsOf(SessionProjection legacy) => SessionHeadFacts(
  isTerminal: legacy.isTerminal,
  completed: legacy.completed,
  humanHeld: legacy.humanHeld,
  closedAt: legacy.closedAt,
);

/// THE OVERLAY (§0.3): [legacy] as BASE with [head] overriding exactly
/// `{isTerminal, completed, humanHeld, closedAt}` — and nothing else.
///
/// What is deliberately NOT overridden, each for a proven reason:
///
///   * **`pgid`/`pid`/`token`** (r4 — J6-B1/J7-B1): `staleFences` falls back to
///     the SCALAR session fence whenever the per-node list is empty — which,
///     since `SessionProjection.cursor` is never populated in production, IS
///     the live path — and `_staleFencesAreDead` returns TRUE on an empty
///     list. P1 SET-NULLs pid/pgid on `attempt.process.exited`, so an overlaid
///     null would yield zero fences, vacuously pass the deadness proof, and
///     authorize spawning over a possibly-live process group. The fence
///     identity triple stays WHOLE on its legacy carrier: one provenance,
///     never spliced across carriers.
///   * **`workTerminalReason`** (r5 — J9-B2): the two sides do not carry the
///     same fact. Legacy projects it only from `grid.work_terminal_reason`,
///     which only the work-bead-closed settle writes; P1 takes ANY terminal's
///     reason, and `_escalateAndClose` stores its reason under a DIFFERENT bd
///     key that never reaches the legacy field. Every escalated session would
///     read legacy-null vs P1-`<reason>` — a divergence BY CONSTRUCTION on
///     exactly the shape the gates make mandatory. Compare-only.
///   * **`round`** (F-M1): P1's `round` is the retired-INTO marker, 0 on every
///     live head. Round parity is a `bySessionId` check on RETIRED rows.
///   * `token`, `results`, `startedAt`, molecule/gate attachments, the cursor —
///     all still written by live carriers in wave 1.
///
/// Returns [legacy] UNCHANGED (identical instance) whenever the overlay would
/// be unsafe: a reconstructed-provenance head (fold bookkeeping, never
/// decision state) or any demotion of a terminal-family fact.
SessionProjection sessionProjectionOverlay(
  SessionProjection legacy,
  SessionHeadView head,
) => resolveSessionOverlay(legacy, head).projection;

/// Why [resolveSessionOverlay] served what it served — the accounting axis C3
/// needs and the reason a soak round can be read: "how many decisions did the
/// fold actually change, and how many did a rule refuse?"
enum SessionOverlayOutcome {
  /// P1 won inside the certified field set and the served projection DIFFERS
  /// from the legacy one. Under `primary` this is the entry the join splices.
  applied,

  /// Both sides already say the same thing on all four fields, so the overlay
  /// is the identity: legacy is served, and the fold changed no decision.
  /// The overwhelmingly common case, and the reason `primary` is quiet.
  agreed,

  /// THE RECONSTRUCTED SUPPRESSOR (r5/r7 — J8-B1, V1-B2): the head's terminal
  /// is TESTIMONY, so pure legacy is served and the pair is adjudicated.
  suppressedReconstructed,

  /// MONOTONIC TERMINALITY (r3 — F-B4) refused a demotion: legacy says
  /// terminal, P1 has not folded it yet. Pure legacy, and the comparator calls
  /// it `terminalLag`.
  suppressedDemotion,
}

/// One resolved overlay — the projection to serve plus WHY.
@immutable
final class SessionOverlayResult {
  const SessionOverlayResult({required this.projection, required this.outcome});

  /// What a decision reads. Identical to the legacy instance unless
  /// [outcome] is [SessionOverlayOutcome.applied].
  final SessionProjection projection;

  final SessionOverlayOutcome outcome;

  /// True when the served projection differs from the legacy base.
  bool get changed => outcome == SessionOverlayOutcome.applied;

  /// True when a RULE declined the merge — the two suppressor classes, which
  /// are the ones a round summary must be able to count separately from plain
  /// agreement.
  bool get suppressed =>
      outcome == SessionOverlayOutcome.suppressedReconstructed ||
      outcome == SessionOverlayOutcome.suppressedDemotion;
}

/// THE OVERLAY, resolved — [sessionProjectionOverlay] plus the reason.
///
/// C3 serves this; C2 counted it. Both call the SAME function, so what the
/// soak certified under `observe` is byte-identical to what `primary` serves —
/// which is the entire point of running the observe window first.
SessionOverlayResult resolveSessionOverlay(
  SessionProjection legacy,
  SessionHeadView head,
) {
  // THE RECONSTRUCTED SUPPRESSOR (r5/r7): pure legacy, adjudicated elsewhere.
  if (head.terminalProvenance == SessionHeadProvenance.reconstructed) {
    return SessionOverlayResult(
      projection: legacy,
      outcome: SessionOverlayOutcome.suppressedReconstructed,
    );
  }
  final facts = sessionHeadFactsOf(head);
  if (demotesTerminalFact(legacy, facts)) {
    return SessionOverlayResult(
      projection: legacy,
      outcome: SessionOverlayOutcome.suppressedDemotion,
    );
  }
  final closedAt = facts.closedAt ?? legacy.closedAt;
  if (facts.isTerminal == legacy.isTerminal &&
      facts.completed == legacy.completed &&
      facts.humanHeld == legacy.humanHeld &&
      closedAt == legacy.closedAt) {
    // The IDENTITY case, returned as the legacy INSTANCE rather than an equal
    // copy: the join's map then holds the very object pure legacy would have
    // held, so "primary changed nothing here" is provable by reference.
    return SessionOverlayResult(
      projection: legacy,
      outcome: SessionOverlayOutcome.agreed,
    );
  }
  return SessionOverlayResult(
    projection: legacy.copyWith(
      isTerminal: facts.isTerminal,
      completed: facts.completed,
      humanHeld: facts.humanHeld,
      closedAt: closedAt,
    ),
    outcome: SessionOverlayOutcome.applied,
  );
}

/// MONOTONIC TERMINALITY's predicate, stated generally (§0.3): `isTerminal`
/// true→false, `completed` true→false and `humanHeld` true→false are demotions
/// the overlay never performs. A P1 value that would demote a legacy terminal
/// fact is a LAG SIGNAL, never a served decision.
bool demotesTerminalFact(SessionProjection legacy, SessionHeadFacts facts) =>
    (legacy.isTerminal && !facts.isTerminal) ||
    (legacy.completed && !facts.completed) ||
    (legacy.humanHeld && !facts.humanHeld);

// ── the comparator ────────────────────────────────────────────────────────

/// What ONE compared pair resolved to.
///
/// The GATE ARITHMETIC (§0.3) reads these classes directly: soak gates count
/// [divergence] only; every LAG class ([terminalLag], [retirementLag]) must be
/// zero at round end; the two ADJUDICATION classes
/// ([incumbentAdjudication], [reconstructedTerminal]) need a logged
/// disposition each but a nonzero count does not dirty the round.
enum DualReadClass {
  /// The derived tuples agree.
  match,

  /// A served-tuple mismatch — the only class the soak gates count.
  divergence,

  /// Legacy terminal, P1 open — the bd-first/append-later window. Healed by
  /// `terminal-reconcile` at the 90 s grace; escalates ONLY on heal failure or
  /// survival past the heal (§0.3's ONE escalation rule).
  terminalLag,

  /// A `p1Orphan` CURRENT-open row whose session bead is `#rN`/`#void-`
  /// re-keyed: the window between the re-key and `roundRetired` landing.
  retirementLag,

  /// Two same-bead sessions coexist and the legacy incumbent picked its winner
  /// by MAP ITERATION ORDER (`_projectOwnedSessions`' own doc). Logged with
  /// both identities and adjudicated — the incumbent rule ("the fold is
  /// presumed wrong") applies only where the incumbent is deterministic.
  incumbentAdjudication,

  /// The head's terminal is reconstructed TESTIMONY (the durable column).
  /// Pure legacy is served and the mismatch is adjudicated, never counted.
  reconstructedTerminal,

  /// More than one CURRENT open row on one bead — a genuine double-mount.
  cardinality,
}

/// One field-level mismatch, rendered for the flare payload and the round
/// summary. Values are stringified because that is what both surfaces carry.
@immutable
final class DualReadFieldMismatch {
  const DualReadFieldMismatch({
    required this.field,
    required this.foldValue,
    required this.legacyValue,
  });

  final String field;
  final String foldValue;
  final String legacyValue;

  @override
  String toString() => '$field(fold=$foldValue, legacy=$legacyValue)';
}

/// The result of comparing one legacy projection against its identity-matched
/// P1 head.
@immutable
final class DualReadComparison {
  const DualReadComparison({
    required this.sessionId,
    required this.workBeadId,
    required this.classification,
    this.mismatches = const <DualReadFieldMismatch>[],
    this.pgidPresenceAgrees = true,
    this.foldWorkTerminalReason,
    this.legacyWorkTerminalReason,
  });

  final String sessionId;
  final String workBeadId;
  final DualReadClass classification;
  final List<DualReadFieldMismatch> mismatches;

  /// The pgid/pid PRESENCE pair — observed, never served (§0.3). False means
  /// one side holds an identity the other does not; informational only.
  final bool pgidPresenceAgrees;

  /// Compare-only informational columns (r5 — J9-B2), reported in the round
  /// summary and never counted as a divergence.
  final String? foldWorkTerminalReason;
  final String? legacyWorkTerminalReason;

  bool get isDivergence => classification == DualReadClass.divergence;
}

/// Compares the DERIVED tuple `(isTerminal, humanHeld, completed, sessionId)`
/// on both sides, plus the pgid/pid presence pair and the compare-only
/// `work_terminal_reason` column.
///
/// The classification precedence is the design's own order of suppressors:
/// the reconstructed mark first (it is DURABLE and immune to settlement), then
/// monotone terminality's lag, then the tuple.
DualReadComparison compareHeadToProjection(
  SessionProjection legacy,
  SessionHeadView head,
) {
  final fold = sessionHeadFactsOf(head);
  final incumbent = legacyFactsOf(legacy);
  final mismatches = <DualReadFieldMismatch>[
    if (fold.isTerminal != incumbent.isTerminal)
      DualReadFieldMismatch(
        field: 'isTerminal',
        foldValue: '${fold.isTerminal}',
        legacyValue: '${incumbent.isTerminal}',
      ),
    if (fold.humanHeld != incumbent.humanHeld)
      DualReadFieldMismatch(
        field: 'humanHeld',
        foldValue: '${fold.humanHeld}',
        legacyValue: '${incumbent.humanHeld}',
      ),
    if (fold.completed != incumbent.completed)
      DualReadFieldMismatch(
        field: 'completed',
        foldValue: '${fold.completed}',
        legacyValue: '${incumbent.completed}',
      ),
    if (head.sessionId != (legacy.sessionId ?? ''))
      DualReadFieldMismatch(
        field: 'sessionId',
        foldValue: head.sessionId,
        legacyValue: legacy.sessionId ?? '',
      ),
  ];
  final classification = () {
    if (head.terminalProvenance == SessionHeadProvenance.reconstructed) {
      return DualReadClass.reconstructedTerminal;
    }
    if (incumbent.isTerminal && head.isOpen) return DualReadClass.terminalLag;
    return mismatches.isEmpty ? DualReadClass.match : DualReadClass.divergence;
  }();
  return DualReadComparison(
    sessionId: head.sessionId,
    workBeadId: head.workBeadId,
    classification: classification,
    mismatches: List.unmodifiable(mismatches),
    // A presence PAIR, not a value compare: legacy's scalar fence is stamped
    // at SessionStarted and never cleared, while P1 SET-NULLs on exit. The
    // pair disagreeing is expected after an exit and says nothing about a
    // decision — which is exactly why neither field is served.
    pgidPresenceAgrees: (head.pgid != null) == (legacy.pgid != null),
    foldWorkTerminalReason: head.workTerminalReason,
    legacyWorkTerminalReason: legacy.workTerminalReason,
  );
}

// ── the miss classifier (B-M5) ────────────────────────────────────────────

/// Why a bead-projected session has no P1 row.
enum DualReadMissClass {
  /// Started AFTER this station first claimed an epoch and still has no head —
  /// the population gate (c) counts, and the only way to reach it is a dropped
  /// append (which disqualifies the round independently).
  postEpoch,

  /// Started before the first epoch claim, or with no `started_at` at all —
  /// its missing head is not a defect.
  legacyEra,
}

/// One miss's classification: its era plus whether the projection's
/// `startedAt` was NULL.
///
/// A null-started POST-epoch projection is classified [legacyEra] and counted
/// separately under `nullStartedAt`, so corruption stays visible without
/// poisoning the post-epoch-miss gate (B-M5).
typedef DualReadMiss = ({DualReadMissClass era, bool nullStartedAt});

/// Classifies one miss against the station's first epoch claim.
DualReadMiss classifyDualReadMiss(
  SessionProjection legacy,
  DateTime? firstEpochClaimedAt,
) {
  final startedAt = legacy.startedAt;
  if (startedAt == null) {
    return (era: DualReadMissClass.legacyEra, nullStartedAt: true);
  }
  // No epoch boundary known (an unseeded snapshot) — nothing post-epoch can be
  // asserted, so the honest reading is legacy-era rather than a gate failure.
  if (firstEpochClaimedAt == null) {
    return (era: DualReadMissClass.legacyEra, nullStartedAt: false);
  }
  return (
    era: startedAt.isBefore(firstEpochClaimedAt)
        ? DualReadMissClass.legacyEra
        : DualReadMissClass.postEpoch,
    nullStartedAt: false,
  );
}

/// True when [workBeadKey] is a RETIRED session key — `<bead>#rN` or
/// `<bead>#void-<sessionId>`.
///
/// Authored against the two key-shape helpers in `rework.dart`
/// ([reworkKeyFor] / [voidKeyFor]) rather than re-deriving either grammar: a
/// retired key is exactly "carries a `#` suffix", and both shapes normalize to
/// the immutable base id.
bool isRetiredWorkBeadKey(String workBeadKey) => workBeadKey.contains('#');

// ── the accounting (§0.4's per-boot counters) ─────────────────────────────

/// The harness's append counters, as the round summary reports them (§0.4's
/// "drops" field, C3's soak-gate arithmetic).
///
/// A record rather than an import: `grid_engine` names no harness type, and
/// the gate only ever reads these as numbers. `dropped > 0` disqualifies a
/// round on its own — a dropped append is a fold hole no comparator can see.
typedef DualReadAppendStats = ({
  int appended,
  int deduped,
  int dropped,
  int suppressed,
  int refusedTestimony,
  int queueDepth,
});

/// The per-boot dual-read counters — the durable round summary's payload.
///
/// GAUGE vs ACCUMULATOR is a deliberate split, and the reason is the join's
/// cadence: `_join` recomputes on EVERY snapshot emission on either axis, so a
/// hit counted per pass would inflate into meaninglessness within a minute.
/// So the per-pass populations (hits, misses, fallbacks, orphans, open lag
/// entries) are GAUGES of the LAST pass — which is what "lag classes zero at
/// round end" is actually asking about — while the event classes are
/// ACCUMULATORS deduped by `(sessionId, field)`, so a divergence that persists
/// across a hundred passes counts, and flares, exactly once.
class DualReadAccounting {
  DualReadAccounting({this.eventKeyBound = 4096});

  /// The bound on the dedupe key set — a busy boot must not grow it forever.
  /// Past it the oldest keys are evicted, so a long-lived divergence may flare
  /// a second time; that is the correct failure direction (louder, never
  /// quieter).
  final int eventKeyBound;

  /// Comparator passes run this boot.
  int passes = 0;

  /// THE OVERLAY DISENGAGE LATCH (§0.2's wave-1 health semantics, C3).
  ///
  /// Any non-`live` snapshot health disengages the overlay FOR THE BOOT:
  /// decisions ride pure legacy — still fully written, still authoritative,
  /// because wave 1 retires nothing — with the loud flare the harness already
  /// raised at the latch and this round-summary field.
  ///
  /// It lives on the ACCOUNTING because the accounting is the one per-boot
  /// object both readers share: the bridge's comparator and the reconciler's
  /// must never disagree about whether this boot is serving the fold.
  /// Latched, never lifted — a health that recovers does not re-engage a boot
  /// whose mirror already missed an append.
  bool overlayDisengaged = false;

  // Gauges — the LAST pass's populations.
  int hits = 0;
  int missPostEpoch = 0;
  int missLegacyEra = 0;
  int nullStartedAt = 0;
  int fallbacks = 0;
  int p1Orphan = 0;
  int openTerminalLag = 0;
  int openRetirementLag = 0;
  int maxTerminalLagMs = 0;
  int maxRetirementLagMs = 0;

  /// Identity-matched heads whose overlay CHANGED the projection this pass —
  /// under `observe` the count of decisions `primary` WOULD have changed,
  /// under `primary` the count it did. Same function on both sides, so the
  /// observe window's number is the flip's forecast.
  ///
  /// **Read it beside [divergences], and expect them to move together.** The
  /// overlay changes a projection exactly when the derived tuples disagree,
  /// which is the comparator's definition of a divergence (the one exception
  /// is a `closedAt`-only difference, which is outside the tuple). So a CLEAN
  /// round under `primary` serves almost nothing, and that is the correct
  /// reading rather than a wiring doubt: what the flip buys is a certified
  /// carrier for wave 2, not different decisions. A round where this number
  /// runs ahead of `divergences` by more than the `closedAt` cases is the
  /// shape worth investigating.
  int overlaysApplied = 0;

  /// Of those, how many were actually spliced into the sessions map. Zero
  /// under `observe`, zero while [overlayDisengaged], and equal to
  /// [overlaysApplied] on a clean `primary` pass — the difference is exactly
  /// the retracted-by-cardinality set.
  int overlaysServed = 0;

  /// Identity-matched heads a RULE declined to merge: the reconstructed
  /// suppressor, the monotone-terminality guard, or a cardinality retraction.
  int overlaysSuppressed = 0;

  // Accumulators — deduped events across the boot.
  int divergences = 0;
  int terminalLagObserved = 0;
  int retirementLagObserved = 0;
  int incumbentAdjudications = 0;
  int reconstructedTerminals = 0;
  int cardinalityBreaches = 0;
  int healsAppended = 0;
  int healsSkipped = 0;
  int healsFailed = 0;
  int healEscalations = 0;
  int reconstructedTerminalSkipped = 0;
  int teardownReplayAppends = 0;

  // ── the STEP AXIS (C4) — the same object, because one boot owes one
  // durable round summary and a gate reads both axes out of it.
  //
  // Same GAUGE/ACCUMULATOR split as above: the populations are the last
  // pass's, the event classes are deduped across the boot by
  // `(sessionId, stepPath)`.

  /// Step comparator passes run this boot.
  int stepPasses = 0;

  /// Live sessions whose P2 rows were found by the identity lookup.
  int stepHits = 0;

  /// Live sessions served from their bead cursor: no same-session P2 rows at
  /// all, or the step axis disengaged for the boot.
  int stepFallbacks = 0;

  /// Sessions whose `trajCursor` was spliced into the map this pass — zero
  /// under `observe`, zero while disengaged.
  int stepCursorsServed = 0;

  /// Nodes the BEAD carries with no P2 row — the per-node P2-miss rule's
  /// counter. Never a default and never an omission: the node stays in the
  /// effective cursor with its bead state, because an omitted node reads as
  /// unclaimed and is re-mounted (I-10).
  int p2Miss = 0;

  /// P2 rows for a node path the legacy session does not carry. Dropped from
  /// the effective cursor (the overlay never creates on this axis either) and
  /// counted, like a `p1Orphan` head.
  int p2Orphan = 0;

  /// The LIVE `stepLag` population — §0.3 gate (b), "all lag classes zero at
  /// round end", now including the step axis (r5).
  int openStepLag = 0;
  int maxStepLagMs = 0;

  /// Deduped step-axis events across the boot.
  int stepLagObserved = 0;
  int stepLagEscalations = 0;
  int stepDivergences = 0;

  final Map<String, int> divergencesByField = <String, int>{};

  /// Health transitions witnessed (`live→compromised`, a refused seed, …) —
  /// §0.4's "health transitions" field.
  final List<String> healthTransitions = <String>[];

  final Set<String> _seenEvents = <String>{};

  /// Records a deduped EVENT, returning true the first time this boot sees it
  /// — which is also the signal to flare. The dedupe key is the caller's:
  /// `<class>:<sessionId>:<field>`.
  bool noteEvent(String key) {
    if (!_seenEvents.add(key)) return false;
    if (_seenEvents.length > eventKeyBound) {
      _seenEvents.remove(_seenEvents.first);
    }
    return true;
  }

  /// Zeroes the per-pass GAUGES. Accumulators and the dedupe set survive —
  /// they are the boot's record, not the pass's.
  void beginPass() {
    passes += 1;
    hits = 0;
    missPostEpoch = 0;
    missLegacyEra = 0;
    nullStartedAt = 0;
    fallbacks = 0;
    p1Orphan = 0;
    openTerminalLag = 0;
    openRetirementLag = 0;
    overlaysApplied = 0;
    overlaysServed = 0;
    overlaysSuppressed = 0;
  }

  /// Zeroes the STEP pass's gauges. Separate from [beginPass] because the two
  /// passes are separate calls over the same join, and a step pass that never
  /// ran (no P2 snapshot composed) must leave the session gauges alone.
  void beginStepPass() {
    stepPasses += 1;
    stepHits = 0;
    stepFallbacks = 0;
    stepCursorsServed = 0;
    p2Miss = 0;
    p2Orphan = 0;
    openStepLag = 0;
  }

  /// Folds one comparison into the counters, returning true when this was a
  /// FIRST observation of an event class (the flare signal).
  bool record(DualReadComparison comparison) {
    switch (comparison.classification) {
      case DualReadClass.match:
        return false;
      case DualReadClass.divergence:
        var first = false;
        for (final mismatch in comparison.mismatches) {
          final key = 'divergence:${comparison.sessionId}:${mismatch.field}';
          if (noteEvent(key)) {
            first = true;
            divergences += 1;
            divergencesByField[mismatch.field] =
                (divergencesByField[mismatch.field] ?? 0) + 1;
          }
        }
        return first;
      case DualReadClass.terminalLag:
        openTerminalLag += 1;
        if (noteEvent('terminalLag:${comparison.sessionId}')) {
          terminalLagObserved += 1;
          return true;
        }
        return false;
      case DualReadClass.retirementLag:
        openRetirementLag += 1;
        if (noteEvent('retirementLag:${comparison.sessionId}')) {
          retirementLagObserved += 1;
          return true;
        }
        return false;
      case DualReadClass.incumbentAdjudication:
        if (noteEvent('incumbent:${comparison.sessionId}')) {
          incumbentAdjudications += 1;
          return true;
        }
        return false;
      case DualReadClass.reconstructedTerminal:
        if (noteEvent('reconstructed:${comparison.sessionId}')) {
          reconstructedTerminals += 1;
          return true;
        }
        return false;
      case DualReadClass.cardinality:
        fallbacks += 1;
        if (noteEvent('cardinality:${comparison.workBeadId}')) {
          cardinalityBreaches += 1;
          return true;
        }
        return false;
    }
  }

  /// Every LAG class's live population — §0.3's gate (b), "all lag classes
  /// must be zero at round end". `stepLag` joins the arithmetic in C4 (r5),
  /// so a gate reading this ONE number covers both axes.
  int get openLagEntries => openTerminalLag + openRetirementLag + openStepLag;

  /// The durable round summary's body (§0.4). JSON so `traj show` and the
  /// `/status` block read the SAME shape, and so a gate can diff two rounds
  /// mechanically rather than by eye.
  ///
  /// C3's soak gate reads FIVE numbers out of this and nothing else:
  /// `divergences` = 0, `append_drops` = 0, `miss_post_epoch` = 0,
  /// `terminal_lag_open` + `retirement_lag_open` = 0 at round end, and
  /// `overlay_engaged` = true (a round that quietly rode legacy certifies
  /// nothing about serving the fold).
  Map<String, Object?> toJson({
    required DualReadMode mode,
    required TrajectorySnapshotHealth health,
    required int snapshotVersion,
    int? snapshotRows,
    DateTime? seededAt,
    String? scope,
    bool overlayEngaged = false,
    bool stepAxisEngaged = false,
    DualReadAppendStats? appendStats,
  }) => <String, Object?>{
    'channel': kDualReadRoundSummaryChannel,
    // BOTH axes ride one note (C4: "the round summary gains the step axis").
    // The key stays `axis` so an existing reader keeps parsing, and the step
    // block below is additive — a C2/C3-era summary simply carries zeros.
    'axis': 'session+step',
    if (scope != null) 'scope': scope,
    'mode': mode.name,
    'health': health.name,
    // WHAT THE ROUND ACTUALLY SERVED, never what it was configured to serve:
    // `mode: primary` with `overlay_engaged: false` is a boot that disengaged
    // on health, and reading the two together is how a gate tells a certified
    // round from a silently-legacy one.
    'overlay_engaged': overlayEngaged,
    'overlay_disengaged_for_boot': overlayDisengaged,
    'snapshot_version': snapshotVersion,
    if (snapshotRows != null) 'snapshot_rows': snapshotRows,
    if (seededAt != null) 'seeded_at': seededAt.toUtc().toIso8601String(),
    'passes': passes,
    'hits': hits,
    'miss_post_epoch': missPostEpoch,
    'miss_legacy_era': missLegacyEra,
    'null_started_at': nullStartedAt,
    'fallbacks': fallbacks,
    'p1_orphan': p1Orphan,
    'overlays_applied': overlaysApplied,
    'overlays_served': overlaysServed,
    'overlays_suppressed': overlaysSuppressed,
    'divergences': divergences,
    'divergences_by_field': Map<String, int>.from(divergencesByField),
    'terminal_lag': terminalLagObserved,
    'terminal_lag_open': openTerminalLag,
    'terminal_lag_max_ms': maxTerminalLagMs,
    'retirement_lag': retirementLagObserved,
    'retirement_lag_open': openRetirementLag,
    'retirement_lag_max_ms': maxRetirementLagMs,
    'incumbent_adjudications': incumbentAdjudications,
    'reconstructed_terminals': reconstructedTerminals,
    'reconstructed_terminal_skipped': reconstructedTerminalSkipped,
    'teardown_replay_appends': teardownReplayAppends,
    'cardinality_breaches': cardinalityBreaches,
    'heals_appended': healsAppended,
    'heals_skipped': healsSkipped,
    'heals_failed': healsFailed,
    'heal_escalations': healEscalations,
    'health_transitions': List<String>.from(healthTransitions),
    // THE STEP AXIS (C4). Same arithmetic as the session axis, one ladder
    // down: gates count `step_divergences` only, `step_lag_open` must be zero
    // at round end, and `step_axis_engaged` distinguishes a certified round
    // from one that quietly rode the bead cursor under `mode: primary`.
    'step_axis_engaged': stepAxisEngaged,
    'step_passes': stepPasses,
    'step_hits': stepHits,
    'step_fallbacks': stepFallbacks,
    'step_cursors_served': stepCursorsServed,
    'p2_miss': p2Miss,
    'p2_orphan': p2Orphan,
    'step_divergences': stepDivergences,
    'step_lag': stepLagObserved,
    'step_lag_open': openStepLag,
    'step_lag_max_ms': maxStepLagMs,
    'step_lag_escalations': stepLagEscalations,
    // THE APPEND SIDE (§0.4's "drops"). The comparator cannot see a dropped
    // append — the hole it leaves in the fold looks exactly like a session
    // that never happened — so the gate reads the harness's own counters, on
    // the same durable vehicle, in the same round.
    if (appendStats != null) ...<String, Object?>{
      'appends': appendStats.appended,
      'append_dedupes': appendStats.deduped,
      'append_drops': appendStats.dropped,
      'append_suppressed': appendStats.suppressed,
      'append_refused_testimony': appendStats.refusedTestimony,
      'append_queue_depth': appendStats.queueDepth,
    },
  };

  /// The note body — the JSON above, encoded. Deterministic key order (the
  /// literal's order), so two rounds diff cleanly.
  String toNoteBody({
    required DualReadMode mode,
    required TrajectorySnapshotHealth health,
    required int snapshotVersion,
    int? snapshotRows,
    DateTime? seededAt,
    String? scope,
    bool overlayEngaged = false,
    bool stepAxisEngaged = false,
    DualReadAppendStats? appendStats,
  }) => jsonEncode(
    toJson(
      mode: mode,
      health: health,
      snapshotVersion: snapshotVersion,
      snapshotRows: snapshotRows,
      seededAt: seededAt,
      scope: scope,
      overlayEngaged: overlayEngaged,
      stepAxisEngaged: stepAxisEngaged,
      appendStats: appendStats,
    ),
  );
}

// ── the terminal-reconcile trigger (r8 — V2-B1, r9 — V3-B1) ───────────────

/// What the tracker says to do about one `terminalLag` entry this pass.
enum TerminalLagAction {
  /// Inside the grace, or fewer than two passes deep, or an append for this
  /// attempt is still QUEUED — watch, do nothing. The normal terminal window
  /// lives entirely here.
  watch,

  /// Past the 90 s grace across at least two comparator passes with no queued
  /// append: append the `terminal-reconcile` heal.
  heal,

  /// The heal FAILED, or the entry survived one further full comparator pass
  /// after a heal that landed. This is the only path to a divergence flare —
  /// escalation signals RECONCILE FAILURE, never the normal window.
  escalate,
}

/// How a heal attempt resolved, reported back by the (async) healer.
///
/// THE ESCALATION SPLIT lives on this enum: only a heal ATTEMPT that reached
/// the log — [appended] or [failed] — arms the one-further-pass escalation.
/// A `skipped*` member is a COUNTED ADJUDICATION STATE: the entry stays
/// lag-classed and never becomes a divergence, because no heal was attempted
/// and a skip is evidence about the WORLD, not about a repair that failed.
///
/// THE SECOND SPLIT (r13) is between the skips: all but one report an
/// UNCHANGING world fact and therefore latch the entry for the boot;
/// [skippedUnavailable] reports a transient fact about the HARNESS and
/// deliberately does not, so the heal is re-requested rather than forgone.
enum TerminalReconcileOutcome {
  /// The reconstructed close landed.
  appended,

  /// The `traj_terminal_guard` pre-check found a terminal row already there —
  /// the real record landed and the head is merely folding. PURE LAG: skip and
  /// count, no append, no escalation.
  skippedGuard,

  /// No attempt id on the P1 head (the head predates process start).
  /// `AttemptTerminal.attemptId` is required and no id is ever minted here.
  ///
  /// PERMANENTLY unhealable — no attempt id will ever appear for such a head —
  /// which is exactly why it must never escalate: an unsatisfiable gate is the
  /// defect class r3/r5/r8 kept re-fixing.
  skippedNoAttemptId,

  /// No healer is wired on this boot at all, so no `traj_terminal_guard` was
  /// ever read. Its OWN member rather than [skippedGuard]: the durable round
  /// evidence must not assert a guard fact nobody observed.
  skippedNoHealer,

  /// THE TRANSIENT SKIP (r13): the healer is wired and the entry is healable,
  /// but the harness was momentarily not accepting — not `live`, or already
  /// shutting down — so no guard was read and nothing was appended.
  ///
  /// The ONLY `skipped*` member that does NOT latch the entry. Every other one
  /// reports an unchanging fact about the WORLD (a guard row is there; no
  /// attempt id will ever appear; no healer is wired this boot), so re-asking
  /// could only re-derive the same answer. This one reports a fact about the
  /// HARNESS at one instant, and reporting it as a guard fact forgave the
  /// repair for the rest of the boot: the entry stayed permanently lag-classed
  /// and never re-requested the heal once the harness returned to `live`.
  skippedUnavailable,

  /// The append itself failed.
  failed,
}

/// One heal request, handed to the (async, store-touching) healer through an
/// emit-only sink. The bridge decides WHETHER; the healer's guard pre-check
/// decides whether the append is admissible.
@immutable
final class TerminalReconcileRequest {
  const TerminalReconcileRequest({
    required this.sessionId,
    required this.attemptId,
    required this.workBeadId,
    required this.report,
  });

  final String sessionId;

  /// From THE P1 HEAD'S OWN `attempt_id` column (written at
  /// `attempt.process.started`) — never the `grid.lease.*` breadcrumb, which
  /// is cleared on a normal lease release, and never minted.
  final String attemptId;

  final String workBeadId;

  /// Emit-only completion: the healer reports what happened so the tracker can
  /// decide between "healed" and "escalate".
  final void Function(TerminalReconcileOutcome outcome) report;
}

typedef TerminalReconcileHealer =
    void Function(TerminalReconcileRequest request);

class _TerminalLagEntry {
  _TerminalLagEntry(this.firstSeenAt);

  final DateTime firstSeenAt;
  int passes = 0;
  int passesSinceHeal = 0;
  bool healAttempted = false;
  bool healFailed = false;
  bool escalated = false;

  /// A heal was declined before it reached the log (guard row present, no
  /// attempt id, no healer). The entry is LAG for the rest of its life: it
  /// never escalates, and it never asks for a second heal it would decline
  /// again on the same unchanged fact.
  bool healSkipped = false;
}

/// THE ONE ESCALATION RULE, mechanized (§0.3 MONOTONIC TERMINALITY, r8).
///
/// Tracks each lagging session across comparator passes and answers exactly
/// one question per pass: watch, heal, or escalate. It owns no clock and no
/// store — the caller supplies `now` and the "is an append still queued"
/// answer, both of which are facts about the world this pure tracker cannot
/// have.
class TerminalLagTracker {
  TerminalLagTracker({this.grace = kTerminalLagHealGrace});

  final Duration grace;
  final Map<String, _TerminalLagEntry> _entries = <String, _TerminalLagEntry>{};

  /// The sessions currently lagging, and the age of the oldest.
  int get openEntries => _entries.length;

  /// Observes [sessionId] as still lagging at [now] and returns the action.
  ///
  /// [appendQueued] is the harness's answer for THIS attempt: a queued append
  /// means the real record is still on its way, so the heal must not race it.
  TerminalLagAction observe(
    String sessionId, {
    required DateTime now,
    required bool appendQueued,
  }) {
    final entry = _entries.putIfAbsent(sessionId, () => _TerminalLagEntry(now));
    entry.passes += 1;
    if (entry.escalated) return TerminalLagAction.watch;
    // A SKIPPED heal is not a heal. The entry is counted lag from here to the
    // end of its life — no escalation (nothing was repaired, so nothing can
    // have failed to repair) and no second request against the same unchanged
    // fact.
    if (entry.healSkipped) return TerminalLagAction.watch;
    if (entry.healAttempted) {
      entry.passesSinceHeal += 1;
      // Heal failure escalates at once; a heal that LANDED gets one further
      // full comparator pass before the entry is called a reconcile failure.
      if (entry.healFailed || entry.passesSinceHeal >= 1) {
        entry.escalated = true;
        return TerminalLagAction.escalate;
      }
      return TerminalLagAction.watch;
    }
    if (appendQueued) return TerminalLagAction.watch;
    if (entry.passes < 2) return TerminalLagAction.watch;
    if (now.difference(entry.firstSeenAt) < grace) {
      return TerminalLagAction.watch;
    }
    return TerminalLagAction.heal;
  }

  /// The age of [sessionId]'s lag at [now] — 0 for a session not tracked.
  Duration ageOf(String sessionId, DateTime now) {
    final entry = _entries[sessionId];
    return entry == null ? Duration.zero : now.difference(entry.firstSeenAt);
  }

  /// Records how the heal resolved.
  ///
  /// ONLY A LANDED-OR-FAILED ATTEMPT ARMS ESCALATION (§0.3 MONOTONIC
  /// TERMINALITY, r8 — "escalation signals RECONCILE FAILURE, never the normal
  /// window"). [TerminalReconcileOutcome.appended] earns the one further full
  /// comparator pass; [TerminalReconcileOutcome.failed] escalates on the next
  /// pass. Every `skipped*` outcome latches the entry as counted LAG instead:
  /// no append was made, so there is no repair whose failure a divergence
  /// could be reporting — and `skippedNoAttemptId` in particular can NEVER be
  /// repaired, which would make the zero-divergence gate unsatisfiable on any
  /// board carrying a head that predates process start.
  void noteHealAttempted(String sessionId, TerminalReconcileOutcome outcome) {
    final entry = _entries[sessionId];
    if (entry == null) return;
    switch (outcome) {
      case TerminalReconcileOutcome.appended:
        entry.healAttempted = true;
        entry.passesSinceHeal = 0;
        entry.healFailed = false;
      case TerminalReconcileOutcome.failed:
        entry.healAttempted = true;
        entry.passesSinceHeal = 0;
        entry.healFailed = true;
      case TerminalReconcileOutcome.skippedGuard:
      case TerminalReconcileOutcome.skippedNoAttemptId:
      case TerminalReconcileOutcome.skippedNoHealer:
        entry.healSkipped = true;
      case TerminalReconcileOutcome.skippedUnavailable:
        // DELIBERATELY NO LATCH (r13): the harness was transiently not
        // accepting, which is a fact about this instant and not about the
        // entry. Leaving `healAttempted`/`healSkipped` alone lets the very
        // next pass re-request the heal once the harness is live again — the
        // repair C2 exists to perform is deferred, never forgone.
        break;
    }
  }

  /// The entry cleared — the head closed, so the lag healed on its own.
  void clear(String sessionId) => _entries.remove(sessionId);

  /// Drops every entry not observed in the pass that just ran. [seen] is the
  /// pass's lagging set.
  void retainOnly(Set<String> seen) =>
      _entries.removeWhere((sessionId, _) => !seen.contains(sessionId));
}

/// The RETIREMENT-lag twin, with the same 90 s grace and a simpler rule: the
/// entry heals when the row leaves the CURRENT partition, and ESCALATES to a
/// divergence only when the successor session is already present in P1 and the
/// row is STILL current past the grace (r9 — the retire-close runs at that
/// mint; its record must have dropped).
class RetirementLagTracker {
  RetirementLagTracker({this.grace = kRetirementLagGrace});

  final Duration grace;
  final Map<String, DateTime> _firstSeenAt = <String, DateTime>{};
  final Set<String> _escalated = <String>{};

  int get openEntries => _firstSeenAt.length;

  /// Observes [sessionId]'s retired-but-current row. Returns true exactly once
  /// when the entry earns its escalation to a divergence.
  bool observe(
    String sessionId, {
    required DateTime now,
    required bool successorPresent,
  }) {
    final first = _firstSeenAt.putIfAbsent(sessionId, () => now);
    if (!successorPresent) return false;
    if (now.difference(first) < grace) return false;
    return _escalated.add(sessionId);
  }

  Duration ageOf(String sessionId, DateTime now) {
    final first = _firstSeenAt[sessionId];
    return first == null ? Duration.zero : now.difference(first);
  }

  void retainOnly(Set<String> seen) {
    _firstSeenAt.removeWhere((sessionId, _) => !seen.contains(sessionId));
    _escalated.removeWhere((sessionId) => !seen.contains(sessionId));
  }
}
