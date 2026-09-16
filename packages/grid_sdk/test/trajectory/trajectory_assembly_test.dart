// W1 (tg-zfek Stage 1) — the assembly threading (stage1-wiring §1.1):
// `assembleStationWork` builds the harness beside the state writer, dry-run
// forces `disabled` (§1.3), and `StationWorkRuntime` lifecycles it — up
// inside `start()` after the sources, down inside `shutdown()` before them,
// never blocking either.
import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart'
    show
        DualReadMode,
        GridIssueTypes,
        Idle,
        JoinedSnapshot,
        SessionProjection,
        SessionBeadKeys,
        StationDriver,
        WorkSessionLiveness;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_sdk/src/stores/state_store_pruner.dart';
import 'package:grid_sdk/src/trajectory/state_store_prune_obligation.dart';
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

final class _RegistrarProbe extends StatelessSeed {
  const _RegistrarProbe(this.seen);

  final List<RelayRegistrar?> seen;

  @override
  Seed build(TreeContext context) {
    seen.add(context.watch<RelayRegistrar>());
    return const Idle();
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

  test(
    'discipline quiesce is bidirectional, station-wide, and includes pause',
    () {
      Bead session(
        String id, {
        required String discipline,
        BeadStatus status = BeadStatus.open,
        bool paused = false,
      }) => Bead(
        id: id,
        issueType: GridIssueTypes.session,
        status: status,
        metadata: {
          SessionBeadKeys.discipline: discipline,
          SessionBeadKeys.workBead: 'other-seat-$id',
          if (paused) SessionBeadKeys.pauseState: 'paused',
        },
      );
      final snapshot = GraphSnapshot.fromParts(
        beads: [
          session('z-shadow-paused', discipline: 'shadow', paused: true),
          session('a-cut', discipline: 'cut'),
          session('closed-cut', discipline: 'cut', status: BeadStatus.closed),
        ],
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime.utc(2026, 9, 13),
      );

      expect(
        disciplineQuiesceOffenders(
          snapshot: snapshot,
          discipline: TrajectoryDiscipline.cut,
        ),
        ['z-shadow-paused'],
      );
      expect(
        disciplineQuiesceOffenders(
          snapshot: snapshot,
          discipline: TrajectoryDiscipline.shadow,
        ),
        ['a-cut'],
      );
    },
  );

  Future<StationWorkRuntime> assemble({
    TrajectoryConfig trajectoryConfig = const TrajectoryConfig(),
    TrajectoryHarness? trajectoryOverride,
    StationWorkDriverBuilder? driverBuilder,
    MaintenanceSink? onStateStorePruneReceipt,
  }) => assembleStationWork(
    stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
    substations: [SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj')],
    resolver: const _NullResolver(),
    dryRun: true,
    trajectoryConfig: trajectoryConfig,
    trajectoryOverride: trajectoryOverride,
    driverBuilder: driverBuilder,
    onStateStorePruneReceipt: onStateStorePruneReceipt,
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
    'dry-run resolves cut to disabled shadow and composes no halt',
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
      expect(cutScope.admissionHalt, isNull);
      expect(cut.wiring.services.trajectoryAdmissionHalt, isNull);
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

  test('dry-run forces a requested non-off G2 posture back to off', () async {
    final work = await assemble(
      trajectoryConfig: const TrajectoryConfig(
        g2Posture: G2Posture.cut,
        g1CertificatePassed: false,
      ),
    );
    addTearDown(work.shutdown);

    expect(work.trajectory.config.g2Posture, G2Posture.off);
    expect(work.trajectory.config.g2G1PrerequisiteRefusal, isNull);
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
    'station assembly appends liveness then prune after authored extensions',
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
        isA<WorkSessionLivenessObligation>(),
        isA<StateStorePruneObligation>(),
      ]);
      expect(
        work.trajectory.config.obligationQueryExtensions[work
                .trajectory
                .config
                .obligationQueryExtensions
                .length -
            2],
        isA<WorkSessionLivenessObligation>().having(
          (obligation) => obligation.liveness,
          'liveness',
          same(work.sessionLiveness),
        ),
      );
      expect(defaultWork.trajectory.config.obligationQueryExtensions, [
        isA<WorkSessionLivenessObligation>(),
        isA<StateStorePruneObligation>(),
      ]);
      expect(
        work.trajectory.config.obligationQueryExtensions.last,
        isA<StateStorePruneObligation>(),
      );
      expect(const TrajectoryConfig().obligationQueryExtensions, isEmpty);
    },
  );

  test(
    'station assembly shares registrar identity and activates after mount',
    () async {
      late StationDriver driver;
      final work = await assemble(
        driverBuilder: ({required buildDefault}) => driver = buildDefault(),
      );
      expect(driver.sessionLiveness, same(work.sessionLiveness));
      expect(work.wiring.relayRegistrar, same(work.sessionLiveness));
      final obligation = work.trajectory.config.obligationQueryExtensions
          .whereType<WorkSessionLivenessObligation>()
          .single;
      expect(obligation.liveness, same(work.sessionLiveness));

      final observer = _RecordingRelayObserver();
      work.wiring.relayRegistrar!.mountRelay(observer: observer, ceiling: 1);
      final due = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      JoinedSnapshot dueSnapshot() => JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: const [],
          dependencies: const [],
          readyIds: const [],
          capturedAt: due,
        ),
        sessionsByWorkBead: {
          'work-1': SessionProjection(
            workBeadId: 'work-1',
            sessionId: 'tgstate-session-1',
            relayNextObservationAt: due,
          ),
        },
      );
      work.sessionLiveness.refresh(dueSnapshot());
      expect(await obligation.repair(const []), isEmpty);
      expect(observer.observations, isEmpty, reason: 'boot tick stays inert');

      final seen = <RelayRegistrar?>[];
      final owner = TreeOwner();
      owner.mountRoot(
        ProviderScope(
          child: StationWork(wiring: work.wiring, child: _RegistrarProbe(seen)),
        ),
      );
      owner.flush();
      expect(seen.single, same(work.sessionLiveness));

      work.afterFlush();
      work.sessionLiveness.refresh(dueSnapshot());
      expect(await obligation.repair(const []), isEmpty);
      expect(observer.observations, hasLength(1));
      work.afterFlush();
      expect(await obligation.repair(const []), isEmpty);
      expect(observer.observations, hasLength(1));

      owner.dispose();
      await work.shutdown();
      expect(
        () => work.sessionLiveness.mountRelay(observer: observer, ceiling: 1),
        throwsStateError,
      );
    },
  );

  test('station assembly keeps liveness-loss recovery cut-only, shared, and '
      'post-flush', () async {
    final source = File('lib/src/work/work_assembly.dart').readAsStringSync();

    expect(
      source,
      contains('trajectoryOverride ??\n      await TrajectoryHarness.build('),
      reason: 'a caller-owned harness is not retrofitted',
    );
    expect(
      source,
      contains(
        'livenessLostHandler:\n'
        '            trajectoryConfig.discipline != '
        'TrajectoryDiscipline.cut\n'
        '            ? null',
      ),
      reason: 'shadow remains record-only',
    );
    expect(
      source,
      allOf(
        contains('attemptLivenessRecovery = StationAttemptLivenessRecovery('),
        contains('services: () => services,'),
        contains('recorder: recorder,'),
        contains(
          'snapshot: () => stateSource.current ?? _emptyGraphSnapshot()',
        ),
      ),
      reason: 'the callback shares assembly\'s authority, recorder, and state',
    );
    final relayActivation = source.indexOf('sessionLiveness.activate();');
    final lossActivation = source.indexOf(
      '_attemptLivenessRecovery.activate();',
    );
    expect(relayActivation, isNonNegative);
    expect(lossActivation, greaterThan(relayActivation));

    final work = await assemble();
    addTearDown(work.shutdown);
    await work.start();
    work.afterFlush();
    work.afterFlush();
    expect(
      work.trajectory.tick,
      isNull,
      reason: 'the resolved shadow/disabled harness owns no recovery query',
    );
  });

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
      stateStorePruneAge: Duration(days: 5),
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
    expect(cloned.stateStorePruneAge, source.stateStorePruneAge);
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
    expect(source.asDisabled.stateStorePruneAge, const Duration(days: 5));
    expect(
      source
          .resolveForAssembly(dryRun: false, breakGlassReason: 'operator')
          .stateStorePruneAge,
      const Duration(days: 5),
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

  test(
    'state-store prune config defaults, validation, and fenced repair',
    () async {
      expect(
        const TrajectoryConfig().stateStorePruneAge,
        kDefaultStateStorePruneAge,
      );
      expect(kDefaultStateStorePruneAge, const Duration(days: 3));
      for (final invalid in [
        Duration.zero,
        const Duration(days: -1),
        const Duration(hours: 36),
      ]) {
        expect(
          () =>
              TrajectoryConfig(stateStorePruneAge: invalid).stateStorePruneAge,
          throwsA(isA<AssertionError>()),
        );
      }

      final receipts = <String>[];
      final work = await assemble(onStateStorePruneReceipt: receipts.add);
      addTearDown(work.shutdown);
      final obligation = work.trajectory.config.obligationQueryExtensions
          .whereType<StateStorePruneObligation>()
          .single;
      expect(obligation.name, 'state-store-prune');
      expect(obligation.sql, 'SELECT 1 AS fenced_tick');
      expect(obligation.parameters, isEmpty);

      expect(await obligation.repair(const []), isEmpty);
      expect(receipts, hasLength(1));
      expect(
        receipts.single,
        startsWith('grid: state-store prune skipped '),
        reason: 'the unstarted dry-run sources remain inert and unavailable',
      );

      final executeGate = Completer<void>();
      var executeCalls = 0;
      final awaited = StateStorePruneObligation(
        StateStorePruner(
          age: const Duration(days: 3),
          freshSnapshots: () async => (
            state: GraphSnapshot.fromParts(
              beads: [
                Bead(
                  id: 'session',
                  issueType: GridIssueTypes.session,
                  status: BeadStatus.closed,
                  closedAt: DateTime.utc(2026, 9, 1),
                  metadata: const {SessionBeadKeys.workBead: 'work'},
                ),
              ],
              dependencies: const [],
              readyIds: const [],
              capturedAt: DateTime.utc(2026, 9, 14),
            ),
            work: GraphSnapshot.fromParts(
              beads: [
                Bead(
                  id: 'work',
                  status: BeadStatus.closed,
                  closedAt: DateTime.utc(2026, 9, 1),
                ),
              ],
              dependencies: const [],
              readyIds: const [],
              capturedAt: DateTime.utc(2026, 9, 14),
            ),
          ),
          execute: ({required protectedIds, required olderThanDays}) async {
            executeCalls++;
            await executeGate.future;
            return (beadsRemoved: 1, dependencyRowsRemoved: 0);
          },
          now: () => DateTime.utc(2026, 9, 14),
          out: (_) {},
        ),
      );
      var returned = false;
      final repair = awaited.repair(const []).then((value) {
        returned = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(executeCalls, 1);
      expect(returned, isFalse);
      executeGate.complete();
      expect(await repair, isEmpty);
      expect(returned, isTrue);
    },
  );

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
    expect(
      harness.config.obligationQueryExtensions,
      isEmpty,
      reason: 'a caller-owned harness remains substitutive',
    );
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
      Future<StationWorkRuntime> contradictory() => assembleStationWork(
        stateStore: GridStateStore.forGridRoot('${tmp.path}/absent'),
        substations: [
          SubstationWorkSpec(name: 'never-acquired', root: '/absent'),
        ],
        resolver: const _NullResolver(),
        dryRun: false,
        trajectoryConfig: const TrajectoryConfig(
          discipline: TrajectoryDiscipline.cut,
          dualRead: DualReadMode.observe,
        ),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          contradictory(),
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
      }
    },
  );

  test(
    'cut refusal runs before trajectory attach and before runGrid',
    () async {
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
      var bundleAcquired = false;

      await expectLater(
        assembleStationWork(
          stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
          substations: [
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj'),
          ],
          resolver: const _NullResolver(),
          dryRun: false,
          trajectoryConfig: harness.config,
          trajectoryOverride: harness,
          bundleBuilder:
              ({
                required storeName,
                required workspace,
                required buildDefault,
              }) async {
                bundleAcquired = true;
                throw StateError('bundle acquisition must not run');
              },
        ),
        throwsA(isA<CutPostureRefused>()),
      );
      expect(attached, isFalse);
      expect(bundleAcquired, isFalse);
    },
  );

  test(
    'every G2 prerequisite mismatch refuses before resource builders',
    () async {
      final cases = <(TrajectoryConfig, String)>[
        (const TrajectoryConfig(g2Posture: G2Posture.shadow), 'g1Certificate'),
        (
          const TrajectoryConfig(
            g2Posture: G2Posture.cut,
            g1CertificatePassed: false,
          ),
          'g1Certificate',
        ),
        (
          const TrajectoryConfig(
            mode: TrajectoryConfigMode.required,
            dualRead: DualReadMode.primary,
            g2Posture: G2Posture.shadow,
            g1CertificatePassed: true,
          ),
          'discipline',
        ),
        (
          const TrajectoryConfig(
            discipline: TrajectoryDiscipline.cut,
            mode: TrajectoryConfigMode.auto,
            g2Posture: G2Posture.shadow,
            g1CertificatePassed: true,
          ),
          'mode',
        ),
        (
          const TrajectoryConfig(
            discipline: TrajectoryDiscipline.cut,
            dualRead: DualReadMode.observe,
            g2Posture: G2Posture.cut,
            g1CertificatePassed: true,
          ),
          'dualRead',
        ),
      ];
      for (final (config, field) in cases) {
        var bundleBuilt = false;
        var driverBuilt = false;
        await expectLater(
          assembleStationWork(
            stateStore: GridStateStore.forGridRoot('${tmp.path}/absent'),
            substations: [
              SubstationWorkSpec(
                name: 'never',
                root: '${tmp.path}/absent-work',
              ),
            ],
            resolver: const _NullResolver(),
            dryRun: false,
            trajectoryConfig: config,
            bundleBuilder:
                ({
                  required storeName,
                  required workspace,
                  required buildDefault,
                }) {
                  bundleBuilt = true;
                  return buildDefault();
                },
            driverBuilder: ({required buildDefault}) {
              driverBuilt = true;
              return buildDefault();
            },
          ),
          throwsA(
            isA<G2G1PrerequisiteRefused>().having(
              (value) => value.field,
              'field',
              field,
            ),
          ),
        );
        expect(bundleBuilt, isFalse, reason: field);
        expect(driverBuilt, isFalse, reason: field);
      }
    },
  );

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
