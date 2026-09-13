// W1 (tg-zfek Stage 1) — the assembly threading (stage1-wiring §1.1):
// `assembleStationWork` builds the harness beside the state writer, dry-run
// forces `disabled` (§1.3), and `StationWorkRuntime` lifecycles it — up
// inside `start()` after the sources, down inside `shutdown()` before them,
// never blocking either.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart'
    show
        DualReadMode,
        JoinedSnapshot,
        RelayObservation,
        RelayObserver,
        RelayVerdict,
        SessionProjection,
        WorkSessionLiveness;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_sdk/src/trajectory/work_session_liveness_obligation.dart';
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

final class _NoOpQuery extends ObligationQuery {
  const _NoOpQuery(this.name);

  @override
  final String name;

  @override
  String get sql => 'SELECT 1 AS one';

  @override
  Future<List<ObligationAppend>> repair(
    List<Map<String, String?>> rows,
  ) async => const [];
}

final class _RecordingRelayObserver implements RelayObserver {
  final List<RelayObservation> observations = <RelayObservation>[];

  @override
  Future<RelayVerdict> observe(RelayObservation observation) async {
    observations.add(observation);
    return const RelayVerdict.escalate(reason: 'tick observed');
  }
}

final class _BuildProbeDelegate extends GridDelegate {
  bool built = false;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    built = true;
    return const RawAssetGrid(root: '/probe');
  }
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

  test("the assembly vends the harness's sockets", () async {
    final work = await assemble();
    addTearDown(work.shutdown);
    expect(
      work.openStores.map((store) => store.name),
      contains('trajectory'),
      reason: "the state server's other writer rides the one closing locus",
    );
  });

  test(
    'cut composes one shared admission halt and shadow composes none',
    () async {
      final cut = await assemble(
        trajectoryConfig: const TrajectoryConfig(
          discipline: TrajectoryDiscipline.cut,
        ),
      );
      final shadow = await assemble();
      addTearDown(cut.shutdown);
      addTearDown(shadow.shutdown);

      final cutScope = cut.wiring.trajectory!;
      expect(cutScope.admissionHalt, isNotNull);
      expect(
        cut.wiring.services.trajectoryAdmissionHalt,
        same(cutScope.admissionHalt),
      );
      expect(shadow.wiring.trajectory!.admissionHalt, isNull);
      expect(shadow.wiring.services.trajectoryAdmissionHalt, isNull);
    },
  );

  test('dry-run FORCES disabled — even a required config claims no epoch and '
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

  test('dry-run cut assembly starts with trajectory disabled', () async {
    final work = await assemble(
      trajectoryConfig: const TrajectoryConfig(
        discipline: TrajectoryDiscipline.cut,
      ),
    );
    addTearDown(work.shutdown);

    expect(work.trajectory.config.mode, TrajectoryConfigMode.disabled);
    expect(work.trajectory.mode, TrajectoryHarnessMode.disabled);
    expect(work.trajectory.config.cutPostureRefusal, isNull);

    await work.start();
    expect(work.lastRestartReport, isNotNull);
  });

  test(
    'the default auto posture on an unprovisioned home is a quiet no-op',
    () async {
      final work = await assemble();
      expect(
        work.trajectory.mode,
        TrajectoryHarnessMode.disabled,
        reason: 'dry-run forced; the config default (auto) never reaches IO',
      );
      await work.start();
      await work.shutdown();
    },
  );

  test(
    'station composition forwards ordered obligation query extensions',
    () async {
      const first = _NoOpQuery('first-extension');
      const second = _NoOpQuery('second-extension');
      final work = await assemble(
        trajectoryConfig: const TrajectoryConfig(
          obligationQueryExtensions: [first, second],
        ),
      );
      final defaultWork = await assemble();
      addTearDown(work.shutdown);
      addTearDown(defaultWork.shutdown);

      expect(work.trajectory.mode, TrajectoryHarnessMode.disabled);
      expect(work.trajectory.config.obligationQueryExtensions, [
        same(first),
        same(second),
      ]);
      expect(defaultWork.trajectory.config.obligationQueryExtensions, isEmpty);
      expect(const TrajectoryConfig().obligationQueryExtensions, isEmpty);
    },
  );

  test('work-session liveness obligation rides the fenced tick seam', () async {
    const first = _NoOpQuery('first-extension');
    const second = _NoOpQuery('second-extension');
    const appended = _NoOpQuery('automatic-extension');
    const source = TrajectoryConfig(
      discipline: TrajectoryDiscipline.cut,
      mode: TrajectoryConfigMode.disabled,
      dualRead: DualReadMode.off,
      tickInterval: Duration(seconds: 7),
      obligationQueryExtensions: [first, second],
      gcInterval: Duration(minutes: 7),
      commitCadence: Duration(seconds: 31),
      queueBound: 123,
      livenessThreshold: Duration(minutes: 8),
      pulseCoalesce: Duration(seconds: 41),
      shutdownDrainTimeout: Duration(seconds: 17),
      soakWindowEpoch: 9,
      reconcileLedgerCloses: false,
    );
    final cloned = source.withAppendedObligationQueries(const [appended]);
    expect(cloned.discipline, source.discipline);
    expect(cloned.mode, source.mode);
    expect(cloned.dualRead, source.dualRead);
    expect(cloned.tickInterval, source.tickInterval);
    expect(cloned.gcInterval, source.gcInterval);
    expect(cloned.commitCadence, source.commitCadence);
    expect(cloned.queueBound, source.queueBound);
    expect(cloned.livenessThreshold, source.livenessThreshold);
    expect(cloned.pulseCoalesce, source.pulseCoalesce);
    expect(cloned.shutdownDrainTimeout, source.shutdownDrainTimeout);
    expect(cloned.soakWindowEpoch, source.soakWindowEpoch);
    expect(cloned.reconcileLedgerCloses, source.reconcileLedgerCloses);
    expect(cloned.obligationQueryExtensions, [
      same(first),
      same(second),
      same(appended),
    ]);
    expect(
      () => cloned.obligationQueryExtensions.add(first),
      throwsUnsupportedError,
    );
    expect(cloned.cutPostureRefusal, isNotNull);
    expect(
      cloned.cutPostureRefusal.toString(),
      source.cutPostureRefusal.toString(),
    );

    final now = DateTime.utc(2026, 9, 12, 12);
    final observer = _RecordingRelayObserver();
    final liveness = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      clock: () => now,
    );
    addTearDown(liveness.dispose);
    liveness.mountRelay(observer: observer, ceiling: 1);
    liveness.refresh(
      JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: const [],
          dependencies: const [],
          readyIds: const [],
          capturedAt: now,
        ),
        sessionsByWorkBead: {
          'work-1': SessionProjection(
            workBeadId: 'work-1',
            sessionId: 'state-session-1',
            relayNextObservationAt: now,
          ),
        },
      ),
    );
    final obligation = WorkSessionLivenessObligation(liveness);
    expect(obligation.name, 'work-session-liveness');
    expect(obligation.sql, 'SELECT 1 AS fenced_tick');
    expect(obligation.parameters, isEmpty);

    expect(await obligation.repair(const []), isEmpty);
    expect(observer.observations, isEmpty, reason: 'boot pass is inert');
    liveness.activate();
    expect(await obligation.repair(const []), isEmpty);
    expect(observer.observations, hasLength(1));

    final adapterSource = File(
      'lib/src/trajectory/work_session_liveness_obligation.dart',
    ).readAsStringSync();
    expect(adapterSource, isNot(contains('Timer.periodic')));
    expect(adapterSource, isNot(contains('Stream.periodic')));
    expect(adapterSource, isNot(contains('TrajectoryTick(')));
  });

  test('the runtime lifecycles the harness: start() brings it up, shutdown() '
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
    expect(
      harness.mode,
      isNot(TrajectoryHarnessMode.down),
      reason: 'StationWorkRuntime.start() drove TrajectoryHarness.start()',
    );
    expect(
      work.lastRestartReport,
      isNotNull,
      reason: 'the boot continued past the trajectory — never blocked',
    );

    await work.shutdown();
    expect(
      db.closed,
      isTrue,
      reason: 'shutdown() settled the harness (connection closed)',
    );
  });

  test(
    'cut contradiction throws named requested and resolved posture',
    () async {
      final db = _FakeDb();
      final harness = await TrajectoryHarness.build(
        config: const TrajectoryConfig(
          discipline: TrajectoryDiscipline.cut,
          dualRead: DualReadMode.observe,
        ),
        gridHome: '${tmp.path}/home',
        station: 'tgstate',
        connect: () async => db,
      );
      final work = await assemble(trajectoryOverride: harness);
      addTearDown(work.shutdown);

      await expectLater(
        work.start(),
        throwsA(
          isA<CutPostureRefused>()
              .having(
                (error) => error.requestedDualRead,
                'requestedDualRead',
                DualReadMode.observe,
              )
              .having(
                (error) => error.resolvedDualRead,
                'resolvedDualRead',
                DualReadMode.primary,
              )
              .having(
                (error) => error.toString(),
                'message',
                allOf(
                  contains('requested dualRead=observe'),
                  contains('resolved dualRead=primary'),
                ),
              ),
        ),
      );
    },
  );

  test('cut refusal runs after trajectory attach and before runGrid', () async {
    var attached = false;
    final db = _FakeDb();
    final harness = await TrajectoryHarness.build(
      config: const TrajectoryConfig(
        discipline: TrajectoryDiscipline.cut,
        dualRead: DualReadMode.observe,
      ),
      gridHome: '${tmp.path}/home',
      station: 'tgstate',
      connect: () async {
        attached = true;
        return db;
      },
    );
    final work = await assemble(trajectoryOverride: harness);
    addTearDown(work.shutdown);
    final delegate = _BuildProbeDelegate();

    await expectLater(() async {
      await work.start();
      final grid = await runGrid(delegate);
      await grid.teardown();
    }(), throwsA(isA<CutPostureRefused>()));
    expect(attached, isTrue);
    expect(delegate.built, isFalse);
  });

  group('W4/W5 — the recorder reaches every observation site (§1.1)', () {
    test(
      'ONE recorder is threaded ambient AND into the off-tree collaborators',
      () async {
        final work = await assemble();
        addTearDown(work.shutdown);
        final recorder = work.trajectory.recorder;

        // The ambient value the in-tree sites (SessionScope, CapabilityHost,
        // WorkList) resolve — provided by `StationWork`, so it must be the
        // harness's own recorder and not a second one.
        expect(work.wiring.trajectory, isNotNull);
        expect(identical(work.wiring.trajectory!.recorder, recorder), isTrue);

        // Sole appender by THREADING (§1.1): a second recorder would mean a
        // second view of the round ladder, the mount sequences, and the lease
        // succession cache — identity is the invariant, not "a recorder is
        // present".
        expect(
          identical(work.trajectory.recorder, recorder),
          isTrue,
          reason: 'the harness vends ONE recorder, memoized',
        );
      },
    );

    test('a DISABLED harness still vends a counting no-op recorder', () async {
      // §1.1: no call site ever branches on "is the trajectory up", so the
      // recorder must exist even when the trajectory does not. Dry-run forces
      // disabled, which is exactly that posture.
      final work = await assemble();
      addTearDown(work.shutdown);
      expect(work.trajectory.mode, TrajectoryHarnessMode.disabled);
      final recorder = work.trajectory.recorder;
      final result = await recorder.sessionCompleted(
        sessionId: 's1',
        workBeadId: 'proj-1',
      );
      expect(result, isA<Suppressed>());
      expect(recorder.stats.skipped, 1);
      expect(recorder.stats.derived, 0);
      expect(work.trajectory.status.appended, 0);
    });
  });
}
