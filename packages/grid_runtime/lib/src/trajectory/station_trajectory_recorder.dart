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
import 'package:meta/meta.dart';

import '../lifecycle/bead_ownership.dart';

/// The flare seam — shape-compatible with `ExplorationTransport.flare` (and
/// with the harness's rate-limited flare, which is what production passes).
typedef TrajectoryRecorderFlare =
    void Function(String name, Map<String, String> data);

typedef _StepObservationKey = ({
  String sessionId,
  String stepPath,
  int stepRound,
  int incarnation,
});

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

/// `provenance_basis` for the tick's `worktree.reaped` backfill (§2.4
/// obligation 2): the legacy reap already ran, the record never landed — the
/// named non-atomic crash class, healed record-only.
const String kTickReapedBackfillBasis = 'tick-reaped-backfill';

/// `provenance_basis` for the tick's settling terminal (§2.4 obligation 1):
/// an `unknown` terminal healed from a process/worktree probe.
const String kTickUnknownSettlementBasis = 'tick-unknown-settlement';

const String _stepCompleteImpliesRunningBasis = 'step-complete-implies-running';

/// The FIFO bound on every warm cache the recorder keeps. Epoch-truncate by
/// insertion order: Dart maps and sets iterate oldest-first, so dropping
/// `keys.first` retires the coldest entries. Sized generously against the
/// station's real storm (a handful of concurrent sessions).
///
/// §2.1's recoverability rule makes eviction SAFE, but "safe" is not "free",
/// and it does not mean the same thing in every cache. What an eviction
/// actually costs, per cache:
///
///   * `_sessionAttempts` / `_workBeadAttempts` / `_provisionAttempts` — the
///     next record for that key mints a fresh attempt id and PAYLOAD-MARKS it
///     (`attempt_id_basis`). The row is outside the shadow's comparable set;
///     nothing durable is lost and nothing is silently wrong.
///   * `_rounds` — the round ladder restarts at 0 for that session until the
///     next `#rN` sighting or seed. A comparative column, never a key.
///   * `_mountSequences` — the next mint evaluation opens a fresh
///     `mount_attempt_id`, so one mint sequence reads as two.
///   * `_leaseAttemptByStep` / `_predecessorByAttempt` — a succession goes
///     unobserved; the log's last attempt row per session+step path is the
///     authority and still carries it.
///   * `_attemptSpawns` — the spawn's correlation facts degrade (incarnation
///     to 0, step path/round to absent); identity is unaffected.
///   * `_runningStepTransitions` — a later complete observation re-enqueues
///     the same inferred running identity with the same
///     `step-complete-implies-running` basis; the sole appender's existing
///     idempotency key deduplicates it.
///   * `_noteOrdinals` — the ONE cache whose naive miss was not benign: the
///     ordinal is the note's idem key (`note:<session>:<n>`), so restarting a
///     live session's counter at 1 re-mints a key the log already holds and
///     the append DEDUPES the note away, silently. The note builder therefore
///     does NOT restart at 1 on a miss — see
///     `StationTrajectoryRecorder.buildObligationStuckNote`.
///
/// No cache holds state that only it holds; none of the above loses a durable
/// fact.
const int kRecorderCacheBound = 1024;

/// The mount-attempt bead's durable counter key — wire-identical to
/// grid_engine's `MountAttemptKeys.count`, duplicated because grid_runtime
/// cannot import grid_engine (the same split the molecule join keys live
/// under). The recorder reads it into `legacy_attempt_count`, the
/// shadow-comparable ordinal `traj shadow-diff` joins against the legacy bead
/// (§2.2, r2 major 8).
const String kLegacyAttemptCountKey = 'grid.attempt.count';

/// The provision join's seed: the spawn's attempt id plus the correlation
/// facts `provisionWorktree` (which holds only the work bead) cannot know.
typedef _ProvisionSeed = ({
  String attemptId,
  String? sessionId,
  String? stepPath,
  int? stepRound,
  int? incarnation,
});

/// One constructed record plus the seat its envelope must carry — what a
/// BUILDER hands back to a caller that owns its own append.
///
/// The queue path ([StationTrajectoryRecorder]'s observation methods) enqueues
/// these itself; the TICK path (stage1-wiring §2.4's obligations) appends them
/// through the fenced appender instead — schema §5: "the tick, never the query,
/// owns the fenced append". Both paths build through the same builders, which
/// is what keeps the concrete record vocabulary in this one library (§2).
@immutable
final class DerivedRecord {
  const DerivedRecord(this.record, {this.seat});

  final TrajectoryRecord record;

  /// §2.2's seat row, or null when the record carries no `work_bead_id` (and
  /// `ck_seat` therefore demands nothing).
  final String? seat;
}

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

  /// ORIGINAL work bead id → the same session-scope attempt id (stamped at
  /// session mint). A LAST-RESORT join only: `worktree.provisioned` prefers
  /// [_provisionAttempts] (the SPAWN's attempt, seeded by the spawner right
  /// before it provisions — §2.2 worktree row), because P6's provisional row
  /// is keyed by attempt_id and must be corrected in place by the `.started`
  /// that follows, which carries the spawn's id, never the session-scope one.
  final Map<String, String> _workBeadAttempts = <String, String>{};

  /// ORIGINAL work bead id → the spawn CURRENTLY provisioning that bead's
  /// worktree: its attempt id AND the correlation the provisioning site has
  /// no way to know — seeded by [provisioningAttempt] (the spawner,
  /// synchronously before `provisionWorkspace` runs) and read by
  /// [worktreeProvisioned].
  ///
  /// The attempt id is what makes the provisioned record carry the SAME
  /// attempt_id the spawn's `attempt.process.started` will carry, so P6's
  /// provisional row is corrected in place rather than orphaned beside a
  /// second row. The SESSION id is what makes there be a row at all
  /// (fidelity B2's tail): `processIdentityDeltaFor`'s `worktree.provisioned`
  /// arm can only take the birth (upsert) arm when the envelope carries a
  /// session — `proj_process_identity.session_id` is NOT NULL, so a
  /// session-less provisioned record degrades to an update that, arriving
  /// BEFORE the spawn as it always does in production, matches zero rows and
  /// loses worktree/branch/base_sha entirely.
  ///
  /// A warm cache of the mount's env export (`GRID_ATTEMPT_ID`) plus the
  /// allocation address — recoverable, never invented (§2.1).
  final Map<String, _ProvisionSeed> _provisionAttempts =
      <String, _ProvisionSeed>{};

  /// attempt id → the spawn-time correlation facts the runtime-event
  /// subscriber cannot read off a `SessionStarted` event (incarnation = the
  /// persisted restartCount; step path/round at the mount). Seeded by
  /// [attemptSpawning] (the CapabilityHost, before it kicks the allocation);
  /// read by [processStarted]. A warm cache of persisted step-bead state
  /// (§2.1) — losing it degrades the record's incarnation to 0, never loses
  /// identity.
  final Map<
    String,
    ({String sessionId, String stepPath, int stepRound, int incarnation})
  >
  _attemptSpawns =
      <
        String,
        ({String sessionId, String stepPath, int stepRound, int incarnation})
      >{};

  /// session id → current round: seeded by parsing the `#rN` shape at first
  /// sight, bumped ONLY by the round-retired observation (§2.2).
  final Map<String, int> _rounds = <String, int>{};

  /// ORIGINAL work bead id → mount_attempt_id: one ULID spans ONE
  /// `SessionScope` mint sequence (§2.2); a successful mint or a terminal
  /// phase (exhausted/abandoned) ends the sequence.
  final Map<String, String> _mountSequences = <String, String>{};

  /// session id → last minted `attempt.note` ordinal (service-minted, §2.3).
  final Map<String, int> _noteOrdinals = <String, int>{};

  /// The largest note ordinal this process has minted, in ANY session — the
  /// floor under [buildObligationStuckNote]'s cache-miss fallback, so the
  /// fallback is strictly increasing even when the clock cannot separate two
  /// misses (a coarse timer, a frozen test clock). Not a cache: one int, no
  /// eviction, nothing recoverable to lose.
  int _maxNoteOrdinal = 0;

  /// step bead id → the attempt id its `grid.lease.*` breadcrumb currently
  /// names — the boot-local view of the durable carrier (§2.1). Seeded by
  /// every observed breadcrumb (acquire, and [leaseObserved]'s read-only
  /// seam), dropped when the breadcrumb is cleared (release, and a sweep that
  /// killed rather than left the group). It exists for ONE derivation: the
  /// spawn-under-existing-breadcrumb succession below.
  final Map<String, String> _leaseAttemptByStep = <String, String>{};

  /// attempt id → the attempt it succeeded (§2.3's *incarnation succession*
  /// row). Written when a fresh spawn's acquire overwrites a breadcrumb that
  /// still named a PRIOR attempt — the outgoing attempt is the successor's
  /// `predecessor_attempt_id`. Read back by the `attempt.process.started`
  /// derivation through [predecessorAttemptIdOf]; a warm cache of a fact the
  /// log also carries (the last attempt row per session+step path), never the
  /// only copy.
  final Map<String, String> _predecessorByAttempt = <String, String>{};

  final Map<_StepObservationKey, bool> _runningStepTransitions =
      <_StepObservationKey, bool>{};

  int _derived = 0;
  int _skipped = 0;
  int _deriveFailures = 0;

  TrajectoryRecorderStats get stats => TrajectoryRecorderStats(
    derived: _derived,
    skipped: _skipped,
    deriveFailures: _deriveFailures,
  );

  /// Whether the sink currently accepts records. Exposed for ONE purpose: a
  /// call site may skip a COSTLY evidence probe (a git subprocess, a stat
  /// storm) whose only consumer is a record that would be skipped anyway.
  /// Never use it to branch legacy behavior — the "no call site ever branches
  /// on 'is the trajectory up'" rule (§1.1) is about the legacy path, and this
  /// getter must never reach one.
  bool get accepting => _sink.accepting;

  /// FIFO epoch-truncate for a warm cache (see [kRecorderCacheBound]).
  static void _cap<K, V>(Map<K, V> cache) {
    while (cache.length > kRecorderCacheBound) {
      cache.remove(cache.keys.first);
    }
  }

  _StepObservationKey _stepObservationKey({
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
  }) => (
    sessionId: sessionId,
    stepPath: stepPath,
    stepRound: stepRound,
    incarnation: incarnation,
  );

  void _rememberRunning(_StepObservationKey key) {
    _runningStepTransitions[key] = true;
    _cap(_runningStepTransitions);
  }

  // ── boot-time cache seeding (§2.1) ───────────────────────────────────────

  /// Re-seeds the session-scope attempt id for [sessionId] — called by boot
  /// recovery with the log's last session-scoped attempt row, or with a
  /// breadcrumb-recovered id. Never invents identity: the value handed in
  /// must itself be recoverable.
  void seedSessionAttempt(String sessionId, String attemptId) {
    _sessionAttempts[sessionId] = attemptId;
    _cap(_sessionAttempts);
  }

  /// Re-seeds the round counter for [sessionId] from the log after a bounce.
  void seedRound(String sessionId, int round) {
    _rounds[sessionId] = round;
    _cap(_rounds);
  }

  /// Seeds the spawn-info cache for the mount that is about to spawn
  /// [attemptId] — called by the host BEFORE it kicks the allocation, with the
  /// correlation facts only the mount has in hand (§2.2): the persisted
  /// `restartCount` as [incarnation], and the step path/round. Appends
  /// nothing: a seed is not a transition. The runtime-event subscriber's
  /// `attempt.process.started` derivation reads these back through
  /// [processStarted], because a `SessionStarted` event carries none of them.
  void attemptSpawning({
    required String attemptId,
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
  }) {
    if (attemptId.isEmpty) return;
    _attemptSpawns[attemptId] = (
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
    );
    _cap(_attemptSpawns);
  }

  /// Seeds the provision join for [workBeadId] with the SPAWN's [attemptId]
  /// AND its correlation — called by the spawner synchronously before
  /// `provisionWorkspace` runs, so the `worktree.provisioned` observation
  /// inside `provisionWorktree` (which has only the work bead in hand)
  /// resolves the SAME attempt the spawn's `.started` will carry, and P6's
  /// provisional row is BORN here and corrected in place (fidelity B2).
  /// Appends nothing. The live call order guarantees the id exists here:
  /// `CapabilityHost.initState` mints it, the allocation env exports it, and
  /// the spawner reads it off that env BEFORE provisioning.
  ///
  /// [sessionId] is the load-bearing addition (fidelity B2's TAIL): without a
  /// session on the record the fold cannot insert — `session_id` is NOT NULL
  /// — so the delta degrades to an update against a row the spawn has not
  /// written yet, matches nothing, and the worktree/branch/base_sha facts
  /// never land. The spawner reads it off the [AllocationAddress] (which is
  /// also where the harness's runtime-event subscriber reads it: the first
  /// '/' of `providerName`).
  ///
  /// Every omitted fact falls back to the mount's own [attemptSpawning] seed
  /// for the same attempt — one seed, two readers, no second source of truth.
  void provisioningAttempt({
    required String workBeadId,
    required String attemptId,
    String? sessionId,
    String? stepPath,
    int? stepRound,
    int? incarnation,
  }) {
    if (attemptId.isEmpty) return;
    final spawn = _attemptSpawns[attemptId];
    _provisionAttempts[parseLegacyWorkKey(workBeadId).workBeadId] = (
      attemptId: attemptId,
      sessionId: sessionId ?? spawn?.sessionId,
      stepPath: stepPath ?? spawn?.stepPath,
      stepRound: stepRound ?? spawn?.stepRound,
      incarnation: incarnation ?? spawn?.incarnation,
    );
    _cap(_provisionAttempts);
  }

  /// Seeds [_leaseAttemptByStep] from a breadcrumb the engine READ but did not
  /// write — the adopt probe and the boot sweep's projection (§2.1: identity
  /// is recovered from the breadcrumb, never invented). Appends nothing: a
  /// read is not a transition. A blank [attemptId] (a pre-Stage-1 breadcrumb,
  /// or the cleared sentinel) forgets the step instead of recording an empty
  /// predecessor.
  void leaseObserved({required String stepBeadId, required String attemptId}) {
    if (attemptId.isEmpty) {
      _leaseAttemptByStep.remove(stepBeadId);
      return;
    }
    _leaseAttemptByStep[stepBeadId] = attemptId;
    _cap(_leaseAttemptByStep);
  }

  /// The attempt [attemptId] succeeded, when a spawn-under-existing-breadcrumb
  /// transition observed one (§2.3's incarnation-succession row) — the
  /// `predecessor_attempt_id` the `attempt.process.started` derivation stamps.
  /// Null means no succession was observed in this process: the caller falls
  /// back to the log's last attempt row for the session+step path, which is
  /// the authority (this map is a warm cache of it).
  String? predecessorAttemptIdOf(String attemptId) =>
      _predecessorByAttempt[attemptId];

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
      _cap(_rounds);
      final attemptId = _sessionAttempts[sessionId] ??= _mintUlid();
      _cap(_sessionAttempts);
      _workBeadAttempts[parsed.workBeadId] = attemptId;
      _cap(_workBeadAttempts);
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
  /// [predecessorAttemptId] is the outgoing breadcrumb's id on a succession —
  /// omitted, it falls back to [predecessorAttemptIdOf]'s warm cache of the
  /// spawn-under-existing-breadcrumb observation.
  ///
  /// [incarnation]/[stepPath]/[stepRound], when omitted, resolve from the
  /// spawn-info cache [attemptSpawning] seeded at the mount — the event
  /// carries none of them. A cache miss (a spawner outside the engine's
  /// allocation path) degrades incarnation to 0: a restart ladder only the
  /// engine's supervised-restart writer climbs, so an unseeded spawn has none.
  void processStarted({
    required String attemptId,
    required String sessionId,
    required int pid,
    required int pgid,
    int? incarnation,
    String? predecessorAttemptId,
    String? stepPath,
    int? stepRound,
    String? worktree,
    String? branch,
    DateTime? occurredAt,
  }) {
    _observe('processStarted', () {
      final seeded = _attemptSpawns[attemptId];
      _enqueue(
        AttemptProcessStarted(
          attemptId: attemptId,
          sessionId: sessionId,
          incarnation: incarnation ?? seeded?.incarnation ?? 0,
          round: _rounds[sessionId],
          stepPath: stepPath ?? seeded?.stepPath,
          stepRound: stepRound ?? seeded?.stepRound,
          worktree: worktree,
          branch: branch,
          pid: pid,
          pgid: pgid,
          predecessorAttemptId:
              predecessorAttemptId ?? predecessorAttemptIdOf(attemptId),
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
      _cap(_mountSequences);
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
  ///
  /// [stepBeadId] is the lease ADDRESS, and supplying it is what makes the
  /// spawn-under-existing-breadcrumb SUCCESSION observable (§2.3's
  /// incarnation-succession row): this write overwrites whatever the step's
  /// breadcrumb named, so a prior attempt standing there is the incoming
  /// attempt's predecessor. Omitting it costs the succession, never the
  /// record.
  void leaseAcquired({
    required String attemptId,
    required String token,
    String? stepBeadId,
    DateTime? occurredAt,
  }) {
    _lease(
      site: 'leaseAcquired',
      attemptId: attemptId,
      phase: LeasePhase.acquired,
      token: token,
      occurredAt: occurredAt,
      before: () {
        if (stepBeadId == null) return;
        final prior = _leaseAttemptByStep[stepBeadId];
        // A re-persist of the SAME attempt (the retry loop) is not a
        // succession — only an attempt displacing a DIFFERENT one is.
        if (prior != null && prior.isNotEmpty && prior != attemptId) {
          _predecessorByAttempt[attemptId] = prior;
          _cap(_predecessorByAttempt);
        }
        if (attemptId.isNotEmpty) {
          _leaseAttemptByStep[stepBeadId] = attemptId;
          _cap(_leaseAttemptByStep);
        }
      },
    );
  }

  /// `attempt.lease.released` — after the release clears the breadcrumb.
  /// [stepBeadId] drops the step's cached attempt: a cleared breadcrumb names
  /// nothing, so the next spawn there succeeds no one.
  void leaseReleased({
    required String attemptId,
    required String token,
    String? stepBeadId,
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
      before: () {
        if (stepBeadId != null) _leaseAttemptByStep.remove(stepBeadId);
      },
    );
  }

  /// `attempt.lease.swept` — after the boot sweep's per-lease disposition.
  ///
  /// The sweep's dispositions differ in what they leave on the bead, and the
  /// cache follows the BEAD: a killed lease had its breadcrumb cleared (the
  /// step forgets its attempt), while [LeaseDisposition.leftAdoptable] and
  /// [LeaseDisposition.refusedUnsafe] deliberately LEAVE it standing — so a
  /// later spawn over either one is a real succession.
  void leaseSwept({
    required String attemptId,
    required String token,
    String? stepBeadId,
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
      before: () {
        if (stepBeadId == null) return;
        // A DROPPED clear (clearFailure) means the breadcrumb is still there,
        // whatever the kill did — follow the bead, not the intent.
        final cleared =
            disposition == LeaseDisposition.killed && clearFailure == null;
        if (cleared) {
          _leaseAttemptByStep.remove(stepBeadId);
        } else if (attemptId.isNotEmpty) {
          _leaseAttemptByStep[stepBeadId] = attemptId;
          _cap(_leaseAttemptByStep);
        }
      },
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
      _enqueue(
        buildObligationStuckNote(sessionId: sessionId, body: body).record,
        occurredAt: occurredAt,
      );
    });
  }

  // ── step family builders (§2.3's four `step.transition` rows) ────────────
  //
  // Every one of these is INTENT-named rather than state-parameterized, and
  // that is a boundary decision, not a style one: `StepState` exists in BOTH
  // `grid_engine` (the cursor's) and `grid_trajectory` (the record's). A
  // state-taking API would force the engine's persist sites to name the
  // record vocabulary, which means a third inbound edge to the leaf package
  // and a colliding import at every call site. Naming the transitions instead
  // keeps the record vocabulary entirely on this side of the seam — the same
  // reason the whole recorder exists (§2's "the ONLY code that names concrete
  // record classes").

  /// `step.transition(running)` — after `_persistStarted`'s step-bead write.
  /// Non-terminal: it carries the kick instant and nothing else.
  void stepRunning({
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
    String? attemptId,
    DateTime? startedAt,
    DateTime? occurredAt,
  }) {
    final key = _stepObservationKey(
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
    );
    _step(
      site: 'stepRunning',
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
      attemptId: attemptId,
      state: StepState.running,
      startedAt: startedAt,
      occurredAt: occurredAt,
      afterEnqueue: () => _rememberRunning(key),
    );
  }

  /// `step.transition(ready)` — a daemon's positive terminal that does NOT
  /// latch (OQ-5); [result] is the rendezvous payload written in the same
  /// legacy update.
  void stepReady({
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
    String? attemptId,
    DateTime? startedAt,
    DateTime? readyAt,
    Map<String, String>? result,
    DateTime? occurredAt,
  }) {
    _step(
      site: 'stepReady',
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
      attemptId: attemptId,
      state: StepState.ready,
      startedAt: startedAt,
      readyAt: readyAt,
      result: result,
      occurredAt: occurredAt,
    );
  }

  /// `step.transition(complete)` — the clean completion; the grade/pr_url the
  /// legacy write merged atomically ride the record's `result` (§2.3: "result
  /// keys on complete ride the payload").
  void stepComplete({
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
    String? attemptId,
    DateTime? startedAt,
    DateTime? completedAt,
    Map<String, String>? result,
    DateTime? occurredAt,
  }) {
    final key = _stepObservationKey(
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
    );
    if (!_runningStepTransitions.containsKey(key)) {
      _step(
        site: 'stepRunningBeforeComplete',
        sessionId: sessionId,
        stepPath: stepPath,
        stepRound: stepRound,
        incarnation: incarnation,
        attemptId: attemptId,
        state: StepState.running,
        startedAt: startedAt,
        occurredAt: startedAt ?? occurredAt,
        provenance: TrajectoryProvenance.inferred,
        provenanceBasis: _stepCompleteImpliesRunningBasis,
        afterEnqueue: () => _rememberRunning(key),
      );
    }
    _step(
      site: 'stepComplete',
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
      attemptId: attemptId,
      state: StepState.complete,
      startedAt: startedAt,
      completedAt: completedAt,
      result: result,
      occurredAt: occurredAt,
    );
  }

  /// `step.transition(failed)` — the D-5 supervised-restart write, whose
  /// [incarnation] is the BUMPED persisted `restartCount`: that bump is the
  /// durable succession signal (§2.3's incarnation-succession row), so the
  /// log carries it without any event to key on.
  ///
  /// [storeUnavailable] splits the tg-7ux CONFLATION the legacy bead cannot
  /// express: a step whose own work failed and a step whose failure write was
  /// a dropped PERSIST both land as `state=failed` on the bead, and only the
  /// caller knows which. `failure_class` is where they separate.
  void stepFailed({
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
    required bool storeUnavailable,
    String? attemptId,
    String? failureReason,
    int? restartBudget,
    DateTime? startedAt,
    DateTime? cooldownUntil,
    DateTime? occurredAt,
  }) {
    _step(
      site: 'stepFailed',
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
      attemptId: attemptId,
      state: StepState.failed,
      startedAt: startedAt,
      cooldownUntil: cooldownUntil,
      restartBudget: restartBudget,
      failureReason: failureReason,
      failureClass: storeUnavailable
          ? StepFailureClass.storeUnavailable
          : StepFailureClass.work,
      occurredAt: occurredAt,
    );
  }

  /// `step.transition(gated)` — the STEP half of the park (§2.3): the gate
  /// BEAD's mint stays wholly legacy at Stage 1, so nothing here appends a
  /// `gate.opened`. Fired by the one shared escalation persist, which is why
  /// the route-declined park and its derived twin produce the same record.
  void stepGated({
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
    String? attemptId,
    String? reason,
    DateTime? startedAt,
    DateTime? occurredAt,
  }) {
    _step(
      site: 'stepGated',
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
      attemptId: attemptId,
      state: StepState.gated,
      startedAt: startedAt,
      cause: StepCause.route,
      failureReason: reason,
      occurredAt: occurredAt,
    );
  }

  /// `step.transition(pending, cause=gate_cleared)` — the re-arm (§2.3's last
  /// row). [fromStepRound] is the supersedes-chain depth OBSERVED at the
  /// re-arm; the record carries `fromStepRound + 1`, because a gate-cleared
  /// re-arm is exactly what bumps `step_round`. That bump is the record which
  /// kills the I-14 stale-join loop at the cut; during the shadow window it
  /// only shadows the legacy `gated → pending` flip.
  void stepRearmed({
    required String sessionId,
    required String stepPath,
    required int fromStepRound,
    required int incarnation,
    String? attemptId,
    DateTime? occurredAt,
  }) {
    _step(
      site: 'stepRearmed',
      sessionId: sessionId,
      stepPath: stepPath,
      stepRound: fromStepRound + 1,
      incarnation: incarnation,
      attemptId: attemptId,
      state: StepState.pending,
      cause: StepCause.gateCleared,
      occurredAt: occurredAt,
    );
  }

  // ── worktree builders (§2.3 worktree rows) ───────────────────────────────

  /// `worktree.provisioned` — INSIDE `provisionWorktree`, where `preexisting`
  /// and the branch are locally in hand and one `git rev-parse HEAD` captures
  /// [baseSha] at the same instant (r2, blocker 3). `ck_provision` promotes
  /// sha + branch to required envelope columns — all three are required here
  /// so the site cannot under-fill the record.
  ///
  /// The site has only the WORK bead in hand, so BOTH the attempt id and the
  /// session join through the SPAWN's provision seed ([provisioningAttempt],
  /// stamped by the spawner right before it provisions). The attempt id is
  /// the one `attempt.process.started` will also carry, so P6's provisional
  /// row is corrected in place; the session is what lets that row be BORN at
  /// all, because the fold's insert arm needs a NOT NULL `session_id` and a
  /// provision always precedes its spawn (fidelity B2 and its tail). An
  /// explicit [attemptId] or [sessionId] wins when the caller has one, and
  /// the session-scope work-bead cache is the last recoverable resort. Only
  /// when EVERY join fails (a provision outside the engine's spawn path) does
  /// the recorder mint — and then it SAYS SO with an `attempt_id_basis`
  /// payload marker, never silently (§2.1's recoverability rule).
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
      final seeded = _provisionAttempts[parsed.workBeadId];
      var resolved =
          attemptId ??
          seeded?.attemptId ??
          (sessionId == null ? null : _sessionAttempts[sessionId]) ??
          _workBeadAttempts[parsed.workBeadId];
      String? basis;
      if (resolved == null) {
        resolved = _mintUlid();
        basis = kRecorderMintedAttemptBasis;
        // Cache the marked mint so a repeat provision of the same bead does
        // not birth a second phantom P6 row.
        _provisionAttempts[parsed.workBeadId] = (
          attemptId: resolved,
          sessionId: sessionId,
          stepPath: null,
          stepRound: null,
          incarnation: null,
        );
        _cap(_provisionAttempts);
      }
      // The correlation for the attempt actually resolved: the provision seed
      // when it named THIS attempt, else the mount's own spawn seed. An
      // explicit attemptId that disagrees with the seed must not borrow the
      // seed's session — that would stamp one spawn's ladder onto another's.
      final correlation = seeded != null && seeded.attemptId == resolved
          ? seeded
          : null;
      final spawn = _attemptSpawns[resolved];
      final session = sessionId ?? correlation?.sessionId ?? spawn?.sessionId;
      _enqueue(
        WorktreeProvisioned(
          attemptId: resolved,
          sessionId: session,
          // The provisional ladder, seeded to the SAME position the spawn's
          // `.started` will claim, so the two never race `uq_incarnation`.
          // The round ladder is the recorder's own (§2.2), exactly as
          // [processStarted] reads it.
          round: session == null ? null : _rounds[session],
          stepPath: correlation?.stepPath ?? spawn?.stepPath,
          stepRound: correlation?.stepRound ?? spawn?.stepRound,
          incarnation: correlation?.incarnation ?? spawn?.incarnation,
          worktree: worktree,
          branch: branch,
          baseSha: baseSha,
          adoptedExisting: adoptedExisting,
          attemptIdBasis: basis,
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
        buildWorktreeReaped(
          sessionId: sessionId,
          worktree: worktree,
          branch: branch,
          uncommitted: uncommitted,
          unpushed: unpushed,
          stashes: stashes,
        ).record,
        occurredAt: occurredAt,
        provenance: inferred
            ? TrajectoryProvenance.inferred
            : TrajectoryProvenance.observed,
        provenanceBasis: inferred ? kTickReapedBackfillBasis : null,
      );
    });
  }

  // ── tick-side builders (§2.4's obligations) ──────────────────────────────
  //
  // The tick owns its own fenced append (schema §5), so these RETURN the
  // record instead of enqueuing it — but they are the SAME constructors the
  // observation methods above ride, which is the whole point: one library
  // names the concrete record classes, whichever path appends them.

  /// The SETTLING `attempt.terminal` an unknown terminal's obligation appends
  /// (§2.4 obligation 1): outcome `settled`, `resolves_record_id` pointing at
  /// the unknown terminal it heals, identity recovered from the log row rather
  /// than from any warm cache.
  DerivedRecord buildSettledTerminal({
    required String sessionId,
    required String attemptId,
    required String resolvesRecordId,
    String? workBeadId,
    String? reason,
  }) => _buildTerminal(
    sessionId: sessionId,
    attemptId: attemptId,
    outcome: TerminalOutcome.settled,
    workBeadId: workBeadId,
    reason: reason,
    resolvesRecordId: resolvesRecordId,
  );

  /// The `worktree.reaped` record — the observation method's builder, and the
  /// backfill obligation's (§2.4 obligation 2).
  DerivedRecord buildWorktreeReaped({
    required String sessionId,
    required String worktree,
    String? branch,
    int? uncommitted,
    int? unpushed,
    int? stashes,
  }) => DerivedRecord(
    WorktreeReaped(
      sessionId: sessionId,
      worktree: worktree,
      branch: branch,
      uncommitted: uncommitted,
      unpushed: unpushed,
      stashes: stashes,
    ),
  );

  /// One `attempt.liveness.*` threshold crossing (§2.4 obligation 3). The
  /// DETECTOR decides when a crossing happened — including the unknown rule
  /// (no beat observed in the current epoch ⇒ no record at all); this only
  /// builds the record for a crossing it was handed.
  DerivedRecord buildLivenessTransition({
    required String attemptId,
    required LivenessCrossing crossing,
    required DateTime lastBeatAt,
    required int thresholdMs,
  }) => DerivedRecord(
    AttemptLivenessTransition(
      attemptId: attemptId,
      crossing: crossing,
      lastBeatAt: lastBeatAt,
      thresholdMs: thresholdMs,
    ),
  );

  /// The stuck-obligation note (§2.4 obligation 4 / schema §5's N-failure
  /// rule). The ordinal is service-minted HERE for both paths, so the two
  /// never mint the same `note:<session>:<ordinal>` key.
  ///
  /// **A cache MISS never restarts at 1.** The ordinal IS the note's idem key
  /// (`note:<session>:<n>`), and `_noteOrdinals` is FIFO-bounded like every
  /// other warm cache ([kRecorderCacheBound]) — so a busy station that
  /// evicted a still-live session's entry would re-mint `…:1`, `…:2`, … keys
  /// the log already holds, and the appender would DEDUPE the new notes away
  /// SILENTLY (a dedupe is a success outcome; the loss would surface
  /// nowhere). On a miss the ordinal therefore falls back to
  /// **epoch-microseconds**, floored above every ordinal this process has
  /// already minted ([_maxNoteOrdinal]) so two misses the clock cannot
  /// separate still get different values. µs since 1970 is ~1.8e15 against
  /// single-digit note counters, so the fallback cannot collide with a small
  /// ordinal from a previous boot either.
  ///
  /// What that costs, EXACTLY: strict per-session ordinal DENSITY degrades —
  /// a session's ordinals are no longer 1, 2, 3…, and the numeric gap across
  /// an eviction counts nothing. What does NOT degrade: ordinals stay
  /// strictly increasing per session (the fallback is above every prior
  /// value, and later notes increment from it), so every reader that treats
  /// them as an ORDER is still right; and DURABILITY is untouched — every
  /// note lands, which is the whole point of not restarting at 1.
  DerivedRecord buildObligationStuckNote({
    required String sessionId,
    required String body,
  }) {
    final last = _noteOrdinals[sessionId];
    final micros = _clock().toUtc().microsecondsSinceEpoch;
    final ordinal = last != null
        ? last + 1
        : (micros > _maxNoteOrdinal ? micros : _maxNoteOrdinal + 1);
    _noteOrdinals[sessionId] = ordinal;
    if (ordinal > _maxNoteOrdinal) _maxNoteOrdinal = ordinal;
    _cap(_noteOrdinals);
    return DerivedRecord(
      AttemptNote(
        sessionId: sessionId,
        body: body,
        channel: kObligationStuckChannel,
        noteOrdinal: ordinal,
      ),
    );
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
      final derived = _buildTerminal(
        sessionId: sessionId,
        outcome: outcome,
        workBeadId: workBeadId,
        attemptId: attemptId,
        reason: reason,
        resolvesRecordId: resolvesRecordId,
        mintedAttemptBasis: mintedAttemptBasis,
      );
      _enqueue(
        derived.record,
        seat: derived.seat,
        occurredAt: occurredAt,
        provenance: provenance,
        provenanceBasis: provenanceBasis,
      );
    });
  }

  DerivedRecord _buildTerminal({
    required String sessionId,
    required TerminalOutcome outcome,
    String? workBeadId,
    String? attemptId,
    String? reason,
    String? resolvesRecordId,
    String mintedAttemptBasis = kRecorderMintedAttemptBasis,
  }) {
    final parsed = workBeadId == null ? null : parseLegacyWorkKey(workBeadId);
    String? attemptIdBasis;
    var resolved = attemptId ?? _sessionAttempts[sessionId];
    if (resolved == null) {
      // No breadcrumb, no cached mint, no seed: mint and SAY SO rather than
      // refuse — such rows are outside the shadow's comparable set (§2.1).
      resolved = _mintUlid();
      _sessionAttempts[sessionId] = resolved;
      _cap(_sessionAttempts);
      attemptIdBasis = mintedAttemptBasis;
    }
    final seat = parsed == null ? null : _seatOf(parsed.workBeadId);
    return DerivedRecord(
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
    );
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
    void Function()? before,
  }) {
    _observe(site, () {
      // The breadcrumb-cache bookkeeping rides INSIDE the guarded derivation:
      // it is the same warm cache the record is built from, so a throw counts
      // and flares here exactly like any other derivation failure.
      before?.call();
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

  void _step({
    required String site,
    required String sessionId,
    required String stepPath,
    required int stepRound,
    required int incarnation,
    required StepState state,
    String? attemptId,
    StepCause? cause,
    DateTime? startedAt,
    DateTime? readyAt,
    DateTime? completedAt,
    DateTime? cooldownUntil,
    int? restartBudget,
    String? failureReason,
    StepFailureClass? failureClass,
    Map<String, String>? result,
    DateTime? occurredAt,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    void Function()? afterEnqueue,
  }) {
    _observe(site, () {
      _enqueue(
        StepTransition(
          sessionId: sessionId,
          // The round ladder is the recorder's (§2.2) — a step transition
          // observes it, never advances it; only round-retired bumps.
          round: _rounds[sessionId] ?? 0,
          stepPath: stepPath,
          stepRound: stepRound,
          incarnation: incarnation,
          attemptId: attemptId == null || attemptId.isEmpty ? null : attemptId,
          state: state,
          cause: cause,
          startedAt: startedAt,
          readyAt: readyAt,
          completedAt: completedAt,
          cooldownUntil: cooldownUntil,
          restartBudget: restartBudget,
          failureReason: failureReason,
          failureClass: failureClass,
          result: result,
        ),
        occurredAt: occurredAt,
        provenance: provenance,
        provenanceBasis: provenanceBasis,
      );
      afterEnqueue?.call();
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
        buildLivenessTransition(
          attemptId: attemptId,
          crossing: crossing,
          lastBeatAt: lastBeatAt,
          thresholdMs: thresholdMs,
        ).record,
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
