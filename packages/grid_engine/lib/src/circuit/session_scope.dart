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
/// Why above the fan-out (the D-2 break it fixes): P0 minted lazily at
/// first-leaf-mount and named the provider session = the bead id, one per work
/// bead. `MultiChildBranch` mounts all frontier children in one pass, so two
/// concurrent leaves would each see `session == null` → two mints, and both
/// would call `provider.start` with the same name → collisions. Minting ONCE,
/// above the fan-out, is the fix.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';

import '../domain/rework.dart';
import '../domain/session_bead.dart';
import '../domain/session_projection.dart';
import '../kernel/station_services.dart';
import '../kernel/idle.dart';
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
  /// The the_grid-internal escalation marker key (NOT a codec-boundary key) — a
  /// human picks it up when a circuit's breaker exhausts (D-5).
  static const _escalationKey = 'grid.escalation';

  /// The capture-only escalation-diagnostic key (FT-1, tg-pez) — the final
  /// failing node + its truncated reason, recorded beside [_escalationKey] in
  /// the SAME write so a human sees WHAT exhausted, not just THAT it did.
  static const _escalationReasonKey = 'grid.escalation_reason';

  /// The the_grid-internal REWORK-DECLINE marker key (tg-x1j, NOT a
  /// codec-boundary key) — a human picks it up when a rework re-key orphaned a
  /// session this scope never observed parked at a gate (the guard principle:
  /// a scope that declines to mint says WHY once, LOUD).
  static const _reworkDeclinedKey = 'grid.rework_declined';

  /// The capture-only decline-diagnostic key, recorded beside
  /// [_reworkDeclinedKey] in the SAME write.
  static const _reworkDeclinedReasonKey = 'grid.rework_declined_reason';

  /// The the_grid-internal AUTO-RESPEC CAP marker keys (tg-b3k, NOT
  /// codec-boundary keys — and outside the `grid.cursor.`/`grid.result.`
  /// namespaces, so no projection misreads them): a machine-actionable gate was
  /// REFUSED because the bead has already exhausted [kMaxReworkRounds]. The gate
  /// bead stays OPEN — past the cap a human decides — so this marker is the
  /// durable half of a LOUD refusal (the flare is the live half).
  static const _respecCappedKey = 'grid.respec_capped';

  /// The capture-only cap-diagnostic key, recorded beside [_respecCappedKey] in
  /// the SAME write.
  static const _respecCappedReasonKey = 'grid.respec_capped_reason';

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

  /// The auto-respec flares (tg-b3k): the successful retire, the LOUD cap
  /// refusal, and any dropped write in the transition.
  static const _autoRespecFlare = 'gate.autoRespec';
  static const _respecCappedFlare = 'gate.respecCapped';
  static const _autoRespecFailedFlare = 'gate.autoRespecFailed';

  StationServices? _ctx;

  /// The ambient [ServiceBundle] captured off `build` (D-H rule 1: re-read on
  /// every `didChangeDependencies`, never `??=`-cached) — held so the off-build
  /// re-arm microtask can LOUD-flare a dropped write through its
  /// `transport` (tg-boq), the SAME emit-only sink `CapabilityHost._emitFlare`
  /// uses.
  ServiceBundle _services = const ServiceBundle();

  String? _sessionId;
  bool _resolving = true;
  bool _failed = false;
  bool _cancelled = false;
  bool _terminalScheduled = false;

  /// How many `createSession` attempts this scope has made (tg-6nf) — bounded
  /// by [_maxMintAttempts]; reaching the cap is the escalation trigger. Reset
  /// to 0 by [_reworkAndRemint] so round N+1 gets its own fresh budget.
  int _mintAttempts = 0;

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

  /// Latches the ONE-SHOT auto-respec transition (tg-b3k). Set BEFORE the re-key
  /// write; CLEARED if that write fails (the next build retries — the tg-boq
  /// discipline: a latch set before a fire-and-forget write made a dropped write
  /// PERMANENT and SILENT); left SET on success, because the transition is
  /// one-shot for this round — the session leaves this bead's join key and
  /// [_reworkAndRemint] resets the latch for round N+1.
  bool _autoRespecScheduled = false;

  /// Latches the LOUD cap refusal (tg-b3k) so a capped, still-parked gate marks
  /// the session bead ONCE instead of on every build. Cleared on a dropped
  /// marker write (retry next build) and by [_reworkAndRemint].
  bool _respecCapMarked = false;

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
  }

  @override
  void initState() {
    final existing = seed.existingSession?.sessionId;
    if (existing != null && existing.isNotEmpty) {
      // ADOPT — synchronous, no mint (the restoration adopt seam is the same
      // resolving→ready transition on restart). The join already reflects
      // this session (that's how we're adopting it), so the rework
      // orphan-check (tg-x1j v2) may fire from the very first build.
      _sessionId = existing;
      _resolving = false;
      _joinedOnce = true;
    } else {
      // MINT — once, above the fan-out.
      unawaited(_mint());
    }
  }

  Future<void> _mint() async {
    // Yield so didChangeDependencies captures _ctx (genesis runs initState then
    // didChangeDependencies within one performRebuild).
    await null;
    if (_cancelled || !context.mounted) return;
    _mintAttempts++;
    try {
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
    } on Object catch (error) {
      if (_cancelled || !context.mounted) return;
      _onMintFailed('$error');
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

  /// Schedules the session close on the positive terminal — latched once, run
  /// off `build` (never a write IN `build`).
  void _scheduleClose(String id) {
    if (_terminalScheduled) return;
    _terminalScheduled = true;
    scheduleMicrotask(() => unawaited(_ctx?.writer.close(id)));
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
  void _scheduleRearm(String id, String nodePath) {
    if (_rearming.contains(nodePath)) return;
    _rearming.add(nodePath);
    scheduleMicrotask(() => unawaited(_rearm(id, nodePath)));
  }

  /// The re-arm write itself (tg-boq): flips the parked node to `pending`, then
  /// clears the in-flight guard so the NEXT build retries on failure and a later
  /// gate cycle can re-arm again. A dropped write is LOUD (a flare through the
  /// emit-only transport) — never SILENT, never PERMANENT (the guard principle:
  /// LOUD or GONE). It is NOT rethrown: an uncaught async error in a resident
  /// station's root zone would terminate the isolate, so a transient bd blip
  /// must not crash the whole station — the retry (via the cleared guard) is the
  /// recovery, the flare is the signal.
  Future<void> _rearm(String id, String nodePath) async {
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
        id,
        metadata: nodeStateMetadata(nodePath, StepState.pending),
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
      _lastKnownGated = false;
      _joinedOnce = false;
      _mintAttempts = 0; // round N+1 gets its own fresh mint budget (tg-6nf).
      _autoRespecScheduled = false; // round N+1 may itself respec (tg-b3k).
      _respecCapMarked = false;
    });
    unawaited(_mint());
  }

  /// Schedules the AUTO-RESPEC transition (tg-b3k) — latched, off `build`.
  void _scheduleAutoRespec(String sessionId, OpenGate gate, int round) {
    _autoRespecScheduled = true;
    scheduleMicrotask(() => unawaited(_autoRespec(sessionId, gate, round)));
  }

  /// The auto-respec writes, in the ONE order that is safe:
  ///
  ///  1. **RE-KEY** this session's `work_bead` → `<bead>#r<N>` through the
  ///     chokepoint — exactly the operator rework verb's mechanic. The session
  ///     drops out of the join at `bead.id`; [build]'s orphan-check observes that
  ///     with [_lastKnownGated] TRUE (the node IS parked — that is why we are
  ///     here), so [_scheduleRework] closes the retired round and mints round N+1
  ///     through the SAME [_mint] path, in the SAME workspace (it is derived from
  ///     the bead id, invariant across rounds).
  ///  2. **CLOSE the gate bead** — only now. Closing FIRST would open a window in
  ///     which a build sees a CLOSED gate over a still-`gated` cursor on a session
  ///     still keyed at `bead.id`: the D-7 re-arm would fire, flip the node back
  ///     to `pending`, and — because [_lastKnownGated] is recomputed from the
  ///     cursor on every build — the later re-key would land on a scope that no
  ///     longer remembers a gated round, taking the [_scheduleReworkDecline] path
  ///     and wedging the bead permanently inert. The store commits the re-key
  ///     BEFORE the close, so no snapshot can show the close without the re-key.
  ///
  /// A failed RE-KEY clears the latch (the next build retries) and FLARES. A
  /// failed CLOSE cannot be retried from here (the session has already left this
  /// bead's join key, so the predicate can never re-fire), so it FLARES LOUD and
  /// leaves an OPEN gate bead blocking a RETIRED session — inert (the join maps
  /// it to the `<bead>#r<N>` projection, which nothing mounts) and visible to a
  /// human in the gate listing; never silent. Neither is rethrown: an uncaught
  /// async error in a resident station's root zone would terminate the isolate,
  /// and a transient bd blip must not take the station down (the tg-boq posture).
  Future<void> _autoRespec(String sessionId, OpenGate gate, int round) async {
    final ctx = _ctx;
    if (ctx == null) {
      _autoRespecScheduled = false;
      _flareRespec(
        _autoRespecFailedFlare,
        gate,
        reason: 'no StationServices captured',
      );
      return;
    }
    try {
      await ctx.writer.update(
        sessionId,
        metadata: {
          SessionBeadKeys.workBead: reworkKeyFor(seed.bead.id, round),
        },
      );
    } on Object catch (error) {
      _autoRespecScheduled = false;
      _flareRespec(_autoRespecFailedFlare, gate, reason: '$error');
      return;
    }
    _flareRespec(_autoRespecFlare, gate, round: round);
    try {
      await ctx.writer.close(gate.gateId, reason: 'auto-respec round $round');
    } on Object catch (error) {
      _flareRespec(
        _autoRespecFailedFlare,
        gate,
        reason: 'gate close failed: $error',
      );
    }
  }

  /// Schedules the LOUD cap refusal (tg-b3k) — latched once, off `build`. The
  /// gate bead is NOT closed and the node stays parked: past [kMaxReworkRounds] a
  /// human decides (the operator rework verb refuses at the same cap, with the
  /// same comparison). The marker is durable on the OWN session bead so the
  /// refusal survives a station bounce; the flare makes it observable live. LOUD
  /// or GONE (ADR-0008 D3).
  void _scheduleRespecCap(String sessionId, OpenGate gate, int rounds) {
    if (_respecCapMarked) return;
    _respecCapMarked = true;
    final reason =
        'auto-respec refused at ${gate.nodePath}: $rounds rework rounds already '
        'retired (cap $kMaxReworkRounds) — the gate stays parked for a human';
    _flareRespec(_respecCappedFlare, gate, reason: reason, rounds: rounds);
    scheduleMicrotask(
      () => unawaited(_markRespecCapped(sessionId, gate, reason)),
    );
  }

  Future<void> _markRespecCapped(
    String sessionId,
    OpenGate gate,
    String reason,
  ) async {
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      await ctx.writer.update(
        sessionId,
        metadata: {
          _respecCappedKey: 'true',
          _respecCappedReasonKey: truncateReason(reason),
        },
      );
    } on Object catch (error) {
      // The live half already fired (the refusal is never silent). Clear the
      // latch so a later build retries the DURABLE half, and flare the drop.
      _respecCapMarked = false;
      _flareRespec(
        _autoRespecFailedFlare,
        gate,
        reason: 'respec-cap marker write failed: $error',
      );
    }
  }

  /// LOUD-signals an auto-respec transition (tg-b3k) through the reserved
  /// emit-only [ExplorationTransport] (D-8) — the SAME sink every other engine
  /// LOUD signal fires through ([_flareRearmFailed], `CapabilityHost._emitFlare`).
  /// A throwing/absent transport never re-breaks the microtask.
  void _flareRespec(
    String name,
    OpenGate gate, {
    String reason = '',
    int? round,
    int? rounds,
  }) {
    try {
      _services.transport?.flare(name, {
        'sessionId': _sessionId ?? '',
        'workBeadId': seed.bead.id,
        'gateId': gate.gateId,
        'nodePath': gate.nodePath,
        'cap': '$kMaxReworkRounds',
        if (round != null) 'round': '$round',
        if (rounds != null) 'rounds': '$rounds',
        if (reason.isNotEmpty) 'reason': truncateReason(reason),
      });
    } catch (_) {
      // A throwing transport never re-breaks the transition — swallow.
    }
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
        _reworkDeclinedKey: 'true',
        _reworkDeclinedReasonKey:
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
        _escalationKey: 'breaker-exhausted',
        // Capture-only (FT-1): the failing node + reason, beside the marker.
        if (reason.isNotEmpty) _escalationReasonKey: reason,
      },
    );
    await ctx.writer.close(id, reason: 'breaker-exhausted');
  }

  @override
  void dispose() {
    _cancelled = true;
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
    final cursor = seed.existingSession?.cursor ?? const <String, NodeCursor>{};
    final results =
        seed.existingSession?.results ?? const <String, Map<String, String>>{};
    // The join reflects this session THIS build — latch it (fresh-mint guard,
    // above) and remember whether it's CURRENTLY parked at a gate (the signal
    // the orphan-check above reads once it stops matching).
    if (matchesJoin) {
      _joinedOnce = true;
      _lastKnownGated = cursor.values.any((n) => n.state == StepState.gated);
    }

    // tg-b3k: AUTO-RESOLVE a MACHINE-ACTIONABLE gate. A `respec:` reason is the
    // asset saying "this park is machine-actionable — rework it; the correction
    // guidance is already durable in the workspace", so the engine performs the
    // rework re-key an operator does by hand today instead of parking for a
    // human. A gate with ANY other reason is a human checkpoint and falls through
    // to the D-7 park/re-arm below, byte-for-byte untouched (ADR-0008 Decision
    // 9). Read-only here; every write is scheduled off `build` (invariant 2).
    final session = seed.existingSession;
    if (matchesJoin && session != null && !_autoRespecScheduled) {
      final gate = machineActionableGate(session);
      if (gate != null) {
        if (session.reworkRounds >= kMaxReworkRounds) {
          _scheduleRespecCap(id, gate, session.reworkRounds);
        } else {
          _scheduleAutoRespec(id, gate, session.reworkRounds + 1);
        }
      }
    }

    // D-7: re-arm any node parked at a gate whose gate bead has CLOSED (its
    // nodePath left `openGateNodes`). Read-only here; the flip to `pending` is
    // scheduled off build (invariant 2), latched once per node. A still-open
    // gate is left parked.
    final openGates = seed.existingSession?.openGateNodes ?? const <String>{};
    cursor.forEach((nodePath, node) {
      if (node.state == StepState.gated && !openGates.contains(nodePath)) {
        _scheduleRearm(id, nodePath);
      }
    });

    // D-2/D-5: own the terminal. Read-only here (the predicates are pure); the
    // actual write is scheduled off build (never a write IN build, invariant 2).
    // Breaker-exhaustion (broken ANYWHERE in the subtree) escalates + tears
    // down; otherwise a positive terminal closes. Distinguishing
    // empty-because-broken from empty-because-complete is the whole point of D-5.
    final registry = context
        .dependOnInheritedSeedOfExactType<CapabilityRegistry>();
    if (registry != null && !_terminalScheduled) {
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
    return InheritedSeed<SessionHandle>(
      value: SessionHandle(id),
      child: InheritedSeed<Workspace>(
        value: workspace,
        child: InheritedSeed<SiblingView>(
          value: SiblingView(cursor: cursor, results: results),
          child: CircuitScope(
            circuit: seed.circuit,
            cursor: cursor,
            nodePath: seed.bead.id,
          ),
        ),
      ),
    );
  }
}
