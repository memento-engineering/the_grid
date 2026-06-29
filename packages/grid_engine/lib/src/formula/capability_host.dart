/// The engine-private capability carrier (ADR-0008 D4 / M4-P1 §5, Track E).
///
/// `CapabilityHost` is the engine's per-step process carrier, keyed on an
/// arbitrary `nodePath`/`stepId` — a tree node whose Branch lifecycle IS the
/// step-process lifecycle: mount (`initState`) = spawn, a `SessionStarted` =
/// persist the per-node identity (pgid/pid/token — D-4), a terminal event =
/// write the node cursor through the chokepoint, unmount (`dispose`) = kill +
/// belt-and-braces teardown. `build()` is a pure `Idle` leaf (A39).
///
/// The author NEVER subclasses this (a structural fence proves it). It carries a
/// concrete [Capability] (resolved by the registry from the step's
/// capabilityId) + the [StepMount] context, and resolves the [EffectContext]
/// (provider/writer) + [ServiceBundle] from the tree in one inherited lookup
/// each. The capability sees only the sandboxed [CapabilityContext] — no
/// TreeContext/writer/notifier (invariants 1/2 hold at depth by construction).
///
/// The three load-bearing guards live entirely here (the engine's async-gap
/// discipline): `_cancelled` (set FIRST in `dispose`) + `TreeContext.mounted`
/// (the never-throwing async-gap probe) drop an out-of-band event reaching an
/// unmounted Branch; the captured `_ctx` is used across gaps (never `context`,
/// which throws post-unmount); `_completed` is the once-only terminal latch.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../domain/session_bead.dart';
import '../effect/effect_context.dart';
import '../kernel/idle.dart';
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

/// The pinned [CapabilityHost] lifecycle (the `EffectSeedState` generalization).
class CapabilityHostState extends State<CapabilityHost> {
  EffectContext? _ctx;
  ServiceBundle _services = const ServiceBundle();
  CapabilityRegistry? _registry;
  CapabilityContext? _capCtx;
  StreamSubscription<RuntimeEvent>? _sub;
  String _token = '';
  String _stepName = '';
  bool _cancelled = false;
  bool _started = false;
  bool _completed = false;

  String get _sessionId => seed.mount.session.sessionId;
  String get _nodePath => seed.mount.nodePath;

  /// The work bead id — the root segment of the nodePath (the root formula's
  /// nodePath IS the bead id, so every step path is `beadId/...`).
  String get _beadId =>
      _nodePath.contains('/') ? _nodePath.split('/').first : _nodePath;

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
    // Build the sandboxed context HERE (synchronously, before _run's async gap)
    // so teardown is guaranteed on EVERY exit path — even a dispose that races
    // _run before it would have built it (Track E review finding #1).
    _capCtx ??= _buildCapCtx();
  }

  @override
  void initState() {
    _token = newInstanceToken();
    unawaited(_run());
  }

  /// The wall clock for the backoff cooldown — the registry's (the kernel owns
  /// it, D-5/F1), falling back to the system clock if no registry is ambient.
  DateTime _now() => _registry?.now() ?? DateTime.now();

  CapabilityContext _buildCapCtx() {
    final ctx = _ctx!;
    return CapabilityContext(
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
  }

  Future<void> _run() async {
    // Yield so didChangeDependencies has captured _ctx/_services + built _capCtx.
    await null;
    if (_cancelled || !context.mounted) return;
    // The per-step provider name — '$sessionId/$nodePath' (the full path already
    // disambiguates every concurrent step → disjoint event routing, D-2).
    _stepName = '$_sessionId/$_nodePath';

    final cap = seed.capability;
    switch (cap) {
      case ProcessCapability():
        // Materialize the workspace BEFORE spawning into it (the host owns
        // provisioning, ADR-0008 D5). Idempotent — a later step in the same
        // worktree no-ops; offline it no-ops. A dispose racing this drops out.
        await _services.sourceControl?.provisionWorkspace(
          beadId: _beadId,
          workspaceDir: _capCtx!.workspaceDir,
        );
        if (_cancelled || !context.mounted) return;
        _sub = _ctx!.provider.events
            .where((e) => e.name == _stepName)
            .listen(_onEvent);
        final base = cap.spawn(_capCtx!);
        final config = base.copyWith(
          env: {
            ...base.env,
            'GRID_BEAD_ID': _beadId,
            // The agent's `grid step --advance` shim writes its OWN session
            // cursor at this step path through the chokepoint — it needs both.
            'GRID_SESSION_ID': _sessionId,
            'GRID_INSTANCE_TOKEN': _token,
            'GRID_STEP_PATH': _nodePath,
          },
        );
        _started = true;
        try {
          await _ctx!.provider.start(_stepName, config);
        } on SessionAlreadyExists {
          // A re-fired ready event raced the spawn — fine.
        }
      case ServiceCapability():
        final outcome = await cap.run(_capCtx!);
        if (_cancelled || !context.mounted) return;
        await _writeOutcome(outcome);
    }
  }

  void _onEvent(RuntimeEvent e) {
    if (e is SessionStarted) {
      unawaited(_persistStarted(e));
      return;
    }
    final cap = seed.capability;
    if (cap is ProcessCapability) {
      final signal = cap.interpretEvent(e);
      if (signal != StepSignal.none) unawaited(_writeSignal(signal));
    }
  }

  /// Test affordance: deliver [event] directly (exercises the post-dispose
  /// guard in isolation from the subscription dispose cancels). Production events
  /// always arrive via the provider stream.
  void deliverEventForTest(RuntimeEvent event) => _onEvent(event);

  Future<void> _persistStarted(SessionStarted s) async {
    if (_cancelled || !context.mounted) return;
    await _ctx!.writer.update(
      _sessionId,
      metadata: nodeStartedMetadata(
        _nodePath,
        pgid: s.pgid,
        pid: s.pid,
        token: _token,
      ),
    );
  }

  Future<void> _writeSignal(StepSignal signal) async {
    if (_cancelled || !context.mounted || _completed) return;
    switch (signal) {
      case StepSignal.none:
        return;
      case StepSignal.ready:
        // A daemon's `ready` is a POSITIVE TERMINAL but does NOT latch — the
        // daemon stays mounted and may later write `failed` on death (OQ-5).
        await _ctx!.writer.update(
          _sessionId,
          metadata: nodeStateMetadata(_nodePath, StepState.ready),
        );
        _emitFlare('step.ready', const {});
      case StepSignal.complete:
        _completed = true;
        // The optional result payload a ProcessCapability contributes on a clean
        // completion (e.g. a critic's grade) — read AFTER latching, merged with
        // the terminal `state=complete` write into ONE chokepoint update so the
        // grade lands atomically alongside the cursor advance (A1/D-5).
        final cap = seed.capability;
        final payload =
            cap is ProcessCapability ? await cap.result(_capCtx!) : null;
        if (_cancelled || !context.mounted) return;
        await _ctx!.writer.update(
          _sessionId,
          metadata: {
            ...nodeStateMetadata(_nodePath, StepState.complete),
            ...nodeResultMetadata(_nodePath, payload),
          },
        );
        _emitFlare('step.complete', const {});
      case StepSignal.failed:
        _completed = true;
        await _writeFailure();
    }
  }

  Future<void> _writeOutcome(StepOutcome outcome) async {
    if (_cancelled || !context.mounted || _completed) return;
    _completed = true;
    switch (outcome) {
      case Ok(:final payload):
        // The terminal state PLUS the optional result payload (e.g. the land
        // step's pr_url) — recorded on the_grid's OWN session bead through the
        // chokepoint (ADR-0006 D3: "record the PR on the lifecycle bead"). The
        // result keys are namespaced disjoint from the cursor, so they merge
        // alongside `state=complete` without colliding (invariant 2 holds: one
        // chokepoint, own session bead, off-build).
        await _ctx!.writer.update(
          _sessionId,
          metadata: {
            ...nodeStateMetadata(_nodePath, StepState.complete),
            ...nodeResultMetadata(_nodePath, payload),
          },
        );
        _emitFlare('step.complete', const {});
      case Failed():
        await _writeFailure();
      case Gate(:final reason):
        // PARK at a human gate (D-7): write `state=gated` (parks the node +
        // withholds its dependents) AND mint a real `type=gate` bead in the OWN
        // state store through the chokepoint — never a write to the foreign work
        // bead (A37). Resolving that gate bead re-arms the node.
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
  }

  /// Authors the SUPERVISED-RESTART cursor on failure (D-5): bump restartCount
  /// and, when still within budget, set a backoff cooldown so the predicate
  /// re-keys after it; at exhaustion write no cooldown so the node is
  /// circuit-broken and SessionScope escalates. The failing leaf host is the
  /// named restart writer (no supervisor node — invariant 1 preserved).
  Future<void> _writeFailure() async {
    final next = seed.mount.node.restartCount + 1;
    final exhausted = next >= seed.mount.maxRestarts;
    final cooldown = exhausted ? null : _now().add(seed.mount.backoff.delayFor(next));
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
    _cancelled = true;
    _capCtx?.cancel.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    final cap = seed.capability;
    // Kill the managed group (if we reached the spawn) + belt-and-braces
    // teardown. Use the captured _ctx (never `context`, which throws here).
    if (cap is ProcessCapability && _started && _stepName.isNotEmpty) {
      unawaited(_ctx?.provider.stop(_stepName));
    }
    final capCtx = _capCtx;
    if (capCtx != null) {
      switch (cap) {
        case ProcessCapability():
          unawaited(cap.teardown(capCtx));
        case ServiceCapability():
          unawaited(cap.teardown(capCtx));
      }
    }
  }

  @override
  Seed build(TreeContext context) => const Idle();
}
