// runGrid — the tg-um8k flush guard (ported from the retired coordinator,
// which held this behaviour while never running in production).
//
// `TreeOwner.flush()` has no internal catch, so one throwing `branch.rebuild()`
// propagates out of the pass. Unguarded that killed the rest of the tick: the
// `onFlushed` rail (which carries `StationDriver.afterFlush`, whose
// `WedgeMonitor.poll` is the station's only stall alarm once a healthy sample
// cancelled its timer) never ran, and the dirty set stranded NON-EMPTY so every
// later `markNeedsRebuild` scheduled nothing. Zero I/O — a fake retry clock.
import 'dart:async';

import 'package:grid_engine/grid_engine.dart' show GridDiagnosticable;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

Future<void> pump([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A recorded re-arm: the callback the grid scheduled, plus whether the grid
/// cancelled it (teardown must).
class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;

  /// Whether the grid cancelled this re-arm.
  bool cancelled = false;

  /// Runs the scheduled callback, as a real timer would at its deadline.
  void fire() => _callback();

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

/// A leaf — an empty fan-out.
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// One extra tree level, so the survivor sits strictly DEEPER than the throwing
/// branch and the owner's `(depth, branchId)` drain order is deterministic
/// (branchId is a decimal STRING, compared lexicographically — sibling order
/// would not be).
class _Deeper extends MultiChildSeed {
  _Deeper(Seed child) : super(children: [child]);
}

/// Builds cleanly until [_BoomState.explode], then throws on every rebuild
/// until [_BoomState.defuse]. Mounted SHALLOWER than the survivor, so the owner
/// drains it first.
class _Boom extends StatefulSeed {
  const _Boom({required this.onState});

  /// Publishes the mounted state so the test can drive it.
  final void Function(_BoomState) onState;

  @override
  State<_Boom> createState() => _BoomState();
}

class _BoomState extends State<_Boom> {
  bool _throwing = false;

  /// How many times this branch has built.
  int builds = 0;

  @override
  void didChangeDependencies() => seed.onState(this);

  /// Marks this branch dirty AND arms the throw.
  void explode() => setState(() => _throwing = true);

  /// Marks this branch dirty and disarms.
  void defuse() => setState(() => _throwing = false);

  /// Marks this branch dirty, changing nothing.
  void bump() => setState(() {});

  @override
  Seed build(TreeContext context) {
    builds++;
    if (_throwing) throw StateError('boom: a branch rebuild threw mid-flush');
    return const _Leaf();
  }
}

/// The DEEPER unrelated branch — a throw upstream in the same pass strands it.
class _Survivor extends StatefulSeed {
  const _Survivor({required this.onState});

  /// Publishes the mounted state so the test can drive it.
  final void Function(_SurvivorState) onState;

  @override
  State<_Survivor> createState() => _SurvivorState();
}

class _SurvivorState extends State<_Survivor> {
  /// How many times this branch has built.
  int builds = 0;

  @override
  void didChangeDependencies() => seed.onState(this);

  /// Marks this branch dirty.
  void bump() => setState(() {});

  @override
  Seed build(TreeContext context) {
    builds++;
    return const _Leaf();
  }
}

/// The delegate's root: the throwing branch, then the survivor one level lower.
/// `GridDiagnosticable` so a wired `TreeProjector` finds a semantic root
/// (`DiagnosticsTreeWalker.walk` throws when nothing diagnosable is mounted).
class _Pair extends MultiChildSeed with GridDiagnosticable {
  _Pair({required Seed boom, required Seed survivor})
    : super(children: [boom, _Deeper(survivor)]);
}

/// The station under test: its master build mounts the pair.
class _GuardDelegate extends GridDelegate {
  _GuardDelegate({required this.onBoom, required this.onSurvivor})
    : super(const GridConfiguration());

  /// Publishes the throwing branch's state.
  final void Function(_BoomState) onBoom;

  /// Publishes the deeper branch's state.
  final void Function(_SurvivorState) onSurvivor;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) => _Pair(
    boom: _Boom(onState: onBoom),
    survivor: _Survivor(onState: onSurvivor),
  );
}

typedef _Harness = ({
  GridHandle handle,
  List<_FakeTimer> timers,
  List<GridHookError> errors,
  List<String> flushes,
  _BoomState Function() boom,
  _SurvivorState Function() survivor,
});

Future<_Harness> _arm({TreeProjector? projector}) async {
  final timers = <_FakeTimer>[];
  final errors = <GridHookError>[];
  final flushes = <String>[];
  _BoomState? boom;
  _SurvivorState? survivor;
  final delegate = _GuardDelegate(
    onBoom: (state) => boom = state,
    onSurvivor: (state) => survivor = state,
  );
  final handle = await runGrid(
    delegate,
    onError: errors.add,
    onFlushed: () => flushes.add('flush'),
    treeProjector: projector,
    scheduleTimer: (_, callback) {
      final timer = _FakeTimer(callback);
      timers.add(timer);
      return timer;
    },
  );
  return (
    handle: handle,
    timers: timers,
    errors: errors,
    flushes: flushes,
    boom: () => boom!,
    survivor: () => survivor!,
  );
}

void main() {
  test('THE REGRESSION: a throwing rebuild no longer decapitates the tick — '
      'the onFlushed rail still runs, so the wedge alarm keeps its '
      'heartbeat', () async {
    final h = await _arm();
    addTearDown(h.handle.teardown);
    final before = h.flushes.length;
    expect(before, 1, reason: 'the mount flush already ran the rail');

    h.boom().explode();
    await pump();

    expect(h.errors, hasLength(1));
    expect(h.errors.single.hook, 'flush');
    expect(h.errors.single.cause, isStateError);
    // Before the guard this stayed at `before` — the runner never heard about
    // the flush and the wedge monitor froze at its last good sample.
    expect(
      h.flushes.length,
      greaterThan(before),
      reason: 'onFlushed must run even when the flush pass threw',
    );
  });

  test(
    'a failed pass RE-ARMS, draining the dirty work the throw STRANDED '
    '(TreeOwner fires onNeedsFlush only on the empty→non-empty edge)',
    () async {
      final h = await _arm();
      addTearDown(h.handle.teardown);
      final survivorBuilds = h.survivor().builds;

      h.boom().explode();
      h.survivor().bump();
      await pump();

      expect(h.errors, hasLength(1));
      expect(
        h.survivor().builds,
        survivorBuilds,
        reason:
            'the throw stranded the deeper branch: the owner drains in '
            '(depth, branchId) order and never reached it',
      );
      expect(
        h.timers,
        hasLength(1),
        reason: 'a failed pass must arm one retry',
      );

      // The branch recovers; firing the re-arm drains the stranded branch.
      h.boom().defuse();
      h.timers.single.fire();
      await pump();

      expect(h.errors, hasLength(1), reason: 'the retry pass succeeded');
      expect(h.survivor().builds, greaterThan(survivorBuilds));
    },
  );

  test('the re-arm is BOUNDED — a branch that throws every pass degrades into '
      'a visible wedge, never a hot retry loop', () async {
    final h = await _arm();
    addTearDown(h.handle.teardown);

    h.boom().explode();
    await pump();

    // Drive every retry the grid offers, re-arming the throw each time so the
    // tree never recovers. (A branch is drained from the dirty set BEFORE its
    // rebuild runs, and `Branch.rebuild` clears the dirty flag before calling
    // `performRebuild`, so a thrown branch does not re-dirty itself — the test
    // stands in for a tree that keeps producing failures.)
    var fired = 0;
    while (h.timers.isNotEmpty && fired < 50) {
      final retry = h.timers.removeLast();
      h.boom().explode();
      retry.fire();
      await pump();
      fired++;
    }

    expect(fired, 5, reason: 'exactly _kMaxFlushRetries re-arms, then stop');
    expect(h.timers, isEmpty);
    // Every attempt was reported — loud and stuck, not silent and stuck.
    expect(h.errors, hasLength(6));
    expect(h.errors.every((error) => error.hook == 'flush'), isTrue);
  });

  test(
    'a clean station is UNCHANGED: no flush error, no retry armed, and two '
    'dirties in one tick COALESCE into one flush and one projection',
    () async {
      final projector = TreeProjector();
      final snapshots = <Object>[];
      projector.snapshots.listen(snapshots.add);
      final h = await _arm(projector: projector);
      addTearDown(() async {
        await h.handle.teardown();
        projector.dispose();
      });

      expect(h.flushes, hasLength(1));
      expect(snapshots, hasLength(1));

      h.boom().bump();
      h.survivor().bump();
      await pump();

      expect(h.errors, isEmpty);
      expect(h.timers, isEmpty);
      expect(h.flushes, hasLength(2), reason: 'two dirties, ONE flush');
      expect(
        snapshots,
        hasLength(2),
        reason: 'the root is walked ONCE per flush',
      );
    },
  );

  test('waiters are completed only for the generation the pass APPLIED: the '
      'failed pass refuses exactly what it carried, the re-armed pass '
      'completes the next generation', () async {
    final h = await _arm();
    addTearDown(h.handle.teardown);

    h.boom().explode();
    final refused = await h.handle.hotReload();

    expect(refused.refused, isTrue);
    expect(refused.generation, 1);
    expect(refused.mode, ReassembleMode.reload);
    expect(
      h.errors,
      isEmpty,
      reason: 'the refusal rode the waiter, not the error rail',
    );

    h.boom().defuse();
    h.timers.single.fire();
    await pump();

    final applied = await h.handle.hotReload();
    expect(applied.refused, isFalse);
    expect(applied.generation, 2);
    expect(applied.rebuiltBranches, greaterThan(0));
  });

  test('teardown CANCELS a pending flush retry', () async {
    final h = await _arm();

    h.boom().explode();
    await pump();
    expect(h.timers, hasLength(1));
    expect(h.timers.single.cancelled, isFalse);

    await h.handle.teardown();

    expect(h.timers.single.cancelled, isTrue);
  });
}
