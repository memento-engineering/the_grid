import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart' show BeadWorktree, RootCheckout;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _FakeProvisioner implements SubstationProvisioner {
  final Set<String> owned = {'coded', 'co', 'state'};
  var provisions = 0;
  var decommissions = 0;

  @override
  Set<String> get ownedIdentityTokens => Set.unmodifiable(owned);

  @override
  Future<void> provision(SubstationWorkSpec spec) async {
    provisions++;
    owned.addAll({spec.name, spec.prefix});
  }

  @override
  Future<int> decommission(String name) async {
    decommissions++;
    return 0;
  }
}

final class _BuildProbe extends SingleChildStatelessSeed {
  // ignore: unused_element_parameter
  const _BuildProbe(this.builds, {super.child, super.key});
  final List<Set<String>> builds;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    builds.add(context.watch<SubstationDrain>()?.beadIds ?? const {});
    return child;
  }
}

final class _DisposeProbe extends StatefulSeed {
  const _DisposeProbe(this.onDispose);
  final void Function() onDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

final class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() => seed.onDispose();

  @override
  Seed build(TreeContext context) => const _Leaf();
}

final class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

final class _RecordingResolver implements engine.SessionResolver {
  final List<String> mounted = [];

  @override
  Seed sessionFor({required Bead bead, engine.SessionProjection? session}) {
    mounted.add(bead.id);
    return const _Leaf();
  }
}

/// A dry git service whose worktree listing THROWS — the injection point that
/// makes a drain settle fail, because `StationWorkRuntime.decommission` lists
/// a detached seat's worktrees before reaping them.
final class _ThrowingDryGit extends DryStationGitService {
  var listings = 0;
  var throwing = false;

  @override
  Future<List<BeadWorktree>?> listBeadWorktrees(RootCheckout root) async {
    if (!throwing) return super.listBeadWorktrees(root);
    listings++;
    throw StateError('worktree listing exploded');
  }
}

engine.JoinedSnapshot _snapshot(Set<String> ready) => engine.JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [
      const Bead(id: 'ea-1', issueType: IssueType.task),
      const Bead(id: 'ea-2', issueType: IssueType.task),
    ],
    dependencies: const [],
    readyIds: ready,
    capturedAt: DateTime.utc(2026),
  ),
  sessionsByWorkBead: const {},
);

final class _LiveRosterDelegate extends GridDelegate {
  _LiveRosterDelegate({
    required this.roster,
    required this.wiring,
    required this.codedBuilds,
    required this.attachedBuilds,
    required this.disposals,
  });

  final SubstationRoster roster;
  final StationWorkWiring wiring;
  final List<int> codedBuilds;
  final List<Set<String>> attachedBuilds;
  final List<String> disposals;
  var boots = 0;

  @override
  Future<void> boot(GridConfiguration configuration) async => boots++;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) =>
      RawAssetGrid(
        root: '/grid',
        assets: [
          Station(
            name: 'station',
            assets: [
              Nest(
                children: [StationWork(wiring: wiring)],
                child: SubstationRosterScope(
                  roster: roster,
                  child: Substations(
                    substations: [
                      Substation(
                        'coded',
                        '/coded',
                        prefix: 'co',
                        assets: [
                          _CodedProbe(
                            codedBuilds,
                            key: const ValueKey('coded'),
                          ),
                        ],
                      ),
                      AttachedSubstations(
                        builder: (seat) => Substation(
                          seat.spec.name,
                          seat.spec.root,
                          prefix: seat.spec.prefix,
                          assets: [
                            Nest(
                              children: [
                                _BuildProbe(
                                  attachedBuilds,
                                  key: ValueKey('probe:${seat.spec.name}'),
                                ),
                              ],
                              child: const SubstationWork(),
                            ),
                            _DisposeProbe(() => disposals.add(seat.spec.name)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
}

final class _CodedProbe extends StatelessSeed {
  const _CodedProbe(this.builds, {super.key});
  final List<int> builds;

  @override
  Seed build(TreeContext context) {
    builds.add(1);
    return const _Leaf();
  }
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

Future<void> _pumpUntilIo(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

/// Drains the microtask/event queue so a fire-and-forget settle has completed.
Future<void> _pumpSettled() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void _seedStore(String root, {String? database}) {
  Directory('$root/.beads').createSync(recursive: true);
  File('$root/.beads/metadata.json').writeAsStringSync(
    database == null
        ? '{"dolt_mode":"embedded"}'
        : '{"dolt_mode":"embedded","dolt_database":"$database"}',
  );
}

Future<void> _initializeStore(String root, {required String database}) async {
  Directory(root).createSync(recursive: true);
  final result = await Process.run('bd', [
    'init',
    '--non-interactive',
    '--quiet',
    '--skip-agents',
    '--skip-hooks',
    '--prefix',
    database,
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('bd init failed: ${result.stderr}');
  }
}

void main() {
  test('attach mounts the new seat frontier without a restart', () async {
    final temp = Directory.systemTemp.createTempSync('attach-live-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final root = '${temp.path}/earth';
    _seedStore(root);
    final provisioner = _FakeProvisioner();
    final roster = SubstationRoster(provisioner: provisioner);
    addTearDown(roster.dispose);
    final codedBuilds = <int>[];
    final attachedBuilds = <Set<String>>[];
    final disposals = <String>[];
    final resolver = _RecordingResolver();
    final notifier = engine.JoinedSnapshotNotifier(_snapshot({'ea-1'}));
    final delegate = _LiveRosterDelegate(
      roster: roster,
      wiring: StationWorkWiring(
        notifier: notifier,
        services: buildFakes().ctx,
        resolver: resolver,
      ),
      codedBuilds: codedBuilds,
      attachedBuilds: attachedBuilds,
      disposals: disposals,
    );
    final grid = await runGrid(delegate);
    addTearDown(grid.teardown);
    final codedBefore = codedBuilds.length;

    await roster.attach(name: 'earth', prefix: 'ea', root: root);
    await _pumpUntil(() => attachedBuilds.isNotEmpty);

    expect(provisioner.provisions, 1);
    expect(delegate.boots, 1, reason: 'the process was never restarted');
    expect(codedBuilds, hasLength(codedBefore));
    expect(attachedBuilds.last, isEmpty);
    expect(resolver.mounted, contains('ea-1'));
  });

  test('detach unmounts the seat and decommissions it', () async {
    final temp = Directory.systemTemp.createTempSync('detach-live-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final root = '${temp.path}/earth';
    _seedStore(root);
    final provisioner = _FakeProvisioner();
    final roster = SubstationRoster(provisioner: provisioner);
    addTearDown(roster.dispose);
    final codedBuilds = <int>[];
    final attachedBuilds = <Set<String>>[];
    final disposals = <String>[];
    final resolver = _RecordingResolver();
    final grid = await runGrid(
      _LiveRosterDelegate(
        roster: roster,
        wiring: StationWorkWiring(
          notifier: engine.JoinedSnapshotNotifier(_snapshot({'ea-1'})),
          services: buildFakes().ctx,
          resolver: resolver,
        ),
        codedBuilds: codedBuilds,
        attachedBuilds: attachedBuilds,
        disposals: disposals,
      ),
    );
    addTearDown(grid.teardown);
    await roster.attach(name: 'earth', root: root);
    await _pumpUntil(() => attachedBuilds.isNotEmpty);
    final codedBefore = codedBuilds.length;

    await roster.detach(name: 'earth', inFlightOf: (_) => const <String>{});
    await _pumpUntil(() => disposals.contains('earth'));

    expect(provisioner.decommissions, 1);
    expect(codedBuilds, hasLength(codedBefore));
  });

  test('draining keeps the seat and narrows its observed work ids', () async {
    final temp = Directory.systemTemp.createTempSync('drain-live-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final root = '${temp.path}/earth';
    _seedStore(root);
    final provisioner = _FakeProvisioner();
    final roster = SubstationRoster(provisioner: provisioner);
    addTearDown(roster.dispose);
    final builds = <Set<String>>[];
    final resolver = _RecordingResolver();
    final notifier = engine.JoinedSnapshotNotifier(_snapshot({'ea-1'}));
    final grid = await runGrid(
      _LiveRosterDelegate(
        roster: roster,
        wiring: StationWorkWiring(
          notifier: notifier,
          services: buildFakes().ctx,
          resolver: resolver,
        ),
        codedBuilds: [],
        attachedBuilds: builds,
        disposals: [],
      ),
    );
    addTearDown(grid.teardown);
    await roster.attach(name: 'earth', root: root);
    await _pumpUntil(() => builds.isNotEmpty);

    await roster.detach(
      name: 'earth',
      force: true,
      inFlightOf: (_) => {'ea-1'},
    );
    await _pumpUntil(() => builds.any((ids) => ids.contains('ea-1')));
    notifier.push(_snapshot({'ea-1', 'ea-2'}));
    await Future<void>.delayed(Duration.zero);

    expect(builds.last, {'ea-1'});
    expect(resolver.mounted, isNot(contains('ea-2')));
    expect(provisioner.decommissions, 0);
  });

  test(
    'a throwing drain settle is reported LOUD and flushing continues',
    // Integration tier: assembleStationWork needs a REAL state store, so this
    // shells out to `bd init` — absent on the unit-tier CI runner.
    tags: ['integration'],
    () async {
      final temp = Directory.systemTemp.createTempSync('settle-guard-');
      addTearDown(() => temp.deleteSync(recursive: true));
      await _initializeStore('${temp.path}/home/.grid', database: 'tgstate');
      _seedStore('${temp.path}/proj', database: 'proj');
      _seedStore('${temp.path}/earth', database: 'earth');
      final refusals = <String>[];
      final git = _ThrowingDryGit();
      final work = await assembleStationWork(
        stateStore: GridStateStore.forGridRoot('${temp.path}/home'),
        substations: [
          SubstationWorkSpec(name: 'proj', root: '${temp.path}/proj'),
        ],
        resolver: _RecordingResolver(),
        dryRun: true,
        gitOverride: git,
        onRefusal: refusals.add,
      );
      addTearDown(work.shutdown);
      await work.start();
      refusals.clear();
      git.throwing = true;

      // An IDLE roster: the settle must be a no-op, so the guard is not yet
      // exercised and no refusal is emitted.
      work.afterFlush();
      await _pumpSettled();
      expect(refusals, isEmpty);
      expect(git.listings, 0);

      // Now a seat that drains and immediately goes idle: the settle finalises
      // it, decommission lists worktrees, the listing throws.
      final attached = await work.roster.attach(
        name: 'earth',
        root: '${temp.path}/earth',
      );
      expect(attached, isA<RosterAttached>());
      final draining = await work.roster.detach(
        name: 'earth',
        force: true,
        inFlightOf: (_) => {'earth-1'},
      );
      expect(draining, isA<RosterDraining>());
      work.afterFlush();
      await _pumpUntilIo(() => refusals.isNotEmpty);

      expect(git.listings, 1);
      expect(refusals.single, contains('roster drain settle failed'));
      expect(refusals.single, contains('worktree listing exploded'));

      // The station keeps flushing: the seat left the roster before the throw,
      // so the next flush settles nothing, raises nothing, and adds no refusal.
      work.afterFlush();
      await _pumpSettled();
      expect(refusals, hasLength(1));
    },
  );
}
