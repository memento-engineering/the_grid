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

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../domain/rework.dart';
import '../domain/session_bead.dart';
import '../kernel/station_services.dart';
import '../kernel/idle.dart';
import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/circuit.dart';
import '../sdk/rewind.dart';
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
        unawaited(_persistStarted(pid: pid, pgid: pgid));
      case AllocationReady(:final payload):
        if (_completed) return;
        unawaited(_persistReady(payload));
      case AllocationCompleted(:final payload):
        if (_completed) return;
        _completed = true;
        unawaited(_persistComplete(payload));
      case AllocationFailed(:final reason):
        if (_completed) return;
        _completed = true;
        unawaited(_persistFailure(reason));
      case AllocationGated(:final reason):
        if (_completed) return;
        _completed = true;
        unawaited(_persistGate(reason));
      case AllocationRewound(:final stepIds, :final reason):
        if (_completed) return;
        _completed = true;
        unawaited(_persistRewind(stepIds, reason));
    }
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

  /// The capture-only flow-telemetry keys (FT-1, tg-pez) for a terminal
  /// transition — the step's start + finish + derived duration (+ an optional
  /// [failureReason]), MERGED into the SAME chokepoint write as the cursor state
  /// (no extra write traffic). Fail-safe: a start that was never measured
  /// (`_startedAt` null AND no persisted `startedAt`) omits both `startedAt` and
  /// `durationMs` rather than blocking the transition.
  Map<String, String> _terminalTelemetry({String? failureReason}) {
    final finishedAt = _now();
    // Prefer the in-memory kick instant (race-free, per-incarnation); fall back
    // to the persisted projection the host already holds (the adopt/restore
    // seam). Null → omit the derived duration.
    final startedAt = _startedAt ?? seed.mount.node.startedAt;
    final durationMs = startedAt == null
        ? null
        : finishedAt.difference(startedAt).inMilliseconds;
    return nodeTelemetryMetadata(
      _nodePath,
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: durationMs,
      failureReason: failureReason,
    );
  }

  Future<void> _persistStarted({required int pid, int? pgid}) async {
    if (_cancelled || !context.mounted) return;
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
    await _ctx!.writer.update(
      _sessionId,
      metadata: {
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
    await _ctx!.writer.update(
      _sessionId,
      metadata: {
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
    final cooldown =
        exhausted ? null : _now().add(seed.mount.backoff.delayFor(next));
    await _ctx!.writer.update(
      _sessionId,
      metadata: {
        ...nodeFailedMetadata(
          _nodePath,
          restartCount: next,
          cooldownUntil: cooldown,
        ),
        ..._terminalTelemetry(failureReason: reason.isEmpty ? null : reason),
      },
    );
    _emitFlare('step.failed', const {});
  }

  /// PARK at a human gate (D-7): write `state=gated` (parks the node + withholds
  /// its dependents) AND mint a real `type=gate` bead in the OWN state store
  /// through the chokepoint — never a write to the foreign work bead (A37).
  /// Resolving that gate bead re-arms the node.
  Future<void> _persistGate(String reason) async {
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.update(
      _sessionId,
      metadata: {
        ...nodeStateMetadata(_nodePath, StepState.gated),
        ..._terminalTelemetry(),
      },
    );
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.createGate(
      substation: _ctx!.stateSubstation,
      sessionId: _sessionId,
      nodePath: _nodePath,
      reason: reason,
    );
    _emitFlare('step.gated', {'reason': reason});
  }

  /// REWIND (routing — the dual of fan-out; M5 D-4 promoted to a first-class arm,
  /// tg-o90): re-run the named SIBLING steps, every node transitively downstream
  /// of them, and SELF. ONE merge-safe chokepoint write flips that whole sub-DAG
  /// to `state=pending` with a bumped per-node `rewindCount`, which RE-KEYS each
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
  ///   to rewind again and parks at a human [Gate] (D-4's bounded rework rounds),
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
      await _persistGate(
        'rework cap reached ($rounds/$kMaxReworkRounds) — a human decides: '
        '$reason',
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
