/// The engine's standard [CapabilityRegistry] (ADR-0008 D4 / M4-P1 Track E).
///
/// Resolves a capabilityId → a concrete [Capability], a circuitId → a [Circuit],
/// and `host` → a `CapabilityHost` wrapping the resolved capability. The
/// capability set + the circuit set are injected (the agent/verify/land
/// capabilities + the `code` circuit are contributed by the extension in
/// Track H; the Burn set by `butane_grid_assets`). The clock is injectable so
/// the frontier predicate stays deterministic in tests.
///
/// **Requirement-slot resolution (D-B5 hook #2, the honesty-pass, 2026-07-03):**
/// a step declaring [CapabilityStep.requires] resolves to its LOCAL capability
/// only when [stationFacts] satisfies it by containment
/// ([CapabilityFacts.matches], ADR-0011 D6); a mismatch resolves to
/// [claimCapabilityFor]'s capability instead — an asset-provided claim+lease
/// [Capability] (e.g. a [LeaseCapability]) — NEVER the local spawn.
/// Local-vs-remote is this resolver's decision; the remote impl is the
/// asset's (the engine names no bus). No asset composed (offline/no
/// federation wired) → [claimCapabilityFor] is null → an unfulfillable step
/// mounts the SAME fail-soft `Idle` a missing capabilityId does (a visible
/// stall, never a crash).
library;

import 'package:genesis_tree/genesis_tree.dart';

import '../kernel/idle.dart';
import '../sdk/capability.dart';
import '../sdk/capability_facts.dart';
import '../sdk/circuit.dart';
import 'capability_host.dart';
import 'capability_registry.dart';

/// The standard registry — a fixed-at-mount handle provided via a plain
/// `InheritedSeed<CapabilityRegistry>` at the root.
class DefaultCapabilityRegistry implements CapabilityRegistry {
  /// Creates the registry over the [capabilities] (capabilityId → impl) and
  /// [circuits] (circuitId → graph), with an optional injected [clock].
  ///
  /// [stationFacts] is this station's own capability profile, checked by
  /// containment against a step's declared [CapabilityStep.requires]
  /// (defaults to empty — every non-empty requirement is then unfulfillable
  /// locally, the conservative default for a station composing no profile at
  /// all). [claimCapabilityFor] resolves the asset-provided claim+lease
  /// capability for an unfulfillable [StepMount] (D-B5 hook #2); null (the
  /// default) means no federation asset is composed, so an unfulfillable step
  /// fails soft to `Idle`.
  DefaultCapabilityRegistry({
    Map<String, Capability> capabilities = const {},
    Map<String, Circuit> circuits = const {},
    DateTime Function()? clock,
    CapabilityFacts stationFacts = const CapabilityFacts(),
    Capability? Function(StepMount mount)? claimCapabilityFor,
  }) : _capabilities = capabilities,
       _circuits = circuits,
       _clock = clock,
       _stationFacts = stationFacts,
       _claimCapabilityFor = claimCapabilityFor;

  final Map<String, Capability> _capabilities;
  final Map<String, Circuit> _circuits;
  final DateTime Function()? _clock;
  final CapabilityFacts _stationFacts;
  final Capability? Function(StepMount mount)? _claimCapabilityFor;

  @override
  Circuit? circuit(String circuitId) => _circuits[circuitId];

  @override
  DateTime now() => (_clock ?? DateTime.now)();

  @override
  Seed host(StepMount mount) {
    final capability = _resolveCapability(mount);
    assert(
      capability != null,
      'No capability registered for "${mount.step.capabilityId}" '
      '(step ${mount.step.stepId} at ${mount.nodePath}), and no claim '
      'capability composed for its unfulfilled requirement',
    );
    // Fail-soft in release: an unregistered capability (or an unfulfillable
    // requirement with no claim asset composed) mounts an inert Idle leaf (the
    // step never advances → the circuit visibly stalls) rather than crashing
    // the flush.
    if (capability == null) return const Idle();
    return CapabilityHost(capability: capability, mount: mount, key: mount.key);
  }

  /// Resolves [mount]'s capability: the LOCAL capabilityId lookup, unless a
  /// declared, non-empty [CapabilityStep.requires] fails containment against
  /// [_stationFacts] — then [_claimCapabilityFor] (an asset's claim+lease
  /// capability) instead of the local spawn (D-B5 hook #2).
  Capability? _resolveCapability(StepMount mount) {
    final requires = mount.step.requires;
    if (requires != null &&
        !requires.isEmpty &&
        !CapabilityFacts.matches(_stationFacts, requires)) {
      return _claimCapabilityFor?.call(mount);
    }
    return _capabilities[mount.step.capabilityId];
  }
}
