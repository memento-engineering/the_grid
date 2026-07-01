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
/// re-key rather than update, and the FormulaScope owns the key); on unmount
/// kicks `dispose` (kill); and **persists** every [AllocationReport] the effect
/// pushes — off `build`, latched, through the single [StationBeadWriter].
///
/// **The effect layer holds NO writer** (invariant 2): the [Allocation] reports;
/// the Host persists. This is layering, not a sandbox (ADR-0009 D3) — the
/// allocation may freely depend on the tree; only the Host writes.
///
/// The load-bearing async-gap guards live entirely here (the tree's discipline):
/// `_cancelled` (set FIRST in `dispose`) + `TreeContext.mounted` drop a report
/// reaching an unmounted Branch; the captured `_ctx` is used across gaps (never
/// `context`, which throws post-unmount); `_completed` is the once-only terminal
/// latch (a daemon `ready` does NOT latch — OQ-5).
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../domain/session_bead.dart';
import '../effect/effect_context.dart';
import '../kernel/idle.dart';
import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/formula.dart';
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
  EffectContext? _ctx;
  ServiceBundle _services = const ServiceBundle();
  CapabilityRegistry? _registry;
  Allocation? _allocation;
  String _token = '';
  bool _cancelled = false;
  bool _completed = false;

  String get _sessionId => seed.mount.session.sessionId;
  String get _nodePath => seed.mount.nodePath;

  /// The work bead id — the root segment of the nodePath (the root formula's
  /// nodePath IS the bead id, so every step path is `beadId/...`).
  String get _beadId =>
      _nodePath.contains('/') ? _nodePath.split('/').first : _nodePath;

  @override
  void initState() {
    _token = newInstanceToken();
  }

  @override
  void didChangeDependencies() {
    _ctx ??= context.dependOnInheritedSeedOfExactType<EffectContext>();
    assert(
      _ctx != null,
      'CapabilityHost requires an ambient InheritedSeed<EffectContext>',
    );
    final services = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    if (services != null) _services = services;
    _registry ??= context.dependOnInheritedSeedOfExactType<CapabilityRegistry>();

    final existing = _allocation;
    if (existing == null) {
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
      // FormulaScope owns (a `restartCount` bump → a new key → a fresh mount).
      // We NEVER re-key here.
      final next = seed.capability.createAllocation(_buildAllocationContext());
      if (existing.canUpdate(next)) unawaited(existing.update(next));
    }
  }

  /// The wall clock for the backoff cooldown — the registry's (the kernel owns
  /// it, D-5/F1), falling back to the system clock if no registry is ambient.
  DateTime _now() => _registry?.now() ?? DateTime.now();

  /// Assembles the [AllocationContext] the effect runs against — the sandboxed
  /// [CapabilityContext] (read-only config slice), the process transport, the
  /// stable address, the engine env overlay, the report sink, and the adopt
  /// fence (the prior identity for a no-adopt-on-faith proof — D4).
  AllocationContext _buildAllocationContext() {
    final ctx = _ctx!;
    final capContext = CapabilityContext(
      params: seed.mount.step.params,
      bead: seed.mount.bead,
      workspaceDir: ctx.worktreeFor(_beadId),
      branch: ctx.branchFor(_beadId),
      baseBranch: ctx.baseBranch,
      services: _services,
      cancel: CancelToken(),
      nodePath: _nodePath,
      // The read-only sibling view (D-5): the WHOLE session cursor + results,
      // threaded down (config, never a subscription/re-query — A39/invariant 1).
      siblings: SiblingView(
        cursor: seed.mount.cursor,
        results: seed.mount.results,
      ),
      logFile: null,
    );
    return AllocationContext(
      capContext: capContext,
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
      // empty for a fresh node. The base families never adopt (Track C/D wire
      // the daemon/lease adopt path).
      fence: AdoptFence(
        pgid: seed.mount.node.pgid,
        pid: seed.mount.node.pid,
        token: seed.mount.node.token,
      ),
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
      case AllocationReady():
        if (_completed) return;
        unawaited(_persistReady());
      case AllocationCompleted(:final payload):
        if (_completed) return;
        _completed = true;
        unawaited(_persistComplete(payload));
      case AllocationFailed():
        if (_completed) return;
        _completed = true;
        unawaited(_persistFailure());
      case AllocationGated(:final reason):
        if (_completed) return;
        _completed = true;
        unawaited(_persistGate(reason));
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

  Future<void> _persistStarted({required int pid, int? pgid}) async {
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.update(
      _sessionId,
      metadata: nodeStartedMetadata(
        _nodePath,
        pgid: pgid,
        pid: pid,
        token: _token,
      ),
    );
  }

  /// A daemon's `ready` — a POSITIVE TERMINAL that does NOT latch (the daemon
  /// stays mounted and may later write `failed` on death, OQ-5).
  Future<void> _persistReady() async {
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.update(
      _sessionId,
      metadata: nodeStateMetadata(_nodePath, StepState.ready),
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
      },
    );
    _emitFlare('step.complete', const {});
  }

  /// Authors the SUPERVISED-RESTART cursor on failure (D-5): bump restartCount
  /// and, when still within budget, set a backoff cooldown so the predicate
  /// re-keys after it; at exhaustion write no cooldown so the node is
  /// circuit-broken and SessionScope escalates. The failing leaf host is the
  /// named restart writer (no supervisor node — invariant 1 preserved).
  Future<void> _persistFailure() async {
    if (_cancelled || !context.mounted) return;
    final next = seed.mount.node.restartCount + 1;
    final exhausted = next >= seed.mount.maxRestarts;
    final cooldown =
        exhausted ? null : _now().add(seed.mount.backoff.delayFor(next));
    await _ctx!.writer.update(
      _sessionId,
      metadata: nodeFailedMetadata(
        _nodePath,
        restartCount: next,
        cooldownUntil: cooldown,
      ),
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
      metadata: nodeStateMetadata(_nodePath, StepState.gated),
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
