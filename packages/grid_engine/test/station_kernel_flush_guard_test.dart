// StationKernel — the tg-60n flush guard.
//
// `TreeOwner.flush()` has no internal catch (genesis_tree 0.2.0
// `tree_owner.dart:69-93`), so one throwing `branch.rebuild()` propagates out
// of the flush pass. Unguarded, that killed the rest of the tick — including
// `StationDriver.afterFlush()`, which carries the WedgeMonitor's only
// heartbeat once a healthy sample has cancelled its timer. A live arm sat 18.6h
// reporting `wedged: false, live: 0` while `/status` computed 6 live sessions
// off the SAME bridge (receipt on tg-60n, 2026-08-06).
//
// `onUnclaimedFrontier` is the observable: the driver calls it once per
// reconciliation phase — the baseline scan at `start()`, then once per
// `afterFlush`. Its call count IS "did the post-flush work run".
//
// Zero I/O — fakes + injected timers, mirroring
// station_kernel_unclaimed_frontier_test.dart's harness.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

const _tgConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
);

/// The scan needs a root circuit to compute anything — without one
/// `onUnclaimedFrontier` is a documented no-op, so it would not observe the
/// post-flush work at all.
const _circuit = Circuit(
  id: 'work',
  terminalStepId: 'code',
  steps: [CapabilityStep(stepId: 'code', capabilityId: 'code')],
);

Future<void> _pump([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _emptyGraph() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026),
);

class _IdleResolver implements SessionResolver {
  const _IdleResolver();
  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

/// A seed that builds cleanly until [_BoomState.explode] is called, then throws
/// on every rebuild until [_BoomState.defuse]. Mounted via `wrapRoot` so its
/// FIRST build runs synchronously in `mountRoot` (outside any flush) and only
/// the later, deliberately-triggered rebuild throws INSIDE a flush pass.
class _Boom extends StatefulSeed {
  const _Boom({required this.onState, required this.child});
  final void Function(_BoomState) onState;
  final Seed child;
  @override
  State<_Boom> createState() => _BoomState();
}

class _BoomState extends State<_Boom> {
  bool _throwing = false;
  int builds = 0;

  @override
  void didChangeDependencies() => seed.onState(this);

  /// Marks this branch dirty AND arms the throw — the next rebuild explodes.
  void explode() => setState(() => _throwing = true);

  /// Marks this branch dirty and disarms — the next rebuild succeeds.
  void defuse() => setState(() => _throwing = false);

  @override
  Seed build(TreeContext context) {
    builds++;
    if (_throwing) throw StateError('boom: a branch rebuild threw mid-flush');
    return seed.child;
  }
}

/// Builds a kernel whose flush passes can be made to throw on demand.
({
  StationKernel kernel,
  List<List<UnclaimedRequirement>> scans,
  List<Object> errors,
  List<void Function()> timers,
  _BoomState Function() boom,
})
_harness() {
  final work = FakeSnapshotSource(_emptyGraph());
  final state = FakeSnapshotSource(_emptyGraph());
  addTearDown(work.close);
  addTearDown(state.close);
  final bridge = StationJoinBridge(work: work, state: state);
  final f = buildFakes();

  final scans = <List<UnclaimedRequirement>>[];
  final errors = <Object>[];
  final timers = <void Function()>[];
  _BoomState? captured;

  final kernel = StationKernel(
    bridge: bridge,
    stationServices: f.ctx,
    resolver: const _IdleResolver(),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(_tgConfig),
        key: const ValueKey('scope.tg'),
      ),
    ],
    wrapRoot: (root) => _Boom(onState: (s) => captured = s, child: root),
    // The scan needs BOTH a root circuit and a registry, or it is a no-op and
    // observes nothing.
    rootCircuitFor: (_) => _circuit,
    registry: RecordingCapabilityRegistry(clock: DateTime(2026)),
    onUnclaimedFrontier: scans.add,
    onFlushError: (error, _) => errors.add(error),
    // Record the re-arm instead of waiting a real second.
    scheduleTimer: (_, cb) {
      timers.add(cb);
      return Timer(const Duration(days: 1), () {});
    },
  );
  addTearDown(kernel.dispose);
  return (
    kernel: kernel,
    scans: scans,
    errors: errors,
    timers: timers,
    boom: () => captured!,
  );
}

void main() {
  test('THE REGRESSION: a throwing rebuild no longer decapitates the tick — '
      'the driver post-flush scans still run, so the wedge alarm keeps its '
      'heartbeat', () async {
    final h = _harness();
    h.kernel.start();
    // The baseline scan at start().
    expect(h.scans, hasLength(1));
    final before = h.scans.length;

    h.boom().explode();
    await _pump();

    // The pass threw...
    expect(h.errors, hasLength(1));
    expect(h.errors.single, isStateError);
    // ...and the post-flush scan STILL ran. Before the guard this was
    // `before` — the driver never heard about the flush, and the wedge
    // monitor froze at its last good sample.
    expect(
      h.scans.length,
      greaterThan(before),
      reason: 'afterFlush must run even when the flush pass threw',
    );
  });

  test('a failed pass RE-ARMS, so a dirty set stranded by the throw cannot '
      'silently freeze the tree (TreeOwner fires onNeedsFlush only on the '
      'empty→non-empty edge)', () async {
    final h = _harness();
    h.kernel.start();

    h.boom().explode();
    await _pump();
    expect(h.errors, hasLength(1));
    expect(h.timers, isNotEmpty, reason: 'a failed pass must schedule a retry');

    // The branch recovers; firing the re-arm drives a clean pass.
    h.boom().defuse();
    final scansBefore = h.scans.length;
    h.timers.removeAt(0)();
    await _pump();

    expect(h.errors, hasLength(1), reason: 'the retry pass succeeded');
    expect(h.scans.length, greaterThan(scansBefore));
  });

  test(
    'the re-arm is BOUNDED — a branch that throws every pass degrades into a '
    'visible wedge, never a hot retry loop',
    () async {
      final h = _harness();
      h.kernel.start();

      h.boom().explode();
      await _pump();

      // Drive every retry the kernel offers, re-arming the throw each time so
      // the tree never recovers. (A branch is drained from the dirty set
      // BEFORE its rebuild runs, so a thrown branch does not re-dirty itself —
      // the test has to stand in for a tree that keeps producing failures.)
      var fired = 0;
      while (h.timers.isNotEmpty && fired < 50) {
        final retry = h.timers.removeAt(0);
        h.boom().explode();
        retry();
        await _pump();
        fired++;
      }

      expect(
        fired,
        lessThan(20),
        reason: 'the kernel must stop re-arming instead of spinning forever',
      );
      expect(h.timers, isEmpty);
      // Every attempt was reported — loud and stuck, not silent and stuck.
      expect(h.errors.length, greaterThan(1));
      expect(h.errors.every((e) => e is StateError), isTrue);
    },
  );

  test('a clean station is UNCHANGED: no flush error is ever reported and no '
      'retry is ever armed', () async {
    final h = _harness();
    h.kernel.start();

    h.boom().defuse(); // a normal dirty→rebuild cycle, no throw
    await _pump();

    expect(h.errors, isEmpty);
    expect(h.timers, isEmpty);
    expect(h.scans.length, greaterThan(1));
  });
}
