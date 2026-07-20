/// The engine-private capability carrier — the **thin sync driver** of the_grid's
/// third tree (ADR-0009 D5 / ADR-0008 D4, Track B).
///
/// `CapabilityHost` is the `Branch`/Element between the pure [Capability]
/// (description) and its [Allocation] (the live effect, the RenderObject
/// analogue). Its whole job is the three-tree interlock:
///
///   Host **kicks** (sync) → Allocation **runs** (async) → Allocation **reports**
///   (push) → Host **persists** (off-build, through the one chokepoint).
///
/// So the Host: computes the [AllocationAddress]; on mount **creates** the
/// allocation (in `didChangeDependencies`, so teardown is guaranteed on EVERY
/// exit path) and **kicks** `startOrAdopt` once; on a context change resolves
/// via `canUpdate` → `update` (or leaves the running effect — the base families
/// re-key rather than update, and the CircuitScope owns the key); on unmount
/// kicks `dispose` (kill); and **persists** every [AllocationReport] the effect
/// pushes — off `build`, latched, through the single [StationBeadWriter].
///
/// **The effect layer holds NO writer** (invariant 2): the [Allocation] reports;
/// the Host persists. This is layering — the effect freely reads the tree with
/// the effect verb (ADR-0009 D3 / ADR-0008 Decision 3, 2026-07-02); only the
/// Host writes. The Host's own inherited reads are `dependOn*` (the tree verb)
/// and are RE-READ on every `didChangeDependencies` — never `??=`-cached
/// (assume every reference can change; D-H rule 1). The captured fields exist
/// for async-gap use (a `TreeContext` throws post-unmount), not as a cache.
///
/// The load-bearing async-gap guards live entirely here (the tree's discipline):
/// `_cancelled` (set FIRST in `dispose`) + `TreeContext.mounted` drop a report
/// reaching an unmounted Branch; `_completed` is the once-only terminal latch
/// (a daemon `ready` does NOT latch — OQ-5).
library;

import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../domain/session_bead.dart';
import '../kernel/station_services.dart';
import '../kernel/idle.dart';
import '../molecule/inherited_circuit.dart' show InheritedCircuit;
import '../molecule/molecule_codec.dart' show stepBeadMetadata;
import '../molecule/process_lease_vendor.dart'
    show ProcessLeaseRequest, requireProcessLeaseVendor;
import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/circuit.dart';
import '../sdk/cursor.dart';
import '../sdk/route.dart';
import 'capability_registry.dart';

/// The carrier for one mounted [CapabilityStep]. Built by the registry's `host`;
/// keyed `ValueKey('$nodePath#$restartCount')` so a supervised restart re-keys.
class CapabilityHost extends StatefulSeed {
  /// Creates the carrier for [capability] at [mount].
  const CapabilityHost({
    required this.capability,
    required this.mount,
    super.key,
  });

  /// The concrete capability (resolved by capabilityId in the registry).
  final Capability capability;

  /// The mount context (step / full nodePath / session / cursor node).
  final StepMount mount;

  @override
  State<CapabilityHost> createState() => CapabilityHostState();
}

/// The pinned [CapabilityHost] lifecycle — the thin driver (ADR-0009 D5).
class CapabilityHostState extends State<CapabilityHost> {
  StationServices? _ctx;
  ServiceBundle _services = const ServiceBundle();
  CapabilityRegistry? _registry;
  Allocation? _allocation;
  StepArgs? _args;
  String _token = '';
  bool _cancelled = false;
  bool _completed = false;

  /// Capture-only flow telemetry (FT-1, tg-pez) — the instant this incarnation
  /// began driving its effect (captured at the FIRST kick, off any build-path
  /// read; the injected clock). The terminal write derives `durationMs` from it.
  /// Null only before the kick (never on a terminal path).
  DateTime? _startedAt;

  String get _sessionId => seed.mount.session.sessionId;
  String get _nodePath => seed.mount.nodePath;

  /// The work bead id — the root segment of the nodePath (the root circuit's
  /// nodePath IS the bead id, so every step path is `beadId/...`).
  String get _beadId =>
      _nodePath.contains('/') ? _nodePath.split('/').first : _nodePath;

  /// Resolves this incarnation's write target — the step's OWN durable bead
  /// (`InheritedCircuit.beadIdByNodePath[_nodePath]`, R2/R5b). The molecule
  /// model is the ONLY circuit engine (tg-eli phase 2): there is no flat
  /// session-bead fallback any more.
  ///
  /// Read with the EFFECT verb (`getInheritedSeedOfExactType`, ADR-0008
  /// Decision 3): every `_persistX` runs OFF `build`, in the report path, on
  /// a still-mounted branch (guarded by its own caller) — exactly like the
  /// existing `Bead`/`Workspace` reads in [_persistAdvance].
  ///
  /// A missing ambient [InheritedCircuit] — a host mounted under an ADOPTED
  /// HISTORICAL flat session, or a mis-composed tree — refuses LOUD (a thrown
  /// [StateError]; [_createAllocationOrFlare] catches it at mount and every
  /// persist call site is itself `async`, so a report-path throw is captured
  /// as a rejected Future and safely contained by [_firePersist]'s
  /// `catchError`). So a legacy flat session never spawns and never writes —
  /// it flares. Same for a MOUNTED circuit missing its own node in
  /// [InheritedCircuit.beadIdByNodePath] (a join/mint mis-composition).
  String get _stepBeadId {
    final circuit = context.getInheritedSeedOfExactType<InheritedCircuit>();
    if (circuit == null) {
      throw StateError(
        'No InheritedCircuit at "$_nodePath" (session "$_sessionId") — the '
        'molecule model is the only circuit engine; a historical flat '
        'session cannot be driven (rework the round instead)',
      );
    }
    final beadId = circuit.beadIdByNodePath[_nodePath];
    if (beadId == null) {
      throw StateError(
        'Molecule session "$_sessionId" has no step bead for node '
        '"$_nodePath" (InheritedCircuit.beadIdByNodePath is missing it)',
      );
    }
    return beadId;
  }

  @override
  void initState() {
    _token = newInstanceToken();
    // One StepArgs per incarnation: its CancelToken is the effect's cooperative
    // unmount signal (the allocation cancels it in dispose).
    _args = StepArgs(
      params: seed.mount.step.params,
      nodePath: seed.mount.nodePath,
      cancel: CancelToken(),
    );
  }

  @override
  void didChangeDependencies() {
    // ALWAYS re-read every dependency (D-H rule 1: assume a reference can
    // change; dependencyChanged re-runs this). The fields are captured for
    // async-gap use — never a read-once cache.
    final ctx = context.dependOnInheritedSeedOfExactType<StationServices>();
    assert(
      ctx != null,
      'CapabilityHost requires an ambient InheritedSeed<StationServices>',
    );
    _ctx = ctx;
    _services =
        context.dependOnInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    _registry = context.dependOnInheritedSeedOfExactType<CapabilityRegistry>();

    final existing = _allocation;
    if (existing == null) {
      // Capture-only flow telemetry (FT-1): stamp the step's begin instant at
      // the kick (off-build, injected clock) — the terminal write derives
      // `durationMs` from it. Set once, before the async kick.
      _startedAt = _now();
      // FIRST call: mint the Allocation HERE (synchronously, before the async
      // kick) so `dispose → allocation.dispose` (teardown) is guaranteed on
      // EVERY exit path — even a dispose that races the kick before it spawns
      // (the Track E finding #1). Then kick `startOrAdopt` exactly once,
      // fire-and-forget (reconcile never awaits I/O — D5).
      final alloc = _createAllocationOrFlare();
      if (alloc == null) return;
      _allocation = alloc;
      unawaited(alloc.startOrAdopt());
    } else {
      // A dependency the effect reads CHANGED (ADR-0009 D3: depending on context
      // is the norm). Resolve coherently: `update` in place if the type supports
      // it, else leave the running effect untouched — the base process/service
      // families are not updatable, and a genuine replace is a re-key the
      // CircuitScope owns (a `restartCount` bump → a new key → a fresh mount).
      // We NEVER re-key here.
      final next = _createAllocationOrFlare();
      if (next != null && existing.canUpdate(next)) {
        unawaited(existing.update(next));
      }
    }
  }

  /// Mints this incarnation's [Allocation] — the R3 routing fork (tg-h4u).
  ///
  /// A [ProcessCapability] routes through the ambient [ProcessLeaseVendor]:
  /// `leaseFor(request)` vends the `LeaseCapability<ProcessHandle>` whose
  /// `LeaseAllocation` drives the spawn — so process identity is LEASED
  /// (`grid.lease.*` on the step bead, written only by the vendor; Decided
  /// item 5), and crash-adoption rides the lease family's adopt-or-reacquire.
  /// Every other capability keeps its own `createAllocation` default.
  ///
  /// A throw (no [InheritedCircuit] ambient — a historical flat session,
  /// [_stepBeadId]'s guard; no vendor mounted — `requireProcessLeaseVendor`'s
  /// LOUD-or-GONE refusal; a missing step-bead mapping) is contained PER-WORK
  /// (ADR-0008 Decision 10: one bad bead never crashes the station): flared
  /// `step.allocationFailed` + routed to a supervised failure, so the bounded
  /// restart budget → breaker → escalation chain surfaces it to a human
  /// instead of a silent stall or a dead station.
  Allocation? _createAllocationOrFlare() {
    try {
      final ctx = _buildAllocationContext();
      final capability = seed.capability;
      // Resolve the write target at MOUNT for every capability — a host that
      // cannot name its step bead must never run an effect it cannot persist.
      final target = _stepBeadId;
      if (capability is ProcessCapability) {
        final vendor = requireProcessLeaseVendor(context);
        final lease = vendor.leaseFor(
          ProcessLeaseRequest(
            stepBeadId: target,
            capability: capability,
            allocation: ctx,
          ),
        );
        return lease.createAllocation(ctx);
      }
      return capability.createAllocation(ctx);
    } on Object catch (e) {
      _emitFlare('step.allocationFailed', {'error': truncateReason('$e')});
      _firePersist(
        'allocation',
        () => _persistFailure('allocation failed: $e'),
      );
      return null;
    }
  }

  /// The wall clock for the backoff cooldown — the registry's (the kernel owns
  /// it, D-5/F1), falling back to the system clock if no registry is ambient.
  DateTime _now() => _registry?.now() ?? DateTime.now();

  /// Assembles the [AllocationContext] the effect runs against — the host's
  /// stable tree context + the per-step args (the effect reads its ambient
  /// values itself, with the effect verb), the process transport, the stable
  /// address, the engine env overlay, the report sink, and the adopt fence
  /// (the prior identity for a no-adopt-on-faith proof — D4).
  AllocationContext _buildAllocationContext() {
    final ctx = _ctx!;
    return AllocationContext(
      treeContext: context,
      args: _args!,
      transport: ctx.provider,
      address: AllocationAddress(_sessionId, _nodePath),
      // The per-incarnation env the effect spawns under. The full path already
      // disambiguates every concurrent effect (disjoint event routing — D-2);
      // the shim writes its OWN cursor at this step path through the chokepoint.
      env: {
        'GRID_BEAD_ID': _beadId,
        'GRID_SESSION_ID': _sessionId,
        'GRID_INSTANCE_TOKEN': _token,
        'GRID_STEP_PATH': _nodePath,
      },
      sink: _onReport,
      // The prior incarnation's identity for an adopt-freshness proof (D4);
      // empty for a fresh node. A job never adopts; a daemon adopts only when the
      // liveness seam proves the group live — offline (P1) that seam is the
      // default `false`, so the Host always spawns fresh (today's behavior). The
      // live pgid-liveness wiring is deferred to the live arm (the human gate).
      fence: AdoptFence(
        pgid: seed.mount.node.pgid,
        pid: seed.mount.node.pid,
        token: seed.mount.node.token,
      ),
      kind: seed.mount.step.kind,
      // The engine pgid-liveness half (D4), co-wired with the reconciler's
      // AdoptProof at the live arm; null → neverLive → no mount-time adopt (P1).
      liveness: _ctx!.liveness ?? neverLive,
      // The COMPLETION FENCE's probe; null → noWorkSignal → inert.
      workSignal: _ctx!.workSignal ?? noWorkSignal,
    );
  }

  /// The report sink handed to the [Allocation] (ADR-0009 D5). Maps each pushed
  /// [AllocationReport] to a cursor write OFF-BUILD through the one chokepoint —
  /// the effect never holds the writer (invariant 2). Guarded: a report reaching
  /// an unmounted/cancelled node is dropped; the terminal latch fires once (a
  /// daemon `ready` does not latch).
  void _onReport(AllocationReport report) {
    if (_cancelled || !context.mounted) return;
    switch (report) {
      case AllocationStarted():
        // The report's pid/pgid are NOT persisted here: process identity is
        // vendor-owned (`grid.lease.*` on the step bead, R3) — this write
        // records only the `running` transition.
        _firePersist('started', _persistStarted);
      case AllocationReady(:final payload):
        if (_completed) return;
        _firePersist('ready', () => _persistReady(payload));
      case AllocationCompleted(:final payload):
        if (_completed) return;
        _completed = true;
        _firePersist('complete', () => _persistComplete(payload));
      case AllocationFailed(:final reason):
        if (_completed) return;
        _completed = true;
        if (reason.contains('sourceless-workspace')) {
          _emitFlare('step.allocationFailed', {
            'error': truncateReason(reason),
          });
        }
        _firePersist('failure', () => _persistFailure(reason));
      case AllocationAdvanced(:final payload):
        if (_completed) return;
        _completed = true;
        _firePersist('advance', () => _persistAdvance(payload));
      case AllocationEscalated(:final reason):
        if (_completed) return;
        _completed = true;
        _firePersist('escalate', () => _persistEscalate(reason));
      case AllocationRewound(:final stepIds, :final reason):
        if (_completed) return;
        _completed = true;
        _firePersist('rewind', () => _persistRewindReport(stepIds, reason));
    }
  }

  /// Fires a persist path that must NEVER take the station down (bead `tg-7ux`).
  ///
  /// [_onReport] is a SYNCHRONOUS callback, so every persist is fired without
  /// being awaited — and a bare `unawaited` turns any throw into an UNHANDLED
  /// async error that kills the whole isolate. Each of these paths WRITES to the
  /// state store, and a store write fails for reasons that are none of this
  /// node's business and usually transient: a bd timeout, a Dolt server that
  /// died with the power, an open circuit breaker. Unguarded, ONE substation's
  /// flaky store takes down every OTHER substation's in-flight agents.
  ///
  /// So the failure is contained to its own node: the cursor is left where it
  /// is, and the throw is flared as `step.persistFailed`. A stuck node is
  /// recoverable — the governor sees it and reworks it; a dead station is not.
  /// LOUD, not silent, and never fatal.
  ///
  /// NOT a retry: a timed-out write is AMBIGUOUS (it may well have landed), and
  /// blindly re-issuing `createGate` would mint duplicate gates — the mint-dedup
  /// race is a known hazard. Retry is a separate decision from not-crashing.
  void _firePersist(String op, Future<void> Function() persist) {
    unawaited(
      persist().catchError((Object e) {
        _emitFlare('step.persistFailed', {
          'op': op,
          'error': truncateReason('$e'),
        });
      }),
    );
  }

  /// Test affordance: deliver [event] directly into the process allocation's
  /// event handler (exercises the Host's post-dispose guard in isolation from the
  /// subscription-cancel). Production events always arrive via the transport
  /// stream.
  void deliverEventForTest(RuntimeEvent event) {
    final alloc = _allocation;
    if (alloc is ProcessAllocation) alloc.deliverEventForTest(event);
  }

  /// Test affordance: deliver [report] straight into the Host's report sink,
  /// BYPASSING the allocation's own terminal latch — so the Host's `_completed`
  /// latch (a duplicate terminal → exactly one chokepoint write) can be exercised
  /// in isolation (the two latches otherwise mutually mask each other).
  void deliverReportForTest(AllocationReport report) => _onReport(report);

  /// The raw (startedAt, finishedAt, durationMs) triple a TERMINAL
  /// transition's telemetry derives from — fed into [_moleculeMetadata]'s
  /// [NodeCursor] (R5b). Prefers the in-memory kick instant (race-free,
  /// per-incarnation); falls back to the persisted projection the host
  /// already holds (the adopt/restore seam). Null [startedAt] → omit the
  /// derived duration.
  ({DateTime? startedAt, DateTime finishedAt, int? durationMs})
  _terminalTiming() {
    final finishedAt = _now();
    final startedAt = _startedAt ?? seed.mount.node.startedAt;
    final durationMs = startedAt == null
        ? null
        : finishedAt.difference(startedAt).inMilliseconds;
    return (
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: durationMs,
    );
  }

  /// The metadata payload for a transition to [state] — ONE
  /// [stepBeadMetadata] call, per-bead with no `{nodePath}` infix, since the
  /// step bead itself IS the node (R1).
  ///
  /// [restartCount] defaults to the CURRENT persisted value
  /// ([StepMount.node]'s — an unrelated transition never touches it);
  /// [terminal] (the default) pulls in [_terminalTiming]'s
  /// startedAt/finishedAt/durationMs triple (FT-1 capture-only telemetry,
  /// merged into the same chokepoint write); the non-terminal `running`
  /// transition ([_persistStarted]) passes `terminal: false` and carries only
  /// the kick instant [_startedAt].
  Map<String, String> _moleculeMetadata(
    StepState state, {
    int? restartCount,
    DateTime? cooldownUntil,
    String? failureReason,
    bool terminal = true,
  }) {
    final timing = terminal ? _terminalTiming() : null;
    return stepBeadMetadata(
      NodeCursor(
        state: state,
        restartCount: restartCount ?? seed.mount.node.restartCount,
        cooldownUntil: cooldownUntil,
        startedAt: timing?.startedAt ?? (terminal ? null : _startedAt),
        finishedAt: timing?.finishedAt,
        durationMs: timing?.durationMs,
        failureReason: failureReason,
      ),
    );
  }

  Future<void> _persistStarted() async {
    if (_cancelled || !context.mounted) return;
    // LOUD-or-GONE (Decided item 5, R3): every process-backed capability
    // MUST have a mounted lease vendor — the vendor, not this write, owns
    // `grid.lease.*`. Belt-and-braces: the routing fork
    // (`_createAllocationOrFlare`, tg-h4u) already resolved the vendor at
    // mount and routed the spawn through `leaseFor`/`acquire` (the real
    // `stationProcessSpawner` surfaces this very report through the sink);
    // this assertion re-checks presence on the persist path so a report
    // arriving through any OTHER composition still refuses loud.
    requireProcessLeaseVendor(context);
    await _ctx!.writer.update(
      _stepBeadId,
      // pgid/pid/token are DELIBERATELY absent here (R3): the vendor owns
      // `grid.lease.*`, never the step bead's cursor keys.
      metadata: _moleculeMetadata(StepState.running, terminal: false),
    );
  }

  /// A daemon's `ready` — a POSITIVE TERMINAL that does NOT latch (the daemon
  /// stays mounted and may later write `failed` on death, OQ-5). It may PUBLISH a
  /// rendezvous [payload] (e.g. the burn-follower's endpoint), recorded under the
  /// disjoint result namespace merged with the `state=ready` write — one atomic
  /// chokepoint update — so a dependent reads it pull-free (D-5), exactly like a
  /// job's completion payload. A null payload writes only the state (no result
  /// keys — a plain up-signal, today's behavior).
  Future<void> _persistReady([Map<String, String>? payload]) async {
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.update(
      _stepBeadId,
      metadata: {
        ..._moleculeMetadata(StepState.ready),
        // ResultKeys is reused VERBATIM on the step bead (R1) — only its
        // host bead moved.
        ...nodeResultMetadata(_nodePath, payload),
      },
    );
    _emitFlare('step.ready', const {});
  }

  /// A clean completion — the terminal `state=complete` merged with the optional
  /// result [payload] into ONE chokepoint update (the grade/pr_url lands
  /// atomically alongside the cursor advance — A1/D-5).
  Future<void> _persistComplete(Map<String, String>? payload) async {
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.update(
      _stepBeadId,
      metadata: {
        ..._moleculeMetadata(StepState.complete),
        ...nodeResultMetadata(_nodePath, payload),
      },
    );
    _emitFlare('step.complete', const {});
  }

  /// Authors the SUPERVISED-RESTART cursor on failure (D-5): bump restartCount
  /// and, when still within budget, set a backoff cooldown so the predicate
  /// re-keys after it; at exhaustion write no cooldown so the node is
  /// circuit-broken and SessionScope escalates. The failing leaf host is the
  /// named restart writer (no supervisor node — invariant 1 preserved).
  ///
  /// [reason] is the `AllocationFailed.reason` — persisted capture-only (FT-1)
  /// as the truncated `failureReason`, merged into the SAME write; an empty
  /// reason (e.g. a bare process death carrying no diagnostic) omits the key.
  Future<void> _persistFailure([String reason = '']) async {
    if (_cancelled || !context.mounted) return;
    final next = seed.mount.node.restartCount + 1;
    final exhausted = next >= seed.mount.maxRestarts;
    final cooldown = exhausted
        ? null
        : _now().add(seed.mount.backoff.delayFor(next));
    final failureReason = reason.isEmpty ? null : reason;
    await _ctx!.writer.update(
      _stepBeadId,
      metadata: _moleculeMetadata(
        StepState.failed,
        restartCount: next,
        cooldownUntil: cooldown,
        failureReason: failureReason,
      ),
    );
    _emitFlare('step.failed', const {});
  }

  /// ADVANCE (M5 D-4a): move the cursor forward. At the ROOT circuit's TERMINAL
  /// step this ACTUATES the substation's bound [DeliveryMethod] and merges its
  /// receipt into the SAME `state=complete` chokepoint write (one atomic update).
  ///
  /// Three shapes, all of them a real posture:
  ///  - NON-terminal advance → an ordinary completion (a sub-circuit's route);
  ///  - terminal advance, NO method bound → COMMIT-ONLY: the work completes and
  ///    nothing leaves the station (what the retired `--land` flag expressed as
  ///    "unarmed", now a per-substation binding);
  ///  - terminal advance WITH a method → deliver, then complete with the receipt.
  ///
  /// A delivery that FAILS (or THROWS) does NOT advance: it routes to supervision
  /// (bounded restart → the breaker → SessionScope's escalation). Silently
  /// completing un-delivered work is exactly the "stranded on a branch" failure
  /// this unification exists to kill.
  Future<void> _persistAdvance(Map<String, String>? payload) async {
    if (_cancelled || !context.mounted) return;
    final terminal = isDeliveryTerminal(
      circuit: seed.mount.circuit,
      circuitPath: seed.mount.circuitPath,
      stepId: seed.mount.step.stepId,
      beadId: _beadId,
    );
    final method = _services.delivery;
    if (!terminal || method == null) {
      if (terminal) _emitFlare('deliver.unarmed', const {});
      await _persistComplete(payload);
      return;
    }
    // The ambient values, read SYNCHRONOUSLY at entry with the EFFECT verb (this
    // runs off `build`, on a still-mounted branch — guarded above) and handed to
    // the method as VALUES, so a long push/PR round-trip cannot race an unmount
    // into a thrown tree lookup (ADR-0013 items 1/4).
    final workBead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workBead == null || workspace == null) {
      // LOUD (ADR-0008 Decision 3): a delivery method bound under a tree that
      // mounts no work bead / no workspace is a MIS-COMPOSITION — never a silent
      // no-op that strands the work.
      await _persistFailure(
        'delivery "${method.id}" needs an ambient Bead + Workspace '
        '(WorkBead/SessionScope provide them) — none found at $_nodePath',
      );
      return;
    }
    final StepOutcome outcome;
    try {
      outcome = await method.deliver(
        DeliveryRequest(
          bead: workBead,
          sessionId: _sessionId,
          nodePath: _nodePath,
          workspace: workspace,
          payload: payload ?? const {},
        ),
      );
    } on Object catch (e) {
      await _persistFailure('delivery "${method.id}" threw: $e');
      return;
    }
    if (_cancelled || !context.mounted) return;
    switch (outcome) {
      case Ok(payload: final receipt):
        await _persistComplete({
          ...?payload,
          ...?receipt,
          ResultKeys.delivery: method.id,
        });
        _emitFlare('step.delivered', {'method': method.id});
      case Failed(:final reason):
        await _persistFailure('delivery "${method.id}" failed: $reason');
    }
  }

  /// ESCALATE (M5 D-4a): the route declined — raise it to the substation's BOUND
  /// [EscalationHandler]. UNBOUND ⇒ [HumanGate], the M5 D-7 default, which returns
  /// [ParkAtGate] and so reproduces the old `Gate` outcome EXACTLY (`state=gated`
  /// + a real `type=gate` bead through the chokepoint; `SessionScope` re-arms the
  /// node when that gate CLOSES). The engine hardcodes no authority.
  ///
  /// A handler that DECLINES ([FailToSupervision]) — or THROWS — routes the node
  /// to supervision instead of parking: an escalation nobody owns must never look
  /// like a park somebody does (LOUD or GONE).
  ///
  /// DISTINCT from `SessionScope`'s breaker-exhaustion escalation (D-5), which is
  /// supervision's, not routing's, and is untouched.
  Future<void> _persistEscalate(String reason) async {
    if (_cancelled || !context.mounted) return;
    final handler = _services.escalation ?? const HumanGate();
    _emitFlare('step.escalated', {
      'handler': handler.id,
      'reason': truncateReason(reason),
    });
    final EscalationDecision decision;
    try {
      decision = await handler.escalate(
        EscalationRequest(
          beadId: _beadId,
          sessionId: _sessionId,
          nodePath: _nodePath,
          reason: reason,
          rewindCount: seed.mount.node.rewindCount,
        ),
      );
    } on Object catch (e) {
      await _persistFailure('escalation handler "${handler.id}" threw: $e');
      return;
    }
    if (_cancelled || !context.mounted) return;
    switch (decision) {
      case ParkAtGate(reason: final parkReason):
        await _persistGate(parkReason);
      case FailToSupervision(reason: final declineReason):
        await _persistFailure(
          'escalation handler "${handler.id}" declined: $declineReason',
        );
    }
  }

  /// PARK at a human gate (D-7): write `state=gated` (parks the node + withholds
  /// its dependents) AND mint a real `type=gate` bead in the OWN state store
  /// through the chokepoint — never a write to the foreign work bead (A37).
  /// Resolving that gate bead re-arms the node. Reached ONLY through
  /// [_persistEscalate] (M5 D-4a): a park is a DECISION of the bound handler, not
  /// a verdict of its own.
  Future<void> _persistGate(String reason) async {
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.update(
      _stepBeadId,
      metadata: _moleculeMetadata(StepState.gated),
    );
    if (_cancelled || !context.mounted) return;
    // The gate bead itself stays keyed to the OWNING SESSION —
    // `createGate`'s `blocks`/`node` linkage re-arms this exact `nodePath`
    // on resolve; the `state=gated` cursor write above rides the step bead
    // (R5b), an orthogonal concern.
    await _ctx!.writer.createGate(
      substation: _ctx!.stateSubstation,
      sessionId: _sessionId,
      nodePath: _nodePath,
      reason: reason,
    );
    _emitFlare('step.gated', {'reason': reason});
  }

  /// The [AllocationRewound] report's dispatch — a REFUSAL, always (Decided
  /// item 7 / `DESIGN-tg-pm6.md` §8/§11): backward motion on the molecule
  /// model is a pure DERIVATION over `validates`-edge stamps ("no
  /// RouteVerdict, no persisted rewindCount, no signal"), so a circuit step
  /// reporting an explicit rewind decision is a mis-composition — routed to a
  /// supervised failure, LOUD, not silent. This was already the molecule
  /// path's exact behavior; the flat model's write cascade (`_persistRewind`)
  /// retired with the flat cursor (tg-eli phase 2), leaving the refusal as
  /// the only behavior.
  Future<void> _persistRewindReport(Set<String> stepIds, String reason) async {
    await _persistFailure(
      'AllocationRewound reached a molecule-mode step at $_nodePath — '
      'backward motion is derived there (R4); this circuit must not report '
      'a rewind decision',
    );
  }

  /// Emits a fire-and-forget observability flare after a terminal cursor write
  /// (D-8) through the reserved emit-only [ExplorationTransport] — never an
  /// inbound pipeline handle (invariant 1). A throwing transport must NOT break
  /// the flush, so errors are swallowed (the cursor already advanced).
  void _emitFlare(String name, Map<String, String> data) {
    try {
      _services.transport?.flare(name, {
        'sessionId': _sessionId,
        'nodePath': _nodePath,
        ...data,
      });
    } catch (_) {
      // A throwing transport never breaks the flush (D-8) — swallow.
    }
  }

  @override
  void dispose() {
    // Set the guard FIRST so any in-flight report is dropped, then unmount the
    // effect. `dispose` (kill) is the floor (ADR-0009 D4); the graceful-restart
    // `detach` (leave running) is orchestrated by the reconciler at controller-
    // shutdown (Track D), not on a normal branch-unmount. Uses the allocation
    // (built in didChangeDependencies), so teardown fires even if the spawn was
    // never reached (finding #1).
    _cancelled = true;
    unawaited(_allocation?.dispose());
  }

  @override
  Seed build(TreeContext context) => const Idle();
}
