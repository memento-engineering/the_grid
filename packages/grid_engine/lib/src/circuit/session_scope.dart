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
import 'package:grid_runtime/grid_runtime.dart';

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
    } on Object {
      if (_cancelled || !context.mounted) return;
      setState(() {
        _failed = true;
        _resolving = false;
      });
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
    // The SourceControl is resolved by the bead's `metadata.grid.root`
    // selector (tg-7gm) — null ⇒ this substation's DEFAULT root
    // (`services.sourceControl`). A reaching bead is guaranteed a REGISTERED
    // selection by the `WorkList` mount-boundary gate, so this resolution
    // never itself refuses; `sourceControlFor` falls back to the default
    // defensively.
    // The bundle captured in `didChangeDependencies` (the dependency is
    // registered there) — reused so `build` and the off-build re-arm flare read
    // the SAME ambient value.
    final services = _services;
    final sc = services.sourceControlFor(
      BeadOwnershipPredicate.rootOf(seed.bead.metadata),
    );
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
