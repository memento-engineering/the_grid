// W1 (tg-zfek Stage 1) — the assembly threading (stage1-wiring §1.1):
// `assembleStationWork` builds the harness beside the state writer, dry-run
// forces `disabled` (§1.3), and `StationWorkRuntime` lifecycles it — up
// inside `start()` after the sources, down inside `shutdown()` before them,
// never blocking either.
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart'
    show SqlResult, TrajectoryDb;
import 'package:test/test.dart';

/// A minimal resolver — nothing resolves in these offline assemblies.
class _NullResolver implements SessionResolver {
  const _NullResolver();
  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('never reached');
}

final class _FakeDb implements TrajectoryDb {
  bool closed = false;

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async =>
      const SqlResult();

  @override
  Future<void> close() async => closed = true;
}

void _seedStore(String dir, {String? database}) {
  Directory('$dir/.beads').createSync(recursive: true);
  File('$dir/.beads/metadata.json').writeAsStringSync(
    database == null
        ? '{"dolt_mode":"embedded"}'
        : '{"dolt_mode":"embedded","dolt_database":"$database"}',
  );
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tg-zfek-w1-asm-');
    _seedStore('${tmp.path}/proj', database: 'proj');
    _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<StationWorkRuntime> assemble({
    TrajectoryConfig trajectoryConfig = const TrajectoryConfig(),
    TrajectoryHarness? trajectoryOverride,
  }) => assembleStationWork(
    stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
    substations: [SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj')],
    resolver: const _NullResolver(),
    dryRun: true,
    trajectoryConfig: trajectoryConfig,
    trajectoryOverride: trajectoryOverride,
  );

  test(
      'dry-run FORCES disabled — even a required config claims no epoch and '
      'writes nothing (§1.3)', () async {
    final work = await assemble(
      trajectoryConfig: const TrajectoryConfig(
        mode: TrajectoryConfigMode.required,
      ),
    );
    expect(work.trajectory.mode, TrajectoryHarnessMode.disabled);
    await work.start();
    expect(work.trajectory.mode, TrajectoryHarnessMode.disabled);
    await work.shutdown();
  });

  test('the default auto posture on an unprovisioned home is a quiet no-op',
      () async {
    final work = await assemble();
    expect(work.trajectory.mode, TrajectoryHarnessMode.disabled,
        reason: 'dry-run forced; the config default (auto) never reaches IO');
    await work.start();
    await work.shutdown();
  });

  test(
      'the runtime lifecycles the harness: start() brings it up, shutdown() '
      'settles it before the sources (§1.2)', () async {
    final flares = <String>[];
    final db = _FakeDb();
    // A required-mode harness over a fake connection: connect succeeds, the
    // belt verify scans zero rows clean, and the epoch claim dies on the fake
    // db's empty read-back — degrading, never throwing. That degradation IS
    // the observable: only a started harness can leave `down`, and the boot
    // must continue past it.
    final harness = await TrajectoryHarness.build(
      config: const TrajectoryConfig(mode: TrajectoryConfigMode.required),
      gridHome: '${tmp.path}/home',
      station: 'tgstate',
      onFlare: (name, data) => flares.add(name),
      connect: () async => db,
    );
    final work = await assemble(trajectoryOverride: harness);
    expect(identical(work.trajectory, harness), isTrue);
    expect(harness.mode, TrajectoryHarnessMode.down);

    await work.start();
    expect(harness.mode, isNot(TrajectoryHarnessMode.down),
        reason: 'StationWorkRuntime.start() drove TrajectoryHarness.start()');
    expect(work.lastRestartReport, isNotNull,
        reason: 'the boot continued past the trajectory — never blocked');

    await work.shutdown();
    expect(db.closed, isTrue,
        reason: 'shutdown() settled the harness (connection closed)');
  });
}
