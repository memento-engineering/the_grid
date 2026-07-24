import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('non-leader parent boot creates an isolated station tree', () async {
    final store = await Directory.systemTemp.createTemp('station-group-');
    final fixture = await Process.start(Platform.resolvedExecutable, <String>[
      'run',
      'test/fixtures/station_group_boot.dart',
      store.path,
    ]);
    addTearDown(() async {
      await fixture.stdin.close();
      await fixture.exitCode;
      await store.delete(recursive: true);
    });

    final ready =
        jsonDecode(
              await fixture.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .first,
            )
            as Map<String, Object?>;
    final stationPid = ready['pid']! as int;
    final childPid = ready['child']! as int;
    final record = StationLockRecord.fromJson(
      jsonDecode(
            await File(StationLockService.lockPath(store.path)).readAsString(),
          )
          as Map<String, Object?>,
    );
    final actual = await const SystemProcessGroupController().resolvePgid(
      stationPid,
    );

    expect(record.pid, stationPid);
    expect(record.pgid, stationPid);
    expect(actual, stationPid);

    final group = await Process.run('ps', <String>[
      '-o',
      'pid=',
      '-g',
      '${record.pgid}',
    ]);
    final members = (group.stdout as String)
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .map(int.parse)
        .toSet();
    expect(members, <int>{stationPid, childPid});
    expect(members, isNot(contains(pid)));
  });
}
