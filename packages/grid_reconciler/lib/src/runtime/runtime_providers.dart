import 'package:grid_controller/grid_controller.dart';
import 'package:riverpod/riverpod.dart';

import 'convergence_source.dart';
import 'ownership.dart';
import 'reconciler_runtime.dart';
import 'shadow_runtime.dart';

/// Riverpod surface for the reconciler runtime (ADR-0002 D2 style; composes
/// with Track A's `convergencesProvider`). The runtime itself is constructed by
/// the application (grid_cli / the integration layer) and injected; these
/// providers expose its read-only projections and the convergence source.

/// The live convergence source over grid_controller's `gridRuntimeProvider` —
/// the read seam the reconciler runtime ingests from. No IO of its own; it
/// reads the controller runtime's event/snapshot streams.
final convergenceSourceProvider = Provider<ConvergenceSource>(
  (ref) => GridConvergenceSource(ref.watch(gridRuntimeProvider)),
);

/// The ownership partition predicate (ADR-0003 Decision 6). Defaults to
/// [OwnsNothing] — the safe coexistence default (the_grid actuates nothing
/// until an owned rig is configured). The application overrides this with an
/// [OwnsRigs]/[OwnsMarked] for M3's drive-one-owned-rig.
final ownershipProvider = Provider<OwnershipPredicate>(
  (ref) => const OwnsNothing(),
);

/// The running reconciler runtime. Has no constructable default (it needs the
/// actuator + gate evaluator, which the integration layer wires); the
/// application builds a configured [ReconcilerRuntime] and overrides this:
///
/// ```dart
/// reconcilerRuntimeProvider.overrideWithValue(runtime)
/// ```
final reconcilerRuntimeProvider = Provider<ReconcilerRuntime>(
  (ref) => throw UnimplementedError(
    'reconcilerRuntimeProvider must be overridden with a configured '
    'ReconcilerRuntime',
  ),
);

/// The cycle-outcome history of the running runtime (diagnostics / DevTools).
final reconcilerCyclesProvider = Provider(
  (ref) => ref.watch(reconcilerRuntimeProvider).outcomes,
);

/// A shadow runtime over the live convergence source — STRICTLY read-only
/// (constructs no writer). Use it to observe gc's convergence traffic and diff
/// it against the_grid's reducer without any risk of a write. The application
/// `start()`s and disposes it.
final shadowRuntimeProvider = Provider<ShadowRuntime>(
  (ref) => ShadowRuntime(source: ref.watch(convergenceSourceProvider)),
);
