import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

void main() {
  late RecordingBdRunner runner;
  late BdCliService bd;
  late List<String> refusals;
  late List<({String name, Map<String, String> data})> flares;

  StationBeadWriter writer() => StationBeadWriter(
    bd: bd,
    reader: runner,
    ownership: BeadOwnershipPredicate({'tgdog'}),
    onRefusal: refusals.add,
    onFlare: (name, data) => flares.add((name: name, data: data)),
    clock: () => DateTime.utc(2026, 9, 7, 12),
  );

  Bead stationGate(
    String id, {
    int epoch = 42,
    String reason = 'admission-halted',
  }) => Bead(
    id: id,
    title: 'grid station gate tgdog/$epoch',
    issueType: GridIssueTypes.gate,
    assignee: 'operator',
    metadata: {
      StationBeadWriter.rigKey: 'tgdog',
      'blocks': 'tgdog/$epoch',
      StationBeadWriter.stationGateScopeKey:
          StationBeadWriter.stationGateScopeValue,
      StationBeadWriter.stationGateEpochKey: '$epoch',
      'reason': reason,
    },
  );

  setUp(() {
    BdCliService.resetGuardedWriteCapabilityForTesting();
    runner = RecordingBdRunner(createdId: 'tgdog-station-gate');
    bd = BdCliService(runner);
    refusals = <String>[];
    flares = <({String name, Map<String, String> data})>[];
  });

  test('mints a station gate for the boot epoch with no node', () async {
    final id = await writer().createStationGate(
      substation: 'tgdog',
      epoch: 42,
      reason: 'admission-halted',
    );

    expect(id, 'tgdog-station-gate');
    expect(runner.callsFor('create'), [
      [
        'create',
        '--json',
        '--actor',
        'grid-controller',
        '--title',
        'grid station gate tgdog/42',
        '--type',
        'gate',
        '--priority',
        '2',
      ],
    ]);
    expect(runner.callsFor('update'), hasLength(1));
    expect(runner.callsFor('update').single[1], 'tgdog-station-gate');
    expect(jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>, {
      'rig': 'tgdog',
      'blocks': 'tgdog/42',
      'grid.gate.scope': 'station',
      'grid.gate.boot_epoch': '42',
      'reason': 'admission-halted',
    });
    expect(
      jsonDecode(runner.metadataOfUpdate(0)!),
      isNot(containsPair('node', anything)),
    );
    expect(flares, isEmpty);
    expect(runner.everyMutationHasActor, isTrue);
    expect(runner.neverCalledShow, isTrue);
  });

  test('closed sessions do not block a station gate', () async {
    runner.exportBeads = const [
      Bead(
        id: 'tgdog-closed-session',
        issueType: GridIssueTypes.session,
        status: BeadStatus.closed,
        metadata: {'rig': 'tgdog'},
      ),
    ];

    expect(
      await writer().createStationGate(
        substation: 'tgdog',
        epoch: 42,
        reason: 'terminal-loss',
      ),
      'tgdog-station-gate',
    );
    final createsBeforeRouteGate = runner.callsFor('create').length;
    final updatesBeforeRouteGate = runner.callsFor('update').length;

    await expectLater(
      writer().createGate(
        substation: 'tgdog',
        sessionId: 'tgdog-closed-session',
        nodePath: 'review/route',
        reason: 'step-loss',
      ),
      throwsA(isA<SessionClosedRefused>()),
    );

    expect(runner.callsFor('create'), hasLength(createsBeforeRouteGate));
    expect(runner.callsFor('update'), hasLength(updatesBeforeRouteGate));
    expect(refusals.single, contains('SessionClosedRefused'));
  });

  test('station gate dedup keys on epoch and reason class', () async {
    final stationWriter = writer();
    final first = await stationWriter.createStationGate(
      substation: 'tgdog',
      epoch: 42,
      reason: 'admission-halted',
    );
    runner.exportBeads = [stationGate(first)];

    final repeated = await stationWriter.createStationGate(
      substation: 'tgdog',
      epoch: 42,
      reason: 'admission-halted',
    );

    expect(repeated, first);
    expect(runner.callsFor('create'), hasLength(1));
    final refresh =
        jsonDecode(runner.metadataOfUpdate(1)!) as Map<String, dynamic>;
    expect(refresh, {
      'reason': 'admission-halted',
      'regate_count': '1',
      'regated_at': '2026-09-07T12:00:00.000Z',
    });
    expect(
      runner.callsFor('update')[1],
      containsAllInOrder(['--if-assignee', 'operator', '--if-status', 'open']),
    );

    runner.nextCreatedId = 'tgdog-other-epoch';
    expect(
      await stationWriter.createStationGate(
        substation: 'tgdog',
        epoch: 43,
        reason: 'admission-halted',
      ),
      'tgdog-other-epoch',
    );
    runner.nextCreatedId = 'tgdog-other-reason';
    expect(
      await stationWriter.createStationGate(
        substation: 'tgdog',
        epoch: 42,
        reason: 'terminal-loss',
      ),
      'tgdog-other-reason',
    );

    expect(runner.callsFor('create'), hasLength(3));
    expect(
      runner.openBeadCalls.map((call) => call.metadataAll),
      containsAll([
        containsPair(StationBeadWriter.stationGateEpochKey, '43'),
        containsPair('reason', 'terminal-loss'),
      ]),
    );
    expect(flares, isEmpty);
  });

  test('refuses an unowned station before its dedup read', () async {
    await expectLater(
      writer().createStationGate(
        substation: 'gascity',
        epoch: 42,
        reason: 'admission-halted',
      ),
      throwsA(isA<OwnershipRefused>()),
    );

    expect(runner.openBeadCalls, isEmpty);
    expect(runner.calls, isEmpty);
    expect(refusals, hasLength(1));
  });
}
