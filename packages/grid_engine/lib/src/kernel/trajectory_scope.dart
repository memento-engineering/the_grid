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

/// The stable gate reason for every cut-only trajectory admission halt.
const String kTrajectoryAdmissionHaltGateReason = 'trajectory-admission-halted';

/// The single boot-lifetime admission breaker shared by the harness, mount
/// authority, offline mount path, and decision-bearing call sites.
final class TrajectoryAdmissionHalt {
  /// Creates the breaker over the station's existing two gate seams.
  TrajectoryAdmissionHalt({
    required StationBeadWriter writer,
    required String stateSubstation,
    required int Function() bootEpoch,
  }) : _writer = writer,
       _stateSubstation = stateSubstation,
       _bootEpoch = bootEpoch;

  final StationBeadWriter _writer;
  final String _stateSubstation;
  final int Function() _bootEpoch;
  final Map<Object, void Function()> _listeners = <Object, void Function()>{};

  bool _halted = false;
  String? _reason;
  String? _recordClass;

  /// Whether fresh mount admission is halted for this boot.
  bool get halted => _halted;

  /// The first loss cause. Later losses never replace it.
  String? get reason => _reason;

  /// The first lost record class. Later losses never replace it.
  String? get recordClass => _recordClass;

  /// Latches the breaker synchronously and invalidates admission listeners.
  /// Returns true only for the first loss in this boot.
  bool latch({required String reason, required String recordClass}) {
    if (_halted) return false;
    _halted = true;
    _reason = reason;
    _recordClass = recordClass;
    for (final listener in _listeners.values.toList(growable: false)) {
      try {
        listener();
      } on Object {
        // A consumer cannot undo the already-latched admission refusal.
      }
    }
    return true;
  }

  /// Adds an admission invalidation listener and returns its remover.
  void Function() addListener(void Function() listener) {
    final token = Object();
    _listeners[token] = listener;
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      _listeners.remove(token);
    };
  }

  /// Routes a decision-bearing step result only to the session-and-node gate.
  Future<void> handleStepResult(
    TrajectoryAppendResult result, {
    required String sessionId,
    required String nodePath,
    required String recordClass,
  }) async {
    switch (result) {
      case Acked():
        return;
      case Dropped():
        await haltStep(
          reason: 'trajectory append dropped',
          recordClass: recordClass,
          sessionId: sessionId,
          nodePath: nodePath,
        );
      case Suppressed():
        await haltStep(
          reason: 'trajectory append suppressed',
          recordClass: recordClass,
          sessionId: sessionId,
          nodePath: nodePath,
        );
    }
  }

  /// Latches and routes a step-class failure to its actual open route.
  Future<void> haltStep({
    required String reason,
    required String recordClass,
    required String sessionId,
    required String nodePath,
  }) async {
    latch(reason: reason, recordClass: recordClass);
    try {
      await _writer.createGate(
        substation: _stateSubstation,
        sessionId: sessionId,
        nodePath: nodePath,
        reason: kTrajectoryAdmissionHaltGateReason,
      );
    } on Object {
      // Gate persistence is best effort; admission remains fail-closed.
    }
  }

  /// Routes a terminal result only to the station gate, never a closed
  /// session.
  Future<void> handleTerminalResult(
    TrajectoryAppendResult result, {
    required String recordClass,
  }) async {
    switch (result) {
      case Acked():
        return;
      case Dropped():
        await haltStation(
          reason: 'trajectory append dropped',
          recordClass: recordClass,
        );
      case Suppressed():
        await haltStation(
          reason: 'trajectory append suppressed',
          recordClass: recordClass,
        );
    }
  }

  /// Latches a node-less or terminal failure and opens the boot-epoch gate.
  Future<void> haltStation({
    required String reason,
    required String recordClass,
  }) async {
    latch(reason: reason, recordClass: recordClass);
    try {
      await _writer.createStationGate(
        substation: _stateSubstation,
        epoch: _bootEpoch(),
        reason: kTrajectoryAdmissionHaltGateReason,
      );
    } on Object {
      // Gate persistence is best effort; admission remains fail-closed.
    }
  }
}

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
  const TrajectoryRecorderScope(this.recorder, {this.admissionHalt});

  /// The station's single derivation layer (§2) — never a second one.
  final StationTrajectoryRecorder recorder;

  /// The cut-only station admission breaker; absent under shadow.
  final TrajectoryAdmissionHalt? admissionHalt;

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
