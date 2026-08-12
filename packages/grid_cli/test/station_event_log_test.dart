import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('station-event-log-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'persists cursors, UTC timestamps, typed events, and replay bounds',
    () async {
      final instant = DateTime.utc(2026, 8, 11, 12, 34, 56);
      var log = await DurableStationEventLog.open(
        directory,
        now: () => instant,
      );
      log.flare('session.minted', {'sessionId': 's1', 'workBeadId': 'w1'});
      log.flare('gate.opened', {
        'gateId': 'g1',
        'sessionId': 's1',
        'nodePath': 'work/review',
        'reason': 'review',
        'reused': 'false',
      });
      log.flare('session.closed', {
        'sessionId': 's1',
        'disposition': 'held',
        'reason': 'needs review',
      });
      await log.close();

      log = await DurableStationEventLog.open(directory, now: () => instant);
      log.flare('future.event', {'opaque': 'preserved'});
      final records = await log.replay(after: 0);

      expect(records.map((record) => record.cursor), [1, 2, 3, 4]);
      expect(records.every((record) => record.timestamp == instant), isTrue);
      expect(records[0].event, isA<SessionMintedEvent>());
      expect(records[1].event, isA<GateOpenedEvent>());
      final closed = records[2].event as SessionClosedEvent;
      expect(switch (closed.disposition) {
        HeldSession(:final reason) => reason,
        DoneSession() => 'done',
        _ => 'other',
      }, 'needs review');
      final generic = records[3].event as GenericStationEvent;
      expect(generic.name, 'future.event');
      expect(generic.data, {'opaque': 'preserved'});
      expect((await log.replay(after: 2)).map((record) => record.cursor), [
        3,
        4,
      ]);
      expect(await log.replay(after: 4), isEmpty);
      expect(await log.replay(after: 99), isEmpty);

      await log.close();
      log.flare('ignored', const {});
      expect((await log.replay(after: 0)).length, 4);
    },
  );

  test('reconstructs done disposition', () async {
    final log = await DurableStationEventLog.open(directory);
    log.flare('session.closed', {'sessionId': 's1', 'disposition': 'done'});
    final event = (await log.replay(after: 0)).single.event;
    expect(switch ((event as SessionClosedEvent).disposition) {
      DoneSession() => true,
      HeldSession() => false,
      _ => false,
    }, isTrue);
    await log.close();
  });

  for (final corrupt in <String, String>{
    'malformed': '{not-json}\n',
    'truncated': '{"cursor":1,"timestamp":"2026-08-11T00:00:00.000Z"',
    'non-contiguous':
        '{"cursor":2,"timestamp":"2026-08-11T00:00:00.000Z",'
        '"name":"x","data":{}}\n',
  }.entries) {
    test('refuses ${corrupt.key} history', () async {
      await File(
        '${directory.path}/${DurableStationEventLog.fileName}',
      ).writeAsString(corrupt.value);
      await expectLater(
        DurableStationEventLog.open(directory),
        throwsA(isA<FormatException>()),
      );
    });
  }
}
