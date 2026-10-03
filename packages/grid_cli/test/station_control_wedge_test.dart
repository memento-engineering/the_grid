import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/station_control.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final _storeTime = DateTime.utc(2026, 9, 22, 10);

GraphSnapshot _storeGraph(List<Bead> beads, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: {for (final bead in beads) bead.id},
      capturedAt: _storeTime.add(Duration(seconds: tick)),
    );

Bead _workBead(int index) =>
    Bead(id: 'work-$index', issueType: IssueType.task, status: BeadStatus.open);

Bead _sessionRow(int index, {bool closed = false}) => sessionBead(
  id: 'session-$index',
  workBeadId: 'work-$index',
  closed: closed,
  metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
);

Bead _stepRow(int index, StepState state) => Bead(
  id: 'step-$index',
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.session: 'session-$index',
    MoleculeStepKeys.path: 'work-$index/build',
    MoleculeStepKeys.state: state.name,
  },
);

List<Bead> _openSessionRows(int count, StepState state) => [
  for (var index = 1; index <= count; index++) ...[
    _sessionRow(index),
    _stepRow(index, state),
  ],
];

Future<void> _settleJoin() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FakeTimer implements Timer {
  var _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// tg-jwh — the wedge signal on the RS-4 status surface: the station derives it
/// (a real [WedgeMonitor] over the producer-side join) and the status route
/// reports it as a first-class block. No live stores, no real bd/git/claude.
void main() {
  final t0 = DateTime.utc(2026, 7, 12, 10);
  late DateTime now;
  late Map<String, SessionProjection> sessions;
  late WedgeMonitor monitor;

  Future<Map<String, Object?>> statusOf(StationControl control) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('${control.url}/status'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer t');
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder()).join();
      return jsonDecode(body) as Map<String, Object?>;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> waitForWedge(
    StationControl control,
    bool Function(Map<String, Object?> wedge) matches,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (true) {
      final body = await statusOf(control);
      final wedge = body['wedge']! as Map<String, Object?>;
      if (matches(wedge)) return wedge;
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for wedge status; last value: $wedge');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  StationStatus status({WedgeState? wedge}) => StationStatus(
    substation: 'tg',
    stateStore: null,
    workRoot: null,
    dryRun: true,
    pid: 1,
    startedAt: t0,
    version: 'test-vm',
    ready: 0,
    mounted: sessions.length,
    liveSessions: sessions.length,
    lastSyncAt: null,
    perSubstation: [
      SubstationStatus(
        substation: 'tg',
        root: '/work/tg',
        ready: 0,
        mounted: sessions.length,
        live: sessions.length,
      ),
    ],
    // The station's OWN truth — never re-derived on the watcher side.
    wedge: wedge ?? monitor.state,
  );

  Future<StationControl> serve({
    StationStatus Function()? view,
    Duration statusSnapshotInterval = const Duration(seconds: 1),
  }) async {
    final control = await StationControl.start(
      port: 0,
      token: 't',
      view: view ?? status,
      commandHandler: _UnusedCommandHandler(),
      statusSnapshotInterval: statusSnapshotInterval,
    );
    addTearDown(control.dispose);
    return control;
  }

  // Molecule fixtures (tg-eli phase 2: the sampler reads ONLY molecule step
  // state — a non-molecule session contributes no nodes).
  Bead step(String id, String nodePath, StepState state) => Bead(
    id: id,
    issueType: GridIssueTypes.step,
    status: BeadStatus.open,
    metadata: {
      MoleculeStepKeys.path: nodePath,
      MoleculeStepKeys.state: state.name,
    },
  );

  SessionProjection moleculeSession(String id, StepState state) =>
      SessionProjection(
        workBeadId: id,
        sessionId: 'tgdog-$id',
        isMolecule: true,
        moleculeBeads: [step('tgdog-$id-step', 'n/x', state)],
      );

  setUp(() {
    now = t0;
    sessions = {
      for (final id in ['tg-a', 'tg-b', 'tg-c'])
        id: moleculeSession(id, StepState.gated),
    };
    monitor = WedgeMonitor(
      latest: () => JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: const [],
          dependencies: const [],
          readyIds: const [],
          capturedAt: t0,
        ),
        sessionsByWorkBead: sessions,
      ),
      threshold: const Duration(minutes: 10),
      clock: () => now,
    );
    addTearDown(monitor.dispose);
  });

  test(
    'ALL sessions gated + 0 running, sustained past M → the status route reports '
    'wedged:true with since + reason',
    () async {
      monitor.poll(); // t0 — the stall begins
      now = t0.add(const Duration(minutes: 10));
      monitor.poll();
      final control = await serve();

      final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
      expect(wedge['wedged'], isTrue);
      expect(wedge['since'], t0.toIso8601String());
      expect(wedge['reason'], contains('parked at a gate'));
      expect(wedge['live'], 3);
      expect(wedge['running'], 0);
      expect(wedge['gated'], 3);
    },
  );

  test('under M minutes → wedged:false (no false alarm on a between-stages '
      'transition)', () async {
    monitor.poll();
    now = t0.add(const Duration(minutes: 9, seconds: 59));
    monitor.poll();
    final control = await serve();

    final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
    expect(wedge['wedged'], isFalse);
    expect(wedge['since'], t0.toIso8601String());
  });

  test('any running session → wedged:false, even with a gate open elsewhere (a '
      'routine gate-open is NOT a wedge)', () async {
    monitor.poll();
    now = t0.add(const Duration(minutes: 20));
    sessions['tg-a'] = moleculeSession('tg-a', StepState.running);
    monitor.poll();
    final control = await serve();

    final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
    expect(wedge['wedged'], isFalse);
    expect(wedge['running'], 1);
    expect(wedge['gated'], 2);
  });

  test(
    'the wedge block is a first-class TOP-LEVEL key — the station/process/work '
    'blocks are unchanged',
    () async {
      final control = await serve();
      final body = await statusOf(control);
      expect(
        body.keys,
        containsAll(<String>['station', 'process', 'work', 'wedge']),
      );
      expect(
        (body['work']! as Map<String, Object?>).containsKey('wedged'),
        isFalse,
        reason: 'the wedge is first-class, not smuggled into the work block',
      );
      final perSubstation =
          (body['work']! as Map<String, Object?>)['perSubstation']!
              as List<Object?>;
      expect((perSubstation.single! as Map<String, Object?>)['live'], 3);
    },
  );

  test('a status built without a work runtime defaults to kNotWedged (never a '
      'phantom alarm)', () async {
    sessions = {};
    final control = await serve(
      view: () => StationStatus(
        substation: 'tg',
        stateStore: null,
        workRoot: null,
        dryRun: true,
        pid: 1,
        startedAt: t0,
        version: 'test-vm',
        ready: 0,
        mounted: 0,
        liveSessions: 0,
        lastSyncAt: null,
      ),
    );

    final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
    expect(wedge['wedged'], isFalse);
    expect(wedge['live'], 0);
  });

  test(
    'resident /status refresh serves every ticked store-derived wedge sample',
    () async {
      final work = FakeSnapshotSource(
        _storeGraph([for (var i = 1; i <= 4; i++) _workBead(i)]),
      );
      final state = FakeSnapshotSource(_storeGraph(const []));
      final bridge = StationJoinBridge(work: work, state: state);
      final driver = StationDriver(bridge: bridge)..start();
      addTearDown(driver.dispose);
      addTearDown(work.close);
      addTearDown(state.close);

      StationStatus residentStatus() {
        final joined = bridge.latest;
        final live = joined.sessionsByWorkBead.values
            .where((session) => !session.isTerminal)
            .length;
        return StationStatus(
          substation: 'tg',
          stateStore: null,
          workRoot: null,
          dryRun: true,
          pid: 1,
          startedAt: t0,
          version: 'test-vm',
          ready: 0,
          mounted: live,
          liveSessions: live,
          lastSyncAt: joined.graph.capturedAt,
          wedge: driver.wedge,
        );
      }

      final control = await serve(
        view: residentStatus,
        statusSnapshotInterval: const Duration(milliseconds: 10),
      );
      expect(
        ((await statusOf(control))['wedge']! as Map<String, Object?>)['live'],
        0,
      );

      state.push(_storeGraph(_openSessionRows(4, StepState.running), tick: 1));
      await _settleJoin();
      driver.afterFlush();
      final first = await waitForWedge(control, (wedge) => wedge['live'] == 4);
      expect(first['reason'], isNot('no live session'));

      state.push(_storeGraph(_openSessionRows(2, StepState.running), tick: 2));
      await _settleJoin();
      driver.afterFlush();
      final second = await waitForWedge(control, (wedge) => wedge['live'] == 2);
      expect(second['reason'], isNot('no live session'));

      state.push(
        _storeGraph([
          _sessionRow(1, closed: true),
          _sessionRow(2, closed: true),
        ], tick: 3),
      );
      await _settleJoin();
      driver.afterFlush();
      final terminal = await waitForWedge(
        control,
        (wedge) => wedge['live'] == 0,
      );
      expect(terminal['reason'], 'no live session');
    },
  );

  test('resident /status and station.wedgeChanged use one sample', () async {
    final work = FakeSnapshotSource(
      _storeGraph([for (var i = 1; i <= 3; i++) _workBead(i)]),
    );
    final state = FakeSnapshotSource(_storeGraph(const []));
    final bridge = StationJoinBridge(work: work, state: state);
    final transport = RecordingExplorationTransport();
    final driver = StationDriver(
      bridge: bridge,
      transport: transport,
      wedgeThreshold: Duration.zero,
      scheduleTimer: (_, _) => _FakeTimer(),
    )..start();
    addTearDown(driver.dispose);
    addTearDown(work.close);
    addTearDown(state.close);

    StationStatus residentStatus() {
      final joined = bridge.latest;
      final live = joined.sessionsByWorkBead.values
          .where((session) => !session.isTerminal)
          .length;
      return StationStatus(
        substation: 'tg',
        stateStore: null,
        workRoot: null,
        dryRun: true,
        pid: 1,
        startedAt: t0,
        version: 'test-vm',
        ready: 0,
        mounted: live,
        liveSessions: live,
        lastSyncAt: joined.graph.capturedAt,
        wedge: driver.wedge,
      );
    }

    final control = await serve(
      view: residentStatus,
      statusSnapshotInterval: const Duration(milliseconds: 10),
    );

    state.push(_storeGraph(_openSessionRows(2, StepState.gated), tick: 1));
    await _settleJoin();
    driver.afterFlush();
    await waitForWedge(control, (wedge) => wedge['live'] == 2);

    state.push(_storeGraph(_openSessionRows(3, StepState.gated), tick: 2));
    await _settleJoin();
    driver.afterFlush();
    final statusWedge = await waitForWedge(
      control,
      (wedge) => wedge['live'] == 3,
    );
    final flare = transport.named(kWedgeChangedFlare).single.data;
    final flareTuple = <String, Object?>{
      'reason': flare['reason'],
      'live': int.parse(flare['live']!),
      'paused': int.parse(flare['paused']!),
      'running': int.parse(flare['running']!),
      'gated': int.parse(flare['gated']!),
      'cooling': int.parse(flare['cooling']!),
    };
    expect({
      for (final field in [
        'reason',
        'live',
        'paused',
        'running',
        'gated',
        'cooling',
      ])
        field: statusWedge[field],
    }, flareTuple);
  });
}

final class _UnusedCommandHandler implements GridCommandHandler {
  @override
  Future<GridCommandResult> call(GridCommandRequest request) async =>
      const GridCommandResult.refused(code: 'unused', message: 'unused');
}
