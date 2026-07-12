// The grid_sdk half of the zombie reap: the assembly WIRES the one bd chokepoint
// into the restart pass, and a DROPPED reap is reported LOUD rather than
// swallowed (a cursor still claiming `running` over a corpse is the exact lie
// that blinds the wedge monitor and vetoes `grid rework`).
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A minimal resolver — nothing in these tests mounts a tree.
class _NullResolver implements SessionResolver {
  const _NullResolver();
  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('never reached — no tree is mounted here');
}

void _seedStore(String dir, {required String database}) {
  Directory('$dir/.beads').createSync(recursive: true);
  File('$dir/.beads/metadata.json').writeAsStringSync(
    '{"dolt_mode":"embedded","dolt_database":"$database"}',
  );
}

void main() {
  group('droppedReapReports — the LOUD contract', () {
    test(
      'a DROPPED reap yields exactly one line naming the session, the node, the '
      'dead pid, and WHY; a reap that LANDED yields none',
      () {
        final report = RestartReport(
          const [],
          reaped: const [
            ZombieReap(
              sessionId: 'tgdog-1wb',
              nodePath: 'pow-77g/agent',
              reapCount: 1,
              pgid: 29629,
              pid: 29629,
              failure: 'bd unavailable',
            ),
            ZombieReap(
              sessionId: 'tgdog-crd',
              nodePath: 'pow-edp/agent',
              reapCount: 1,
              pid: 89933,
            ),
          ],
        );

        final lines = droppedReapReports(report);
        expect(lines, hasLength(1), reason: 'only the DROPPED one is reported');
        expect(lines.single, contains('tgdog-1wb/pow-77g/agent'));
        expect(lines.single, contains('bd unavailable'));
        expect(lines.single, contains('29629'));
        expect(lines.single, contains('running'));
        expect(
          lines.single,
          isNot(contains('tgdog-crd')),
          reason: 'a reap that LANDED is not an alarm',
        );
      },
    );

    test('a clean pass reports nothing', () {
      expect(droppedReapReports(RestartReport(const [])), isEmpty);
    });
  });

  group('buildStationWork wires the reap', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('tg-szb-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test(
      'the ONE bd chokepoint reaches the RestartReconciler — without it the reap '
      'would silently never run, which is the failure this change exists to fix',
      () async {
        _seedStore('${tmp.path}/proj', database: 'pow');
        _seedStore('${tmp.path}/home/.grid', database: 'houston');

        final work = await buildStationWork(
          stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
          substations: [
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj'),
          ],
          resolver: const _NullResolver(),
          dryRun: true,
        );
        addTearDown(work.shutdown);

        expect(work.restart.hasChokepoint, isTrue);
        expect(
          work.lastRestartReport,
          isNull,
          reason: 'the pass has not run yet — start() latches it',
        );
      },
    );
  });
}
