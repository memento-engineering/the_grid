/// The Stage-1 derivation layer — stage1-wiring §2, mechanically.
///
/// [StationTrajectoryRecorder] is the ONLY Stage-1 code that names concrete
/// trajectory record classes. It exposes intent-named observation methods
/// (`sessionMinted`, `processExited`, …) that build the sealed record plus its
/// envelope correlation (§2.2) and hand the constructed record to the
/// harness's single-writer queue through a [TrajectoryRecordSink] — never a
/// second appender, never a second connection that writes.
///
/// **The §2.3 trigger discipline is encoded in the API shape** so call sites
/// cannot get it wrong:
///
///   * every method is a PAST-TENSE observation — it is called after the
///     legacy write it shadows has returned successfully (the recorder appends
///     only on legacy success, so the shadow never leads the incumbent);
///   * every method is synchronous `void` — there is nothing to await, so no
///     engine hot path can ever block on, or be reordered by, an append
///     (§2.5: enqueue, never await);
///   * every method is NON-FATAL by construction — derivation is wrapped, a
///     throw is counted and flared (`trajectory.deriveFailed`), and the legacy
///     path is entirely unaffected (§3).
///
/// **Recoverable identity only (§2.1).** The maps below — session-scope
/// attempt ids, round counters, mount sequences, note ordinals — are warm
/// caches of state that is recoverable from the `grid.lease.*` breadcrumbs
/// plus the log (last-row queries) plus persisted step-bead state. Losing them
/// loses nothing durable; boot-time recovery re-seeds them through
/// [seedSessionAttempt] / [seedRound].
library;

import 'package:grid_trajectory/grid_trajectory.dart';

import '../lifecycle/bead_ownership.dart';

/// The flare seam — shape-compatible with `ExplorationTransport.flare` (and
/// with the harness's rate-limited flare, which is what production passes).
typedef TrajectoryRecorderFlare =
    void Function(String name, Map<String, String> data);

/// The enqueue-only handle to the harness's bounded append queue (§2.5).
///
/// The derivation layer holds THIS, never the appender: the sink preserves the
/// sole-appender invariant (the harness's single writer loop is the only code
/// that touches `TrajectoryAppender`) and the non-blocking one ([enqueue] is
/// synchronous and returns immediately).
abstract interface class TrajectoryRecordSink {
  /// False once the harness latched (fenced out / halted), degraded, was
  /// disabled, or is shutting down — the recorder short-circuits derivation to
  /// a count instead of building records nobody will append (§3's "counting
  /// no-op" posture).
  bool get accepting;

  /// Hands one constructed record to the single writer and returns. Must
  /// never block and never throw into the caller.
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance,
    String? provenanceBasis,
  });
}

/// The seat stamped when no known prefix owns a work bead id (§2.2, r2 minor
/// 12) — deterministic, never CHECK-refused, so `ck_seat`'s presence rule
/// cannot turn an unowned id into a permanent clean-round blocker.
const String kUnownedSeat = 'unowned';

/// The payload marker accompanying [kUnownedSeat] (`seat_basis`).
const String kUnownedSeatBasis = 'no-owned-prefix';

/// The `grant_basis` payload marker on Stage-1 pre-grant ids (§2.2): no
/// grants exist before Stage 3, so the recorder mints a placeholder ULID per
/// mount and says so. At Stage 3 the real `admission.grant.issued` takes over
/// the same slot.
const String kPreStage3GrantBasis = 'pre-stage3';

/// `attempt_id_basis` for a settlement whose session predates Stage 1 — no
/// attempt_id breadcrumb exists, so the reconciler path mints one (§2.1's
/// bounce rule); such sessions are outside the shadow's comparable set.
const String kReconcilerMintedAttemptBasis = 'reconciler-minted';

/// `attempt_id_basis` for the defensive fallback: a terminal observed for a
/// session the recorder never saw minted and nobody seeded (should not happen
/// on a healthy boot — recovery seeds the cache first). Non-fatal law: mint
/// and mark rather than refuse.
const String kRecorderMintedAttemptBasis = 'recorder-minted';

/// The one `attempt.note` channel armed at Stage 1 (§2.3): the tick's
/// stuck-obligation accounting (schema §5's N-failure rule). The Q5
/// content-split for agent journaling is deferred.
const String kObligationStuckChannel = 'obligation-stuck';

/// The mount-attempt bead's durable counter key — wire-identical to
/// grid_engine's `MountAttemptKeys.count`, duplicated because grid_runtime
/// cannot import grid_engine (the same split the molecule join keys live
/// under). The recorder reads it into `legacy_attempt_count`, the
/// shadow-comparable ordinal `traj shadow-diff` joins against the legacy bead
/// (§2.2, r2 major 8).
const String kLegacyAttemptCountKey = 'grid.attempt.count';

/// A recorder status read — plain counters for the `/status` trajectory block.
final class TrajectoryRecorderStats {
  const TrajectoryRecorderStats({
    required this.derived,
    required this.skipped,
    required this.deriveFailures,
  });

  /// Records built and handed to the sink.
  final int derived;

  /// Observations short-circuited to a count because the sink was not
  /// accepting (latched / degraded / disabled — §3).
  final int skipped;

  /// Observations lost to a derivation throw — counted and flared, never
  /// propagated into the legacy path.
  final int deriveFailures;

  @override
  String toString() =>
      'TrajectoryRecorderStats(derived: $derived, skipped: $skipped, '
      'deriveFailures: $deriveFailures)';
}

/// The engine-side derivation layer (stage1-wiring §2), constructed by the
/// harness and injected everywhere as an OPTIONAL collaborator: disabled or
/// degraded it is a counting no-op, and no call site ever branches on "is the
/// trajectory up" (§1.1).
class StationTrajectoryRecorder {
  StationTrajectoryRecorder({
    required TrajectoryRecordSink sink,
    Set<String> seatPrefixes = const {},
    DateTime Function()? clock,
    TrajectoryRecorderFlare? onFlare,
  }) : _sink = sink,
       _seatPrefixes = Set<String>.unmodifiable(seatPrefixes),
       _clock = clock ?? DateTime.now,
       _onFlare = onFlare;

  /// The null-object (§1.1): a recorder whose sink never accepts. Every
  /// observation counts as skipped; nothing is ever built or enqueued.
  StationTrajectoryRecorder.disabled() : this(sink: const _NeverAccepting());

  final TrajectoryRecordSink _sink;

  /// The `allowSet` (§1.1) — input to [BeadOwnershipPredicate.ownedPrefixOf].
  /// Note it carries both identity axes (name and prefix); longest-match is
  /// deterministic but the resolved seat may be either axis (§2.2).
  final Set<String> _seatPrefixes;

  final DateTime Function() _clock;
  final TrajectoryRecorderFlare? _onFlare;

  // ── warm caches (§2.1 recoverability rule — never durable state) ─────────

  /// session id → session-scope attempt id (minted at session mint; re-seeded
  /// from the log's last session-scoped attempt row after a bounce).
  final Map<String, String> _sessionAttempts = <String, String>{};

  /// ORIGINAL work bead id → the same session-scope attempt id — the join
  /// `worktree.provisioned` uses, since `provisionWorktree` has only the work
  /// bead in hand (§2.2 worktree row).
  final Map<String, String> _workBeadAttempts = <String, String>{};

  /// session id → current round: seeded by parsing the `#rN` shape at first
  /// sight, bumped ONLY by the round-retired observation (§2.2).
  final Map<String, int> _rounds = <String, int>{};

  /// ORIGINAL work bead id → mount_attempt_id: one ULID spans ONE
  /// `SessionScope` mint sequence (§2.2); a successful mint or a terminal
  /// phase (exhausted/abandoned) ends the sequence.
  final Map<String, String> _mountSequences = <String, String>{};

  /// session id → last minted `attempt.note` ordinal (service-minted, §2.3).
  final Map<String, int> _noteOrdinals = <String, int>{};

  int _derived = 0;
  int _skipped = 0;
  int _deriveFailures = 0;

  TrajectoryRecorderStats get stats => TrajectoryRecorderStats(
    derived: _derived,
    skipped: _skipped,
    deriveFailures: _deriveFailures,
  );

  // ── boot-time cache seeding (§2.1) ───────────────────────────────────────

  /// Re-seeds the session-scope attempt id for [sessionId] — called by boot
  /// recovery with the log's last session-scoped attempt row, or with a
  /// breadcrumb-recovered id. Never invents identity: the value handed in
  /// must itself be recoverable.
  void seedSessionAttempt(String sessionId, String attemptId) {
    _sessionAttempts[sessionId] = attemptId;
  }

  /// Re-seeds the round counter for [sessionId] from the log after a bounce.
  void seedRound(String sessionId, int round) {
    _rounds[sessionId] = round;
  }

  // ── legacy-string normalization (§2.2 work_bead_id row) ──────────────────

  /// Splits a legacy `work_bead` string into the ORIGINAL immutable id and,
  /// for the `#rN` rework shape, the round it names. `#void-<sessionId>` and
  /// any unrecognized suffix normalize to the original id with no round —
  /// the record never carries a mutated key.
  static ({String workBeadId, int? round}) parseLegacyWorkKey(String raw) {
    final hash = raw.indexOf('#');
    if (hash <= 0) return (workBeadId: raw, round: null);
    final id = raw.substring(0, hash);
    final suffix = raw.substring(hash + 1);
    if (suffix.length > 1 && suffix.startsWith('r')) {
      final round = int.tryParse(suffix.substring(1));
      if (round != null) return (workBeadId: id, round: round);
    }
    return (workBeadId: id, round: null);
  }

  // ── attempt family builders (§2.3, top of the table down) ────────────────

  /// `attempt.session.started` — after `createSession`'s birth-stamping merge
  /// (site: `station_bead_writer.dart` createSession's sole caller).
  ///
  /// [workBeadId] may be the raw legacy string (`#rN` tolerated — it seeds the
  /// round counter at first sight and is stripped from the record).
  /// [mountAttemptMetadata] is the legacy mount-attempt bead's metadata; the
  /// recorder reads `grid.attempt.count` out of it as `legacy_attempt_count`.
  void sessionMinted({
    required String sessionId,
    required String workBeadId,
    required String rig,
    required String model,
    Map<String, dynamic> mountAttemptMetadata = const {},
    DateTime? occurredAt,
  }) {
    _observe('sessionMinted', () {
      final parsed = parseLegacyWorkKey(workBeadId);
      _rounds.putIfAbsent(sessionId, () => parsed.round ?? 0);
      final attemptId = _sessionAttempts[sessionId] ??= _mintUlid();
      _workBeadAttempts[parsed.workBeadId] = attemptId;
      // A successful mint CONSUMES the mount sequence (§2.2): the next mint
      // sequence for this work bead gets a fresh ULID.
      final mountAttemptId =
          _mountSequences.remove(parsed.workBeadId) ?? _mintUlid();
      final seat = _seatOf(parsed.workBeadId);
      _enqueue(
        AttemptSessionStarted(
          sessionId: sessionId,
          // Stage-1 placeholder (§2.2 grant_id row): ck_grant_link wants a
          // grant id but no grants exist before Stage 3 — a fresh pre-grant
          // ULID per mount, payload-marked.
          grantId: _mintUlid(),
          grantBasis: kPreStage3GrantBasis,
          rig: rig,
          model: model,
          workBeadId: parsed.workBeadId,
          mountAttemptId: mountAttemptId,
          legacyAttemptCount: _legacyAttemptCount(mountAttemptMetadata),
          seatBasis: seat.basis,
        ),
        seat: seat.seat,
        occurredAt: occurredAt,
      );
    });
  }

  /// `attempt.process.started` — from the `SessionStarted` runtime event; the
  /// attempt id is the event's breadcrumb-backed field (§2.1), and
  /// [predecessorAttemptId] is the outgoing breadcrumb's id on a succession,
  /// recovered by the caller from breadcrumb/log — not from memory alone.
  void processStarted({
    required String attemptId,
    required String sessionId,
    required int incarnation,
    required int pid,
    required int pgid,
    String? predecessorAttemptId,
    String? stepPath,
    int? stepRound,
    String? worktree,
    String? branch,
    DateTime? occurredAt,
  }) {
    _observe('processStarted', () {
      _enqueue(
        AttemptProcessStarted(
          attemptId: attemptId,
          sessionId: sessionId,
          incarnation: incarnation,
          round: _rounds[sessionId],
          stepPath: stepPath,
          stepRound: stepRound,
          worktree: worktree,
          branch: branch,
          pid: pid,
          pgid: pgid,
          predecessorAttemptId: predecessorAttemptId,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  /// `attempt.process.exited` — from `_emitExit`'s two shapes (r2, major 7):
  /// `RuntimeEvent.exited` (read code, or the oneTurn vanish with
  /// [inferred] true) and `RuntimeEvent.died` ([exitKind] died). An inferred
  /// exit stamps envelope `provenance='inferred'`.
  void processExited({
    required String attemptId,
    required int pid,
    required ExitKind exitKind,
    required bool inferred,
    String? sessionId,
    int? exitCode,
    String? reason,
    DateTime? occurredAt,
  }) {
    _observe('processExited', () {
      _enqueue(
        AttemptProcessExited(
          attemptId: attemptId,
          sessionId: sessionId,
          pid: pid,
          exitCode: exitCode,
          exitKind: exitKind,
          inferred: inferred,
          reason: reason,
        ),
        occurredAt: occurredAt,
        provenance: inferred
            ? TrajectoryProvenance.inferred
            : TrajectoryProvenance.observed,
        provenanceBasis: inferred ? 'exit-code-inferred' : null,
      );
    });
  }

  /// `attempt.terminal(outcome=succeeded)` — at `_completeAndClose`, the
  /// outcome-bearing caller (r2, major 6; the bare writer `close` is NOT a
  /// derivation site). One record, NO tail.
  void sessionCompleted({
    required String sessionId,
    required String workBeadId,
    String? reason,
    DateTime? occurredAt,
  }) {
    _terminal(
      site: 'sessionCompleted',
      sessionId: sessionId,
      workBeadId: workBeadId,
      outcome: TerminalOutcome.succeeded,
      reason: reason,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.terminal(outcome=escalated)` — at `_escalateAndClose`; [reason]
  /// from `grid.escalation_reason`.
  void sessionEscalated({
    required String sessionId,
    required String workBeadId,
    String? reason,
    DateTime? occurredAt,
  }) {
    _terminal(
      site: 'sessionEscalated',
      sessionId: sessionId,
      workBeadId: workBeadId,
      outcome: TerminalOutcome.escalated,
      reason: reason,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.terminal(outcome=lost)` — at the voidRetireMetadata write. The
  /// record carries the ORIGINAL work bead id (intact keys) while legacy
  /// still writes `#void-` (§2.3).
  void sessionVoided({
    required String sessionId,
    required String workBeadId,
    String? reason,
    DateTime? occurredAt,
  }) {
    _terminal(
      site: 'sessionVoided',
      sessionId: sessionId,
      workBeadId: workBeadId,
      outcome: TerminalOutcome.lost,
      reason: reason,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.terminal(outcome=settled)` — `settleSessionForTerminalWork`'s
  /// two callers. The gate-sweep settle is observed; a reconciler-originated
  /// settle is `provenance='inferred'` with [attemptId] recovered from the
  /// breadcrumb where present. A null [attemptId] with no cached mint means a
  /// pre-Stage-1 session: the recorder mints one and payload-marks the basis
  /// (§2.1's bounce rule); [resolvesRecordId] makes this the SETTLING record
  /// healing an earlier unknown terminal (§2.4 obligation 1).
  void sessionSettled({
    required String sessionId,
    String? workBeadId,
    String? attemptId,
    String? workTerminalReason,
    String? resolvesRecordId,
    bool reconcilerOriginated = false,
    DateTime? occurredAt,
  }) {
    _terminal(
      site: 'sessionSettled',
      sessionId: sessionId,
      workBeadId: workBeadId,
      attemptId: attemptId,
      outcome: TerminalOutcome.settled,
      reason: workTerminalReason,
      resolvesRecordId: resolvesRecordId,
      provenance: reconcilerOriginated
          ? TrajectoryProvenance.inferred
          : TrajectoryProvenance.observed,
      provenanceBasis: reconcilerOriginated ? 'restart-reconciler' : null,
      mintedAttemptBasis: reconcilerOriginated
          ? kReconcilerMintedAttemptBasis
          : kRecorderMintedAttemptBasis,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.round.retired` — one record per retire (rework re-key or
  /// void-retired close); bumps the recorder's round counter, which nothing
  /// else bumps (§2.2 round row).
  void roundRetired({
    required String sessionId,
    required RoundRetireCause cause,
    int? oldRound,
    DateTime? occurredAt,
  }) {
    _observe('roundRetired', () {
      final old = oldRound ?? _rounds[sessionId] ?? 0;
      final next = old + 1;
      _rounds[sessionId] = next;
      _enqueue(
        AttemptRoundRetired(
          sessionId: sessionId,
          oldRound: old,
          newRound: next,
          cause: cause,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  /// `attempt.rework_declined` — after the HELD merge.
  void reworkDeclined({
    required String sessionId,
    required String reason,
    DateTime? occurredAt,
  }) {
    _observe('reworkDeclined', () {
      _enqueue(
        AttemptReworkDeclined(
          sessionId: sessionId,
          round: _rounds[sessionId] ?? 0,
          reason: reason,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  /// `attempt.mint.outcome` — per evaluation, ABOVE any flare-throttle latch
  /// (r2, minor 14): every failed/refused evaluation appends. One
  /// mount_attempt_id spans the whole mint sequence; [MintPhase.exhausted]
  /// and [MintPhase.abandoned] END it.
  void mintOutcome({
    required String workBeadId,
    required MintPhase phase,
    required int mintAttempt,
    int? maxAttempts,
    String? stage,
    String? reason,
    Map<String, dynamic> mountAttemptMetadata = const {},
    DateTime? occurredAt,
  }) {
    _observe('mintOutcome', () {
      final parsed = parseLegacyWorkKey(workBeadId);
      final mountAttemptId = _mountSequences.putIfAbsent(
        parsed.workBeadId,
        _mintUlid,
      );
      if (phase == MintPhase.exhausted || phase == MintPhase.abandoned) {
        _mountSequences.remove(parsed.workBeadId);
      }
      final seat = _seatOf(parsed.workBeadId);
      _enqueue(
        AttemptMintOutcome(
          workBeadId: parsed.workBeadId,
          mountAttemptId: mountAttemptId,
          phase: phase,
          mintAttempt: mintAttempt,
          maxAttempts: maxAttempts,
          stage: stage,
          reason: reason,
          legacyAttemptCount: _legacyAttemptCount(mountAttemptMetadata),
          seatBasis: seat.basis,
        ),
        seat: seat.seat,
        occurredAt: occurredAt,
      );
    });
  }

  /// `attempt.lease.acquired` — after `_persistBreadcrumb` returns; the
  /// breadcrumb now CARRIES the attempt id (§2.1) — the record reads it,
  /// never invents it, and the [token] rides beside it through the window
  /// (`GRID_INSTANCE_TOKEN` retirement is a cut change).
  void leaseAcquired({
    required String attemptId,
    required String token,
    DateTime? occurredAt,
  }) {
    _lease(
      site: 'leaseAcquired',
      attemptId: attemptId,
      phase: LeasePhase.acquired,
      token: token,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.lease.released` — after the release clears the breadcrumb.
  void leaseReleased({
    required String attemptId,
    required String token,
    LeaseDisposition? disposition,
    String? terminateResult,
    String? clearFailure,
    DateTime? occurredAt,
  }) {
    _lease(
      site: 'leaseReleased',
      attemptId: attemptId,
      phase: LeasePhase.released,
      token: token,
      disposition: disposition,
      terminateResult: terminateResult,
      clearFailure: clearFailure,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.lease.swept` — after the boot sweep's per-lease disposition.
  void leaseSwept({
    required String attemptId,
    required String token,
    LeaseDisposition? disposition,
    String? terminateResult,
    String? clearFailure,
    DateTime? occurredAt,
  }) {
    _lease(
      site: 'leaseSwept',
      attemptId: attemptId,
      phase: LeasePhase.swept,
      token: token,
      disposition: disposition,
      terminateResult: terminateResult,
      clearFailure: clearFailure,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.adopt.proved` — adopted-vs-respawned durable at last; the
  /// attempt id is the breadcrumb's, CONTINUED (§2.1: no fresh mint on
  /// adopt).
  void adoptProved({
    required String attemptId,
    required AdoptOutcome outcome,
    int? fencePgid,
    int? fencePid,
    DateTime? occurredAt,
  }) {
    _observe('adoptProved', () {
      _enqueue(
        AttemptAdoptProved(
          attemptId: attemptId,
          outcome: outcome,
          fencePgid: fencePgid,
          fencePid: fencePid,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  /// `attempt.liveness.lost` — a threshold crossing observed by the tick's
  /// detector, which may emit `lost` ONLY for a beat observed within the
  /// current epoch (§2.3); raw beats ride `traj_pulse`, never the log.
  void livenessLost({
    required String attemptId,
    required DateTime lastBeatAt,
    required int thresholdMs,
    DateTime? occurredAt,
  }) {
    _liveness(
      site: 'livenessLost',
      attemptId: attemptId,
      crossing: LivenessCrossing.lost,
      lastBeatAt: lastBeatAt,
      thresholdMs: thresholdMs,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.liveness.regained` — the recovering crossing.
  void livenessRegained({
    required String attemptId,
    required DateTime lastBeatAt,
    required int thresholdMs,
    DateTime? occurredAt,
  }) {
    _liveness(
      site: 'livenessRegained',
      attemptId: attemptId,
      crossing: LivenessCrossing.regained,
      lastBeatAt: lastBeatAt,
      thresholdMs: thresholdMs,
      occurredAt: occurredAt,
    );
  }

  /// `attempt.note(channel='obligation-stuck')` — the ONE note channel armed
  /// at Stage 1 (§2.3): the tick's stuck-obligation accounting. The ordinal
  /// is service-minted here (free text has no natural key).
  void obligationStuckNoted({
    required String sessionId,
    required String body,
    DateTime? occurredAt,
  }) {
    _observe('obligationStuckNoted', () {
      final ordinal = (_noteOrdinals[sessionId] ?? 0) + 1;
      _noteOrdinals[sessionId] = ordinal;
      _enqueue(
        AttemptNote(
          sessionId: sessionId,
          body: body,
          channel: kObligationStuckChannel,
          noteOrdinal: ordinal,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  // ── worktree builders (§2.3 worktree rows) ───────────────────────────────

  /// `worktree.provisioned` — INSIDE `provisionWorktree`, where `preexisting`
  /// and the branch are locally in hand and one `git rev-parse HEAD` captures
  /// [baseSha] at the same instant (r2, blocker 3). `ck_provision` promotes
  /// sha + branch to required envelope columns — all three are required here
  /// so the site cannot under-fill the record.
  ///
  /// The site has only the WORK bead in hand, so the attempt id joins through
  /// the recorder's work-bead cache (stamped at session mint); an explicit
  /// [attemptId] or [sessionId] wins when the caller has one.
  void worktreeProvisioned({
    required String workBeadId,
    required String worktree,
    required String branch,
    required String baseSha,
    required bool adoptedExisting,
    String? sessionId,
    String? attemptId,
    DateTime? occurredAt,
  }) {
    _observe('worktreeProvisioned', () {
      final parsed = parseLegacyWorkKey(workBeadId);
      final resolved =
          attemptId ??
          (sessionId == null ? null : _sessionAttempts[sessionId]) ??
          (_workBeadAttempts[parsed.workBeadId] ??= _mintUlid());
      _enqueue(
        WorktreeProvisioned(
          attemptId: resolved,
          sessionId: sessionId,
          worktree: worktree,
          branch: branch,
          baseSha: baseSha,
          adoptedExisting: adoptedExisting,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  /// `worktree.reaped` — after the reap attempt; the payload gains path +
  /// branch (the legacy flares omit them — the record does not, §2.3).
  /// [inferred] marks the tick's non-atomic-crash backfill (§2.4 obligation
  /// 2), where the legacy reap already ran but the record never landed.
  void worktreeReaped({
    required String sessionId,
    required String worktree,
    String? branch,
    int? uncommitted,
    int? unpushed,
    int? stashes,
    bool inferred = false,
    DateTime? occurredAt,
  }) {
    _observe('worktreeReaped', () {
      _enqueue(
        WorktreeReaped(
          sessionId: sessionId,
          worktree: worktree,
          branch: branch,
          uncommitted: uncommitted,
          unpushed: unpushed,
          stashes: stashes,
        ),
        occurredAt: occurredAt,
        provenance: inferred
            ? TrajectoryProvenance.inferred
            : TrajectoryProvenance.observed,
        provenanceBasis: inferred ? 'tick-reaped-backfill' : null,
      );
    });
  }

  /// `worktree.held` — the reap refused to delete (uncommitted/unpushed
  /// work); per-epoch, re-observed each boot.
  void worktreeHeld({
    required String sessionId,
    required String worktree,
    String? branch,
    int? uncommitted,
    int? unpushed,
    int? stashes,
    DateTime? occurredAt,
  }) {
    _observe('worktreeHeld', () {
      _enqueue(
        WorktreeHeld(
          sessionId: sessionId,
          worktree: worktree,
          branch: branch,
          uncommitted: uncommitted,
          unpushed: unpushed,
          stashes: stashes,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  // ── internals ────────────────────────────────────────────────────────────

  /// The non-fatal wrapper every observation rides (§3): skipped when the
  /// sink is latched/disabled, counted + flared on a derivation throw, never
  /// propagated — an append failure NEVER fails, delays, or reorders a
  /// legacy write.
  void _observe(String site, void Function() derive) {
    if (!_sink.accepting) {
      _skipped += 1;
      return;
    }
    try {
      derive();
      _derived += 1;
    } on Object catch (error) {
      _deriveFailures += 1;
      _flare('trajectory.deriveFailed', {'site': site, 'reason': '$error'});
    }
  }

  void _enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {
    _sink.enqueue(
      record,
      // The observation instant is NOW, at the derivation site — the append
      // happens later on the writer loop and must not re-stamp it (§2.2).
      occurredAt: occurredAt ?? _clock(),
      seat: seat,
      provenance: provenance,
      provenanceBasis: provenanceBasis,
    );
  }

  void _terminal({
    required String site,
    required String sessionId,
    required TerminalOutcome outcome,
    String? workBeadId,
    String? attemptId,
    String? reason,
    String? resolvesRecordId,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    String mintedAttemptBasis = kRecorderMintedAttemptBasis,
    DateTime? occurredAt,
  }) {
    _observe(site, () {
      final parsed = workBeadId == null ? null : parseLegacyWorkKey(workBeadId);
      String? attemptIdBasis;
      var resolved = attemptId ?? _sessionAttempts[sessionId];
      if (resolved == null) {
        // No breadcrumb, no cached mint, no seed: mint and SAY SO rather
        // than refuse — such rows are outside the shadow's comparable set
        // (§2.1).
        resolved = _mintUlid();
        _sessionAttempts[sessionId] = resolved;
        attemptIdBasis = mintedAttemptBasis;
      }
      final seat = parsed == null ? null : _seatOf(parsed.workBeadId);
      _enqueue(
        AttemptTerminal(
          attemptId: resolved,
          sessionId: sessionId,
          workBeadId: parsed?.workBeadId,
          outcome: outcome,
          reason: reason,
          resolvesRecordId: resolvesRecordId,
          attemptIdBasis: attemptIdBasis,
          seatBasis: seat?.basis,
        ),
        seat: seat?.seat,
        occurredAt: occurredAt,
        provenance: provenance,
        provenanceBasis: provenanceBasis,
      );
    });
  }

  void _lease({
    required String site,
    required String attemptId,
    required LeasePhase phase,
    required String token,
    LeaseDisposition? disposition,
    String? terminateResult,
    String? clearFailure,
    DateTime? occurredAt,
  }) {
    _observe(site, () {
      _enqueue(
        AttemptLeaseTransition(
          attemptId: attemptId,
          phase: phase,
          token: token,
          disposition: disposition,
          terminateResult: terminateResult,
          clearFailure: clearFailure,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  void _liveness({
    required String site,
    required String attemptId,
    required LivenessCrossing crossing,
    required DateTime lastBeatAt,
    required int thresholdMs,
    DateTime? occurredAt,
  }) {
    _observe(site, () {
      _enqueue(
        AttemptLivenessTransition(
          attemptId: attemptId,
          crossing: crossing,
          lastBeatAt: lastBeatAt,
          thresholdMs: thresholdMs,
        ),
        occurredAt: occurredAt,
      );
    });
  }

  /// §2.2 seat row: `ownedPrefixOf` over the allowSet, longest-prefix match,
  /// with the deterministic [kUnownedSeat] fallback and its payload marker.
  ({String seat, String? basis}) _seatOf(String workBeadId) {
    final prefix = BeadOwnershipPredicate.ownedPrefixOf(
      workBeadId,
      _seatPrefixes,
    );
    return prefix == null
        ? (seat: kUnownedSeat, basis: kUnownedSeatBasis)
        : (seat: prefix, basis: null);
  }

  /// Tolerant read of the mount-attempt bead's `grid.attempt.count` (the
  /// stored value may be an int or a string; unreadable reads as absent — the
  /// join column is comparative telemetry, never load-bearing).
  static int? _legacyAttemptCount(Map<String, dynamic> metadata) {
    final raw = metadata[kLegacyAttemptCountKey];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _mintUlid() => mintUlid(now: _clock());

  void _flare(String name, Map<String, String> data) {
    try {
      _onFlare?.call(name, data);
    } on Object {
      // Emit-only: a throwing transport never breaks the recorder.
    }
  }
}

/// The disabled recorder's sink: never accepts, never reachable by a record.
final class _NeverAccepting implements TrajectoryRecordSink {
  const _NeverAccepting();

  @override
  bool get accepting => false;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {}
}
