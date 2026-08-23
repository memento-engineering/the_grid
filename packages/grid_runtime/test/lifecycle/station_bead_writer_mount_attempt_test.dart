import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

/// Tests for `StationBeadWriter.recordMountAttempt` (tg-zlfu): the DURABLE half
/// of the remount budget.
///
/// The load-bearing property is ONE record per work bead, never one per
/// attempt — a bead per attempt would make the mechanism that bounds the
/// storage amplifier into one, emitting records at exactly the rate it exists
/// to stop. Offline: a recording BdRunner, no live `bd`.
void main() {
  late RecordingBdRunner runner;
  late BdCliService bd;
  late List<String> refusals;

  BeadOwnershipPredicate predicate() => BeadOwnershipPredicate({'tgdog'});

  StationBeadWriter writer() => StationBeadWriter(
    bd: bd,
    reader: runner,
    ownership: predicate(),
    onRefusal: refusals.add,
  );

  Bead record(
    String id, {
    String workBead = 'tg-1',
    String count = '1',
    bool closed = false,
  }) => Bead(
    id: id,
    title: 'grid mount-attempt $workBead',
    issueType: GridIssueTypes.mountAttempt,
    status: closed ? BeadStatus.closed : BeadStatus.open,
    metadata: {
      StationBeadWriter.rigKey: 'tgdog',
      StationBeadWriter.mountAttemptWorkBeadKey: workBead,
      StationBeadWriter.mountAttemptCountKey: count,
    },
  );

  Bead session(String id, {String workBead = 'tg-1'}) => Bead(
    id: id,
    issueType: GridIssueTypes.session,
    status: BeadStatus.open,
    metadata: {StationBeadWriter.rigKey: 'tgdog', 'work_bead': workBead},
  );

  Map<String, String> setMetadataOf(List<String> call) {
    final metadata = <String, String>{};
    for (var i = 0; i + 1 < call.length; i++) {
      if (call[i] != '--set-metadata') continue;
      final assignment = call[i + 1];
      final separator = assignment.indexOf('=');
      if (separator < 0) continue;
      metadata[assignment.substring(0, separator)] = assignment.substring(
        separator + 1,
      );
    }
    return metadata;
  }

  setUp(() {
    runner = RecordingBdRunner();
    bd = BdCliService(runner);
    refusals = <String>[];
  });

  test('the FIRST attempt mints one record carrying the join key, the count, '
      'and the owned-substation marker from birth', () async {
    final id = await writer().recordMountAttempt(
      substation: 'tgdog',
      workBeadId: 'tg-1',
      attempt: 1,
    );

    final creates = runner.callsFor('create');
    expect(creates, hasLength(1));
    expect(creates.single, containsAllInOrder(['--type', 'mount-attempt']));
    expect(
      creates.single,
      containsAllInOrder(['--title', 'grid mount-attempt tg-1']),
    );

    final updates = runner.callsFor('update');
    expect(updates, hasLength(1));
    expect(updates.single[1], id);
    final metadata = setMetadataOf(updates.single);
    expect(metadata[StationBeadWriter.rigKey], 'tgdog');
    expect(metadata[StationBeadWriter.mountAttemptWorkBeadKey], 'tg-1');
    expect(metadata[StationBeadWriter.mountAttemptCountKey], '1');
    expect(metadata[StationBeadWriter.mountAttemptLastAtKey], isNotNull);
  });

  test('a LATER attempt merges into the SAME record — one bead per work bead, '
      'never one per attempt', () async {
    runner.exportBeads = [record('tgdog-att1', workBead: 'tg-1', count: '1')];

    final id = await writer().recordMountAttempt(
      substation: 'tgdog',
      workBeadId: 'tg-1',
      attempt: 2,
    );

    expect(id, 'tgdog-att1');
    expect(
      runner.callsFor('create'),
      isEmpty,
      reason:
          'the record already exists — a second bead would be the very '
          'storage amplification this budget exists to bound',
    );
    final updates = runner.callsFor('update');
    expect(updates, hasLength(1));
    expect(setMetadataOf(updates.single), {
      StationBeadWriter.mountAttemptCountKey: '2',
      StationBeadWriter.mountAttemptLastAtKey: anything,
    });
  });

  test('the bump merges ONLY the two budget keys — every other key on the '
      'record survives (no whole-map read-modify-write)', () async {
    runner.exportBeads = [record('tgdog-att1', workBead: 'tg-1', count: '1')];

    await writer().recordMountAttempt(
      substation: 'tgdog',
      workBeadId: 'tg-1',
      attempt: 2,
    );

    final update = runner.callsFor('update').single;
    expect(
      update.contains('--metadata'),
      isFalse,
      reason: '--metadata REPLACES the whole map; the merge must be per-key',
    );
    final keys = setMetadataOf(update).keys;
    expect(keys, isNot(contains(StationBeadWriter.rigKey)));
    expect(keys, isNot(contains(StationBeadWriter.mountAttemptWorkBeadKey)));
  });

  test('forensics APPEND to the record, never replace its notes', () async {
    runner.exportBeads = [record('tgdog-att1', workBead: 'tg-1', count: '1')];

    await writer().recordMountAttempt(
      substation: 'tgdog',
      workBeadId: 'tg-1',
      attempt: 2,
      note: 'mount attempt 2 of 3',
    );

    final update = runner.callsFor('update').single;
    expect(
      update,
      containsAllInOrder(['--append-notes', 'mount attempt 2 of 3']),
    );
    expect(
      update.contains('--notes'),
      isFalse,
      reason: '--notes REPLACES and has silently clobbered accrued corpus',
    );
  });

  test('the probe is keyed by work bead id and scoped to the record type — it '
      'never scans the work store', () async {
    await writer().recordMountAttempt(
      substation: 'tgdog',
      workBeadId: 'tg-1',
      attempt: 1,
    );

    final probe = runner.openBeadCalls.single;
    expect(probe.types, {GridIssueTypes.mountAttempt});
    expect(probe.metadataAll, {
      StationBeadWriter.mountAttemptWorkBeadKey: 'tg-1',
    });
  });

  test("another work bead's record is never reused as this one's", () async {
    runner.exportBeads = [
      record('tgdog-att1', workBead: 'tg-OTHER', count: '9'),
    ];

    await writer().recordMountAttempt(
      substation: 'tgdog',
      workBeadId: 'tg-1',
      attempt: 1,
    );

    expect(runner.callsFor('create'), hasLength(1));
  });

  test('positive-terminal settlement retires mount attempt and leaves no '
      'open record', () async {
    runner.exportBeads = [
      session('tgdog-sess1'),
      const Bead(id: 'tg-1', status: BeadStatus.closed),
      record('tgdog-att1'),
    ];
    await writer().settleSessionForTerminalWork(
      sessionId: 'tgdog-sess1',
      terminalWorkBead: const Bead(id: 'tg-1', status: BeadStatus.closed),
    );
    final batch = runner.callsFor('batch').single;
    expect(runner.stdins[runner.calls.indexOf(batch)]!.split('\n'), [
      'close tgdog-att1',
    ]);
    expect(
      await runner.openBeads(
        types: {GridIssueTypes.mountAttempt},
        metadataAll: const {StationBeadWriter.mountAttemptWorkBeadKey: 'tg-1'},
      ),
      isEmpty,
    );
  });

  test(
    'a closed prior record gives a re-drive a fresh count-one budget',
    () async {
      runner.exportBeads = [record('tgdog-att-old', count: '3', closed: true)];
      runner.nextCreatedId = 'tgdog-att-new';
      final id = await writer().recordMountAttempt(
        substation: 'tgdog',
        workBeadId: 'tg-1',
        attempt: 1,
      );
      expect(id, 'tgdog-att-new');
      expect(runner.callsFor('create'), hasLength(1));
      final update = runner.callsFor('update').single;
      expect(update, isNot(contains('tgdog-att-old')));
      expect(
        setMetadataOf(update),
        containsPair(StationBeadWriter.mountAttemptCountKey, '1'),
      );
    },
  );

  test('a FOREIGN substation is refused before any bd call — the record lives '
      'in the station OWN store, never on the work bead (A37)', () async {
    await expectLater(
      writer().recordMountAttempt(
        substation: 'someone-else',
        workBeadId: 'tg-1',
        attempt: 1,
      ),
      throwsA(isA<OwnershipRefused>()),
    );
    expect(runner.calls, isEmpty);
    expect(refusals, hasLength(1));
  });
}
