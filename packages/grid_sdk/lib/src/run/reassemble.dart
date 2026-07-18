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

  /// Emits [next]. A fresh instance ALWAYS notifies (`StateNotifier`'s
  /// `updateShouldNotify` is `!identical`), so back-to-back reloads both land.
  ///
  /// A statement body, not an expression one: the D-H fence bans `=> state` in
  /// this package's source outright (it cannot tell a write from a re-surfacing
  /// read), and a structural guard is worth more than a saved line.
  void request(ReassembleRequest next) {
    state = next;
  }
}

/// What a dev-mode re-composition DID — returned by `GridHandle.hotReload` /
/// `GridHandle.hotRestart`, and (as [toJson]) the `value` body of the reload
/// tool's reply when successful. A post-source-swap tree failure is represented
/// as a refused variant so the VM-service caller receives a structured refusal
/// instead of an unhandled microtask error.
sealed class ReassembleReport {
  /// Creates a successful report.
  const factory ReassembleReport({
    required ReassembleMode mode,
    required int generation,
    required int rebuiltBranches,
  }) = ReassembleReportSuccess;

  /// Creates the transactional-refuse report for a re-compose failure after the
  /// VM has already accepted swapped sources.
  const factory ReassembleReport.refusedAfterSourceSwap({
    required ReassembleMode mode,
    required int generation,
    required String details,
  }) = ReassembleReportRefused;

  const ReassembleReport._();

  /// Which verb ran.
  ReassembleMode get mode;

  /// The generation this re-composition produced (1 for the first reload).
  int get generation;

  /// How many branches the resulting flush rebuilt — the drained dirty set.
  int get rebuiltBranches;

  /// True when the station caught a post-source-swap re-compose failure.
  bool get refused;

  /// The operator-facing refusal text, present only when [refused] is true.
  String? get error;

  /// The machine-readable refusal reason, present only when [refused] is true.
  String? get reason;

  /// True when the swapped sources may have left the live tree unrecoverable.
  bool get requiresBounce;

  /// The captured cause text, present only when [refused] is true.
  String? get details;

  /// The wire body the reload tool returns under `value` on success, or promotes
  /// into an `ok:false` tool envelope on refusal.
  Map<String, Object?> toJson();
}

/// A successful dev-mode re-composition report.
class ReassembleReportSuccess extends ReassembleReport {
  /// Creates a successful report.
  const ReassembleReportSuccess({
    required this.mode,
    required this.generation,
    required this.rebuiltBranches,
  }) : super._();

  @override
  final ReassembleMode mode;

  @override
  final int generation;

  @override
  final int rebuiltBranches;

  @override
  bool get refused => false;

  @override
  String? get error => null;

  @override
  String? get reason => null;

  @override
  bool get requiresBounce => false;

  @override
  String? get details => null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wire,
    'generation': generation,
    'rebuiltBranches': rebuiltBranches,
  };
}

/// A refused dev-mode re-composition after sources were already swapped.
class ReassembleReportRefused extends ReassembleReport {
  /// Creates the post-source-swap refusal report.
  const ReassembleReportRefused({
    required this.mode,
    required this.generation,
    required this.details,
  }) : super._();

  @override
  final ReassembleMode mode;

  @override
  final int generation;

  @override
  int get rebuiltBranches => 0;

  @override
  bool get refused => true;

  @override
  String get error =>
      'refused: re-compose failed after source swap - bounce the station';

  @override
  String get reason => 'post_swap_recompose_failed';

  @override
  bool get requiresBounce => true;

  @override
  final String details;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wire,
    'generation': generation,
    'rebuiltBranches': rebuiltBranches,
    'refused': true,
    'error': error,
    'reason': reason,
    'requiresBounce': requiresBounce,
    'details': details,
  };
}
