/// The engine's standard [CapabilityRegistry] (ADR-0008 D4 / M4-P1 Track E).
///
/// Resolves a capabilityId → a concrete [Capability], a formulaId → a [Formula],
/// and `host` → a `CapabilityHost` wrapping the resolved capability. The
/// capability set + the formula set are injected (the agent/verify/land
/// capabilities + the `code` formula are contributed by the extension in
/// Track H; the Burn set by `butane_grid_assets`). The clock is injectable so
/// the frontier predicate stays deterministic in tests.
library;

import 'package:genesis_tree/genesis_tree.dart';

import '../kernel/idle.dart';
import '../sdk/capability.dart';
import '../sdk/formula.dart';
import 'capability_host.dart';
import 'capability_registry.dart';

/// The standard registry — a fixed-at-mount handle provided via a plain
/// `InheritedSeed<CapabilityRegistry>` at the root.
class DefaultCapabilityRegistry implements CapabilityRegistry {
  /// Creates the registry over the [capabilities] (capabilityId → impl) and
  /// [formulas] (formulaId → graph), with an optional injected [clock].
  DefaultCapabilityRegistry({
    Map<String, Capability> capabilities = const {},
    Map<String, Formula> formulas = const {},
    DateTime Function()? clock,
  }) : _capabilities = capabilities,
       _formulas = formulas,
       _clock = clock;

  final Map<String, Capability> _capabilities;
  final Map<String, Formula> _formulas;
  final DateTime Function()? _clock;

  @override
  Formula? formula(String formulaId) => _formulas[formulaId];

  @override
  DateTime now() => (_clock ?? DateTime.now)();

  @override
  Seed host(StepMount mount) {
    final capability = _capabilities[mount.step.capabilityId];
    assert(
      capability != null,
      'No capability registered for "${mount.step.capabilityId}" '
      '(step ${mount.step.stepId} at ${mount.nodePath})',
    );
    // Fail-soft in release: an unregistered capability mounts an inert Idle leaf
    // (the step never advances → the formula visibly stalls) rather than
    // crashing the flush.
    if (capability == null) return const Idle();
    return CapabilityHost(capability: capability, mount: mount, key: mount.key);
  }
}
