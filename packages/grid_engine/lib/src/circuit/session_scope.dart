/// The engine-private session lifecycle owner (ADR-0008 D4 / M4-P1 D-2).
///
/// `SessionScope` is mounted by `WorkBead` ABOVE the circuit fan-out (the
/// resolver returns it). It **adopt-or-mints** the the_grid session bead, holds
/// `{resolving | ready | failed}`, and on `ready` provides a stable
/// `InheritedSeed<SessionHandle>` over the `CircuitScope` so the inflater + every
/// `CapabilityHost` attach to the SAME session — establishing the session is a
/// tree *state* (a loading state, `const Idle()` until resolved), not a
/// synchronous id injection. This is the "Route resolves before its Page
/// attaches" shape (an abstraction, not a literal router). It is ALSO where the
/// per-session ambient values mount (2026-07-02): the `Workspace` (computed from
/// the per-substation `SourceControl`) and the `SiblingView` (this session's
/// cursor + results) — the values an effect reads with the non-binding lookup.
///
/// It owns the session lifecycle END-TO-END: it also CLOSES the session on the
/// circuit's positive terminal (D-2 — one owner for open+close, not the terminal
/// step's host). The close is SCHEDULED off `build` (never a write IN `build` —
/// invariant 2) and latched once. Breaker-exhaustion close + escalation fold in
/// at Track G.
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
/// **The drain seam (`DESIGN-tg-pm6.md` §12, R5) — the ADDITIVE molecule
/// mint-mode.** [_mint] branches on the ambient `SubstationConfig.circuitMintMode`
/// (default [CircuitMintMode.flatCursor]) ONLY when minting a FRESH session:
/// `flatCursor` mints exactly today's `writer.createSession(...)`, untouched;
/// `molecule` additionally stamps `grid.session.model=molecule` and pours a
/// durable `type=molecule`/`type=step` graph (`instantiateMolecule` → R6's
/// `createMolecule`) under the SAME [_maxMintAttempts] budget. [build] then
/// projects a molecule session's OWN beads
/// (`SessionProjection.moleculeBeads`) through `projectMoleculeCursor` into
/// the IDENTICAL `CircuitCursor` shape the flat path already feeds
/// `CircuitScope` — so the inflater is consumed UNCHANGED in both modes —
/// and wraps it in a 4th `InheritedSeed<InheritedCircuit>` so
/// `CapabilityHost` (R5b) targets each step's own durable bead. **Drain,
/// never convert:** [initState]'s `LiveSession()` arm adopts synchronously,
/// before any mode check runs — an in-flight session (flat OR molecule) is
/// never reinterpreted mid-round; only a FRESH mint ever reads
/// [CircuitMintMode].
///
/// A52 Ratified wires R4 live for molecule sessions: invalidated terminal
/// steps mint successor incarnation beads on a `supersedes` chain, and
/// `live_frontier.dart` derives generation from that chain depth.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';

import '../domain/session_bead.dart';
import '../domain/session_disposition.dart';
import '../domain/session_projection.dart';
import '../domain/rework.dart' show kMaxReworkRounds;
import '../domain/substation_config.dart';
import '../kernel/station_services.dart';
import '../kernel/idle.dart';
import '../molecule/bead_path_key.dart';
import '../molecule/inherited_circuit.dart';
import '../molecule/live_frontier.dart'
    show derivedEscalation, effectiveCursor, invalidatedNodes;
import '../molecule/molecule_codec.dart';
import '../molecule/molecule_schema.dart' show MoleculeStepKeys;
import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/cursor.dart';
import '../sdk/circuit.dart';
import '../sdk/frontier.dart';
import 'capability_registry.dart';
import 'circuit_scope.dart';
import 'session_handle.dart';

/// The adopt-or-mint session lifecycle owner for one work [bead]'s [circuit]
/// (D-2). Key it `ValueKey('${bead.id}:session')` so it persists across cursor
/// ticks while the work node keeps its branch identity.
class SessionScope extends StatefulSeed {
  /// Creates the scope for [bead] running [circuit], with the bead's linked
  /// [existingSession] (null until a session exists — then `SessionScope` mints
  /// one; non-null → it adopts).
  const SessionScope({
    required this.bead,
    required this.circuit,
    this.existingSession,
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

  @override
  State<SessionScope> createState() => SessionScopeState();
}

/// The `{resolving | ready | failed}` lifecycle (D-2). The async-gap guards
/// (`_cancelled` set first in `dispose`, `context.mounted` after every await,
/// the captured `_ctx`) are the same discipline as `CapabilityHostState`.
class SessionScopeState extends State<SessionScope> {
  /// The bounded `createSession` retry budget (tg-6nf) — a mint failure is
  /// RETRIED up to this many TOTAL attempts before the scope escalates LOUD
  /// (the circuit-breaker's bounded-retry discipline, D-5). Small on purpose:
  /// the FIRST-LIVE-ARM incident (2026-07-10) was a PERSISTENT store
  /// misconfiguration (`bd create -t session` rejected — no `types.custom`),
  /// for which retry cannot help; the budget exists to ride out a TRANSIENT bd
  /// blip, and its EXHAUSTION is the escalation trigger.
  static const _maxMintAttempts = 5;

  /// The per-attempt mint-failed flare (tg-6nf) — a mint attempt threw and the
  /// scope is still RETRYING under [_maxMintAttempts].
  static const _mintFailedFlare = 'session.mintFailed';

  /// The terminal mint-EXHAUSTED flare (tg-6nf) — the [_maxMintAttempts] budget
  /// is spent; the scope escalates LOUD and goes inert (a human must fix the
  /// store — the exact FIRST-LIVE-ARM incident).
  static const _mintExhaustedFlare = 'session.mintExhausted';

  StationServices? _ctx;

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

  /// The DRAIN MIGRATION's mint-mode (`DESIGN-tg-pm6.md` §12, R5), captured
  /// off the ambient `SubstationConfig` for [_mint]'s async use — D-H rule 1.
  /// Consulted ONLY at [_mint] time; an ADOPTED session (`LiveSession()` in
  /// [initState]) never reads this at all (the drain guarantee).
  CircuitMintMode _mintMode = CircuitMintMode.flatCursor;

  String? _sessionId;
  bool _resolving = true;
  bool _failed = false;
  bool _cancelled = false;
  bool _terminalScheduled = false;

  /// True once THIS scope's session is known to be molecule-mode — set on
  /// ADOPT (`initState`'s `LiveSession()` arm reads
  /// `seed.existingSession!.isMolecule`) or on a successful molecule
  /// [_mint]; reset by [_reworkAndRemint] so round N+1 re-derives it fresh
  /// from [_mintMode]. Read by [_completeAndClose] (captured-field async use,
  /// D-H rule 1) to decide whether the positive-terminal close ALSO fires
  /// [StationBeadWriter.reapMolecule] (R6's session-close collection).
  bool _isMolecule = false;

  /// The session id already minted for an IN-PROGRESS molecule mint (tg-6nf)
  /// — set the instant `createSession` returns and cleared only when the
  /// WHOLE mint settles ([_reworkAndRemint]'s reset for round N+1). A retry
  /// that re-enters [_mint] after `createMolecule` throws must NEVER re-call
  /// `createSession` — that would strand the first session bead un-poured
  /// and mint a SECOND, exactly the "crashed pour" ambiguity
  /// `SessionBeadKeys.model` exists to prevent (`DESIGN-tg-pm6.md` §3
  /// conflict 2). Null on every flat-mode mint and before any molecule mint
  /// attempt.
  String? _moleculeSessionId;

  /// How many `createSession` attempts this scope has made (tg-6nf) — bounded
  /// by [_maxMintAttempts]; reaching the cap is the escalation trigger. Reset
  /// to 0 by [_reworkAndRemint] so round N+1 gets its own fresh budget.
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

  /// Whether the CURRENTLY adopted session was last observed with a node
  /// parked `gated` (tg-x1j v2) — refreshed every `build()` where
  /// `seed.existingSession` matches [_sessionId]; read once it stops matching
  /// (the rework orphan signal, see [build]) to decide whether re-minting is
  /// safe.
  bool _lastKnownGated = false;

  /// Whether `seed.existingSession` has EVER matched [_sessionId] (tg-x1j v2)
  /// — true once the join has genuinely reflected this scope's session at
  /// least one build. Guards the orphan-check in [build]: a FRESH MINT'S
  /// `existingSession` also reads null/mismatched until the join catches up
  /// (offline tests may never push that catch-up snapshot at all), and that
  /// must never be confused with an already-observed session vanishing.
  bool _joinedOnce = false;

  /// Latches the ONE-TIME rework transition (tg-x1j v2): `grid rework`
  /// re-keyed the adopted session's `work_bead` off this bead.id while it was
  /// still OPEN — scheduled off `build` (never a write IN `build`), so a
  /// repeated build tick during the async gap never re-schedules.
  bool _reworkScheduled = false;

  @override
  void didChangeDependencies() {
    // ALWAYS re-read (D-H rule 1) — the captured field exists for async-gap use
    // (`context` throws post-unmount), never as a read-once cache.
    final ctx = context.dependOnInheritedSeedOfExactType<StationServices>();
    assert(
      ctx != null,
      'SessionScope requires an ambient InheritedSeed<StationServices>',
    );
    _ctx = ctx;
    // Capture the (fixed-at-mount) ambient bundle for the off-build re-arm
    // flare (tg-boq) — same discipline as `CapabilityHostState._services`.
    _services =
        context.dependOnInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    // Captured for [_mint]'s async use (D-H rule 1) — the reentrant registry
    // (a molecule mint's sub-circuit resolution) and the drain seam's
    // mint-mode (`DESIGN-tg-pm6.md` §12, R5), read off the SAME ambient
    // `SubstationConfig` `WorkBead`'s subtree already provides.
    _registry = context.dependOnInheritedSeedOfExactType<CapabilityRegistry>();
    _mintMode =
        context
            .dependOnInheritedSeedOfExactType<SubstationConfig>()
            ?.circuitMintMode ??
        CircuitMintMode.flatCursor;
  }

  @override
  void initState() {
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
        // (tg-x1j v2) may fire from the very first build. DRAIN (§12): this is
        // the short-circuit BEFORE any [CircuitMintMode] check — an in-flight
        // session's OWN durable model stamp governs, never the ambient config.
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
      case DoneSession() || HeldSession():
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
      HeldSession(:final reason) => reason,
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

  Future<void> _mint() async {
    // Yield so didChangeDependencies captures _ctx (genesis runs initState then
    // didChangeDependencies within one performRebuild).
    await null;
    if (_cancelled || !context.mounted) return;
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
        if (!_staleFencesAreDead(dead)) {
          _refuseVoidMint(dead);
          return;
        }
        final deadId = dead.sessionId ?? '';
        if (deadId.isNotEmpty) {
          await _ctx!.writer.update(
            deadId,
            metadata: voidRetireMetadata(
              workBeadId: seed.bead.id,
              deadSessionId: deadId,
              reason: _voidReason,
            ),
          );
          if (_cancelled || !context.mounted) return;
        }
        // Retired — a bounded retry must never re-key twice.
        _voidSession = null;
        _flare('session.voided', {
          'workBeadId': seed.bead.id,
          'deadSessionId': deadId,
          'reason': truncateReason(_voidReason),
        });
      }
      // The drain seam (`DESIGN-tg-pm6.md` §12, R5): branches AFTER the
      // void-retire block above — a fresh mint over a retired dead key still
      // reads the SAME ambient mode. `flatCursor` (the default) is today's
      // path, byte-for-byte; `molecule` mints the additive graph.
      if (_mintMode == CircuitMintMode.molecule) {
        await _mintMolecule();
      } else {
        final id = await _ctx!.writer.createSession(
          substation: _ctx!.stateSubstation,
          title: 'grid session ${seed.bead.id}',
          workBeadId: seed.bead.id,
        );
        if (_cancelled || !context.mounted) return;
        setState(() {
          _sessionId = id;
          _resolving = false;
        });
      }
    } on Object catch (error) {
      if (_cancelled || !context.mounted) return;
      _onMintFailed('$error');
    }
  }

  /// The molecule-mode mint (`DESIGN-tg-pm6.md` §9/§12, R5/R6): `createSession`
  /// stamping `grid.session.model=molecule`, THEN `createMolecule` pours the
  /// pure `instantiateMolecule` compile step's plan — both under [_mint]'s
  /// SAME [_maxMintAttempts] budget (a throw here propagates to [_mint]'s
  /// `catch`, which retries or escalates exactly like a flat mint failure).
  ///
  /// [_moleculeSessionId] makes a retry-after-`createMolecule`-throws SAFE: on
  /// re-entry the session id from the FIRST attempt is reused (`??=`
  /// short-circuits the second `createSession` call entirely), so a transient
  /// pour failure can never strand an un-poured session bead behind a fresh
  /// second mint (`DESIGN-tg-pm6.md` §3 conflict 2's exact "crashed pour"
  /// ambiguity, avoided here rather than merely detected on restart).
  /// `createMolecule` itself is ALSO re-entry-safe (R6's own dedup probe), so
  /// the two guards compose rather than race.
  Future<void> _mintMolecule() async {
    final id = _moleculeSessionId ??= await _ctx!.writer.createSession(
      substation: _ctx!.stateSubstation,
      title: 'grid session ${seed.bead.id}',
      workBeadId: seed.bead.id,
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    );
    if (_cancelled || !context.mounted) return;
    final plan = instantiateMolecule(
      seed.circuit,
      sessionId: id,
      root: BeadPathKey([seed.bead.id, id]),
      nodePath: seed.bead.id,
      circuitById: _registry?.circuit,
    );
    await _ctx!.writer.createMolecule(
      plan,
      substation: _ctx!.stateSubstation,
      sessionId: id,
    );
    if (_cancelled || !context.mounted) return;
    setState(() {
      _sessionId = id;
      _resolving = false;
      _isMolecule = true;
      _moleculeSessionId = null;
    });
  }

  /// Whether EVERY process fence the VOIDED [session] still records is provably
  /// DEAD — the fail-closed half of the I-10 re-mint.
  ///
  /// The probe is the ambient engine liveness seam (`StationServices.liveness`,
  /// ADR-0009 D4) — the SAME pgid-alive half the daemon adopt-proof uses. It
  /// NARROWS the re-mint; it is not its precondition. UNWIRED (the P1/offline
  /// default, [neverLive]) nothing probes alive and the mint proceeds on the two
  /// structural guarantees that stand without it: a work bead whose session went
  /// terminal UNMOUNTS, and unmount DISPOSES its allocations (kill); and a station
  /// restart SWEEPS a terminal session's live groups before the tree re-mounts
  /// (`RestartReconciler`'s live-group sweep). WIRED (the live arm), a fence that
  /// is STILL alive refuses the mint LOUD — a truly-live orphan is never
  /// double-run.
  bool _staleFencesAreDead(SessionProjection session) {
    final probe = _ctx?.liveness ?? neverLive;
    for (final fence in staleFences(session)) {
      if (probe(fence)) return false;
    }
    return true;
  }

  /// LOUD-refuses the I-10 re-mint: the dead session still records a LIVE process
  /// group, so minting would double-run it. Says WHY once (naming the pgids) and
  /// goes inert — an operator kills the orphan group, or `grid rework` retires the
  /// round. Never a silent wedge (the guard principle).
  void _refuseVoidMint(SessionProjection session) {
    _flare('session.voidRefused', {
      'workBeadId': seed.bead.id,
      'deadSessionId': session.sessionId ?? '',
      'pgids': staleFences(session).map((f) => '${f.pgid}').join(','),
      'reason': truncateReason(_voidReason),
    });
    setState(() {
      _failed = true;
      _resolving = false;
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

  /// Handles a `createSession` failure (tg-6nf) — LOUD, bounded, never the
  /// silent permanent latch it was (ADR-0008 D3: LOUD or GONE).
  ///
  /// Every failed attempt FLARES through the emit-only [ExplorationTransport]
  /// (the SAME sink `CapabilityHost._emitFlare` and [_flareRearmFailed] use), so
  /// a dead mint is OBSERVABLE — leonard reads it over the exploration host
  /// (A39/A40), an operator counts which scopes are dead-minting — never an
  /// invisible `mounted=0` (the FIRST-LIVE-ARM incident, 2026-07-10, boot #1:
  /// every `createSession` threw and the station stood ARMED-but-silently-dead).
  ///
  /// Under the [_maxMintAttempts] budget it RETRIES (scheduled off `build`,
  /// never a write IN `build`), so a TRANSIENT bd blip recovers with no
  /// operator action. AT the budget it ESCALATES: a distinct terminal flare
  /// then `_failed` inert — so the `_failed` state is now reached ONLY as an
  /// EXPLICIT, flared escalation, never as the first-failure swallow.
  ///
  /// There is NO session bead on the mint path (the mint is what failed), so —
  /// unlike breaker-exhaustion (D-5), which marks its OWN session bead — the
  /// flare is the only escalation channel; a human fixes the store and bounces
  /// the station.
  void _onMintFailed(String reason) {
    if (_mintAttempts < _maxMintAttempts) {
      _flareMint(_mintFailedFlare, reason);
      // Retry off `build` (invariant 2) — the scope stays `resolving` (it was
      // never rendered ready), so no setState is needed. The guard re-checks
      // liveness before re-entering the mint; a disposed scope drops the retry.
      scheduleMicrotask(() {
        if (_cancelled || !context.mounted) return;
        unawaited(_mint());
      });
      return;
    }
    _flareMint(_mintExhaustedFlare, reason);
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
  void _flareMint(String name, String reason) {
    try {
      _services.transport?.flare(name, {
        'workBeadId': seed.bead.id,
        'attempt': '$_mintAttempts',
        'maxAttempts': '$_maxMintAttempts',
        'reason': truncateReason(reason),
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
  /// On the MOLECULE arm ([_isMolecule], captured — D-H rule 1) this ALSO
  /// fires [StationBeadWriter.reapMolecule] (R6's session-close collection,
  /// `DESIGN-tg-pm6.md` §9/§12): a POSITIVE terminal is exactly when the
  /// molecule's own `type=molecule`/`type=step` beads stop being needed live
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
      await ctx.writer.update(id, metadata: sessionCompleteMetadata());
    } on Object catch (error) {
      _flare('session.outcomeUnmarked', {
        'sessionId': id,
        'reason': truncateReason('$error'),
      });
    }
    if (_isMolecule) {
      try {
        await ctx.writer.reapMolecule(sessionId: id);
      } on Object catch (error) {
        _flare('session.moleculeReapFailed', {
          'sessionId': id,
          'reason': truncateReason('$error'),
        });
      }
    }
    try {
      await ctx.writer.close(id);
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

  /// Re-arms ONE parked node whose gate bead has closed (D-7): flips its cursor
  /// `gated` → `pending` through the chokepoint so the route re-runs. Deduped
  /// per node via the in-flight [_rearming] guard (see its doc), scheduled off
  /// `build` (never a write IN `build`).
  ///
  /// [moleculeTarget] is the STEP bead id to target instead of [id] when this
  /// node belongs to a MOLECULE session (`build`'s `beadIdByNodePath[nodePath]`,
  /// resolved at SCHEDULE time — the write itself runs off-build); null on
  /// the flat path, whose write is BYTE-FOR-BYTE unchanged.
  void _scheduleRearm(String id, String nodePath, {String? moleculeTarget}) {
    if (_rearming.contains(nodePath)) return;
    _rearming.add(nodePath);
    scheduleMicrotask(() => unawaited(_rearm(id, nodePath, moleculeTarget)));
  }

  void _scheduleStepSuccessorMint({
    required String sessionId,
    required String nodePath,
    required Bead priorStep,
    required int currentDepth,
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
        ),
      ),
    );
  }

  Future<void> _mintStepSuccessor({
    required String sessionId,
    required String nodePath,
    required Bead priorStep,
    required int currentDepth,
  }) async {
    final ctx = _ctx;
    if (ctx == null) {
      _mintingSuccessorForPath.remove(nodePath);
      return;
    }
    try {
      await ctx.writer.createStepSuccessor(
        substation: ctx.stateSubstation,
        priorStep: priorStep,
        currentDepth: currentDepth,
        maxDepth: kMaxReworkRounds,
      );
    } on Object catch (error) {
      _flare('session.stepSuccessorMintFailed', {
        'sessionId': sessionId,
        'nodePath': nodePath,
        'reason': truncateReason('$error'),
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
  /// [moleculeTarget] (R5b's additive write fork): a MINIMAL single-key
  /// `grid.step.state` merge write on the STEP bead — mirrors
  /// [nodeStateMetadata]'s own merge-safety (never a full [stepBeadMetadata]
  /// rebuild, which would clobber the persisted `restartCount`/telemetry with
  /// fresh defaults). `build` never schedules a re-arm for a node the R4
  /// DERIVATION currently holds back (its own `invalidated` exclusion), so
  /// this write only ever targets a node parked by a REAL `HumanGate`.
  Future<void> _rearm(
    String id,
    String nodePath,
    String? moleculeTarget,
  ) async {
    final ctx = _ctx;
    if (ctx == null) {
      // Impossible for a mounted scope (`didChangeDependencies` captures `_ctx`
      // before any build) — but do NOT drop silently if it ever happens: clear
      // the guard (a later build retries) and flare.
      _rearming.remove(nodePath);
      _flareRearmFailed(nodePath, 'no StationServices captured');
      return;
    }
    try {
      await ctx.writer.update(
        moleculeTarget ?? id,
        metadata: moleculeTarget != null
            ? {MoleculeStepKeys.state: StepState.pending.name}
            : nodeStateMetadata(nodePath, StepState.pending),
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

  /// Schedules the rework re-mint (tg-x1j v2): the just-retired [retiredId]
  /// round is closed (D-2 fold: "on resolve, close the retired round session"
  /// — today the operator hand-closes it every round), then this scope resets
  /// to its pre-`initState` shape and mints round N+1 through the SAME
  /// [_mint] path a fresh work-bead mount would use. Latched via
  /// [_reworkScheduled], scheduled off `build`.
  void _scheduleRework(String retiredId) {
    if (_reworkScheduled) return;
    _reworkScheduled = true;
    scheduleMicrotask(() => unawaited(_reworkAndRemint(retiredId)));
  }

  Future<void> _reworkAndRemint(String retiredId) async {
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      await ctx.writer.close(retiredId, reason: 'reworked');
    } on Object {
      // The close is a cleanup fold, not a precondition for the fresh mint
      // below — a failure here just leaves the retired session open for a
      // human to close by hand; it must never block round N+1.
    }
    if (_cancelled || !context.mounted) return;
    setState(() {
      _sessionId = null;
      _resolving = true;
      _reworkScheduled = false;
      _terminalScheduled = false;
      _rearming.clear();
      _mintingSuccessorForPath.clear();
      _lastKnownGated = false;
      _joinedOnce = false;
      _mintAttempts = 0; // round N+1 gets its own fresh mint budget (tg-6nf).
      // Round N+1 re-derives its mode fresh from the ambient [_mintMode] the
      // NEXT [_mint] call reads — never inherits the retired round's mode.
      _isMolecule = false;
      _moleculeSessionId = null;
    });
    unawaited(_mint());
  }

  /// Schedules a LOUD rework decline (tg-x1j v2, the guard principle): the
  /// adopted session vanished from the join but this scope never observed it
  /// parked at a gate — re-minting could silently abandon a live round, so it
  /// marks the (still-reachable-by-id) session and goes permanently inert
  /// (mirroring [_mint]'s `_failed` path). Latched via [_reworkScheduled].
  void _scheduleReworkDecline(String retiredId) {
    if (_reworkScheduled) return;
    _reworkScheduled = true;
    scheduleMicrotask(() => unawaited(_declineRework(retiredId)));
  }

  Future<void> _declineRework(String retiredId) async {
    final ctx = _ctx;
    if (ctx == null) return;
    await ctx.writer.update(
      retiredId,
      metadata: {
        SessionBeadKeys.reworkDeclined: 'true',
        SessionBeadKeys.reworkDeclinedReason:
            'session retired (work_bead re-keyed) while this scope never '
            'observed it parked at a gate — refusing to abandon a possibly-'
            'live round; a human must investigate',
      },
    );
    if (_cancelled || !context.mounted) return;
    setState(() {
      _failed = true;
    });
  }

  Future<void> _escalateAndClose(String id, String reason) async {
    // Runs to completion even if SessionScope is mid-dispose — the escalation
    // marker + close must be durable (uses the captured ctx, never `context`).
    final ctx = _ctx;
    if (ctx == null) return;
    await ctx.writer.update(
      id,
      metadata: {
        SessionBeadKeys.escalation: 'breaker-exhausted',
        // Capture-only (FT-1): the failing node + reason, beside the marker.
        if (reason.isNotEmpty) SessionBeadKeys.escalationReason: reason,
      },
    );
    await ctx.writer.close(id, reason: 'breaker-exhausted');
  }

  @override
  void dispose() {
    _cancelled = true;
    _mintingSuccessorForPath.clear();
  }

  @override
  Seed build(TreeContext context) {
    final matchesJoin = seed.existingSession?.sessionId == _sessionId;

    // tg-x1j v2: the adopted session vanished from the join while this scope
    // stayed MOUNTED — the only way that happens (once the join has ALREADY
    // reflected this session at least once, [_joinedOnce]) is `grid rework`
    // re-keying its `work_bead` off this bead.id while the session was still
    // OPEN (a gated round; A40 keeps a GATED work bead mounted rather than
    // unmounting it, so the usual close→unmount→remount→mint path never
    // fires for it). [_joinedOnce] is the guard that keeps this from firing
    // on a FRESH MINT, whose `existingSession` also reads unmatched until the
    // join catches up. Detected BEFORE the stale-id/empty-cursor read below
    // would otherwise silently keep serving the OLD id over an EMPTY cursor
    // (a corrupted handle, not a parked one) — the session handle stays
    // stable up to exactly this point, never past it.
    if (!_resolving &&
        !_failed &&
        _sessionId != null &&
        _joinedOnce &&
        !matchesJoin &&
        !_reworkScheduled) {
      if (_lastKnownGated) {
        _scheduleRework(_sessionId!);
      } else {
        // The guard principle: a scope that declines to mint says WHY once,
        // LOUD — this scope never observed the retired session parked at a
        // gate, so re-minting here could silently abandon a live round.
        _scheduleReworkDecline(_sessionId!);
      }
    }

    if (_resolving || _failed || _sessionId == null || _reworkScheduled) {
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

    // The reentrant capability/circuit resolution seam — read ONCE, ambient;
    // the flat broken/complete check below needs it to resolve a
    // `SubCircuitStep`'s own nested circuit (`firstBrokenNode`/
    // `isCircuitComplete`).
    final registry = context
        .dependOnInheritedSeedOfExactType<CapabilityRegistry>();

    // The drain seam's molecule arm (`DESIGN-tg-pm6.md` §12, R5): project this
    // session's OWN molecule graph into the same in-memory shape the flat path
    // consumes, then layer A52 Ratified live derivation over it. The flat `else`
    // arm remains the absent-key drain guarantee by construction.
    final isMolecule = joined?.isMolecule ?? false;
    final CircuitCursor cursor;
    final Map<String, Map<String, String>> results;
    var beadIdByNodePath = const <String, String>{};
    var invalidated = const <String>{};
    var heldForSuccessor = const <String>{};
    var moleculeProjectedCursor = const <String, NodeCursor>{};
    if (isMolecule) {
      final projected = projectMoleculeCursor(
        joined!.moleculeBeads,
        dependencies: joined.moleculeDependencies,
      );
      moleculeProjectedCursor = projected.cursor;
      beadIdByNodePath = projected.beadIdByNodePath;
      final depthByPath = supersedesDepthByPath(
        joined.moleculeBeads,
        joined.moleculeDependencies,
      );
      final activeByPath = activeStepBeadsByPath(
        joined.moleculeBeads,
        joined.moleculeDependencies,
      );
      // ResultKeys is reused VERBATIM on the step bead (R1) — each step
      // bead's OWN `grid.result.<itsOwnNodePath>.*` keys project through the
      // SAME `projectCircuitResults` the flat codec uses on the session bead;
      // merging every step bead's slice yields the identical shape.
      final stepResults = <String, Map<String, String>>{};
      for (final b in joined.moleculeBeads) {
        if (b.issueType != IssueType.step) continue;
        stepResults.addAll(projectCircuitResults(b));
      }
      results = stepResults;
      invalidated = invalidatedNodes(
        seed.circuit,
        projected.cursor,
        results,
        seed.bead.id,
        circuitById: registry?.circuit ?? (String _) => null,
        supersedesDepthByPath: depthByPath,
      );
      final effective = effectiveCursor(
        seed.circuit,
        projected.cursor,
        results,
        seed.bead.id,
        circuitById: registry?.circuit ?? (String _) => null,
        supersedesDepthByPath: depthByPath,
      );
      final holds = <String>{};
      for (final path in invalidated) {
        final depth = depthByPath[path] ?? 0;
        if (depth >= kMaxReworkRounds) continue;
        final priorStep = activeByPath[path];
        final node = projected.cursor[path];
        if (priorStep == null || node == null || !node.isPositiveTerminal) {
          continue;
        }
        _scheduleStepSuccessorMint(
          sessionId: id,
          nodePath: path,
          priorStep: priorStep,
          currentDepth: depth,
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
    // The join reflects this session THIS build — latch it (fresh-mint guard,
    // above) and remember whether it's CURRENTLY parked at a gate (the signal
    // the orphan-check above reads once it stops matching).
    if (matchesJoin) {
      _joinedOnce = true;
      _lastKnownGated = cursor.values.any((n) => n.state == StepState.gated);
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
        _scheduleRearm(
          id,
          nodePath,
          moleculeTarget: beadIdByNodePath[nodePath],
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
                supersedesDepthByPath: supersedesDepthByPath(
                  joined!.moleculeBeads,
                  joined.moleculeDependencies,
                ),
              )
            : null;
        if (derived != null) {
          _scheduleEscalation(id, '${derived.path}: ${derived.reason}');
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
            _scheduleClose(id);
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
    );
    if (isMolecule) {
      // R2/R5: the ambient storage seam, provided as the 4th nested
      // InheritedSeed ONLY in molecule mode — a flat session provides
      // nothing new here (the additive fork lives entirely at
      // `CapabilityHost`'s persist call sites, R5b).
      inflater = InheritedSeed<InheritedCircuit>(
        value: InheritedCircuit(
          root: BeadPathKey([seed.bead.id, id]),
          beadIdByNodePath: beadIdByNodePath,
          cursor: cursor,
        ),
        child: inflater,
      );
    }
    return InheritedSeed<SessionHandle>(
      value: SessionHandle(id),
      child: InheritedSeed<Workspace>(
        value: workspace,
        child: InheritedSeed<SiblingView>(
          value: SiblingView(cursor: cursor, results: results),
          child: inflater,
        ),
      ),
    );
  }
}
