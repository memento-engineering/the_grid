// Track J (tg-yl8) — assembleStationWork's fail-closed store binding: EXACT at
// the root, LOUD refusal, never a walk-up. The A37 gate is the load-bearing
// one: a missing `<grid.root>/.grid/.beads` must REFUSE — the old walk-up
// discovery would have silently bound the dual-role repo's WORK store and
// minted sessions into the work source.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_runtime/grid_runtime.dart'
    show
        BeadWorktree,
        OwnershipRefused,
        RootCheckout,
        StationGitService,
        SubprocessProvider;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A minimal resolver — assembly refusals fire before anything resolves.
class _NullResolver implements SessionResolver {
  const _NullResolver();
  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('never reached in refusal tests');
}

final class _RecordingBdRunner implements BdRunner {
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    final id = args.length > 1 ? args[1] : '';
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$id"}}',
      stderr: '',
    );
  }
}

final class _RecordingDryGit extends DryStationGitService {
  final List<String> listedRoots = [];

  @override
  Future<List<BeadWorktree>?> listBeadWorktrees(RootCheckout root) async {
    listedRoots.add(p.canonicalize(root.path));
    return const <BeadWorktree>[];
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('tg-yl8-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<StationWorkRuntime> build({
    List<SubstationWorkSpec>? substations,
    String? gridRoot,
    GridStateStore? stateStore,
  }) => assembleStationWork(
    stateStore:
        stateStore ??
        GridStateStore.forGridRoot(gridRoot ?? '${tmp.path}/home'),
    substations:
        substations ??
        [SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj')],
    resolver: const _NullResolver(),
    dryRun: true,
  );

  group('Track J — the assembly is fail-closed at the stores', () {
    String relativeUnnormalized(String absolute) =>
        '${p.relative(absolute)}${p.separator}.';

    test('an empty substation list refuses (no default substation)', () {
      expect(() => build(substations: []), throwsA(isA<ArgumentError>()));
    });

    test('every substation root reaches restart reconciliation', () async {
      _seedStore('${tmp.path}/first', database: 'first');
      _seedStore('${tmp.path}/second', database: 'second');
      _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
      final git = _RecordingDryGit();
      final work = await assembleStationWork(
        stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
        substations: [
          SubstationWorkSpec(name: 'first', root: '${tmp.path}/first'),
          SubstationWorkSpec(name: 'second', root: '${tmp.path}/second'),
        ],
        resolver: const _NullResolver(),
        dryRun: true,
        gitOverride: git,
      );
      addTearDown(work.shutdown);

      await work.start();

      expect(git.listedRoots, [
        p.canonicalize('${tmp.path}/first'),
        p.canonicalize('${tmp.path}/second'),
      ]);
      expect(work.lastRestartReport, isNotNull);
    });

    test('a duplicate substation name refuses (two WorkLists would race)', () {
      expect(
        () => build(
          substations: [
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/a'),
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/b'),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'CROSS-AXIS identity overlap refuses: one substation\'s prefix colliding '
      'with another\'s name would mount the same bead under BOTH WorkLists '
      '(ownership matches either axis)',
      () {
        expect(
          () => build(
            substations: [
              SubstationWorkSpec(
                name: 'the_grid',
                prefix: 'tg',
                root: '${tmp.path}/a',
              ),
              SubstationWorkSpec(name: 'tg', root: '${tmp.path}/b'),
            ],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains('"tg"'),
            ),
          ),
        );
        // The clean disjoint pairing sails past the identity guard (and
        // refuses later at the missing stores — the positive control that the
        // guard is not over-broad).
        expect(
          () => build(
            substations: [
              SubstationWorkSpec(
                name: 'the_grid',
                prefix: 'tg',
                root: '${tmp.path}/a',
              ),
              SubstationWorkSpec(
                name: 'power_station',
                prefix: 'pow',
                root: '${tmp.path}/b',
              ),
            ],
          ),
          throwsA(isA<StoreRefusal>()),
        );
      },
    );

    test('a substation root with no .beads refuses LOUD (no walk-up)', () {
      Directory('${tmp.path}/proj').createSync(recursive: true);
      _seedStore('${tmp.path}/home/.grid', database: 'houston');
      expect(() => build(), throwsA(isA<StoreRefusal>()));
    });

    test('THE A37 GATE: a missing grid state store refuses — even when the '
        'dual-role grid root itself holds a work store the old walk-up would '
        'have silently bound (sessions must never land in a work source)', () {
      _seedStore('${tmp.path}/proj', database: 'pow');
      // The grid HOME has a work store at its root (the dual-role repo
      // shape) — but NO state store under .grid/. Walk-up discovery from
      // <home>/.grid would find <home>/.beads; the assembly must refuse
      // instead.
      _seedStore('${tmp.path}/home', database: 'space');
      expect(
        () => build(),
        throwsA(
          isA<StoreRefusal>().having(
            (r) => r.message,
            'message',
            contains('.grid'),
          ),
        ),
      );
    });

    test(
      'canonical-equivalent relative and unnormalized store roots bind',
      () async {
        _seedStore('${tmp.path}/proj', database: 'pow');
        _seedStore('${tmp.path}/home/.grid', database: 'tgstate');

        final work = await build(
          substations: [
            SubstationWorkSpec(
              name: 'proj',
              root: relativeUnnormalized('${tmp.path}/proj'),
            ),
          ],
          stateStore: GridStateStore(
            gridRoot: relativeUnnormalized('${tmp.path}/home'),
          ),
        );
        addTearDown(work.shutdown);

        expect(work.stateSubstation, 'tgstate');
      },
    );

    test(
      'a canonical-different state store still refuses instead of walking up',
      () {
        _seedStore('${tmp.path}/proj', database: 'pow');
        _seedStore('${tmp.path}/home', database: 'space');

        expect(
          () => build(
            stateStore: GridStateStore(
              gridRoot: relativeUnnormalized('${tmp.path}/home'),
            ),
          ),
          throwsA(
            isA<StoreRefusal>().having(
              (r) => r.message,
              'message',
              contains('.grid'),
            ),
          ),
        );
      },
    );

    test('a state store naming no dolt_database refuses — the owned state '
        'partition derives from the store identity, never a flag (Q5a)', () {
      _seedStore('${tmp.path}/proj', database: 'pow');
      _seedStore('${tmp.path}/home/.grid');
      expect(
        () => build(),
        throwsA(
          isA<StoreRefusal>().having(
            (r) => r.message,
            'message',
            contains('dolt_database'),
          ),
        ),
      );
    });

    test('the built runtime sweeps orphans against the OWNED state partition '
        '(the runner has one to hand to runGrid)', () async {
      _seedStore('${tmp.path}/proj', database: 'pow');
      _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
      final work = await build();
      addTearDown(work.shutdown);

      // A dry-run station spawns nothing, so a teardown sweep is CLEAN — and it
      // reconciles the dry transport under the OWNED prefix, never a foreign
      // one.
      final report = await work.sweepOrphans();
      expect(report.isClean, isTrue);
      expect(report.settled, isTrue);
      expect(work.stateSubstation, 'tgstate');
    });
  });

  group('dry-run effect posture (ONE dry/live switch, asserted by type)', () {
    Future<void> git(List<String> args, String dir) async {
      final result = await Process.run('git', args, workingDirectory: dir);
      expect(
        result.exitCode,
        0,
        reason: 'git $args: ${result.stdout}${result.stderr}',
      );
    }

    test('dryRun: true selects the INERT provider and git service — no '
        'effect transport is wired', () async {
      _seedStore('${tmp.path}/proj', database: 'pow');
      _seedStore('${tmp.path}/home/.grid', database: 'tgstate');

      final work = await build();
      addTearDown(work.shutdown);

      // The posture the tree observes: the ambient services carry the
      // recording no-spawn transport and the inert git service, by TYPE —
      // not a banner flag.
      expect(work.wiring.services.provider, isA<DryRunProvider>());
      expect(work.git, isA<DryStationGitService>());
    });

    test('assembleStationWork binds CircuitResolver reap seam', () async {
      final gridRoot = '${tmp.path}/home';
      final workRoot = '${tmp.path}/proj';
      _seedStore(workRoot, database: 'pow');
      _seedStore('$gridRoot/.grid', database: 'tgstate');
      engine.Circuit rootCircuitFor(Bead bead) =>
          throw StateError('resolver policy is not invoked by assembly');
      final supplied = engine.CircuitResolver(rootCircuitFor);

      final work = await assembleStationWork(
        stateStore: GridStateStore.forGridRoot(gridRoot),
        substations: [
          SubstationWorkSpec(name: 'proj', root: workRoot, head: 'main'),
        ],
        resolver: supplied,
        dryRun: true,
      );
      addTearDown(work.shutdown);

      final rebound = work.wiring.resolver as engine.CircuitResolver;
      expect(rebound, isNot(same(supplied)));
      expect(rebound.rootCircuitFor, same(rootCircuitFor));
      expect(rebound.reapWorktree, equals(work.git.reap));
      expect(rebound.workRoot, isNotNull);
      expect(rebound.workRoot!.path, p.normalize(workRoot));
      expect(rebound.workRoot!.defaultBranch, 'main');
      expect(rebound.workRoot!.substation, 'proj');
    });

    test('dryRun: false selects the REAL subprocess provider and live git '
        'service', () async {
      _seedStore('${tmp.path}/proj', database: 'pow');
      _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
      // A live assembly registers the root checkout against REAL git; the
      // assigned head skips the origin/HEAD probe (no remote in the fixture).
      await git(['init', '--initial-branch=main'], '${tmp.path}/proj');

      final work = await assembleStationWork(
        stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
        substations: [
          SubstationWorkSpec(
            name: 'proj',
            root: '${tmp.path}/proj',
            head: 'main',
          ),
        ],
        resolver: const _NullResolver(),
        dryRun: false,
      );
      addTearDown(work.shutdown);

      expect(work.wiring.services.provider, isA<SubprocessProvider>());
      expect(work.wiring.services.provider, isNot(isA<DryRunProvider>()));
      expect(work.git, isA<StationGitService>());
      expect(work.git, isNot(isA<DryStationGitService>()));
    });
  });

  group('registry builder seam', () {
    test(
      'registry builder seam routes append-notes by owned store and refuses unowned ids',
      () async {
        _seedStore('${tmp.path}/proj', database: 'pow');
        _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
        final stateRunner = _RecordingBdRunner();
        final workRunner = _RecordingBdRunner();
        late WorkNoteAppender appendWorkNote;
        final builtRegistry = engine.DefaultCapabilityRegistry();

        final work = await assembleStationWork(
          stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
          substations: [
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj'),
          ],
          resolver: const _NullResolver(),
          dryRun: true,
          stateBdOverride: BdCliService(stateRunner),
          workBdOverrides: {'proj': BdCliService(workRunner)},
          registryBuilder: (appender) {
            appendWorkNote = appender;
            return builtRegistry;
          },
        );
        addTearDown(work.shutdown);

        expect(identical(work.wiring.registry, builtRegistry), isTrue);

        await appendWorkNote('proj-note1', 'work finding');
        expect(workRunner.calls, [
          <String>[
            'update',
            'proj-note1',
            '--json',
            '--actor',
            'grid-controller',
            '--append-notes',
            'work finding',
          ],
        ]);
        expect(stateRunner.calls, isEmpty);

        await appendWorkNote('tgstate-note1', 'state finding');
        expect(stateRunner.calls, [
          <String>[
            'update',
            'tgstate-note1',
            '--json',
            '--actor',
            'grid-controller',
            '--append-notes',
            'state finding',
          ],
        ]);
        expect(workRunner.calls, hasLength(1));

        await expectLater(
          appendWorkNote('foreign-note1', 'refused finding'),
          throwsA(isA<OwnershipRefused>()),
        );
        expect(stateRunner.calls, hasLength(1));
        expect(workRunner.calls, hasLength(1));
        expect(stateRunner.calls.single, isNot(contains('--metadata')));
        expect(workRunner.calls.single, isNot(contains('--metadata')));
      },
    );

    test('registry and registryBuilder refuse before assembly', () async {
      var builderCalled = false;

      await expectLater(
        assembleStationWork(
          stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
          substations: [
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj'),
          ],
          resolver: const _NullResolver(),
          dryRun: true,
          registry: engine.DefaultCapabilityRegistry(),
          registryBuilder: (_) {
            builderCalled = true;
            return engine.DefaultCapabilityRegistry();
          },
        ),
        throwsA(
          isA<ArgumentError>()
              .having((e) => '${e.message}', 'message', contains('registry'))
              .having(
                (e) => '${e.message}',
                'message',
                contains('registryBuilder'),
              ),
        ),
      );
      expect(builderCalled, isFalse);
    });
  });

  test(
    'station runtime disposes its assembled admission authority once',
    () async {
      _seedStore('${tmp.path}/proj', database: 'pow');
      _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
      final stateRunner = _RecordingBdRunner();
      final runtime = await assembleStationWork(
        stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
        substations: [
          SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj'),
        ],
        resolver: const _NullResolver(),
        dryRun: true,
        stateBdOverride: BdCliService(stateRunner),
      );
      final admission = runtime.wiring.services.admission;
      expect(admission, same(runtime.wiring.services.admission));
      var notifications = 0;
      admission.addInvalidationListener(() => notifications++);

      await runtime.shutdown();
      await runtime.shutdown();

      const bead = Bead(
        id: 'proj-1',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      final result = admission.admitPending(
        engine.JoinedSnapshot(
          graph: GraphSnapshot.fromParts(
            beads: const [bead],
            dependencies: const [],
            readyIds: const {'proj-1'},
            capturedAt: DateTime.utc(2026, 9, 4),
          ),
        ),
        const engine.SubstationConfig(
          substationId: 'proj',
          ownedSubstations: {'proj'},
        ),
        const engine.ServiceBundle(),
        const [engine.StationAdmissionCandidate(bead: bead, session: null)],
      );
      expect(result.admitted, isEmpty);
      expect(result.waiting, isEmpty);
      expect(result.refused.single.clause, 'disposed');
      expect(stateRunner.calls, isEmpty);
      expect(notifications, 0);
    },
  );
}
