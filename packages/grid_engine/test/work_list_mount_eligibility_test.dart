import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:test/test.dart';

final class _MutableEligibility {
  MountEligibilityDecision decision = const MountEligibilityDecision.eligible();

  MountEligibilityDecision call(Bead bead) => decision;
}

final class _RecordingTransport implements ExplorationTransport {
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map.unmodifiable(data)));
  }
}

final class _ThrowingTransport implements ExplorationTransport {
  @override
  void flare(String name, Map<String, String> data) {
    throw StateError('transport unavailable');
  }
}

final class _RecordingResolver implements SessionResolver {
  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

final class _Harness {
  _Harness({
    required this.owner,
    required this.root,
    required this.joined,
    required this.bead,
  });

  final TreeOwner owner;
  final Branch root;
  final JoinedSnapshotNotifier joined;
  final Bead bead;
  var _second = 1;

  void pushAndFlush() {
    joined.push(_snapshot(bead, _second++));
    owner.flush();
  }

  List<WorkBead> workBeads() => _workBeads(root);
}

Bead _task() =>
    const Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _snapshot(Bead bead, int second) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [bead],
    dependencies: const [],
    readyIds: {bead.id},
    capturedAt: DateTime(2026, 1, 1, 0, 0, second),
  ),
  sessionsByWorkBead: const {},
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

_Harness _mountHarness({
  MountEligibilityPredicate? mountEligibility,
  ExplorationTransport? transport,
}) {
  final bead = _task();
  final joined = JoinedSnapshotNotifier(_snapshot(bead, 0));
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<SessionResolver>(
          value: _RecordingResolver(),
          child: Station([
            SubstationScope(
              configNotifier: SubstationConfigNotifier(
                const SubstationConfig(
                  substationId: 'test',
                  ownedSubstations: {'tg'},
                  maxConcurrentWork: 10,
                ),
              ),
              services: ServiceBundle(
                transport: transport,
                mountEligibility: mountEligibility,
              ),
            ),
          ]),
        ),
      ),
    ),
  );
  addTearDown(owner.dispose);
  return _Harness(owner: owner, root: root, joined: joined, bead: bead);
}

void main() {
  test('refusal edges exclude work and carry bead id plus clause', () {
    final eligibility = _MutableEligibility();
    final transport = _RecordingTransport();
    final harness = _mountHarness(
      mountEligibility: eligibility.call,
      transport: transport,
    );

    eligibility.decision = const MountEligibilityDecision.refused(
      clause: 'required-field',
    );
    harness.pushAndFlush();
    expect(harness.workBeads(), isEmpty);
    expect(transport.flares, hasLength(1));
    expect(transport.flares.single.name, 'work.mountEligibilityRefused');
    expect(transport.flares.single.data, {
      'beadId': 'tg-1',
      'clause': 'required-field',
    });

    harness.pushAndFlush();
    expect(transport.flares, hasLength(1));

    eligibility.decision = const MountEligibilityDecision.refused(
      clause: 'approval',
    );
    harness.pushAndFlush();
    expect(transport.flares, hasLength(1));

    eligibility.decision = const MountEligibilityDecision.eligible();
    harness.pushAndFlush();
    expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
    expect(transport.flares.last.name, 'work.mountEligibilityRestored');
    expect(transport.flares.last.data, {
      'beadId': 'tg-1',
      'clause': 'approval',
    });

    eligibility.decision = const MountEligibilityDecision.refused(
      clause: 'required-field',
    );
    harness.pushAndFlush();
    expect(transport.flares.last.name, 'work.mountEligibilityRefused');
    expect(transport.flares, hasLength(3));
  });

  test('null predicate preserves mounting', () {
    final harness = _mountHarness(mountEligibility: null);
    expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
  });

  test('null and throwing transports do not break eligibility edges', () {
    for (final transport in <ExplorationTransport?>[
      null,
      _ThrowingTransport(),
    ]) {
      final eligibility = _MutableEligibility();
      final harness = _mountHarness(
        mountEligibility: eligibility.call,
        transport: transport,
      );
      eligibility.decision = const MountEligibilityDecision.refused(
        clause: 'required-field',
      );
      expect(harness.pushAndFlush, returnsNormally);
      expect(harness.workBeads(), isEmpty);
      eligibility.decision = const MountEligibilityDecision.eligible();
      expect(harness.pushAndFlush, returnsNormally);
      expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
    }
  });

  test('the public seam is exported and the join bridge stays ignorant', () {
    final barrel = File('lib/grid_engine.dart').readAsStringSync();
    final bridge = File(
      'lib/src/bridge/station_join_bridge.dart',
    ).readAsStringSync();
    expect(barrel, contains("export 'src/domain/mount_eligibility.dart';"));
    expect(bridge, isNot(contains('MountEligibility')));
    expect(bridge, isNot(contains('mountEligibility')));
  });

  test(
    'the new engine surface contains no assets convention or competing name',
    () {
      final sources = [
        File('lib/src/domain/mount_eligibility.dart').readAsStringSync(),
        File('lib/src/seeds/work_list.dart').readAsStringSync(),
        File('lib/src/sdk/capability.dart').readAsStringSync(),
      ].join('\n');
      expect(sources, isNot(contains('validation_plan')));
      expect(sources, isNot(contains('package:grid_assets')));
      expect(
        File('lib/src/domain/mount_eligibility.dart').readAsStringSync(),
        isNot(contains('DriveabilityPredicate')),
      );
    },
  );
}
