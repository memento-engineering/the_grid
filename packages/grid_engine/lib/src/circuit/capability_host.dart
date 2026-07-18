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

import '../domain/rework.dart';
import '../domain/session_bead.dart';
import '../kernel/station_services.dart';
import '../kernel/idle.dart';
import '../molecule/inherited_circuit.dart' show InheritedCircuit;
import '../molecule/molecule_codec.dart' show stepBeadMetadata;
import '../molecule/process_lease_vendor.dart' show requireProcessLeaseVendor;
import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/circuit.dart';
import '../sdk/cursor.dart';
import '../sdk/rewind.dart';
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

  /// Resolves this incarnation's write target — the additive fork
  /// (`DESIGN-tg-pm6.md` §11, pm6-r5b-host): an ambient [InheritedCircuit]
  /// (R2) means a MOLECULE session, and every `_persistX` below targets its
  /// OWN durable step bead (`beadIdByNodePath[_nodePath]`) instead of the
  /// session bead. Absent (no [InheritedCircuit] provided — every in-flight
  /// and every not-yet-molecule-minted session) → null, and every persist
  /// falls back to today's FLAT target (`_sessionId`), byte-for-byte
  /// unchanged (conflict 2's "absent key ⇒ flat", by construction).
  ///
  /// Read with the EFFECT verb (`getInheritedSeedOfExactType`, ADR-0008
  /// Decision 3): every `_persistX` runs OFF `build`, in the report path, on
  /// a still-mounted branch (guarded by its own caller) — exactly like the
  /// existing `Bead`/`Workspace` reads in [_persistAdvance].
  ///
  /// A MOUNTED [InheritedCircuit] missing its own node in
  /// [InheritedCircuit.beadIdByNodePath] is a join/mint mis-composition —
  /// LOUD (a thrown [StateError]; every call site below is itself `async`, so
  /// the throw is captured as a rejected Future and safely contained by
  /// [_firePersist]'s `catchError`), never a silent fall-through to the
  /// session bead, which would quietly reintroduce the flat write shape
  /// mid-molecule-session.
  String? get _moleculeTarget {
    final circuit = context.getInheritedSeedOfExactType<InheritedCircuit>();
    if (circuit == null) return null;
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
      final alloc = seed.capability.createAllocation(_buildAllocationContext());
      _allocation = alloc;
      unawaited(alloc.startOrAdopt());
    } else {
      // A dependency the effect reads CHANGED (ADR-0009 D3: depending on context
      // is the norm). Resolve coherently: `update` in place if the type supports
      // it, else leave the running effect untouched — the base process/service
      // families are not updatable, and a genuine replace is a re-key the
      // CircuitScope owns (a `restartCount` bump → a new key → a fresh mount).
      // We NEVER re-key here.
      final next = seed.capability.createAllocation(_buildAllocationContext());
      if (existing.canUpdate(next)) unawaited(existing.update(next));
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
      case AllocationStarted(:final pid, :final pgid):
        _firePersist('started', () => _persistStarted(pid: pid, pgid: pgid));
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
  /// transition's telemetry derives from — factored out of
  /// [_terminalTelemetry] so the molecule-mode writes ([_moleculeMetadata],
  /// R5b) can feed the SAME triple into a [NodeCursor] instead of the flat
  /// [nodeTelemetryMetadata] keys. Prefers the in-memory kick instant
  /// (race-free, per-incarnation); falls back to the persisted projection the
  /// host already holds (the adopt/restore seam). Null [startedAt] → omit the
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

  /// The capture-only flow-telemetry keys (FT-1, tg-pez) for a terminal
  /// transition — the step's start + finish + derived duration (+ an optional
  /// [failureReason]), MERGED into the SAME chokepoint write as the cursor state
  /// (no extra write traffic). Fail-safe: a start that was never measured
  /// (`_startedAt` null AND no persisted `startedAt`) omits both `startedAt` and
  /// `durationMs` rather than blocking the transition.
  Map<String, String> _terminalTelemetry({String? failureReason}) {
    final t = _terminalTiming();
    return nodeTelemetryMetadata(
      _nodePath,
      startedAt: t.startedAt,
      finishedAt: t.finishedAt,
      durationMs: t.durationMs,
      failureReason: failureReason,
    );
  }

  /// The molecule-mode metadata payload for a transition to [state] — the
  /// per-bead, no-`{nodePath}`-infix mirror of the flat model's per-call
  /// builders ([nodeStateMetadata] / [nodeFailedMetadata] /
  /// [nodeStartedMetadata] + [nodeTelemetryMetadata]), collapsed into ONE
  /// [stepBeadMetadata] call since the step bead itself IS the node (R1) — no
  /// infix left to disambiguate.
  ///
  /// [restartCount] defaults to the CURRENT persisted value
  /// ([StepMount.node]'s — an unrelated transition never touches it);
  /// [terminal] (the default) pulls in [_terminalTiming]'s
  /// startedAt/finishedAt/durationMs triple, exactly like [_terminalTelemetry]
  /// does for the flat write; the non-terminal `running` transition
  /// ([_persistStarted]) passes `terminal: false` and carries only the kick
  /// instant [_startedAt].
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

  Future<void> _persistStarted({required int pid, int? pgid}) async {
    if (_cancelled || !context.mounted) return;
    final target = _moleculeTarget;
    if (target != null) {
      // LOUD-or-GONE (Decided item 5, R3): every process-backed capability on
      // the molecule path MUST have a mounted lease vendor — the vendor, not
      // this write, owns `grid.lease.*`. This call is ONLY the presence
      // assertion (a process-backed capability is exactly what reaches this
      // method — only `ProcessAllocation` ever reports `AllocationStarted`);
      // it does not itself call `leaseFor`/`acquire`. Routing this Host's
      // actual process spawn/dispatch through the vendor (instead of the
      // unchanged `ProcessAllocation`/`RuntimeProvider` path below) is a
      // follow-up rung, NOT delivered by `pm6-r5-drain` — see
      // `process_lease_vendor.dart`'s library doc.
      requireProcessLeaseVendor(context);
      await _ctx!.writer.update(
        target,
        // pgid/pid/token are DELIBERATELY absent here (R3): the vendor owns
        // `grid.lease.*`, never the step bead's cursor keys.
        metadata: _moleculeMetadata(StepState.running, terminal: false),
      );
      return;
    }
    await _ctx!.writer.update(
      _sessionId,
      metadata: {
        ...nodeStartedMetadata(_nodePath, pgid: pgid, pid: pid, token: _token),
        // Capture-only (FT-1): stamp the step-begin instant on the `running`
        // write so a live step's start is durable before its terminal.
        ...nodeTelemetryMetadata(_nodePath, startedAt: _startedAt),
      },
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
    final target = _moleculeTarget;
    await _ctx!.writer.update(
      target ?? _sessionId,
      metadata: target != null
          ? {
              ..._moleculeMetadata(StepState.ready),
              // ResultKeys is reused VERBATIM on the step bead (R1) — only its
              // host bead moves.
              ...nodeResultMetadata(_nodePath, payload),
            }
          : {
              ...nodeStateMetadata(_nodePath, StepState.ready),
              ...nodeResultMetadata(_nodePath, payload),
              ..._terminalTelemetry(),
            },
    );
    _emitFlare('step.ready', const {});
  }

  /// A clean completion — the terminal `state=complete` merged with the optional
  /// result [payload] into ONE chokepoint update (the grade/pr_url lands
  /// atomically alongside the cursor advance — A1/D-5).
  Future<void> _persistComplete(Map<String, String>? payload) async {
    if (_cancelled || !context.mounted) return;
    final target = _moleculeTarget;
    await _ctx!.writer.update(
      target ?? _sessionId,
      metadata: target != null
          ? {
              ..._moleculeMetadata(StepState.complete),
              ...nodeResultMetadata(_nodePath, payload),
            }
          : {
              ...nodeStateMetadata(_nodePath, StepState.complete),
              ...nodeResultMetadata(_nodePath, payload),
              ..._terminalTelemetry(),
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
    final target = _moleculeTarget;
    await _ctx!.writer.update(
      target ?? _sessionId,
      metadata: target != null
          ? _moleculeMetadata(
              StepState.failed,
              restartCount: next,
              cooldownUntil: cooldown,
              failureReason: failureReason,
            )
          : {
              ...nodeFailedMetadata(
                _nodePath,
                restartCount: next,
                cooldownUntil: cooldown,
              ),
              ..._terminalTelemetry(failureReason: failureReason),
            },
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
    final target = _moleculeTarget;
    await _ctx!.writer.update(
      target ?? _sessionId,
      metadata: target != null
          ? _moleculeMetadata(StepState.gated)
          : {
              ...nodeStateMetadata(_nodePath, StepState.gated),
              ..._terminalTelemetry(),
            },
    );
    if (_cancelled || !context.mounted) return;
    // The gate bead itself stays keyed to the OWNING SESSION regardless of
    // mode (unchanged from today) — `createGate`'s `blocks`/`node` linkage
    // re-arms this exact `nodePath` on resolve; which bead carries the
    // `state=gated` cursor write above is an orthogonal, R5b-only concern.
    await _ctx!.writer.createGate(
      substation: _ctx!.stateSubstation,
      sessionId: _sessionId,
      nodePath: _nodePath,
      reason: reason,
    );
    _emitFlare('step.gated', {'reason': reason});
  }

  /// The [AllocationRewound] report's target-aware dispatch (R5b, the
  /// additive fork): on the FLAT path (`_moleculeTarget == null`), this calls
  /// exactly today's [_persistRewind] — unchanged. On the MOLECULE path,
  /// [_persistRewind]'s write cascade is DEAD CODE and is NEVER called
  /// (Decided item 7 / `DESIGN-tg-pm6.md` §8/§11: backward motion is a pure
  /// DERIVATION over `validates`-edge stamps, "no RouteVerdict, no persisted
  /// rewindCount, no signal"). A molecule circuit step reporting an explicit
  /// rewind decision is therefore a mis-composition — routed to a supervised
  /// failure instead, LOUD, not silent, exactly like [_persistRewind]'s own
  /// empty/dangling-[stepIds] guard below.
  Future<void> _persistRewindReport(Set<String> stepIds, String reason) async {
    if (_moleculeTarget != null) {
      await _persistFailure(
        'AllocationRewound reached a molecule-mode step at $_nodePath — '
        'backward motion is derived there (R4); this circuit must not report '
        'a rewind decision',
      );
      return;
    }
    await _persistRewind(stepIds, reason);
  }

  /// REWIND (routing — the dual of fan-out; M5 D-4 promoted to a first-class arm,
  /// tg-o90): re-run the named SIBLING steps, every node transitively downstream
  /// of them, and SELF. FLAT-MODEL ONLY (R5b): [_persistRewindReport] never
  /// calls this on the molecule path (backward motion is derived there, R4).
  /// ONE merge-safe chokepoint write flips that whole sub-DAG to
  /// `state=pending` with a bumped per-node `rewindCount`, which RE-KEYS each
  /// node (`CircuitScope`) — so keyed reconcile disposes (KILLS, ADR-0009 D4) the
  /// old incarnations and re-runs them virgin. NO `type=gate` bead is minted and
  /// the session is NOT re-minted: the round happens INSIDE the live session, in
  /// the same workspace, with no human in the loop.
  ///
  /// Two LOUD refusals (ADR-0008 D3 — a guard exists only where it protects a
  /// named invariant with a concrete failure story, and is LOUD when violated):
  ///
  /// - an EMPTY or DANGLING [stepIds] would silently degrade into "re-run only
  ///   myself, forever" → a supervised failure instead (bounded by the breaker,
  ///   then escalation);
  /// - a node whose own `rewindCount` already reached [kMaxReworkRounds] REFUSES
  ///   to rewind again and ESCALATES through the bound [EscalationHandler] (D-4's
  ///   bounded rework rounds; the default [HumanGate] parks exactly as before),
  ///   so a mis-specified route can never spin the loop. The operator's lever to
  ///   grant a fresh budget is `grid rework` (a new session ⇒ a new cursor).
  Future<void> _persistRewind(Set<String> stepIds, String reason) async {
    if (_cancelled || !context.mounted) return;
    final circuit = seed.mount.circuit;
    final unknown = stepIds.where((id) => circuit.stepById(id) == null).toList()
      ..sort();
    if (stepIds.isEmpty || unknown.isNotEmpty) {
      await _persistFailure(
        stepIds.isEmpty
            ? 'rewind named no steps (circuit "${circuit.id}")'
            : 'rewind names unknown step(s) ${unknown.join(', ')} in circuit '
                  '"${circuit.id}"',
      );
      return;
    }
    final rounds = seed.mount.node.rewindCount;
    if (rounds >= kMaxReworkRounds) {
      // The BELT (M5 D-4/A47): refuse and ESCALATE to the bound handler — whose
      // DEFAULT (HumanGate) parks exactly as before. The cap no longer assumes
      // the authority is a human; it just refuses to spin the loop.
      await _persistEscalate(
        'rework cap reached ($rounds/$kMaxReworkRounds): $reason',
      );
      return;
    }
    final registry = _registry;
    final paths = rewindNodePaths(
      circuit,
      seed.mount.circuitPath,
      stepIds,
      selfStepId: seed.mount.step.stepId,
      circuitById: (id) => registry?.circuit(id),
    );
    // The per-node PRIOR counts, read with the EFFECT verb (ADR-0008 Decision 3,
    // amended 2026-07-02): this runs OFF `build`, in the report path, on a
    // still-mounted branch (guarded above). Never `dependOn` the SiblingView — it
    // is a fresh instance per build, so binding to it would rebuild every host on
    // every cursor tick. Each node's OWN count is bumped (monotonic per node), so
    // the key ALWAYS changes; a shared round number could equal a node's existing
    // count and silently skip its re-key.
    final view =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    await _ctx!.writer.update(
      _sessionId,
      metadata: {
        for (final path in paths)
          ...nodeRewoundMetadata(
            path,
            rewindCount: view.cursorOf(path).rewindCount + 1,
          ),
        // SELF's bump is authoritative from the mount (the view agrees in the
        // tree; a bare-mounted host has no view at all).
        ...nodeRewoundMetadata(_nodePath, rewindCount: rounds + 1),
        ..._terminalTelemetry(),
      },
    );
    _emitFlare('step.rewound', {
      'steps': (stepIds.toList()..sort()).join(','),
      'nodes': '${paths.length}',
      'round': '${rounds + 1}',
      'reason': truncateReason(reason),
    });
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
