// The PRODUCTION path's flush guard (tg-um8k). UpCommand's default runner is
// `defaultRunMountedGrid` → `runGrid`, wired with `onFlushed: () =>
// live.afterFlush()` — the delegate rail that reaches `StationDriver.afterFlush`
// and its `WedgeMonitor.poll`, the station's ONLY stall alarm once a healthy
// sample has cancelled the monitor's timer. tg-60n's live receipt: 18.6 hours
// reporting `wedged: false, live: 0` beside 6 live sessions on the SAME bridge,
// because a throwing rebuild skipped that rail. Zero I/O — fake sources, a fake
// wedge-poll clock.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart' show Bead, GraphSnapshot;
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart'
    show Flowing, Stalling, StationDriver, StationJoinBridge;
import 'package:grid_engine/testing.dart' show FakeSnapshotSource, sessionBead;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

Future<void> pump([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _graph(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026),
);

/// A recorded wedge-poll re-arm — captured, never fired, so the suite arms no
/// real wall clock.
class _FakeTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}

/// A leaf — an empty fan-out.
final class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// A station whose master build throws once [explode] has been called — the
/// throwing rebuild, driven through a configuration emission.
final class _BoomDelegate extends GridDelegate {
  _BoomDelegate() : super(const GridConfiguration());

  bool _throwing = false;

  /// Emits a fresh configuration WITHOUT arming the throw — a clean flush.
  void bump() =>
      state = const GridConfiguration(settings: <String, Object?>{'v': 1});

  /// Arms the throw and emits, so the resulting flush pass fails.
  void explode() {
    _throwing = true;
    state = const GridConfiguration(settings: <String, Object?>{'v': 2});
  }

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    if (_throwing) throw StateError('boom: the master build threw mid-flush');
    return const _Leaf();
  }
}

({StationDriver driver, FakeSnapshotSource state}) _armDriver() {
  final work = FakeSnapshotSource(_graph(const []));
  final state = FakeSnapshotSource(_graph(const []));
  addTearDown(work.close);
  addTearDown(state.close);
  final driver = StationDriver(
    bridge: StationJoinBridge(work: work, state: state),
    clock: () => DateTime(2026),
    scheduleTimer: (_, _) => _FakeTimer(),
  );
  addTearDown(driver.dispose);
  driver.start();
  return (driver: driver, state: state);
}

Future<GridResource> _run(_BoomDelegate delegate, StationDriver driver) =>
    defaultRunMountedGrid(
      delegate,
      onFlushed: driver.afterFlush,
      orphanSweep: () async {},
      onDelegateSwapped: (_) {},
      treeProjector: null,
    );

void main() {
  test('POSITIVE CONTROL: a CLEAN flush through the production runner samples '
      'the live session the state store carries', () async {
    final rig = _armDriver();
    final delegate = _BoomDelegate();
    final grid = await _run(delegate, rig.driver);
    addTearDown(grid.teardown);

    expect(rig.driver.wedge, isA<Flowing>());
    expect(rig.driver.wedge.toJson()['live'], 0);

    rig.state.push(_graph([sessionBead(id: 'tgdog-s1', workBeadId: 'tg-1')]));
    await pump();
    // The bridge has the session, but no flush has run — the alarm is still
    // frozen at its last sample.
    expect(rig.driver.wedge.toJson()['live'], 0);

    delegate.bump();
    await pump();

    expect(rig.driver.wedge, isA<Stalling>());
    expect(rig.driver.wedge.toJson()['live'], 1);
  });

  test('THE REGRESSION: a throwing rebuild on the production UpCommand → '
      'runGrid path leaves the wedge heartbeat ALIVE', () async {
    final rig = _armDriver();
    final delegate = _BoomDelegate();
    final zoneErrors = <Object>[];
    late GridResource grid;

    await runZonedGuarded(() async {
      grid = await _run(delegate, rig.driver);
      rig.state.push(_graph([sessionBead(id: 'tgdog-s1', workBeadId: 'tg-1')]));
      await pump();
      expect(rig.driver.wedge.toJson()['live'], 0);

      // The rebuild throws on the very tick that would have re-sampled.
      delegate.explode();
      await pump();
    }, (error, stack) => zoneErrors.add(error));

    expect(zoneErrors, hasLength(1), reason: 'the failure is reported LOUD');
    expect(zoneErrors.single, isA<GridHookError>());
    expect((zoneErrors.single as GridHookError).hook, 'flush');
    // Before the guard this stayed `Flowing`/`live: 0` for the life of the
    // process: the alarm could not fire in the one scenario it exists for.
    expect(rig.driver.wedge, isA<Stalling>());
    expect(
      rig.driver.wedge.toJson()['live'],
      1,
      reason: 'afterFlush ran in the finally, so the alarm re-sampled',
    );
    await grid.teardown();
  });
}
