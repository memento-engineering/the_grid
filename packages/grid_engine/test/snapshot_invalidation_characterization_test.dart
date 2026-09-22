import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const _workA = 'station-a';
const _workB = 'station-b';

/// One immutable tree-facing projection of the joined store state plus the two
/// station-wide correctness rails that a local session cannot represent.
final class _ProjectionFrame {
  const _ProjectionFrame({
    required this.snapshot,
    required this.stationCapacityRevision,
    required this.crossStoreBlockerRevision,
  });

  final JoinedSnapshot snapshot;
  final int stationCapacityRevision;
  final int crossStoreBlockerRevision;
}

/// A deterministic out-of-band observer seam with no synchronous state read.
final class _InvalidationProbeNotifier {
  _InvalidationProbeNotifier(this._value);

  _ProjectionFrame _value;
  final Set<void Function(_ProjectionFrame)> _listeners = {};
  bool _disposed = false;

  void Function() addListener(
    void Function(_ProjectionFrame) listener, {
    bool fireImmediately = false,
  }) {
    if (_disposed) throw StateError('probe notifier is disposed');
    _listeners.add(listener);
    if (fireImmediately) listener(_value);
    return () => _listeners.remove(listener);
  }

  void push(_ProjectionFrame value) {
    if (_disposed) throw StateError('probe notifier is disposed');
    if (identical(_value, value)) return;
    _value = value;
    for (final listener in List.of(_listeners)) {
      listener(value);
    }
  }

  void dispose() {
    if (_listeners.isNotEmpty) {
      throw StateError('probe notifier disposed with live listeners');
    }
    _disposed = true;
  }
}

enum _SnapshotAspect { sessionA, sessionB, stationCapacity, crossStoreBlocker }

/// Mutable instrumentation owned by one freshly mounted event harness.
final class _BuildCounts {
  int projections = 0;
  int consumerA = 0;
  int consumerB = 0;

  int get total => projections + consumerA + consumerB;

  ({int projections, int consumerA, int consumerB, int total}) get values => (
    projections: projections,
    consumerA: consumerA,
    consumerB: consumerB,
    total: total,
  );

  void reset() {
    projections = 0;
    consumerA = 0;
    consumerB = 0;
  }
}

/// One WorkList-shaped lifecycle subscriber that republishes the whole frame.
final class _WholeSnapshotProjection extends StatefulSeed {
  const _WholeSnapshotProjection({
    required this.counts,
    required this.child,
    super.key,
  });

  final _BuildCounts counts;
  final Seed child;

  @override
  State<_WholeSnapshotProjection> createState() =>
      _WholeSnapshotProjectionState();
}

final class _WholeSnapshotProjectionState
    extends State<_WholeSnapshotProjection> {
  late _ProjectionFrame _frame;
  _InvalidationProbeNotifier? _notifier;
  void Function()? _removeListener;

  @override
  void didChangeDependencies() {
    final notifier = context.watch<_InvalidationProbeNotifier>();
    if (notifier == null) {
      throw StateError(
        '_WholeSnapshotProjection requires an invalidation notifier',
      );
    }
    if (identical(notifier, _notifier)) return;
    _removeListener?.call();
    _notifier = notifier;
    var first = true;
    _removeListener = notifier.addListener((frame) {
      if (first) {
        first = false;
        _frame = frame;
        return;
      }
      if (!context.mounted) return;
      setState(() => _frame = frame);
    }, fireImmediately: true);
  }

  @override
  Seed build(TreeContext context) {
    seed.counts.projections += 1;
    return InheritedSeed<_ProjectionFrame>(value: _frame, child: seed.child);
  }

  @override
  void dispose() {
    _removeListener?.call();
    _removeListener = null;
  }
}

/// One WorkList-shaped subscriber that republishes an aspect-aware frame.
final class _AspectSnapshotProjection extends StatefulSeed {
  const _AspectSnapshotProjection({required this.counts, required this.child});

  final _BuildCounts counts;
  final Seed child;

  @override
  State<_AspectSnapshotProjection> createState() =>
      _AspectSnapshotProjectionState();
}

final class _AspectSnapshotProjectionState
    extends State<_AspectSnapshotProjection> {
  late _ProjectionFrame _frame;
  _InvalidationProbeNotifier? _notifier;
  void Function()? _removeListener;

  @override
  void didChangeDependencies() {
    final notifier = context.watch<_InvalidationProbeNotifier>();
    if (notifier == null) {
      throw StateError(
        '_AspectSnapshotProjection requires an invalidation notifier',
      );
    }
    if (identical(notifier, _notifier)) return;
    _removeListener?.call();
    _notifier = notifier;
    var first = true;
    _removeListener = notifier.addListener((frame) {
      if (first) {
        first = false;
        _frame = frame;
        return;
      }
      if (!context.mounted) return;
      setState(() => _frame = frame);
    }, fireImmediately: true);
  }

  @override
  Seed build(TreeContext context) {
    seed.counts.projections += 1;
    return _AspectSnapshotModel(value: _frame, child: seed.child);
  }

  @override
  void dispose() {
    _removeListener?.call();
    _removeListener = null;
  }
}

final class _AspectSnapshotModel
    extends InheritedModelSeed<_ProjectionFrame, _SnapshotAspect> {
  const _AspectSnapshotModel({required super.value, required super.child});

  @override
  bool updateShouldNotifyDependent(
    covariant _AspectSnapshotModel oldSeed,
    Set<_SnapshotAspect> dependencies,
  ) => dependencies.any(
    (aspect) => switch (aspect) {
      _SnapshotAspect.sessionA =>
        value.snapshot.sessionsByWorkBead[_workA] !=
            oldSeed.value.snapshot.sessionsByWorkBead[_workA],
      _SnapshotAspect.sessionB =>
        value.snapshot.sessionsByWorkBead[_workB] !=
            oldSeed.value.snapshot.sessionsByWorkBead[_workB],
      _SnapshotAspect.stationCapacity =>
        value.stationCapacityRevision != oldSeed.value.stationCapacityRevision,
      _SnapshotAspect.crossStoreBlocker =>
        value.crossStoreBlockerRevision !=
            oldSeed.value.crossStoreBlockerRevision,
    },
  );
}

final class _CountingSnapshotConsumer extends StatelessSeed {
  const _CountingSnapshotConsumer({
    required this.counts,
    required this.consumerA,
    required this.aspectScoped,
    super.key,
  });

  final _BuildCounts counts;
  final bool consumerA;
  final bool aspectScoped;

  @override
  Seed build(TreeContext context) {
    final frame = aspectScoped
        ? context.dependOnInheritedSeedOfExactType<_ProjectionFrame>(
            aspect: consumerA
                ? _SnapshotAspect.sessionA
                : _SnapshotAspect.sessionB,
          )
        : context.dependOnInheritedSeedOfExactType<_ProjectionFrame>();
    if (frame == null) {
      throw StateError('_CountingSnapshotConsumer requires a projection');
    }
    if (aspectScoped) {
      context.dependOnInheritedSeedOfExactType<_ProjectionFrame>(
        aspect: _SnapshotAspect.stationCapacity,
      );
      context.dependOnInheritedSeedOfExactType<_ProjectionFrame>(
        aspect: _SnapshotAspect.crossStoreBlocker,
      );
    }
    if (consumerA) {
      counts.consumerA += 1;
    } else {
      counts.consumerB += 1;
    }
    return const _ProbeLeaf();
  }
}

final class _ProbeLeaf extends Seed {
  const _ProbeLeaf();

  @override
  Branch createBranch() => _ProbeBranch(this);
}

final class _ProbeBranch extends Branch {
  _ProbeBranch(super.seed);
}

final class _ProjectionChildren extends MultiChildSeed {
  const _ProjectionChildren(List<Seed> children) : super(children: children);
}

enum _ProbeEvent {
  localSessionA,
  equalInput,
  stationCapacity,
  crossStoreBlocker,
  sessionADisappears,
}

GraphSnapshot _graph() => GraphSnapshot.fromParts(
  beads: const [
    Bead(id: _workA, issueType: IssueType.task, status: BeadStatus.open),
    Bead(id: _workB, issueType: IssueType.task, status: BeadStatus.open),
  ],
  dependencies: const [],
  readyIds: const {_workA, _workB},
  capturedAt: DateTime.utc(2026, 9, 21),
);

const _sessionA0 = SessionProjection(
  workBeadId: _workA,
  sessionId: 'session-a',
  cursor: {'station-a/agent': NodeCursor()},
);
const _sessionA1 = SessionProjection(
  workBeadId: _workA,
  sessionId: 'session-a',
  cursor: {'station-a/agent': NodeCursor(state: StepState.running)},
);
const _sessionB = SessionProjection(
  workBeadId: _workB,
  sessionId: 'session-b',
  cursor: {'station-b/agent': NodeCursor()},
);

_ProjectionFrame _initialFrame() => _ProjectionFrame(
  snapshot: JoinedSnapshot(
    graph: _graph(),
    sessionsByWorkBead: const {_workA: _sessionA0, _workB: _sessionB},
  ),
  stationCapacityRevision: 0,
  crossStoreBlockerRevision: 0,
);

_ProjectionFrame _nextFrame(_ProbeEvent event, _ProjectionFrame initial) =>
    switch (event) {
      _ProbeEvent.localSessionA => _ProjectionFrame(
        snapshot: JoinedSnapshot(
          graph: initial.snapshot.graph,
          sessionsByWorkBead: const {_workA: _sessionA1, _workB: _sessionB},
        ),
        stationCapacityRevision: 0,
        crossStoreBlockerRevision: 0,
      ),
      _ProbeEvent.equalInput => initial,
      _ProbeEvent.stationCapacity => _ProjectionFrame(
        snapshot: initial.snapshot,
        stationCapacityRevision: 1,
        crossStoreBlockerRevision: 0,
      ),
      _ProbeEvent.crossStoreBlocker => _ProjectionFrame(
        snapshot: initial.snapshot,
        stationCapacityRevision: 0,
        crossStoreBlockerRevision: 1,
      ),
      _ProbeEvent.sessionADisappears => _ProjectionFrame(
        snapshot: JoinedSnapshot(
          graph: initial.snapshot.graph,
          sessionsByWorkBead: const {_workB: _sessionB},
        ),
        stationCapacityRevision: 0,
        crossStoreBlockerRevision: 0,
      ),
    };

_BuildCounts _measure(_ProbeEvent event, {required bool aspectScoped}) {
  final initial = _initialFrame();
  final notifier = _InvalidationProbeNotifier(initial);
  final counts = _BuildCounts();
  final consumerA = _CountingSnapshotConsumer(
    counts: counts,
    consumerA: true,
    aspectScoped: aspectScoped,
    key: const ValueKey('consumer-a'),
  );
  final consumerB = _CountingSnapshotConsumer(
    counts: counts,
    consumerA: false,
    aspectScoped: aspectScoped,
    key: const ValueKey('consumer-b'),
  );
  final projection = aspectScoped
      ? _AspectSnapshotProjection(
          counts: counts,
          child: _ProjectionChildren([consumerA, consumerB]),
        )
      : _ProjectionChildren([
          _WholeSnapshotProjection(
            counts: counts,
            child: consumerA,
            key: const ValueKey('projection-a'),
          ),
          _WholeSnapshotProjection(
            counts: counts,
            child: consumerB,
            key: const ValueKey('projection-b'),
          ),
        ]);
  final owner = TreeOwner();
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<_InvalidationProbeNotifier>(
        value: notifier,
        child: projection,
      ),
    ),
  );
  owner.flush();
  counts.reset();

  try {
    notifier.push(_nextFrame(event, initial));
    owner.flush();
    return counts;
  } finally {
    owner.dispose();
    notifier.dispose();
  }
}

void _expectCounts(
  _BuildCounts actual, {
  required int projections,
  required int consumerA,
  required int consumerB,
}) {
  expect(actual.values, (
    projections: projections,
    consumerA: consumerA,
    consumerB: consumerB,
    total: projections + consumerA + consumerB,
  ));
}

void main() {
  test('whole-value projection reports the baseline matrix', () {
    final local = _measure(_ProbeEvent.localSessionA, aspectScoped: false);
    final equal = _measure(_ProbeEvent.equalInput, aspectScoped: false);
    final capacity = _measure(_ProbeEvent.stationCapacity, aspectScoped: false);
    final blocker = _measure(
      _ProbeEvent.crossStoreBlocker,
      aspectScoped: false,
    );
    final disappearance = _measure(
      _ProbeEvent.sessionADisappears,
      aspectScoped: false,
    );

    _expectCounts(local, projections: 2, consumerA: 1, consumerB: 1);
    _expectCounts(equal, projections: 0, consumerA: 0, consumerB: 0);
    _expectCounts(capacity, projections: 2, consumerA: 1, consumerB: 1);
    _expectCounts(blocker, projections: 2, consumerA: 1, consumerB: 1);
    _expectCounts(disappearance, projections: 2, consumerA: 1, consumerB: 1);
    expect(
      [
        local,
        equal,
        capacity,
        blocker,
        disappearance,
      ].map((counts) => counts.total).reduce((left, right) => left + right),
      16,
    );
  });

  test('aspect projection reports the scoped matrix', () {
    final local = _measure(_ProbeEvent.localSessionA, aspectScoped: true);
    final equal = _measure(_ProbeEvent.equalInput, aspectScoped: true);
    final capacity = _measure(_ProbeEvent.stationCapacity, aspectScoped: true);
    final blocker = _measure(_ProbeEvent.crossStoreBlocker, aspectScoped: true);
    final disappearance = _measure(
      _ProbeEvent.sessionADisappears,
      aspectScoped: true,
    );

    _expectCounts(local, projections: 1, consumerA: 1, consumerB: 0);
    _expectCounts(equal, projections: 0, consumerA: 0, consumerB: 0);
    _expectCounts(capacity, projections: 1, consumerA: 1, consumerB: 1);
    _expectCounts(blocker, projections: 1, consumerA: 1, consumerB: 1);
    _expectCounts(disappearance, projections: 1, consumerA: 1, consumerB: 0);
    expect(
      [
        local,
        equal,
        capacity,
        blocker,
        disappearance,
      ].map((counts) => counts.total).reduce((left, right) => left + right),
      10,
    );
  });
}
