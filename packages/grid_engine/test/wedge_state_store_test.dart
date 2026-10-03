import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 9, 22, 12);

GraphSnapshot _graph(List<Bead> beads, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: {for (final bead in beads) bead.id},
      capturedAt: _now.add(Duration(seconds: tick)),
    );

Bead _session(
  String id, {
  required String workBeadId,
  bool closed = false,
  bool paused = false,
}) => sessionBead(
  id: id,
  workBeadId: workBeadId,
  closed: closed,
  metadata: {
    SessionBeadKeys.model: kSessionModelMolecule,
    if (paused) SessionBeadKeys.pauseState: 'paused',
  },
);

Bead _step(
  String id, {
  required String sessionId,
  required String path,
  required StepState state,
  DateTime? cooldownUntil,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.path: path,
    MoleculeStepKeys.state: state.name,
    if (cooldownUntil != null)
      MoleculeStepKeys.cooldownUntil: cooldownUntil.toIso8601String(),
  },
);

Bead _gate(
  String id, {
  required String sessionId,
  required String node,
  String reason = 'manual',
}) => Bead(
  id: id,
  issueType: GridIssueTypes.gate,
  status: BeadStatus.open,
  metadata: {'blocks': sessionId, 'node': node, 'reason': reason},
);

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Object?> _counts(WedgeState state) {
  final json = state.toJson();
  return {
    'live': json['live'],
    'gated': json['gated'],
    'running': json['running'],
    'cooling': json['cooling'],
    'paused': json['paused'],
  };
}

Map<String, Object?> _flareTuple(Map<String, String> data) => {
  'reason': data['reason'],
  'live': int.parse(data['live']!),
  'paused': int.parse(data['paused']!),
  'running': int.parse(data['running']!),
  'gated': int.parse(data['gated']!),
  'cooling': int.parse(data['cooling']!),
};

Map<String, Object?> _stateTuple(WedgeState state) {
  final json = state.toJson();
  return {
    'reason': json['reason'],
    'live': json['live'],
    'paused': json['paused'],
    'running': json['running'],
    'gated': json['gated'],
    'cooling': json['cooling'],
  };
}

void main() {
  test('state-store counts drive each resident wedge tick', () async {
    final work = FakeSnapshotSource(
      _graph([for (var i = 1; i <= 7; i++) bead('work-$i')]),
    );
    final state = FakeSnapshotSource(_graph(const []));
    final bridge = StationJoinBridge(work: work, state: state)..start();
    final transport = RecordingExplorationTransport();
    final driver = StationDriver(
      bridge: bridge,
      clock: () => _now,
      transport: transport,
      wedgeThreshold: Duration.zero,
      scheduleTimer: (_, _) => _FakeTimer(),
    )..start();
    addTearDown(driver.dispose);
    addTearDown(work.close);
    addTearDown(state.close);

    state.push(
      _graph([
        _session('session-running', workBeadId: 'work-1'),
        _step(
          'step-running',
          sessionId: 'session-running',
          path: 'work-1/build',
          state: StepState.running,
        ),
        _session('session-cooling', workBeadId: 'work-2'),
        _step(
          'step-cooling',
          sessionId: 'session-cooling',
          path: 'work-2/build',
          state: StepState.failed,
          cooldownUntil: _now.add(const Duration(minutes: 5)),
        ),
        _session('session-gated', workBeadId: 'work-3'),
        _step(
          'step-gated',
          sessionId: 'session-gated',
          path: 'work-3/review',
          state: StepState.pending,
        ),
        _gate('gate-1', sessionId: 'session-gated', node: 'work-3/review'),
        _gate('gate-2', sessionId: 'session-gated', node: 'work-3/review'),
        _session('session-paused', workBeadId: 'work-4', paused: true),
        _step(
          'step-paused',
          sessionId: 'session-paused',
          path: 'work-4/build',
          state: StepState.pending,
        ),
        _gate('gate-paused', sessionId: 'session-paused', node: 'work-4/build'),
        _session('session-pending', workBeadId: 'work-5'),
        _step(
          'step-pending',
          sessionId: 'session-pending',
          path: 'work-5/build',
          state: StepState.pending,
        ),
      ], tick: 1),
    );
    await _settle();

    driver.afterFlush();
    final first = driver.wedge;
    expect(_counts(first), {
      'live': 5,
      'gated': 3,
      'running': 1,
      'cooling': 1,
      'paused': 1,
    });
    expect(first.sample.frozenSessionIds, ['session-gated', 'session-pending']);
    expect(first.sample.reason, isNot('no live session'));

    state.push(
      _graph([
        _session('session-next-gated', workBeadId: 'work-6'),
        _step(
          'step-next-gated',
          sessionId: 'session-next-gated',
          path: 'work-6/review',
          state: StepState.pending,
        ),
        _gate(
          'gate-next',
          sessionId: 'session-next-gated',
          node: 'work-6/review',
        ),
        _session('session-next-pending', workBeadId: 'work-7'),
        _step(
          'step-next-pending',
          sessionId: 'session-next-pending',
          path: 'work-7/build',
          state: StepState.pending,
        ),
      ], tick: 2),
    );
    await _settle();

    driver.afterFlush();
    final second = driver.wedge;
    expect(_counts(second), {
      'live': 2,
      'gated': 1,
      'running': 0,
      'cooling': 0,
      'paused': 0,
    });
    expect(second.sample.reason, isNot('no live session'));

    state.push(
      _graph([
        _session('session-next-pending', workBeadId: 'work-7'),
        _step(
          'step-next-pending',
          sessionId: 'session-next-pending',
          path: 'work-7/build',
          state: StepState.pending,
        ),
      ], tick: 3),
    );
    await _settle();

    driver.afterFlush();
    final changed = driver.wedge;
    expect(_counts(changed), {
      'live': 1,
      'gated': 0,
      'running': 0,
      'cooling': 0,
      'paused': 0,
    });
    final flare = transport.named(kWedgeChangedFlare).single;
    expect(_flareTuple(flare.data), _stateTuple(changed));

    state.push(
      _graph([
        _session('session-next-gated', workBeadId: 'work-6', closed: true),
        _session('session-next-pending', workBeadId: 'work-7', closed: true),
      ], tick: 4),
    );
    await _settle();

    driver.afterFlush();
    final finalState = driver.wedge;
    expect(_counts(finalState), {
      'live': 0,
      'gated': 0,
      'running': 0,
      'cooling': 0,
      'paused': 0,
    });
    expect(finalState.sample.reason, 'no live session');
  });

  test('lane.down gate counts as blocked live work', () {
    final work = FakeSnapshotSource(_graph([bead('work-lane')]));
    final state = FakeSnapshotSource(
      _graph([
        _session('session-lane', workBeadId: 'work-lane'),
        _step(
          'step-lane',
          sessionId: 'session-lane',
          path: 'work-lane/build',
          state: StepState.pending,
        ),
        _gate(
          'gate-lane',
          sessionId: 'session-lane',
          node: 'work-lane/build',
          reason: 'lane.down',
        ),
      ]),
    );
    final bridge = StationJoinBridge(work: work, state: state);
    final driver = StationDriver(
      bridge: bridge,
      scheduleTimer: (_, _) => _FakeTimer(),
    )..start();
    addTearDown(driver.dispose);
    addTearDown(work.close);
    addTearDown(state.close);

    final sample = driver.wedge.sample;

    expect(sample.live, 1);
    expect(sample.gated, 1);
    expect(sample.running, 0);
    expect(sample.cooling, 0);
    expect(sample.reason, isNot('no live session'));
  });
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
