/// The engine-private capability carrier (ADR-0008 D4 / M4-P1 §5, Track E).
///
/// `CapabilityHost` is `EffectSeed` GENERALIZED off the 3-value `WorkPhase` onto
/// an arbitrary `nodePath`/`stepId` — a tree node whose Branch lifecycle IS the
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
/// The three load-bearing guards live entirely here (ported verbatim from
/// `EffectSeed`): `_cancelled` (set FIRST in `dispose`) + `TreeContext.mounted`
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
  }

  @override
  void initState() {
    _token = newInstanceToken();
    unawaited(_run());
  }

  CapabilityContext _buildCapCtx() {
    final ctx = _ctx!;
    return CapabilityContext(
      params: seed.mount.step.params,
      beadId: _beadId,
      workspaceDir: ctx.worktreeFor(_beadId),
      branch: ctx.branchFor(_beadId),
      baseBranch: ctx.baseBranch,
      services: _services,
      cancel: CancelToken(),
      logFile: null,
    );
  }

  Future<void> _run() async {
    // Yield so didChangeDependencies has captured _ctx/_services.
    await null;
    if (_cancelled || !context.mounted) return;
    _capCtx = _buildCapCtx();
    // The per-step provider name — '$sessionId/$nodePath' (the full path already
    // disambiguates every concurrent step → disjoint event routing, D-2).
    _stepName = '$_sessionId/$_nodePath';

    final cap = seed.capability;
    switch (cap) {
      case ProcessCapability():
        _sub = _ctx!.provider.events
            .where((e) => e.name == _stepName)
            .listen(_onEvent);
        final base = cap.spawn(_capCtx!);
        final config = base.copyWith(
          env: {
            ...base.env,
            'GRID_BEAD_ID': _beadId,
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
    final state = switch (signal) {
      StepSignal.ready => StepState.ready,
      StepSignal.complete => StepState.complete,
      StepSignal.failed => StepState.failed,
      StepSignal.none => null,
    };
    if (state == null) return;
    // A job's complete/failed is a terminal latch; a daemon's `ready` is NOT
    // (it stays mounted and may later write a non-positive cursor on death).
    if (state == StepState.complete || state == StepState.failed) {
      _completed = true;
    }
    await _ctx!.writer.update(
      _sessionId,
      metadata: nodeStateMetadata(_nodePath, state),
    );
  }

  Future<void> _writeOutcome(StepOutcome outcome) async {
    if (_cancelled || !context.mounted || _completed) return;
    _completed = true;
    final state = switch (outcome) {
      Ok() => StepState.complete,
      Failed() => StepState.failed,
    };
    await _ctx!.writer.update(
      _sessionId,
      metadata: nodeStateMetadata(_nodePath, state),
    );
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
