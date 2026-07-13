import 'package:state_notifier/state_notifier.dart';

import 'grid_delegate.dart';

/// WHICH dev-mode re-composition ran.
enum ReassembleMode {
  /// Re-ran the master build on the SAME delegate — new CODE bodies take effect
  /// in place (hot RELOAD).
  reload,

  /// Re-ran the delegate FACTORY and re-composed on a FRESH delegate (hot
  /// RESTART — the Flutter hot-restart shape, minus the teardown).
  restart;

  /// The wire token. `grid_exploration`'s `ReassembleTool.modes` owns the wire;
  /// `grid_cli`'s `reassemble_mode_pin_test.dart` pins the two equal.
  String get wire => name;
}

/// A dev-mode reassemble REQUEST — what the running grid must re-do. Sealed,
/// consumed with an exhaustive `switch` (house style).
sealed class ReassembleRequest {
  /// Creates a request at [generation].
  const ReassembleRequest(this.generation);

  /// The monotonic re-composition counter; 0 is the launch baseline (never a
  /// request).
  final int generation;
}

/// Re-run the master build on the SAME delegate.
class ReloadRequest extends ReassembleRequest {
  /// Creates the reload request at [generation].
  const ReloadRequest(super.generation);
}

/// Re-run the delegate FACTORY: [delegate] replaces the running one, and its
/// build re-composes the tree.
class RestartRequest extends ReassembleRequest {
  /// Creates the restart request at [generation] carrying the fresh [delegate].
  const RestartRequest(super.generation, this.delegate);

  /// The FRESH delegate the factory produced.
  final GridDelegate delegate;
}

/// The OFF-TREE reassemble bus: `runGrid` holds it and hands it to the
/// configuration scope BY CONSTRUCTION — exactly as it holds the delegate. It
/// never rides the tree, so no consumer can snapshot its `.state` (ADR-0008
/// D-H); only the request it emits reaches the scope, through the listener.
class ReassembleBus extends StateNotifier<ReassembleRequest> {
  /// Creates the bus at the launch baseline (generation 0).
  ReassembleBus() : super(const ReloadRequest(0));

  /// Emits [request]. A fresh instance ALWAYS notifies (`StateNotifier`'s
  /// `updateShouldNotify` is `!identical`), so back-to-back reloads both land.
  void request(ReassembleRequest request) => state = request;
}

/// What a dev-mode re-composition DID — returned by `GridHandle.hotReload` /
/// `GridHandle.hotRestart`, and (as [toJson]) the `value` body of the reload
/// tool's reply.
class ReassembleReport {
  /// Creates the report.
  const ReassembleReport({
    required this.mode,
    required this.generation,
    required this.rebuiltBranches,
  });

  /// Which verb ran.
  final ReassembleMode mode;

  /// The generation this re-composition produced (1 for the first reload).
  final int generation;

  /// How many branches the resulting flush actually rebuilt — the drained dirty
  /// set (`TreeOwner.flush()`'s return).
  final int rebuiltBranches;

  /// The wire body the reload tool returns under `value`.
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wire,
    'generation': generation,
    'rebuiltBranches': rebuiltBranches,
  };
}
