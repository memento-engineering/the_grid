import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';
import 'package:grid_engine/src/seeds/provider.dart';

final class _ThrowingTrust implements Trust {
  var calls = 0;

  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) {
    calls++;
    throw StateError('levelOf must stay off the mount path');
  }
}

final class _RecordingTransport implements ExplorationTransport {
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map.unmodifiable(data)));
  }
}

final class _RecordingResolver implements SessionResolver {
  final mounted = <String>[];

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) {
    mounted.add(bead.id);
    return const Idle();
  }
}

Bead _bead(String id, [Map<String, dynamic> metadata = const {}]) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.open,
  metadata: metadata,
);

Map<String, dynamic> _stamp(String level) => {
  OriginTrustKeys.scheme: 'github',
  OriginTrustKeys.actor: 'octocat',
  OriginTrustKeys.level: level,
};

JoinedSnapshot _snapshot(Bead bead, [int second = 0]) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [bead],
    dependencies: const [],
    readyIds: {bead.id},
    capturedAt: DateTime(2026, 1, 1, 0, 0, second),
  ),
  sessionsByWorkBead: const {},
);

SubstationConfigNotifier _config(String id) => SubstationConfigNotifier(
  SubstationConfig(
    substationId: id,
    ownedSubstations: const {'tg'},
    maxConcurrentWork: 10,
  ),
);

Seed _root({
  required JoinedSnapshotNotifier joined,
  required SessionResolver resolver,
  required List<SubstationScope> scopes,
}) => InheritedSeed<StationServices>(
  value: buildFakes().ctx,
  child: InheritedSeed<JoinedSnapshotNotifier>(
    value: joined,
    child: InheritedSeed<SessionResolver>(
      value: resolver,
      child: Station(scopes),
    ),
  ),
);

List<WorkBead> _workBeads(Branch root) {
  final found = <WorkBead>[];
  void walk(Branch branch) {
    if (branch.seed case final WorkBead bead) found.add(bead);
    branch.visitChildren(walk);
  }

  walk(root);
  return found;
}

Future<void> _settleAdmissions(TreeOwner owner) async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
    owner.flush();
  }
}

void main() {
  test(
    'the origin floor is isolated at each substation mount boundary',
    () async {
      final bead = _bead('tg-1', _stamp('external'));
      final joined = JoinedSnapshotNotifier(_snapshot(bead));
      final strictTrust = _ThrowingTrust();
      final strictTransport = _RecordingTransport();
      final legacyTransport = _RecordingTransport();
      final resolver = _RecordingResolver();
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final root = owner.mountRoot(
        ProviderScope(
          child: _root(
            joined: joined,
            resolver: resolver,
            scopes: [
              SubstationScope(
                configNotifier: _config('strict'),
                services: ServiceBundle(
                  trust: strictTrust,
                  trustFloor: const TrustFloor(TrustLevel.trusted),
                  transport: strictTransport,
                ),
                key: const ValueKey('strict'),
              ),
              SubstationScope(
                configNotifier: _config('legacy'),
                services: ServiceBundle(transport: legacyTransport),
                key: const ValueKey('legacy'),
              ),
            ],
          ),
        ),
      );
      await _settleAdmissions(owner);

      expect(_workBeads(root).map((work) => work.bead.id), ['tg-1']);
      expect(resolver.mounted, ['tg-1']);
      expect(strictTrust.calls, 0);
      expect(legacyTransport.flares, isEmpty);
      expect(strictTransport.flares, hasLength(1));
      expect(strictTransport.flares.single.name, 'work.trustRefused');
      expect(strictTransport.flares.single.data, {
        'beadId': 'tg-1',
        'origin': 'github:octocat',
        'floor': 'trusted',
        'reason':
            'grid: tg-1 origin trust external is below floor trusted — '
            'excluding tg-1 from ready.',
      });

      joined.push(_snapshot(bead, 1));
      owner.flush();
      expect(strictTransport.flares, hasLength(1));
      expect(strictTrust.calls, 0);
    },
  );

  for (final scenario in [
    (name: 'unstamped', metadata: <String, dynamic>{}),
    (name: 'at-floor', metadata: _stamp('trusted')),
  ]) {
    test('${scenario.name} work mounts with configured trust', () async {
      final bead = _bead('tg-1', scenario.metadata);
      final trust = _ThrowingTrust();
      final joined = JoinedSnapshotNotifier(_snapshot(bead));
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        ProviderScope(
          child: _root(
            joined: joined,
            resolver: _RecordingResolver(),
            scopes: [
              SubstationScope(
                configNotifier: _config('strict'),
                services: ServiceBundle(
                  trust: trust,
                  trustFloor: const TrustFloor(TrustLevel.trusted),
                ),
              ),
            ],
          ),
        ),
      );
      await _settleAdmissions(owner);
      expect(_workBeads(root).map((work) => work.bead.id), ['tg-1']);
      expect(trust.calls, 0);
    });
  }

  test('the station join remains trust-ignorant', () {
    final source = File(
      'lib/src/bridge/station_join_bridge.dart',
    ).readAsStringSync();
    for (final forbidden in [
      'Trust',
      'trustFloor',
      'applyTrustGuard',
      'OriginTrust',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
