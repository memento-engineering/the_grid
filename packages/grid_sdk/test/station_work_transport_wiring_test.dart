import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart' hide Substation;
import 'package:grid_engine/testing.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _SourceControl implements SourceControl {
  const _SourceControl();

  @override
  String get baseBranch => 'main';

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}

  @override
  String workspaceFor(String beadId) => '/tmp/$beadId';
}

final class _Trust implements Trust {
  const _Trust();

  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) async => TrustLevel.self;
}

final class _BundleProbe extends StatelessSeed {
  const _BundleProbe(this.seen, {super.key});

  final List<ServiceBundle> seen;

  @override
  Seed build(TreeContext context) {
    seen.add(context.watch<ServiceBundle>()!);
    return const Idle();
  }
}

final class _ProbeResolver implements SessionResolver {
  const _ProbeResolver(this.seen);

  final List<ServiceBundle> seen;

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      _BundleProbe(seen, key: ValueKey<String>('${bead.id}:probe'));
}

JoinedSnapshot _readySnapshot() => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [
      Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open),
    ],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime.utc(2026, 8, 9),
  ),
  sessionsByWorkBead: const {},
);

ServiceBundle _mount({
  required ServiceBundle existingBundle,
  required ExplorationTransport? transport,
}) {
  final seen = <ServiceBundle>[];
  final joined = JoinedSnapshotNotifier(_readySnapshot());
  final fakes = buildFakes();
  final owner = TreeOwner();
  owner.mountRoot(
    ProviderScope(
      child: Provider<ServiceBundle>.value(
        existingBundle,
        child: StationWork(
          wiring: StationWorkWiring(
            notifier: joined,
            services: fakes.ctx,
            resolver: _ProbeResolver(seen),
            transport: transport,
          ),
          child: Substation(
            'the_grid',
            '/tmp/the_grid',
            prefix: 'tg',
            assets: const [SubstationWork()],
          ),
        ),
      ),
    ),
  );
  owner.flush();
  addTearDown(owner.dispose);
  expect(seen, hasLength(1));
  return seen.single;
}

void main() {
  test('assembled transport reaches the substation capability bundle', () {
    const sourceControl = _SourceControl();
    final delivery = RecordingDeliveryMethod();
    final escalation = RecordingEscalationHandler();
    const trust = _Trust();
    const trustFloor = TrustFloor(TrustLevel.self);
    final transport = RecordingExplorationTransport();
    MountEligibilityDecision mountEligibility(Bead bead) =>
        const MountEligibilityDecision.eligible();
    final existingBundle = ServiceBundle(
      sourceControl: sourceControl,
      delivery: delivery,
      escalation: escalation,
      trust: trust,
      trustFloor: trustFloor,
      mountEligibility: mountEligibility,
    );

    final seen = _mount(existingBundle: existingBundle, transport: transport);

    expect(seen.transport, same(transport));
    expect(seen.sourceControl, same(sourceControl));
    expect(seen.delivery, same(delivery));
    expect(seen.escalation, same(escalation));
    expect(seen.trust, same(trust));
    expect(seen.trustFloor, trustFloor);
    // The 2026-08-21 incident, pinned at the CONSUMER position: the seat
    // composed a mount predicate and THIS wrapper (the nearest bundle above
    // WorkList) hand-copied every field EXCEPT the newest, so the gate tested
    // green one level up while an unapproved, plan-less bead mounted in 2s.
    // A new ServiceBundle field that is not threaded through the transport
    // re-provision never reaches WorkList — this assertion is the tripwire.
    expect(
      seen.mountEligibility,
      same(mountEligibility),
      reason:
          'the transport overlay must DERIVE, never drop — a dropped '
          'field silently disarms whatever the seat composed',
    );
  });

  test(
    'transport overlay preserves the substation bundle and null is identity',
    () {
      const existingBundle = ServiceBundle(
        trustFloor: TrustFloor(TrustLevel.external),
      );

      final seen = _mount(existingBundle: existingBundle, transport: null);

      expect(seen, same(existingBundle));
    },
  );

  test('assembleStationWork retains its transport on the returned wiring', () {
    final source = File('lib/src/work/work_assembly.dart').readAsStringSync();
    final start = source.indexOf('wiring: StationWorkWiring(');
    expect(start, isNonNegative);
    final end = source.indexOf('\n    ),', start);
    expect(end, greaterThan(start));
    final wiringBlock = source.substring(start, end);
    expect(wiringBlock, contains('transport: transport,'));
  });
}
