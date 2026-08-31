/// The ambient carrier for the Stage-1 derivation layer (stage1-wiring §1.1).
///
/// The harness owns the ONE [StationTrajectoryRecorder]; this is the single
/// new ambient value that hands it to the IN-TREE observation sites —
/// `SessionScope`, `CapabilityHost`, `WorkList`. The off-tree collaborators
/// (the lease vendor, the source-control service, the command handler, the
/// restart reconciler) take the recorder on their constructors instead,
/// because they are built beside the harness rather than mounted under it.
///
/// **Injected as an OPTIONAL collaborator, everywhere.** Disabled, degraded,
/// unprovisioned, or simply absent (a test tree that mounts no `StationWork`),
/// the recorder is a counting no-op — [disabled] is the null object every
/// resolution falls back to, so **no call site ever branches on "is the
/// trajectory up"** (§1.1) and no derivation site needs a null check.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:meta/meta.dart';

import '../seeds/provider.dart';

/// The ambient value a `Provider<TrajectoryRecorderScope>` vends.
///
/// A wrapper rather than a bare `Provider<StationTrajectoryRecorder>` for one
/// reason worth the type: the provider lookup is keyed by EXACT type, and the
/// recorder is a class a composer could plausibly subclass or a test could
/// fake. Naming the SCOPE keeps the ambient key stable no matter what concrete
/// recorder rides inside it.
@immutable
final class TrajectoryRecorderScope {
  /// Wraps the harness's one recorder for ambient provision.
  const TrajectoryRecorderScope(this.recorder);

  /// The station's single derivation layer (§2) — never a second one.
  final StationTrajectoryRecorder recorder;

  /// The null object: a scope whose recorder's sink never accepts. A single
  /// shared instance, so the fallback below is allocation-free and — more to
  /// the point — IDENTITY-STABLE, which is what keeps a `Provider.value`
  /// carrying it from looking like a changed value on every rebuild.
  static final TrajectoryRecorderScope disabled = TrajectoryRecorderScope(
    StationTrajectoryRecorder.disabled(),
  );
}

/// Resolves the ambient recorder for a derivation site, falling back to the
/// counting no-op.
///
/// Uses the `read<T>()` EFFECT verb, not the tree verb, for the same reason
/// `requireProcessLeaseVendor` does: the recorder is a station-lifetime
/// collaborator whose identity never changes, so registering a dependency edge
/// on it would couple every observing branch to the harness's object identity
/// while buying nothing. It also means a tree with no `ProviderScope` at all
/// (an offline fixture) resolves the null object instead of tripping
/// `watch`'s missing-registry assert — observation must never be the thing
/// that breaks a mount.
StationTrajectoryRecorder trajectoryRecorderOf(TreeContext context) =>
    context.read<TrajectoryRecorderScope>()?.recorder ??
    TrajectoryRecorderScope.disabled.recorder;
