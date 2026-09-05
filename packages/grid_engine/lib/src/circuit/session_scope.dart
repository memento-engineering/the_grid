/// The engine-private session lifecycle owner (ADR-0008 D4 / M4-P1 D-2).
///
/// `SessionScope` is mounted by `WorkBead` ABOVE the circuit fan-out (the
/// resolver returns it). It projects the authority's adopted or reserved
/// attempt into `{resolving | ready | failed}`, and on `ready` provides a stable
/// `InheritedSeed<SessionHandle>` over the `CircuitScope` so the inflater + every
/// `CapabilityHost` attach to the SAME session — establishing the session is a
/// tree *state* (a loading state, `const Idle()` until resolved), not a
/// synchronous id injection. This is the "Route resolves before its Page
/// attaches" shape (an abstraction, not a literal router). It is ALSO where the
/// per-session ambient values mount (2026-07-02): the `Workspace` (computed from
/// the per-substation `SourceControl`) and the `SiblingView` (this session's
/// cursor + results) — the values an effect reads with the non-binding lookup.
///
/// It owns tree execution END-TO-END and asks `StationAdmissionAuthority` for
/// each durable attempt transition, including the positive-terminal close. The
/// request is SCHEDULED off `build` (never a write IN `build` — invariant 2)
/// and latched once. Breaker-exhaustion close + escalation fold in at Track G.
///
/// **Adopt-or-mint DISPOSITIONS a closed session (I-10, tg-4rw).** An existing
/// session bead is not simply "there or not": it is `live` (adopt), `done` /
/// `held` (a blocking terminal — `WorkList` never mounts it), or a `voided` DEAD
/// KEY — closed mid-flight with an in-flight cursor and no human marker. A dead
/// key is never adoptable AND never blocking: the scope retires it (re-keys its
/// `work_bead` off this bead — the engine-automatic member of A47's re-run
/// taxonomy) and mints a fresh round, LOUD. Before that, a dead key blocked its
/// work bead forever, silently.
///
/// Why above the fan-out (the D-2 break it fixes): P0 minted lazily at
/// first-leaf-mount and named the provider session = the bead id, one per work
/// bead. `MultiChildBranch` mounts all frontier children in one pass, so two
/// concurrent leaves would each see `session == null` → two mints, and both
/// would call `provider.start` with the same name → collisions. Minting ONCE,
/// above the fan-out, is the fix.
///
/// **Molecule is the ONLY mint (tg-eli phase 2 — the flat cursor retired).**
/// Every FRESH mint stamps `grid.session.model=molecule` and pours a durable
/// `type=molecule`/`type=step` graph (`instantiateMolecule` → R6's
/// `createMolecule`) under the [_maxMintAttempts] budget. [build] projects a
/// molecule session's OWN beads (`SessionProjection.moleculeBeads`) through
/// `projectMoleculeCursor` into the `CircuitCursor` shape `CircuitScope`
/// consumes, and wraps it in a 4th `InheritedSeed<InheritedCircuit>` so
/// `CapabilityHost` (R5b) targets each step's own durable bead. **Drain,
/// never convert:** [initState]'s `LiveSession()` arm adopts synchronously —
/// an in-flight session is never reinterpreted mid-round. A HISTORICAL flat
/// session (no `grid.session.model` marker) still ADOPTS, but the engine can
/// no longer drive it: its cursor no longer projects (empty), no
/// `InheritedCircuit` mounts under it, and every host persist refuses LOUD —
/// the operator's lever is `grid rework` on the closed round.
///
/// A52 Ratified wires R4 live for molecule sessions: invalidated terminal
/// steps mint successor incarnation beads on a `supersedes` chain, and
/// `live_frontier.dart` derives generation from that chain depth.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../diagnostics/diagnosable.dart';
import '../diagnostics/state_store_deadline.dart';
import '../domain/joined_snapshot.dart';
import '../domain/session_bead.dart';
import '../domain/session_disposition.dart';
import '../domain/session_projection.dart';
import '../domain/rework.dart' show kMaxReworkRounds, reworkRoundOf;
import '../domain/step_cursor_read.dart' show effectiveStepCursor;
import '../kernel/station_services.dart';
import '../kernel/station_admission_authority.dart';
import '../kernel/idle.dart';
import '../kernel/trajectory_scope.dart';
import '../molecule/bead_path_key.dart';
import '../molecule/inherited_circuit.dart';
import '../molecule/live_frontier.dart'
    show derivedEscalation, effectiveCursor, invalidatedNodes;
import '../molecule/molecule_codec.dart';
import '../molecule/molecule_schema.dart' show MoleculeStepKeys;
import '../restart/restart_reconciler.dart' show ReapWorktree;
import '../sdk/capability.dart';
import '../sdk/cursor.dart';
import '../sdk/circuit.dart';
import '../sdk/frontier.dart';
import '../sdk/route.dart' show EscalationRequest;
import '../seeds/provider.dart';
import 'capability_host.dart' show persistRaisedEscalation;
import 'capability_registry.dart';
import 'circuit_scope.dart';
import 'session_handle.dart';

/// The tree execution lifecycle for one admitted work [bead]'s [circuit].
///
/// It asks the station admission authority for durable attempt transitions.
/// Key it `ValueKey('${bead.id}:session')` so it persists across cursor ticks
/// while the work node keeps its branch identity.
class SessionScope extends StatefulSeed with GridDiagnosticable {
  /// Creates the scope for [bead] running [circuit], with the bead's linked
  /// [existingSession] (null until the authority creates one; non-null means
  /// the authority admitted an adoption or a retire-then-remint lifecycle).
  const SessionScope({
    required this.bead,
    required this.circuit,
    this.existingSession,
    this.reapWorktree,
    this.workRoot,
    super.key,
  });

  /// The work bead this session drives (its id is the circuit's root nodePath
  /// and the mint's `work_bead` linkage).
  final Bead bead;

  /// The root circuit for this work bead.
  final Circuit circuit;

  /// The bead's linked session projection (the JOIN row) — null when no session
  /// exists yet (mint), non-null once the bridge projects one (adopt). Its
  /// [SessionProjection.cursor] threads the per-node cursor down to
  /// `CircuitScope` pull-free (A39).
  final SessionProjection? existingSession;

  /// Existing domain-free three-gate seam; null with [workRoot] disables reap.
  ///
  /// The concrete VCS implementation remains outside `grid_engine`.
  final ReapWorktree? reapWorktree;

  /// Root checkout paired with [reapWorktree].
  final RootCheckout? workRoot;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties.addTyped(
      ReferenceProperty('bead', bead.id, kind: ReferenceKind.bead),
    );
    if (existingSession?.sessionId case final sessionId?) {
      properties.addTyped(
        ReferenceProperty('session', sessionId, kind: ReferenceKind.session),
      );
    }
  }

  @override
  State<SessionScope> createState() => SessionScopeState();
}

/// The `{resolving | ready | failed}` lifecycle (D-2). The async-gap guards
/// (`_cancelled` set first in `dispose`, `context.mounted` after every await,
/// the captured `_ctx`) are the same discipline as `CapabilityHostState`.
class SessionScopeState extends State<SessionScope>
    with Diagnosticable, GridDiagnosticable {
  /// The bounded `createSession` retry budget (tg-6nf) — a mint failure is
  /// RETRIED up to this many TOTAL attempts before the scope escalates LOUD
  /// (the circuit-breaker's bounded-retry discipline, D-5). Small on purpose:
  /// the FIRST-LIVE-ARM incident (2026-07-10) was a PERSISTENT store
  /// misconfiguration (`bd create -t session` rejected — no `types.custom`),
  /// for which retry cannot help; the budget exists to ride out a TRANSIENT bd
  /// blip, and its EXHAUSTION is the escalation trigger.
  static const _maxMintAttempts = 5;

  /// The bounded successor-mint retry budget. Unlike [_maxMintAttempts], this
  /// budget is per node path because one live session can mint successors for
  /// several independently-invalidated nodes.
  static const _maxStepSuccessorMintAttempts = 5;

  /// The per-attempt mint-failed flare (tg-6nf) — a mint attempt threw and the
  /// scope is still RETRYING under [_maxMintAttempts].
  static const _mintFailedFlare = 'session.mintFailed';
  static const _mintAbandonedFlare = 'session.mintAbandoned';

  /// The terminal mint-EXHAUSTED flare (tg-6nf) — the [_maxMintAttempts] budget
  /// is spent; the scope escalates LOUD and goes inert (a human must fix the
  /// store — the exact FIRST-LIVE-ARM incident).
  static const _mintExhaustedFlare = 'session.mintExhausted';

  /// A successor mint spent its full retry budget and the live session is
  /// being parked durably for operator repair.
  static const _stepSuccessorMintExhaustedFlare =
      'session.stepSuccessorMintExhausted';

  /// A session exists, but its molecule graph could not be poured. The session
  /// is parked at a durable gate for operator repair and rework.
  static const _moleculePourFailedFlare = 'session.moleculePourFailed';

  /// An adopted session's failed molecule pour could not be parked durably.
  /// The scope remains retryable and reports the failed park without allowing
  /// its unawaited orphan-resume microtask to escape into the resident's zone.
  static const _moleculePourParkFailedFlare = 'session.moleculePourParkFailed';

  GateSweepSessionDisposition _gateSweepDisposition(
    SessionDisposition disposition,
  ) => switch (disposition) {
    LiveSession() ||
    NoSession() ||
    PausedSession() => GateSweepSessionDisposition.live,
    DoneSession() => GateSweepSessionDisposition.done,
    HeldSession() => GateSweepSessionDisposition.held,
    VoidedSession() => GateSweepSessionDisposition.voided,
  };

  Future<void> _closeTerminalGates(
    String sessionId,
    GateCloseCause cause,
    SessionDisposition disposition,
  ) async {
    try {
      await _ctx!.admission.closeTerminalGates(
        sessionId: sessionId,
        cause: cause,
        disposition: _gateSweepDisposition(disposition),
        services: _services,
      );
    } on Object catch (error) {
      _flare('gate.autoCloseFailed', {
        'sessionId': sessionId,
        'cause': cause.wireValue,
        'reason': truncateReason('$error'),
        ...stateStoreDeadlineMetadata(error),
      });
    }
  }

  Future<void> _closeRetiredReworkSession(String sessionId) async {
    try {
      await _ctx!.admission.closeRetiredReworkSession(
        workBeadId: seed.bead.id,
        sessionId: sessionId,
        reapMolecule: _isMolecule,
        services: _services,
      );
      // §2.3's `attempt.round.retired` row, second observation site: the
      // command handler saw the re-key, this scope sees the retired round
      // CLOSE. One retire, two observers, ONE record — the idem key is
      // `round-retired:<session>:<oldRound>`, so whichever lands first wins
      // and the other dedupes. `_retiredReworkRound` is the NEW round the
      // `#rN` key names, so the round being retired is one below it.
      if (_retiredReworkRound case final round?) {
        _recorder.roundRetired(
          sessionId: sessionId,
          cause: RoundRetireCause.rework,
          oldRound: round - 1,
        );
      }
    } on Object catch (error) {
      _flare('gate.autoCloseFailed', {
        'sessionId': sessionId,
        'cause': GateCloseCause.supersededRound.wireValue,
        'reason': truncateReason('$error'),
        ...stateStoreDeadlineMetadata(error),
      });
      rethrow;
    }
  }

  StationServices? _ctx;

  /// The Stage-1 derivation layer (stage1-wiring §2), re-resolved on every
  /// `didChangeDependencies` like every other captured reference (D-H rule 1)
  /// and held for the off-build observation sites — every write this scope
  /// makes is scheduled off `build`, so every record it derives is too.
  ///
  /// Absent it is a counting no-op ([TrajectoryRecorderScope.disabled]), which
  /// is why nothing below ever asks whether the trajectory is up.
  StationTrajectoryRecorder _recorder =
      TrajectoryRecorderScope.disabled.recorder;

  /// The ambient [ServiceBundle] captured off `build` (D-H rule 1: re-read on
  /// every `didChangeDependencies`, never `??=`-cached) — held so the off-build
  /// re-arm microtask can LOUD-flare a dropped write through its
  /// `transport` (tg-boq), the SAME emit-only sink `CapabilityHost._emitFlare`
  /// uses.
  ServiceBundle _services = const ServiceBundle();

  /// The reentrant resolution seam, captured for [_mint]'s ASYNC use (D-H
  /// rule 1: re-read every `didChangeDependencies`, never cached past it) —
  /// a molecule mint's `instantiateMolecule` call resolves a `SubCircuitStep`
  /// through `registry.circuit`, exactly like `build`'s own broken/complete
  /// checks already do synchronously. Null when no registry is ambient (a
  /// non-reentrant test fixture); `instantiateMolecule` degrades to minting
  /// no nested sub-circuit rather than throwing (its own null-tolerant
  /// default).
  CapabilityRegistry? _registry;

  JoinedSnapshot? _joinedSnapshot;
  Completer<JoinedSnapshot?>? _mintReadiness;
  DateTime? _mintDecisionAt;
  bool _mintBlockedReported = false;
  bool _requiresFreshMintSnapshot = false;

  String? _sessionId;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties.addTyped(FlagProperty('mintFailed', _mintFailureActive));
    if (_sessionId case final sessionId?) {
      properties.addTyped(
        ReferenceProperty('session', sessionId, kind: ReferenceKind.session),
      );
    }
  }

  bool _resolving = true;
  bool _failed = false;
  bool _mintFailureActive = false;
  bool _cancelled = false;
  bool _terminalScheduled = false;
  bool _deliveryOutcomeBlocked = false;

  /// True once THIS scope's session is known to be molecule-mode — set on
  /// ADOPT (`initState`'s `LiveSession()` arm reads
  /// `seed.existingSession!.isMolecule`) or on a successful [_mint] (every
  /// fresh mint is molecule); retained through rework retirement so the old
  /// graph is collected before round N+1. False only for an ADOPTED historical
  /// flat session, which the engine no longer drives. Captured before async
  /// authority completion calls to decide whether an engine-owned close also
  /// reaps the molecule (R6's session-close collection).
  bool _isMolecule = false;

  /// The session id already minted for an IN-PROGRESS molecule mint (tg-6nf)
  /// — set the instant `createSession` returns and cleared only when the
  /// WHOLE mint settles ([_scheduleRetiredRework]'s reset for round N+1). A retry
  /// that re-enters [_mint] after `createMolecule` throws must NEVER re-call
  /// `createSession` — that would strand the first session bead un-poured
  /// and mint a SECOND, exactly the "crashed pour" ambiguity
  /// `SessionBeadKeys.model` exists to prevent (`DESIGN-tg-pm6.md` §3
  /// conflict 2). Null before any mint attempt.
  String? _moleculeSessionId;

  /// How many `createSession` attempts this scope has made (tg-6nf) — bounded
  /// by [_maxMintAttempts]; reaching the cap is the escalation trigger. Reset
  /// to 0 by [_scheduleRetiredRework] so round N+1 gets its own fresh budget.
  int _mintAttempts = 0;

  /// The VOIDED session this scope must RETIRE before it mints (I-10) — set in
  /// [initState] when the joined session is a DEAD KEY (closed mid-flight, no
  /// human marker); cleared the instant the re-key lands, so a bounded mint RETRY
  /// (tg-6nf) can never re-key twice.
  SessionProjection? _voidSession;

  /// WHY the joined session was voided — carried into the retire write (durable,
  /// on the dead bead) and the `session.voided` flare (live). Empty when none.
  String _voidReason = '';

  /// The nodePaths whose gate re-arm is IN FLIGHT (tg-boq) — an in-flight DEDUP
  /// guard, **not** a permanent latch. A path is added before the write and
  /// removed when the write SETTLES (success OR failure):
  ///
  /// - On **success** the store's `gated`→`pending` flip stops D-7 from
  ///   re-firing on the next build, AND a legitimate SECOND gate cycle (a route
  ///   that parks, resolves, re-runs, and parks again) can re-arm again — a
  ///   permanent latch would wedge multi-round committee reruns.
  /// - On **failure** the guard clears so the very next build (any state/work
  ///   tick) RETRIES. The previous permanent `_rearmed` latch was set BEFORE the
  ///   fire-and-forget write, so a dropped write made the drop PERMANENT and
  ///   SILENT — the exact tg-boq incident (a gate closed, the parked node never
  ///   re-armed, cursor stuck `gated` for 30+ min, operator recovery = a station
  ///   bounce). LOUD or GONE (ADR-0008 D3).
  final Set<String> _rearming = {};
  final Set<String> _mintingSuccessorForPath = {};
  final Map<String, int> _stepSuccessorMintAttemptsByPath = {};

  /// Whether `seed.existingSession` has EVER matched [_sessionId] — retained
  /// only as a fresh-mint join-lag guard. It never authorizes a re-mint:
  /// durable `#rN` graph state does that.
  bool _joinedOnce = false;

  /// The retired round awaiting cleanup before the fresh mint. This is a
  /// transient effect payload, never an eligibility cursor.
  String? _retiredReworkSessionId;

  /// The round number the retiring `#rN` key names — captured beside
  /// [_retiredReworkSessionId] purely so the `attempt.round.retired` record
  /// can state the round it retires (§2.2's round row). Null when this scope
  /// mounted on a bead with no retired round.
  int? _retiredReworkRound;

  @override
  void didChangeDependencies() {
    // ALWAYS re-read (D-H rule 1) — the captured field exists for async-gap use
    // (`context` throws post-unmount), never as a read-once cache.
    final ctx = context.watch<StationServices>();
    assert(
      ctx != null,
      'SessionScope requires an ambient InheritedSeed<StationServices>',
    );
    _ctx = ctx;
    // Capture the (fixed-at-mount) ambient bundle for the off-build re-arm
    // flare (tg-boq) — same discipline as `CapabilityHostState._services`.
    _services = context.watch<ServiceBundle>() ?? const ServiceBundle();
    // Captured for [_mint]'s async use (D-H rule 1) — the reentrant registry
    // (a molecule mint's sub-circuit resolution).
    _registry = context.watch<CapabilityRegistry>();
    _joinedSnapshot = context.watch<JoinedSnapshot>();
    // Snapshot lookup, not a binding one (see `trajectoryRecorderOf`): the
    // recorder is station-lifetime, so there is nothing here to rebuild on.
    _recorder = trajectoryRecorderOf(context);
    _considerMintReadiness();
  }

  @override
  void initState() {
    final existing = seed.existingSession;
    final mountedRound = existing == null
        ? null
        : reworkRoundOf(seed.bead.id, existing.workBeadId);
    if (existing != null && mountedRound != null) {
      _retiredReworkSessionId = existing.sessionId;
      _retiredReworkRound = mountedRound;
      _isMolecule = existing.isMolecule;
      _requiresFreshMintSnapshot = true;
      unawaited(_mint());
      return;
    }
    // Adopt-or-mint DISPOSITIONS the joined session (I-10, tg-4rw): a CLOSED
    // session is `done`, `held`, or a `voided` DEAD KEY — never "unadoptable but
    // blocking", which is what wedged tg-1di for 62 minutes with no session and
    // no line saying why.
    final disposition = sessionDispositionOf(seed.existingSession);
    switch (disposition) {
      case LiveSession():
        // ADOPT — synchronous, no mint (the restoration adopt seam is the same
        // resolving→ready transition on restart). The join already reflects this
        // session (that's how we're adopting it), so the rework orphan-check
        // (tg-x1j v2) may fire from the very first build. An in-flight
        // session's OWN durable model stamp governs — a historical flat
        // session adopts here too, but the engine no longer drives it (see
        // the library doc).
        _sessionId = seed.existingSession!.sessionId;
        _resolving = false;
        _joinedOnce = true;
        _isMolecule = seed.existingSession!.isMolecule;
      case VoidedSession(:final reason):
        // A DEAD KEY: never adoptable, never blocking. Retire it, then mint
        // round N+1 through the SAME bounded-budget path a fresh bead uses —
        // LOUD, and fail-closed against a stale process that is still alive.
        _voidSession = seed.existingSession;
        _voidReason = reason;
        unawaited(_mint());
      case NoSession():
        // MINT — once, above the fan-out.
        unawaited(_mint());
      case DoneSession() || HeldSession() || PausedSession():
        // Unreachable through `WorkList` (a blocking disposition never mounts a
        // WorkBead). If any other composition mounts one anyway, say WHY once and
        // go inert — never silently adopt a terminal session's id, never mint a
        // second round over finished work (LOUD or GONE, ADR-0008 D3).
        _declineMount(disposition);
    }
  }

  /// LOUD-declines a mount over a BLOCKING session (I-10) — a defensive guard
  /// with a concrete failure story (a mis-composed tree re-running landed work),
  /// loud when violated.
  ///
  /// The fields are assigned directly (this runs in `initState`, BEFORE the first
  /// build — `setState` there is illegal), and the flare is scheduled off
  /// `initState`: `_services` is captured in `didChangeDependencies`, which
  /// genesis runs AFTER `initState` within one `performRebuild`, so flaring inline
  /// would fire into the default (transport-less) bundle and be silently dropped
  /// — the exact bug class this bead exists to kill.
  void _declineMount(SessionDisposition disposition) {
    final reason = switch (disposition) {
      HeldSession(:final reason) || PausedSession(:final reason) => reason,
      DoneSession() => 'the session already closed at a positive terminal',
      // Unreachable: only the blocking arms decline (initState dispatches the
      // other three) — named for exhaustiveness, never a silent default.
      NoSession() ||
      LiveSession() ||
      VoidedSession() => 'non-blocking disposition',
    };
    _failed = true;
    _resolving = false;
    scheduleMicrotask(() {
      if (_cancelled) return;
      _flare('session.mountDeclined', {
        'workBeadId': seed.bead.id,
        'sessionId': seed.existingSession?.sessionId ?? '',
        'reason': truncateReason(reason),
      });
    });
  }

  bool _isBlockingDisposition(SessionDisposition disposition) =>
      switch (disposition) {
        DoneSession() || HeldSession() || PausedSession() => true,
        NoSession() || LiveSession() || VoidedSession() => false,
      };

  /// How long the fresh-snapshot barrier waits for a post-decision publish
  /// before letting the SESSION-view evidence decide (see
  /// [_considerMintReadiness]). Static and mutable so an offline test can
  /// shrink the quiet-board window; production never changes it.
  static Duration freshMintSnapshotGrace = const Duration(seconds: 90);

  Timer? _mintGraceTimer;
  bool _mintGraceLapsed = false;

  Future<bool> _awaitFreshReadySnapshot() async {
    final completer = Completer<JoinedSnapshot?>();
    _mintDecisionAt = DateTime.now();
    _mintBlockedReported = false;
    // A fresh mint decision opens a fresh refusal window: its FIRST refusal
    // always records, whatever the previous sequence's tail looked like.
    _lastMintRefusalAt = null;
    _lastMintRefusalReason = null;
    _mintGraceLapsed = false;
    _mintReadiness = completer;
    _considerMintReadiness();
    final snapshot = await completer.future;
    if (identical(_mintReadiness, completer)) {
      _mintReadiness = null;
      _mintDecisionAt = null;
    }
    _mintGraceTimer?.cancel();
    _mintGraceTimer = null;
    return snapshot != null;
  }

  void _considerMintReadiness() {
    final completer = _mintReadiness;
    final decisionAt = _mintDecisionAt;
    final snapshot = _joinedSnapshot;
    if (completer == null || completer.isCompleted || decisionAt == null) {
      return;
    }
    if (snapshot == null) {
      // The record sits ABOVE the `_mintBlockedReported` latch (§2.3, r2
      // minor 14): the latch throttles the FLARE — one line per mint sequence
      // — while every refused EVALUATION appends. Reading refusal pressure off
      // the throttled flare undercounts it, which is exactly what the record
      // is for.
      _recordMintRefused('fresh joined snapshot is unavailable');
      if (!_mintBlockedReported) {
        _mintBlockedReported = true;
        _flare('session.mintRefused', {
          'workBeadId': seed.bead.id,
          'reason': 'fresh joined snapshot is unavailable',
        });
      }
      return;
    }
    if (snapshot.graph.capturedAt.isBefore(decisionAt)) {
      // The barrier's authored case (tg-x1j v2): a dep-add raced against an
      // immediate re-key — the fresh round must NOT mint from the snapshot
      // that predates the operator's own writes, so an older capture WAITS.
      //
      // But a change-gated pipeline withholds publishes for unchanged
      // stores, so on a QUIET board capturedAt may never pass decisionAt —
      // waiting on the clock alone parked every post-rework mint forever
      // (the 2026-08-07 afternoon: admission clean, slots free, no round
      // ever minted; the same freshness-vs-change-gating class as the
      // federation heartbeat fix). So the wait is BOUNDED: past
      // [freshMintSnapshotGrace] the SESSION view decides — the staleness
      // that matters is a snapshot still carrying a LIVE session for this
      // bead (pre-retire); one already showing it sessionless/terminal is
      // current in every fact the mint reads, whatever its capture time.
      if (!_mintGraceLapsed) {
        _mintGraceTimer ??= Timer(freshMintSnapshotGrace, () {
          _mintGraceLapsed = true;
          _considerMintReadiness();
        });
        return;
      }
      final joined = snapshot.sessionsByWorkBead[seed.bead.id];
      if (joined != null && !joined.isTerminal) return;
    }
    if (!snapshot.graph.readyIds.contains(seed.bead.id)) {
      // Per-evaluation again, above the same latch (§2.3).
      _recordMintRefused('work bead is absent from the fresh ready frontier');
      if (!_mintBlockedReported) {
        _mintBlockedReported = true;
        _flare('session.mintRefused', {
          'workBeadId': seed.bead.id,
          'reason': 'work bead is absent from the fresh ready frontier',
          'snapshotCapturedAt': snapshot.graph.capturedAt
              .toUtc()
              .toIso8601String(),
        });
      }
      return;
    }
    completer.complete(snapshot);
  }

  /// The legacy mount-attempt bead's durable ordinal (`grid.attempt.count`),
  /// as the recorder's `legacy_attempt_count` join column (§2.2, r2 major 8).
  ///
  /// The ULID mount_attempt_id keys the RECORD; this ordinal is what
  /// `traj shadow-diff` joins against the legacy bead, which is why an
  /// unshadowable identity does not cost the mint its comparable fact. Read
  /// off the SAME projection `WorkList` writes the budget from; absent (the
  /// bead has not been minted yet, or the projection lags the write) it is
  /// simply omitted — the column is comparative telemetry, never load-bearing.
  Map<String, dynamic> get _mountAttemptMetadata {
    final count = _joinedSnapshot?.mountAttemptsByWorkBead[seed.bead.id]?.count;
    return count == null
        ? const <String, dynamic>{}
        : <String, dynamic>{kLegacyAttemptCountKey: count};
  }

  /// The per-bead-per-window dedupe on refusal records (§2.5's amended note):
  /// `_considerMintReadiness` runs on EVERY joined-snapshot publish, so a
  /// publish storm against a persistently-refused bead would append one
  /// refusal per publish, indefinitely — the noisiest record type racing the
  /// 4096-entry queue whose overflow disqualifies the round. An IDENTICAL
  /// (same-reason) refusal within the window dedupes; a reason CHANGE records
  /// immediately, and each fresh mint decision resets the window
  /// ([_awaitFreshReadySnapshot]), so refusal pressure stays countable at the
  /// tick's own granularity without being per-publish.
  static const _mintRefusalDedupeWindow = Duration(seconds: 30);

  DateTime? _lastMintRefusalAt;
  String? _lastMintRefusalReason;

  /// `attempt.mint.outcome(refused)` — per REFUSED evaluation of the
  /// fresh-snapshot barrier (§2.3), above the flare latch, deduped per bead
  /// per [_mintRefusalDedupeWindow] (see its doc).
  void _recordMintRefused(String reason) {
    final now = DateTime.now();
    final last = _lastMintRefusalAt;
    if (last != null &&
        reason == _lastMintRefusalReason &&
        now.difference(last) < _mintRefusalDedupeWindow) {
      return;
    }
    _lastMintRefusalAt = now;
    _lastMintRefusalReason = reason;
    _recorder.mintOutcome(
      workBeadId: seed.bead.id,
      phase: MintPhase.refused,
      mintAttempt: _mintAttempts,
      maxAttempts: _maxMintAttempts,
      stage: 'fresh-snapshot',
      reason: reason,
      mountAttemptMetadata: _mountAttemptMetadata,
    );
  }

  Future<void> _mint() async {
    // Yield so didChangeDependencies captures _ctx (genesis runs initState then
    // didChangeDependencies within one performRebuild).
    await null;
    if (_cancelled || !context.mounted) return;
    final retiredId = _retiredReworkSessionId;
    if (retiredId != null) {
      _retiredReworkSessionId = null;
      try {
        await _closeRetiredReworkSession(retiredId);
      } on Object {
        if (await _stopAbandonedMint(
          stage: 'retired-gates-close-failed',
          retiredSessionId: retiredId,
        )) {
          return;
        }
        setState(() {
          _failed = true;
          _resolving = false;
        });
        return;
      }
      if (await _stopAbandonedMint(
        stage: 'retired-gates-closed',
        retiredSessionId: retiredId,
      )) {
        return;
      }
    }
    if (_requiresFreshMintSnapshot) {
      final snapshotReady = await _awaitFreshReadySnapshot();
      if (!snapshotReady) {
        await _stopAbandonedMint(
          stage: 'fresh-snapshot',
          retiredSessionId: retiredId,
        );
        return;
      }
      if (await _stopAbandonedMint(
        stage: 'fresh-snapshot-ready',
        retiredSessionId: retiredId,
      )) {
        return;
      }
      _requiresFreshMintSnapshot = false;
    }
    _mintAttempts++;
    try {
      // I-10: RETIRE a dead key before minting over it. Re-keying the voided
      // session's `work_bead` off this bead (through the ONE chokepoint, onto
      // the_grid's OWN bead — A37) keeps the join single-valued: two sessions on
      // one work bead would make the join's winner map-order-dependent, and
      // `grid rework` refuses an ambiguous bead outright. This is the operator's
      // I-10 workaround, mechanized — A47's re-run taxonomy gains its fourth,
      // engine-automatic member (`voidKeyFor`, never a `#r<N>` rework round).
      final dead = _voidSession;
      if (dead != null) {
        final deadId = dead.sessionId ?? '';
        if (deadId.isNotEmpty) {
          final refusal = await _ctx!.admission.retireVoidedSession(
            workBead: seed.bead,
            deadSession: dead,
            reason: _voidReason,
            services: _services,
          );
          if (refusal != null) {
            _mintAttempts--;
            if (_cancelled || !context.mounted) return;
            setState(() {
              _failed = true;
              _resolving = false;
            });
            return;
          }
          // §2.3's `attempt.terminal(lost)` row: the DEAD KEY's terminal, and
          // the round it retires. The record carries the ORIGINAL work bead id
          // while the legacy write is re-keying the dead session onto
          // `#void-<sessionId>` — intact keys are the whole point of the row.
          _recorder.sessionVoided(
            sessionId: deadId,
            workBeadId: seed.bead.id,
            reason: _voidReason,
          );
          // The retired round is DERIVED, never a bare 0 default (§2.1's
          // recoverable-only rule): the dead projection's own work_bead key
          // carries the `#rN` shape when the void landed on a reworked round
          // (parsed here), and the recorder's round counter — seeded at the
          // mint that this boot observed, or by boot recovery — decides
          // otherwise. Only a session no recoverable state names at all
          // retires as round 0, which is then the honest answer, not a
          // fallback that shadows a real round.
          _recorder.roundRetired(
            sessionId: deadId,
            cause: RoundRetireCause.voided,
            oldRound: StationTrajectoryRecorder.parseLegacyWorkKey(
              dead.workBeadId,
            ).round,
          );
          if (await _stopAbandonedMint(
            stage: 'void-session-retired',
            retiredSessionId: retiredId,
          )) {
            return;
          }
        }
        // Retired — a bounded retry must never re-key twice.
        _voidSession = null;
        _flare('session.voided', {
          'workBeadId': seed.bead.id,
          'deadSessionId': deadId,
          'reason': truncateReason(_voidReason),
        });
      }
      // Every fresh mint — including one over a retired dead key — pours the
      // molecule graph (tg-eli phase 2: molecule is the only circuit engine).
      await _mintMolecule(retiredSessionId: retiredId);
    } on Object catch (error) {
      if (await _stopAbandonedMint(
        stage: 'mint-catch',
        retiredSessionId: retiredId,
      )) {
        return;
      }
      _onMintFailed(error);
    }
  }

  /// The molecule-mode mint (`DESIGN-tg-pm6.md` §9/§12, R5/R6): `createSession`
  /// stamping `grid.session.model=molecule`, THEN `createMolecule` pours the
  /// pure `instantiateMolecule` compile step's plan. The two throws differ by
  /// lifecycle position: a `createSession` throw happens BEFORE a durable
  /// session exists and propagates to [_mint]'s `catch` under the
  /// [_maxMintAttempts] budget; a `createMolecule` throw happens AFTER the
  /// session exists. A raw SQL timeout is compensated by the authority before
  /// this scope reports abandonment; every other failure parks the session
  /// durably via [_parkFailedMoleculePour] — terminal, budget-untouched. Only a
  /// throwing PARK (the gate write itself failing) falls back to [_mint]'s
  /// bounded retry.
  ///
  /// [_moleculeSessionId] keeps a post-create attempt tied to the authority's
  /// reservation until pour or compensation finishes. It therefore cannot
  /// mint a rival while the first id is being retired. `createMolecule` itself
  /// remains re-entry-safe for adopted orphan-pour recovery (R6's dedup probe).
  Future<void> _mintMolecule({required String? retiredSessionId}) async {
    var id = _moleculeSessionId;
    if (id == null) {
      final result = await _ctx!.admission.createSessionAttempt(
        _joinedSnapshot ?? JoinedSnapshot.empty(),
        StationAdmissionCandidate(bead: seed.bead, session: _voidSession),
        title: 'grid session ${seed.bead.id}',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      switch (result) {
        case (sessionId: final createdId?, refusal: null):
          id = createdId;
        case (sessionId: null, refusal: final refusal?):
          _recordMintRefused('${refusal.clause}: ${refusal.detail}');
          _flare('session.mintRefused', {
            'workBeadId': seed.bead.id,
            'clause': refusal.clause,
            'reason': refusal.detail,
          });
          setState(() {
            _failed = true;
            _resolving = false;
          });
          return;
        default:
          throw StateError('invalid session-attempt result');
      }
      _moleculeSessionId = id;
      // §2.3's `attempt.session.started` row, derived at `createSession`'s SOLE
      // caller: rig and model are the same two values the birth-stamping merge
      // just wrote. Inside the null check on purpose — a retry that reuses the
      // FIRST attempt's session id re-enters this method without a second
      // `createSession`, and a record with no legacy write behind it is exactly
      // the shadow leading the incumbent.
      _recorder.sessionMinted(
        sessionId: id,
        workBeadId: seed.bead.id,
        rig: _ctx!.stateSubstation,
        model: kSessionModelMolecule,
        mountAttemptMetadata: _mountAttemptMetadata,
      );
    }
    if (await _stopAbandonedMint(
      stage: 'molecule-session-created',
      retiredSessionId: retiredSessionId,
    )) {
      return;
    }
    final root = BeadPathKey([seed.bead.id, id]);
    final plan = instantiateMolecule(
      seed.circuit,
      sessionId: id,
      root: root,
      nodePath: seed.bead.id,
      circuitById: _registry?.circuit,
    );
    try {
      await _ctx!.admission.pourMolecule(
        plan,
        workBeadId: seed.bead.id,
        sessionId: id,
        rootCrumbs: root.crumbs,
        services: _services,
      );
    } on StationMintVoided catch (voided) {
      _recorder.sessionVoided(
        sessionId: voided.retiredSessionId,
        workBeadId: voided.workBeadId,
        reason: kMintTimeoutVoidReason,
      );
      _recorder.roundRetired(
        sessionId: voided.retiredSessionId,
        cause: RoundRetireCause.voided,
        oldRound: 0,
      );
      _flare(_mintAbandonedFlare, {
        'workBeadId': voided.workBeadId,
        'retiredSessionId': voided.retiredSessionId,
        'stage': 'molecule-pour',
        'reason': kMintTimeoutVoidReason,
        ...stateStoreDeadlineMetadata(voided.cause),
      });
      _moleculeSessionId = null;
      _sessionId = null;
      return;
    } on Object catch (error) {
      await _parkFailedMoleculePour(
        id,
        error,
        retiredSessionId: retiredSessionId,
      );
      return;
    }
    if (await _stopAbandonedMint(
      stage: 'molecule-poured',
      retiredSessionId: retiredSessionId,
    )) {
      return;
    }
    setState(() {
      _sessionId = id;
      _resolving = false;
      _isMolecule = true;
      _moleculeSessionId = null;
      _mintFailureActive = false;
    });
  }

  /// Makes a thrown post-session molecule-pour failure LOUD and durable.
  ///
  /// No step bead is guaranteed to exist, so this parks the existing session
  /// at the work-bead root. Once the gate lands this mounted scope is terminal;
  /// recovery is cause repair followed by rework.
  ///
  /// Lifecycle rule: a `createSession` throw happens BEFORE a durable session
  /// exists and stays under [_maxMintAttempts]; a `createMolecule` throw
  /// happens AFTER the session exists and — when this gate write lands — parks
  /// once without consuming that retry budget. If the fresh-path gate write
  /// itself throws, it propagates to [_mint] and remains under the existing
  /// bounded LOUD retry path, because durable parking did not complete.
  Future<void> _parkFailedMoleculePour(
    String sessionId,
    Object error, {
    required String? retiredSessionId,
  }) async {
    final reason = truncateReason('Molecule pour failed: $error');
    _flare(_moleculePourFailedFlare, {
      'sessionId': sessionId,
      'workBeadId': seed.bead.id,
      'reason': reason,
      ...stateStoreDeadlineMetadata(error),
    });
    // The chokepoint's session-lifecycle park — NOT the router's gate-mint
    // verb (tg-6gn one-router): no step exists, so there is no route verdict
    // here, only a session that must not stay silently un-drivable.
    await _ctx!.writer.parkSessionAtGate(
      substation: _ctx!.stateSubstation,
      sessionId: sessionId,
      nodePath: seed.bead.id,
      reason: reason,
    );
    if (await _stopAbandonedMint(
      stage: 'molecule-pour-parked',
      retiredSessionId: retiredSessionId,
    )) {
      return;
    }
    setState(() {
      _failed = true;
      _resolving = false;
      _mintFailureActive = false;
    });
  }

  /// The generic emit-only flare sink (D-8) for this scope's I-10 signals — the
  /// SAME `ExplorationTransport` `CapabilityHost._emitFlare` and `WorkList` fire
  /// through. A throwing/absent transport never re-breaks the caller's microtask.
  void _flare(String name, Map<String, String> data) {
    try {
      _services.transport?.flare(name, data);
    } catch (_) {
      // A throwing transport never breaks the scope's lifecycle — swallow.
    }
  }

  Future<bool> _stopAbandonedMint({
    required String stage,
    required String? retiredSessionId,
  }) async {
    final reason = _cancelled
        ? 'cancelled'
        : !context.mounted
        ? 'unmounted'
        : null;
    if (reason == null) return false;
    final retiredMintSessionId = await _ctx?.admission.abandonSessionAttempt(
      workBeadId: seed.bead.id,
      sessionId: _moleculeSessionId,
      services: _services,
    );
    if (retiredMintSessionId != null) {
      _recorder.sessionVoided(
        sessionId: retiredMintSessionId,
        workBeadId: seed.bead.id,
        reason: 'mint-abandoned',
      );
      _recorder.roundRetired(
        sessionId: retiredMintSessionId,
        cause: RoundRetireCause.voided,
        oldRound: 0,
      );
      _moleculeSessionId = null;
    }
    // §2.3's mint row: `abandoned` ENDS the mount sequence, so the next mint
    // sequence for this work bead gets a fresh mount_attempt_id.
    _recorder.mintOutcome(
      workBeadId: seed.bead.id,
      phase: MintPhase.abandoned,
      mintAttempt: _mintAttempts,
      maxAttempts: _maxMintAttempts,
      stage: stage,
      reason: reason,
      mountAttemptMetadata: _mountAttemptMetadata,
    );
    _flare(_mintAbandonedFlare, {
      'workBeadId': seed.bead.id,
      'retiredSessionId': retiredMintSessionId ?? retiredSessionId ?? '',
      'stage': stage,
      'reason': reason,
    });
    return true;
  }

  /// Handles a `createSession` failure (tg-6nf) — LOUD, bounded, never the
  /// silent permanent latch it was (ADR-0008 D3: LOUD or GONE).
  ///
  /// Every failed attempt FLARES through the emit-only [ExplorationTransport]
  /// (the SAME sink `CapabilityHost._emitFlare` and [_flareRearmFailed] use), so
  /// a dead mint is OBSERVABLE — leonard reads it over the exploration host
  /// (A39/A40), while `mintFailed` projects the active failure into the
  /// StationControl status counts — never an invisible `mounted=0` (the
  /// FIRST-LIVE-ARM incident, 2026-07-10, boot #1: every `createSession` threw
  /// and the station stood ARMED-but-silently-dead).
  ///
  /// Under the [_maxMintAttempts] budget it RETRIES (scheduled off `build`,
  /// never a write IN `build`), so a TRANSIENT bd blip recovers with no
  /// operator action. AT the budget it ESCALATES: a distinct terminal flare
  /// then `_failed` inert — so the `_failed` state is now reached ONLY as an
  /// EXPLICIT, flared escalation, never as the first-failure swallow.
  ///
  /// There is NO session bead on the mint path (the mint is what failed), so —
  /// unlike breaker-exhaustion (D-5), which marks its OWN session bead — the
  /// scope retains the active diagnostic beside its flares; a human fixes the
  /// store and bounces the station.
  void _onMintFailed(Object error) {
    if (!_mintFailureActive) {
      setState(() {
        _mintFailureActive = true;
      });
    }
    if (_mintAttempts < _maxMintAttempts) {
      _flareMint(_mintFailedFlare, error);
      // Retry off `build` (invariant 2) — the scope stays `resolving` (it was
      // never rendered ready), so no setState is needed. The guard re-checks
      // liveness before re-entering the mint; a disposed scope drops the retry.
      scheduleMicrotask(() {
        if (_cancelled || !context.mounted) return;
        unawaited(_mint());
      });
      return;
    }
    _flareMint(_mintExhaustedFlare, error);
    setState(() {
      _failed = true;
      _resolving = false;
    });
  }

  /// LOUD-signals a mint failure (tg-6nf) through the reserved emit-only
  /// [ExplorationTransport] (D-8) — the SAME sink `CapabilityHost._emitFlare`
  /// and [_flareRearmFailed] fire through. Carries the work bead + the attempt
  /// budget so an observer can COUNT which scopes are dead-minting (the
  /// visibility that replaces a silent `mounted=0`). A throwing/absent transport
  /// never re-breaks the mint microtask.
  ///
  /// The trajectory record rides HERE rather than at the two call sites so the
  /// flare and the append can never disagree about which mint outcome just
  /// happened: [name] is the discriminator both read.
  void _flareMint(String name, Object error) {
    final reason = '$error';
    _recorder.mintOutcome(
      workBeadId: seed.bead.id,
      // `exhausted` ends the mount sequence (the budget is spent and the scope
      // goes inert); `failed` leaves it open for the next bounded retry.
      phase: name == _mintExhaustedFlare
          ? MintPhase.exhausted
          : MintPhase.failed,
      mintAttempt: _mintAttempts,
      maxAttempts: _maxMintAttempts,
      reason: reason,
      mountAttemptMetadata: _mountAttemptMetadata,
    );
    try {
      _services.transport?.flare(name, {
        'workBeadId': seed.bead.id,
        'attempt': '$_mintAttempts',
        'maxAttempts': '$_maxMintAttempts',
        'reason': truncateReason(reason),
        ...stateStoreDeadlineMetadata(error),
      });
    } catch (_) {
      // A throwing transport never re-breaks the mint microtask — swallow.
    }
  }

  /// Schedules the positive-terminal close — latched once, run off `build`
  /// (never a write IN `build`).
  void _scheduleClose(String id) {
    if (_terminalScheduled) return;
    _terminalScheduled = true;
    scheduleMicrotask(() => unawaited(_completeAndClose(id)));
  }

  String get _rootDeliveryNodePath =>
      stepPath(seed.bead.id, seed.circuit.terminalStepId);

  bool _deliveryOutcomeReady(Map<String, Map<String, String>> results) {
    final method = _services.delivery;
    if (method == null) return true;
    return results[_rootDeliveryNodePath]?[ResultKeys.delivery] != null;
  }

  void _flareDeliveryOutcomeMissing(String id) {
    if (_deliveryOutcomeBlocked) return;
    _deliveryOutcomeBlocked = true;
    final method = _services.delivery;
    _flare('delivery.outcomeMissing', {
      'sessionId': id,
      'workBeadId': seed.bead.id,
      'nodePath': _rootDeliveryNodePath,
      'method': method?.id ?? '',
    });
  }

  /// Stamps the durable POSITIVE-TERMINAL marker (`grid.outcome=complete`, I-10)
  /// through the chokepoint, THEN closes. The marker is what a later mount reads
  /// to tell a FINISHED round from a session somebody closed mid-flight — without
  /// it, the disposition falls back to cursor shape, which cannot see a circuit
  /// closed BETWEEN steps (every WRITTEN node complete, the circuit not).
  ///
  /// Neither write rethrows: an unhandled async error in a resident station's
  /// root zone would terminate the isolate (the same discipline as `_rearm`). A
  /// dropped marker is LOUD but not fatal (the legacy cursor fallback still reads
  /// a finished round as `done`), so the close ALWAYS runs.
  ///
  /// On the MOLECULE arm ([_isMolecule], captured — D-H rule 1) every close
  /// path fires [StationBeadWriter.reapMolecule] (R6's session-close
  /// collection, `DESIGN-tg-pm6.md` §9/§12): a terminal session is exactly
  /// when its own `type=molecule`/`type=step` beads stop being needed live
  /// (`bd purge` reaps only ephemerals, and this pour is deliberately
  /// persistent — item 1). Placed AFTER the outcome stamp so a reader who
  /// sees `grid.outcome=complete` before the reap lands still reads a
  /// coherent "this round finished" signal; a reap failure is LOUD, never
  /// fatal (the same non-rethrow discipline as the two writes above), and
  /// the close ALWAYS still runs — an un-reaped molecule is inert leftover
  /// state, not a wedge.
  Future<void> _completeAndClose(String id) async {
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      await ctx.admission.completeSession(
        workBeadId: seed.bead.id,
        sessionId: id,
        outcomeMarked: false,
        reapMolecule: _isMolecule,
        services: _services,
      );
    } on Object catch (error) {
      _flare('session.outcomeUnmarked', {
        'sessionId': id,
        'reason': truncateReason('$error'),
      });
    }
    final reapWorktree = seed.reapWorktree;
    final workRoot = seed.workRoot;
    final sourceControl = _services.sourceControl;
    if (reapWorktree != null && workRoot != null && sourceControl != null) {
      try {
        final outcome = await reapWorktree(
          root: workRoot,
          worktree: BeadWorktree(
            beadId: seed.bead.id,
            path: sourceControl.workspaceFor(seed.bead.id),
            branch: sourceControl.branchFor(seed.bead.id),
          ),
        );
        if (outcome.removed) {
          // §2.3's worktree rows: the record carries the path + branch the
          // flares below omit — the two facts an operator has to reconstruct
          // by hand today.
          _recorder.worktreeReaped(
            sessionId: id,
            worktree: sourceControl.workspaceFor(seed.bead.id),
            branch: sourceControl.branchFor(seed.bead.id),
          );
          _flare('session.worktreeReaped', {
            'sessionId': id,
            'workBeadId': seed.bead.id,
          });
        } else {
          _recorder.worktreeHeld(
            sessionId: id,
            worktree: sourceControl.workspaceFor(seed.bead.id),
            branch: sourceControl.branchFor(seed.bead.id),
          );
          _flare('session.worktreeReapHeld', {
            'sessionId': id,
            'workBeadId': seed.bead.id,
            'uncommitted': outcome.uncommitted.name,
            'unpushed': outcome.unpushed.name,
            'stashes': outcome.stashed.name,
            'reason': truncateReason(outcome.refusedReason ?? 'reap refused'),
          });
        }
      } on Object catch (error) {
        _flare('session.worktreeReapFailed', {
          'sessionId': id,
          'workBeadId': seed.bead.id,
          'reason': truncateReason('$error'),
        });
      }
    }
    try {
      await ctx.admission.completeSession(
        workBeadId: seed.bead.id,
        sessionId: id,
        outcomeMarked: true,
        reapMolecule: _isMolecule,
        services: _services,
      );
      // §2.3's `attempt.terminal(succeeded)` row — derived at the
      // OUTCOME-BEARING caller (r2 major 6). The bare `writer.close` is the
      // shared close for every disposition and carries no outcome, so it is
      // deliberately not a derivation site; this method is the one that knows
      // the close means "done". ONE record, no tail: the four-step terminal
      // tail stays legacy for the whole shadow window.
      _recorder.sessionCompleted(sessionId: id, workBeadId: seed.bead.id);
      _flare('session.closed', {'sessionId': id, 'disposition': 'done'});
      await _closeTerminalGates(
        id,
        GateCloseCause.sessionTerminal,
        const SessionDisposition.done(),
      );
    } on Object catch (error) {
      _flare('session.closeFailed', {
        'sessionId': id,
        'reason': truncateReason('$error'),
      });
    }
  }

  /// Schedules the breaker-exhaustion escalation (D-5): write the human marker
  /// (+ the capture-only [reason] diagnostic, FT-1) onto the OWN session bead,
  /// then close — which tears the subtree down, killing any leaked daemons (the
  /// §9 failure path). Latched once, off `build`.
  void _scheduleEscalation(String id, String reason) {
    if (_terminalScheduled) return;
    _terminalScheduled = true;
    scheduleMicrotask(() => unawaited(_escalateAndClose(id, reason)));
  }

  void _scheduleDerivedEscalation({
    required String sessionId,
    required String nodePath,
    required String stepBeadId,
    required String reason,
    required NodeCursor node,
    required int stepRound,
  }) {
    if (_terminalScheduled) return;
    _terminalScheduled = true;
    scheduleMicrotask(
      () => unawaited(
        _persistDerivedEscalation(
          sessionId: sessionId,
          nodePath: nodePath,
          stepBeadId: stepBeadId,
          reason: reason,
          node: node,
          stepRound: stepRound,
        ),
      ),
    );
  }

  Future<void> _persistDerivedEscalation({
    required String sessionId,
    required String nodePath,
    required String stepBeadId,
    required String reason,
    required NodeCursor node,
    required int stepRound,
  }) async {
    final station = _ctx;
    if (station == null) return;
    await persistRaisedEscalation(
      // The derived TWIN of `CapabilityHost`'s park (§2.3's gated row) — same
      // shared persist, so the same `step.transition(gated)` record.
      recorder: _recorder,
      stepRound: stepRound,
      incarnation: node.restartCount,
      station: station,
      services: _services,
      request: EscalationRequest(
        beadId: seed.bead.id,
        sessionId: sessionId,
        nodePath: nodePath,
        reason: reason,
        rewindCount: node.rewindCount,
      ),
      stepBeadId: stepBeadId,
      gatedMetadata: stepBeadMetadata(node.copyWith(state: StepState.gated)),
      isActive: () => !_cancelled && context.mounted,
      failToSupervision: (failure) =>
          _escalateAndClose(sessionId, '$nodePath: $failure'),
      emitFlare: _flare,
    );
  }

  /// Re-arms ONE parked node whose gate bead has closed (D-7): flips its cursor
  /// `gated` → `pending` through the chokepoint so the route re-runs. Deduped
  /// per node via the in-flight [_rearming] guard (see its doc), scheduled off
  /// `build` (never a write IN `build`).
  ///
  /// [moleculeTarget] is the STEP bead id the flip targets (`build`'s
  /// `beadIdByNodePath[nodePath]`, resolved at SCHEDULE time — the write
  /// itself runs off-build). Null is unreachable by construction (a legacy
  /// flat session's cursor is empty, so no gated node ever schedules) and is
  /// refused LOUD in [_rearm] rather than falling back to a session-bead
  /// write the flat model used to make.
  /// [stepRound] and [incarnation] are the correlation facts the trajectory's
  /// re-arm record needs (§2.2): the gate-resume predecessor round and the
  /// persisted `restartCount` at THIS node, both of which `build` has in hand
  /// and the off-build write does not. Captured at schedule time, exactly like
  /// [moleculeTarget] — and REQUIRED: a second caller that forgot them would
  /// compile clean and append `step_round: 0`, the exact silent-0 the field
  /// exists to kill.
  void _scheduleRearm(
    String id,
    String nodePath, {
    required int stepRound,
    required int incarnation,
    String? moleculeTarget,
  }) {
    if (_rearming.contains(nodePath)) return;
    _rearming.add(nodePath);
    scheduleMicrotask(
      () => unawaited(
        _rearm(
          id,
          nodePath,
          moleculeTarget,
          stepRound: stepRound,
          incarnation: incarnation,
        ),
      ),
    );
  }

  /// In-flight guard for [_resumeOrphanedPour] — a build can fire many times
  /// while the resume's own write is in flight; the pour must not be
  /// re-submitted per tick. Reset on BOTH arms (tg-q3q0 deep): a resume whose
  /// createMolecule no-ops (R6 dedup) used to leave the latch set forever,
  /// idling the scope; re-submission is dedup-safe and snapshot-gated.
  bool _resumingOrphanedPour = false;

  /// Schedules [_resumeOrphanedPour] off the build (a build never awaits).
  void _scheduleOrphanedPourResume(String sessionId) {
    if (_resumingOrphanedPour) return;
    _resumingOrphanedPour = true;
    scheduleMicrotask(() => unawaited(_resumeOrphanedPour(sessionId)));
  }

  /// Completes an ORPHANED molecule pour (tg-nmhy case 2): this scope joined
  /// a molecule session bead whose step graph never landed — the minting
  /// predecessor was reconciled away between `createSession` and
  /// `createMolecule`, and its mounted-check abandoned the pour silently.
  /// The plan is rebuilt deterministically and poured through the SAME
  /// re-entry-safe `createMolecule` (R6 dedup) the original mint uses.
  Future<void> _resumeOrphanedPour(String sessionId) async {
    final ctx = _ctx;
    if (ctx == null || _cancelled) {
      _resumingOrphanedPour = false;
      return;
    }
    try {
      final root = BeadPathKey([seed.bead.id, sessionId]);
      final plan = instantiateMolecule(
        seed.circuit,
        sessionId: sessionId,
        root: root,
        nodePath: seed.bead.id,
        circuitById: _registry?.circuit,
      );
      await ctx.admission.pourMolecule(
        plan,
        workBeadId: seed.bead.id,
        sessionId: sessionId,
        rootCrumbs: root.crumbs,
        services: _services,
      );
    } on Object catch (error) {
      // Same terminal park as the fresh-mint path: the session bead EXISTS
      // (this scope adopted it), so a thrown pour is made LOUD and durable
      // instead of silently retried against the same cause forever.
      try {
        await _parkFailedMoleculePour(sessionId, error, retiredSessionId: null);
      } on Object catch (parkError) {
        // Recovery invariant: the gate write did not land, so no durable park
        // exists and this adopted step-less session must remain non-terminal.
        // Clearing the in-flight latch lets a later snapshot-driven build
        // re-attempt the dedup-safe pour; this flare keeps that retryable debt
        // LOUD without escaping the unawaited resident microtask.
        _flare(_moleculePourParkFailedFlare, {
          'sessionId': sessionId,
          'workBeadId': seed.bead.id,
          'reason': truncateReason('$parkError'),
        });
      }
    } finally {
      // tg-q3q0 (deep): reset after EVERY outcome. createMolecule's R6 dedup
      // can no-op (steps exist but closed, or the projection lags), while a
      // failed park must remain retryable because no durable terminal exists.
      // Re-submission is dedup-safe and builds are snapshot-gated, so resetting
      // here is bounded, not a hot loop.
      _resumingOrphanedPour = false;
    }
  }

  void _scheduleStepSuccessorMint({
    required String sessionId,
    required String nodePath,
    required Bead priorStep,
    required int currentDepth,
    required int spentRounds,
  }) {
    if (_mintingSuccessorForPath.contains(nodePath)) return;
    _mintingSuccessorForPath.add(nodePath);
    scheduleMicrotask(
      () => unawaited(
        _mintStepSuccessor(
          sessionId: sessionId,
          nodePath: nodePath,
          priorStep: priorStep,
          currentDepth: currentDepth,
          spentRounds: spentRounds,
        ),
      ),
    );
  }

  Future<void> _mintStepSuccessor({
    required String sessionId,
    required String nodePath,
    required Bead priorStep,
    required int currentDepth,
    required int spentRounds,
  }) async {
    final ctx = _ctx;
    if (ctx == null) {
      _mintingSuccessorForPath.remove(nodePath);
      return;
    }
    final attempt = (_stepSuccessorMintAttemptsByPath[nodePath] ?? 0) + 1;
    _stepSuccessorMintAttemptsByPath[nodePath] = attempt;
    try {
      if (spentRounds >= kMaxReworkRounds) {
        throw StateError(
          'step successor refused at verdict cap '
          '($spentRounds/$kMaxReworkRounds) for "$nodePath"',
        );
      }
      await ctx.writer.createStepSuccessor(
        substation: ctx.stateSubstation,
        priorStep: priorStep,
        spentRounds: spentRounds,
        maxRounds: kMaxReworkRounds,
      );
      _stepSuccessorMintAttemptsByPath.remove(nodePath);
    } on Object catch (error) {
      final reason = truncateReason('$error');
      _flare('session.stepSuccessorMintFailed', {
        'sessionId': sessionId,
        'nodePath': nodePath,
        'attempt': '$attempt',
        'maxAttempts': '$_maxStepSuccessorMintAttempts',
        'reason': reason,
      });
      if (attempt < _maxStepSuccessorMintAttempts) {
        // Retry off the current write/build turn through the existing
        // same-path dedup seam. The scheduled callback runs after [finally]
        // clears the in-flight guard.
        scheduleMicrotask(() {
          if (_cancelled || !context.mounted) return;
          _scheduleStepSuccessorMint(
            sessionId: sessionId,
            nodePath: nodePath,
            priorStep: priorStep,
            currentDepth: currentDepth,
            spentRounds: spentRounds,
          );
        });
        return;
      }
      _flare(_stepSuccessorMintExhaustedFlare, {
        'sessionId': sessionId,
        'nodePath': nodePath,
        'attempt': '$attempt',
        'maxAttempts': '$_maxStepSuccessorMintAttempts',
        'reason': reason,
      });
      // SessionScope is outside the one router where EscalationHandler is
      // ambient. This is the same durable chokepoint HumanGate resolves to,
      // reused at a successor-write site the handler seam does not reach.
      await ctx.writer.parkSessionAtGate(
        substation: ctx.stateSubstation,
        sessionId: sessionId,
        nodePath: nodePath,
        reason: reason,
      );
      if (_cancelled || !context.mounted) return;
      setState(() {
        _failed = true;
        _resolving = false;
      });
    } finally {
      _mintingSuccessorForPath.remove(nodePath);
    }
  }

  /// The re-arm write itself (tg-boq): flips the parked node to `pending`, then
  /// clears the in-flight guard so the NEXT build retries on failure and a later
  /// gate cycle can re-arm again. A dropped write is LOUD (a flare through the
  /// emit-only transport) — never SILENT, never PERMANENT (the guard principle:
  /// LOUD or GONE). It is NOT rethrown: an uncaught async error in a resident
  /// station's root zone would terminate the isolate, so a transient bd blip
  /// must not crash the whole station — the retry (via the cleared guard) is the
  /// recovery, the flare is the signal.
  ///
  /// The write is a MINIMAL single-key `grid.step.state` merge write on the
  /// STEP bead [moleculeTarget] (never a full [stepBeadMetadata] rebuild,
  /// which would clobber the persisted `restartCount`/telemetry with fresh
  /// defaults). `build` never schedules a re-arm for a node the R4
  /// DERIVATION currently holds back (its own `invalidated` exclusion), so
  /// this write only ever targets a node parked by a REAL `HumanGate`.
  Future<void> _rearm(
    String id,
    String nodePath,
    String? moleculeTarget, {
    required int stepRound,
    required int incarnation,
  }) async {
    final ctx = _ctx;
    if (ctx == null) {
      // Impossible for a mounted scope (`didChangeDependencies` captures `_ctx`
      // before any build) — but do NOT drop silently if it ever happens: clear
      // the guard (a later build retries) and flare.
      _rearming.remove(nodePath);
      _flareRearmFailed(nodePath, 'no StationServices captured');
      return;
    }
    if (moleculeTarget == null) {
      // Unreachable by construction (see [_scheduleRearm]'s doc) — but never
      // fall back to the retired flat session-bead write; refuse LOUD.
      _rearming.remove(nodePath);
      _flareRearmFailed(
        nodePath,
        'no step bead maps nodePath "$nodePath" — cannot re-arm',
      );
      return;
    }
    final current = seed.existingSession;
    final disposition = sessionDispositionOf(
      current?.sessionId == id ? current : null,
    );
    if (_isBlockingDisposition(disposition)) {
      _rearming.remove(nodePath);
      _flare('gate.rearmRefused', {
        'sessionId': id,
        'nodePath': nodePath,
        'reason': 'session is closed',
      });
      return;
    }
    try {
      await ctx.writer.update(
        moleculeTarget,
        metadata: {MoleculeStepKeys.state: StepState.pending.name},
      );
      // §2.3's re-arm row: `cause='gate_cleared'` with `step_round` BUMPED —
      // the record that kills the I-14 stale-join loop at the cut. During the
      // shadow window it only shadows the legacy single-key flip above, which
      // stays exactly as it is (nothing about what mounts changes).
      _recorder.stepRearmed(
        sessionId: id,
        stepPath: nodePath,
        fromStepRound: stepRound,
        incarnation: incarnation,
      );
      // Settled OK: clear the guard. The store's `gated`→`pending` flip stops
      // D-7 from re-firing (and frees a future gate cycle to re-arm).
      _rearming.remove(nodePath);
    } on Object catch (error) {
      // Settled FAILED: clear the guard so the next build retries, and flare so
      // the drop is not silent. NOT rethrown (see the method doc — a crash would
      // be worse than the wedge this fixes).
      _rearming.remove(nodePath);
      _flareRearmFailed(nodePath, '$error');
    }
  }

  /// LOUD-signals a DROPPED gate re-arm (tg-boq) through the reserved emit-only
  /// [ExplorationTransport] (D-8) — the same sink `CapabilityHost._emitFlare`
  /// and `WorkList` use. A silently-swallowed re-arm failure wedged the parked
  /// node `gated` forever (operator recovery was a station bounce); this makes
  /// the failure observable (leonard reads it over the exploration host, A39/A40)
  /// while the cleared guard makes it retryable. A throwing/absent transport
  /// never re-breaks the microtask.
  void _flareRearmFailed(String nodePath, String reason) {
    try {
      _services.transport?.flare('gate.rearmFailed', {
        'sessionId': _sessionId ?? '',
        'nodePath': nodePath,
        'reason': truncateReason(reason),
      });
    } catch (_) {
      // A throwing transport never re-breaks the re-arm microtask — swallow.
    }
  }

  void _scheduleRetiredRework(SessionProjection retired) {
    if (_resolving || _failed || retired.sessionId != _sessionId) return;
    _retiredReworkSessionId = retired.sessionId;
    // The `#rN` key names the round being MINTED; the retired-round close
    // derives its `attempt.round.retired` from it (§2.2's round row). Set here
    // as well as in `initState`: this is the LIVE path — a mounted scope
    // observing the operator's re-key — while that one covers a scope that
    // MOUNTS on an already-retired round.
    _retiredReworkRound = reworkRoundOf(seed.bead.id, retired.workBeadId);
    _sessionId = null;
    _resolving = true;
    _terminalScheduled = false;
    _rearming.clear();
    _mintingSuccessorForPath.clear();
    _stepSuccessorMintAttemptsByPath.clear();
    _mintAttempts = 0;
    _moleculeSessionId = null;
    _mintFailureActive = false;
    _requiresFreshMintSnapshot = true;
    scheduleMicrotask(() => unawaited(_mint()));
  }

  /// Schedules a LOUD rework decline (tg-x1j v2, the guard principle): the
  /// adopted session vanished from the join but this scope never observed it
  /// parked at a gate — re-minting could silently abandon a live round, so it
  /// marks the (still-reachable-by-id) session and goes permanently inert
  /// (mirroring [_mint]'s `_failed` path).
  void _scheduleReworkDecline(String retiredId) {
    if (_resolving || _failed || retiredId != _sessionId) return;
    _resolving = true;
    scheduleMicrotask(() => unawaited(_declineRework(retiredId)));
  }

  /// The durable decline reason — one string, written to the bead and carried
  /// into the record, so the two can never drift.
  static const _reworkDeclinedReason =
      'session retired (work_bead re-keyed) while this scope never '
      'observed it parked at a gate — refusing to abandon a possibly-'
      'live round; a human must investigate';

  Future<void> _declineRework(String retiredId) async {
    final ctx = _ctx;
    if (ctx == null) return;
    await ctx.admission.markReworkDeclined(
      workBeadId: seed.bead.id,
      sessionId: retiredId,
      reason: _reworkDeclinedReason,
    );
    // §2.3's `attempt.rework_declined` row: after the HELD merge landed.
    _recorder.reworkDeclined(
      sessionId: retiredId,
      reason: _reworkDeclinedReason,
    );
    if (_cancelled || !context.mounted) return;
    setState(() {
      _failed = true;
      _resolving = false;
    });
  }

  Future<void> _escalateAndClose(String id, String reason) async {
    // Runs to completion even if SessionScope is mid-dispose — the escalation
    // marker + close must be durable (uses the captured ctx, never `context`).
    final ctx = _ctx;
    if (ctx == null) return;
    await ctx.admission.escalateAndCloseSession(
      workBeadId: seed.bead.id,
      sessionId: id,
      reason: reason,
      reapMolecule: _isMolecule,
      services: _services,
    );
    // §2.3's `attempt.terminal(escalated)` row — the reason is the same
    // `grid.escalation_reason` the marker write above carried.
    _recorder.sessionEscalated(
      sessionId: id,
      workBeadId: seed.bead.id,
      reason: reason.isEmpty ? null : reason,
    );
    _flare('session.closed', {
      'sessionId': id,
      'disposition': 'held',
      'reason': truncateReason(reason),
    });
  }

  @override
  void dispose() {
    final mintReadiness = _mintReadiness;
    if (mintReadiness != null && !mintReadiness.isCompleted) {
      // Null completion means disposal; there is no other producer.
      mintReadiness.complete(null);
    }
    _mintReadiness = null;
    _mintDecisionAt = null;
    _mintGraceTimer?.cancel();
    _mintGraceTimer = null;
    _cancelled = true;
    _mintingSuccessorForPath.clear();
  }

  @override
  Seed build(TreeContext context) {
    final existing = seed.existingSession;
    final retiredRound = existing == null
        ? null
        : reworkRoundOf(seed.bead.id, existing.workBeadId);
    if (retiredRound != null &&
        !_resolving &&
        !_failed &&
        existing!.sessionId == _sessionId) {
      _scheduleRetiredRework(existing);
      return const Idle();
    }
    final matchesJoin = existing?.sessionId == _sessionId;

    // A genuinely missing, non-`#rN` row after a prior join is malformed
    // disappearance, not operator rework. Refuse it LOUD. [_joinedOnce] keeps
    // fresh-mint join lag out of this arm; the durable retired-row branch above
    // is the only path that authorizes a re-mint.
    if (!_resolving &&
        !_failed &&
        _sessionId != null &&
        _joinedOnce &&
        !matchesJoin &&
        retiredRound == null) {
      _scheduleReworkDecline(_sessionId!);
    }

    if (!_failed && matchesJoin) {
      final disposition = sessionDispositionOf(existing);
      if (_isBlockingDisposition(disposition)) {
        _rearming.clear();
        _declineMount(disposition);
        return const Idle();
      }
    }

    if (_resolving || _failed || _sessionId == null) {
      return const Idle();
    }
    final id = _sessionId!;
    // The join reflects THIS scope's session only when the ids match. A
    // MISMATCHED projection is some other row — the DEAD key we just minted over
    // (I-10), until the join catches up, or a rework-retired round — and
    // threading ITS cursor down under OUR handle would corrupt the frontier
    // (steps reading `complete`/`running` that this session never ran). So the
    // cursor is read ONLY from a matching join; otherwise it is empty, which is
    // exactly what a fresh round's cursor IS.
    final joined = matchesJoin ? seed.existingSession : null;
    final closedGateCountByNodePath =
        joined?.closedGateCountByNodePath ?? const <String, int>{};

    // The reentrant capability/circuit resolution seam — read ONCE, ambient;
    // the flat broken/complete check below needs it to resolve a
    // `SubCircuitStep`'s own nested circuit (`firstBrokenNode`/
    // `isCircuitComplete`).
    final registry = context.watch<CapabilityRegistry>();

    // Project this session's OWN molecule graph into the in-memory
    // CircuitCursor shape, then layer A52 Ratified live derivation over it.
    // The `else` arm is the HISTORICAL-flat-adopt residual (tg-eli phase 2):
    // a legacy session's `grid.cursor.*` keys no longer project
    // (`SessionProjection.cursor` is always empty), so it feeds an empty
    // cursor/results — the frontier would mount from `pending`, and every
    // host persist under it refuses LOUD (no `InheritedCircuit` mounts).
    final isMolecule = joined?.isMolecule ?? false;
    final CircuitCursor cursor;
    final Map<String, Map<String, String>> results;
    var beadIdByNodePath = const <String, String>{};
    var invalidated = const <String>{};
    var heldForSuccessor = const <String>{};
    var moleculeProjectedCursor = const <String, NodeCursor>{};
    var structuralDepthByPath = const <String, int>{};
    var spentRoundsByPath = const <String, int>{};
    var circuitRoundsByPath = const <String, int>{};
    if (isMolecule) {
      final projected = projectMoleculeCursor(
        joined!.moleculeBeads,
        dependencies: joined.moleculeDependencies,
      );
      // CONSUMER 6 of the step dual read (cut-wiring C4) — the MOUNT-FRONTIER
      // authority and the most decision-bearing cursor read in the tree. It
      // adopts at the projection point, so everything downstream (the R4
      // derivation, the invalidation walk, the successor holds, the gate
      // re-arm sweep) reads ONE cursor: without it the station would run two
      // cursor truths under `primary` — the park check and the unclaimed
      // frontier on the fold, the scope that actually mounts steps on its own
      // bead recompute.
      //
      // The site's today-read is the bead recompute, so the unengaged branch
      // is the identity and this is a pure read swap.
      moleculeProjectedCursor = effectiveStepCursor(
        joined,
        siteCursor: projected.cursor,
        beadCursor: projected.cursor,
      );
      beadIdByNodePath = projected.beadIdByNodePath;
      if (beadIdByNodePath.isEmpty) {
        // A molecule session ALWAYS carries step beads — `_mintMolecule`
        // pours them (`createMolecule`) immediately after `createSession`.
        // A joined snapshot that claims `isMolecule` yet projects ZERO step
        // beads is one of two things (tg-nmhy):
        //
        // 1. The store-write gap BETWEEN the two writes — the next tick
        //    carries the poured graph; idling is enough.
        // 2. An ORPHANED POUR: `_mintMolecule`'s own post-`createSession`
        //    mounted-check silently abandoned the pour because the session
        //    write's snapshot tick reconciled THIS scope's predecessor out
        //    from under it mid-mint. The adopting scope (us) joins a
        //    step-less molecule session that NO ONE will ever pour — the
        //    exact `DESIGN-tg-pm6.md` §3 "crashed pour" ambiguity. Live
        //    receipt: 14/14 sessions minted and ZERO poured, an entire arm
        //    idle (2026-07-26).
        //
        // Idling alone cannot distinguish them, so RESUME the pour: the
        // plan is deterministic (`instantiateMolecule`) and `createMolecule`
        // is re-entry-safe (R6's dedup probe), so case 1 degrades to a
        // no-op and case 2 completes the mint. Either way the next
        // snapshot carries the steps and this branch stops firing.
        _scheduleOrphanedPourResume(id);
        return const Idle();
      }
      structuralDepthByPath = supersedesDepthByPath(
        joined.moleculeBeads,
        joined.moleculeDependencies,
      );
      spentRoundsByPath = supersedesVerdictCountByPath(
        joined.moleculeBeads,
        joined.moleculeDependencies,
      );
      circuitRoundsByPath = {
        for (final entry in structuralDepthByPath.entries)
          entry.key:
              entry.value +
              (closedGateCountByNodePath[closedGateCountKey(
                    entry.key,
                    entry.value,
                  )] ??
                  0),
      };
      final activeByPath = activeStepBeadsByPath(
        joined.moleculeBeads,
        joined.moleculeDependencies,
      );
      // ResultKeys is reused VERBATIM on the step bead (R1) — each ACTIVE
      // step bead's OWN `grid.result.<itsOwnNodePath>.*` keys project through
      // the SAME `projectCircuitResults` the flat codec used on the session
      // bead; merging the active incarnation at each path yields that shape
      // without allowing superseded results to overwrite current results.
      final stepResults = <String, Map<String, String>>{};
      for (final b in activeByPath.values) {
        stepResults.addAll(projectCircuitResults(b));
      }
      results = mergeOperatorRulings(stepResults, joined.results);
      invalidated = invalidatedNodes(
        seed.circuit,
        moleculeProjectedCursor,
        results,
        seed.bead.id,
        circuitById: registry?.circuit ?? (String _) => null,
        supersedesDepthByPath: structuralDepthByPath,
      );
      final effective = effectiveCursor(
        seed.circuit,
        moleculeProjectedCursor,
        results,
        seed.bead.id,
        circuitById: registry?.circuit ?? (String _) => null,
        supersedesDepthByPath: structuralDepthByPath,
        spentReworkRoundsByPath: spentRoundsByPath,
      );
      final holds = <String>{};
      for (final path in invalidated) {
        final depth = structuralDepthByPath[path] ?? 0;
        final spentRounds = spentRoundsByPath[path] ?? 0;
        if (spentRounds >= kMaxReworkRounds) continue;
        final priorStep = activeByPath[path];
        final node = moleculeProjectedCursor[path];
        if (priorStep == null || node == null || !node.isPositiveTerminal) {
          continue;
        }
        _scheduleStepSuccessorMint(
          sessionId: id,
          nodePath: path,
          priorStep: priorStep,
          currentDepth: depth,
          spentRounds: spentRounds,
        );
        holds.add(path);
      }
      heldForSuccessor = holds;
      cursor = {
        ...effective,
        for (final path in holds)
          path: (effective[path] ?? const NodeCursor()).copyWith(
            state: StepState.gated,
          ),
      };
    } else {
      cursor = joined?.cursor ?? const <String, NodeCursor>{};
      results = joined?.results ?? const <String, Map<String, String>>{};
    }
    // The join reflects this session THIS build — latch it for the fresh-mint
    // join-lag guard above.
    if (matchesJoin) {
      _joinedOnce = true;
    }

    // D-7: re-arm any node parked at a gate whose gate bead has CLOSED (its
    // nodePath left `openGateNodes`). Read-only here; the flip to `pending` is
    // scheduled off build (invariant 2), latched once per node. A still-open
    // gate is left parked. `invalidated` (always empty on the flat path)
    // excludes a node the R4 derivation currently holds back — see above.
    final openGates = joined?.openGateNodes ?? const <String>{};
    cursor.forEach((nodePath, node) {
      if (node.state == StepState.gated &&
          !openGates.contains(nodePath) &&
          !invalidated.contains(nodePath)) {
        final structuralRound = structuralDepthByPath[nodePath] ?? 0;
        final resumedStepRound =
            circuitRoundsByPath[nodePath] ?? structuralRound;
        final closedGateCount =
            closedGateCountByNodePath[closedGateCountKey(
              nodePath,
              structuralRound,
            )] ??
            0;
        _scheduleRearm(
          id,
          nodePath,
          moleculeTarget: beadIdByNodePath[nodePath],
          // `stepRearmed` advances its supplied predecessor round, while the
          // resumed StepMount receives the already-incremented circuit round.
          stepRound: closedGateCount == 0
              ? resumedStepRound
              : resumedStepRound - 1,
          incarnation: node.restartCount,
        );
      }
    });

    // D-2/D-5: own the terminal. Read-only here (the predicates are pure); the
    // actual write is scheduled off build (never a write IN build, invariant 2).
    // Breaker-exhaustion (broken ANYWHERE in the subtree) escalates + tears
    // down; otherwise a positive terminal closes. Distinguishing
    // empty-because-broken from empty-because-complete is the whole point of D-5.
    if (registry != null && !_terminalScheduled) {
      if (!_terminalScheduled) {
        final derived = isMolecule && heldForSuccessor.isEmpty
            ? derivedEscalation(
                seed.circuit,
                moleculeProjectedCursor,
                results,
                seed.bead.id,
                circuitById: registry.circuit,
                supersedesDepthByPath: structuralDepthByPath,
                spentReworkRoundsByPath: spentRoundsByPath,
              )
            : null;
        if (derived != null) {
          final stepBeadId = beadIdByNodePath[derived.path];
          final node = cursorNodeAt(cursor, derived.path);
          if (stepBeadId == null) {
            throw StateError(
              'derived escalation path "${derived.path}" has no step bead '
              'in session "$id"',
            );
          }
          _scheduleDerivedEscalation(
            sessionId: id,
            nodePath: derived.path,
            stepBeadId: stepBeadId,
            reason: derived.reason,
            node: node,
            stepRound: structuralDepthByPath[derived.path] ?? 0,
          );
        } else {
          final broken = firstBrokenNode(
            seed.circuit,
            cursor,
            seed.bead.id,
            circuitById: registry.circuit,
          );
          if (broken != null) {
            // Capture-only (FT-1): record WHICH node exhausted + its reason (read
            // from the cursor's persisted telemetry) beside the escalation marker.
            // Read-only here; the write is scheduled off build (invariant 2).
            final reason = truncateReason(
              '${broken.nodePath}: ${broken.node.failureReason ?? ''}',
            );
            _scheduleEscalation(id, reason);
          } else if (isCircuitComplete(
            seed.circuit,
            cursor,
            seed.bead.id,
            circuitById: registry.circuit,
          )) {
            if (_deliveryOutcomeReady(results)) {
              _scheduleClose(id);
            } else {
              _flareDeliveryOutcomeMissing(id);
            }
          }
        }
      }
    }

    // The per-session ambient values (ADR-0008 Decision 3, 2026-07-02 — the
    // context rip-out): the SessionHandle (value-equal, so a same-id re-provide
    // never notifies), the Workspace (computed HERE from the per-substation
    // SourceControl — the synthetic placeholder covers the no-source-control
    // offline case, where nothing provisions nor lands), and the SiblingView
    // (this session's whole cursor + results — capabilities read it with the
    // effect verb; nothing registers on it, so a fresh instance per build
    // notifies nobody).
    //
    // The SourceControl is this substation's ONE root (v3 single-root: a
    // bead's root IS its substation's root — no `metadata.grid.root` selector).
    // The bundle captured in `didChangeDependencies` (the dependency is
    // registered there) — reused so `build` and the off-build re-arm flare read
    // the SAME ambient value.
    final services = _services;
    final sc = services.sourceControl;
    final beadId = seed.bead.id;
    final workspace = Workspace(
      workspaceDir: sc?.workspaceFor(beadId) ?? '/grid/workspaces/$beadId',
      branch: sc?.branchFor(beadId) ?? '',
      baseBranch: sc?.baseBranch ?? 'main',
    );
    Seed inflater = CircuitScope(
      circuit: seed.circuit,
      cursor: cursor,
      nodePath: seed.bead.id,
      circuitRoundsByPath: circuitRoundsByPath,
    );
    return Nest(
      children: [
        Provider<SessionHandle>.value(SessionHandle(id)),
        Provider<Workspace>.value(workspace),
        Provider<SiblingView>.value(
          SiblingView(cursor: cursor, results: results),
        ),
        if (isMolecule)
          Provider<InheritedCircuit>.value(
            InheritedCircuit(
              root: BeadPathKey([seed.bead.id, id]),
              beadIdByNodePath: beadIdByNodePath,
              cursor: cursor,
            ),
          ),
      ],
      child: inflater,
    );
  }
}
