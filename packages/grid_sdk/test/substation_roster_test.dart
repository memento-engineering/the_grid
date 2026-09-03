import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart'
    show SessionBeadKeys, SnapshotSource;
import 'package:grid_runtime/grid_runtime.dart'
    show BeadOwnershipPredicate, GridIssueTypes, StationBeadWriter;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _FakeProvisioner implements SubstationProvisioner {
  _FakeProvisioner([Set<String>? owned]) : owned = owned ?? <String>{};

  final Set<String> owned;
  final List<SubstationWorkSpec> provisioned = [];
  final List<String> decommissioned = [];
  Object? provisionError;

  @override
  Set<String> get ownedIdentityTokens => Set.unmodifiable(owned);

  @override
  Future<void> provision(SubstationWorkSpec spec) async {
    if (provisionError case final error?) throw error;
    provisioned.add(spec);
    owned.addAll(<String>{spec.name, spec.prefix});
  }

  @override
  Future<int> decommission(String name) async {
    decommissioned.add(name);
    return 2;
  }
}

final class _FakeBd implements BdRunner, BeadProbeReader {
  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async => BdResult(
    exitCode: 0,
    stdout: '{"schema_version":1,"data":{}}',
    stderr: '',
  );

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async =>
      null;

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const <Bead>[];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async =>
      const <Bead>[];
}

final class _StateSource implements SnapshotSource {
  _StateSource(this.current);

  @override
  GraphSnapshot? current;

  @override
  Stream<GraphSnapshot> get snapshots => Stream<GraphSnapshot>.empty();
}

GraphSnapshot _emptyState() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.utc(2026),
);

final class _Delegate extends GridDelegate {}

void _seedStore(String root) {
  Directory('$root/.beads').createSync(recursive: true);
  File(
    '$root/.beads/metadata.json',
  ).writeAsStringSync('{"dolt_mode":"embedded"}');
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory temp;
  late String root;
  late _FakeProvisioner provisioner;
  late SubstationRoster roster;
  late AttachedRoster current;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('substation-roster-');
    root = '${temp.path}/earth';
    _seedStore(root);
    provisioner = _FakeProvisioner({'state'});
    roster = SubstationRoster(provisioner: provisioner);
    roster.addListener((value) => current = value);
  });

  tearDown(() {
    roster.dispose();
    temp.deleteSync(recursive: true);
  });

  test('clean attach emits one seat and provisions once', () async {
    final result = await roster.attach(name: 'earth', prefix: 'ea', root: root);

    expect(result, isA<RosterAttached>());
    expect(provisioner.provisioned, hasLength(1));
    expect(current.seats.single.spec.name, 'earth');
    expect(current.seats.single.spec.prefix, 'ea');
  });

  for (final collision in <({String name, String prefix})>[
    (name: 'state', prefix: 'ea'),
    (name: 'earth', prefix: 'state'),
  ]) {
    test(
      'collision on ${collision.name}/${collision.prefix} is zero effect',
      () async {
        final result = await roster.attach(
          name: collision.name,
          prefix: collision.prefix,
          root: root,
        );

        expect(
          result,
          isA<RosterRefused>().having(
            (value) => value.code,
            'code',
            'identity_collision',
          ),
        );
        expect(provisioner.provisioned, isEmpty);
        expect(current.seats, isEmpty);
      },
    );
  }

  test('relative and absent roots refuse before provision', () async {
    final relative = await roster.attach(name: 'earth', root: 'relative');
    expect(
      relative,
      isA<RosterRefused>().having(
        (value) => value.code,
        'code',
        'root_invalid',
      ),
    );
    final absent = await roster.attach(
      name: 'earth',
      root: '${temp.path}/absent',
    );
    expect(
      absent,
      isA<RosterRefused>().having(
        (value) => value.code,
        'code',
        'store_absent',
      ),
    );
    expect(provisioner.provisioned, isEmpty);
  });

  test('unparsed store and provision failure leave the roster empty', () async {
    roster.dispose();
    roster = SubstationRoster(
      provisioner: provisioner,
      discoverWorkspace: (_) => null,
    );
    roster.addListener((value) => current = value);
    final unparsed = await roster.attach(name: 'earth', root: root);
    expect(
      unparsed,
      isA<RosterRefused>().having(
        (value) => value.code,
        'code',
        'store_unparsed',
      ),
    );

    roster.dispose();
    provisioner.provisionError = StateError('boom');
    roster = SubstationRoster(provisioner: provisioner);
    roster.addListener((value) => current = value);
    final failed = await roster.attach(name: 'earth', root: root);
    expect(
      failed,
      isA<RosterRefused>().having(
        (value) => value.code,
        'code',
        'provision_failed',
      ),
    );
    expect(current.seats, isEmpty);
  });

  test(
    'detach refuses live sessions; force drains and settles when idle',
    () async {
      await roster.attach(name: 'earth', root: root);
      final refused = await roster.detach(
        name: 'earth',
        inFlightOf: (_) => {'earth-1'},
      );
      expect(
        refused,
        isA<RosterRefused>().having(
          (value) => value.code,
          'code',
          'sessions_live',
        ),
      );
      expect(provisioner.decommissioned, isEmpty);

      final draining = await roster.detach(
        name: 'earth',
        force: true,
        inFlightOf: (_) => {'earth-1'},
      );
      expect(draining, isA<RosterDraining>());
      expect(current.seats.single.drainIds, {'earth-1'});

      await roster.settleDrains(
        () async =>
            (_) => const <String>{},
      );
      await _pump();
      expect(current.seats, isEmpty);
      expect(provisioner.decommissioned, ['earth']);
    },
  );

  test(
    'idle detach finalises and coded or unknown names are not detachable',
    () async {
      final missing = await roster.detach(
        name: 'coded',
        inFlightOf: (_) => const <String>{},
      );
      expect(
        missing,
        isA<RosterRefused>().having(
          (value) => value.code,
          'code',
          'not_attached',
        ),
      );

      await roster.attach(name: 'earth', root: root);
      final detached = await roster.detach(
        name: 'earth',
        inFlightOf: (_) => const <String>{},
      );
      expect(
        detached,
        isA<RosterDetached>().having(
          (value) => value.reapedWorktrees,
          'reaped',
          2,
        ),
      );
    },
  );

  test(
    'a drain shrinks as sessions finish without admitting new work',
    () async {
      await roster.attach(name: 'earth', root: root);
      await roster.detach(
        name: 'earth',
        force: true,
        inFlightOf: (_) => {'earth-1', 'earth-2'},
      );

      await roster.settleDrains(
        () async =>
            (_) => {'earth-2'},
      );

      expect(current.seats.single.drainIds, {'earth-2'});
      expect(provisioner.decommissioned, isEmpty);
    },
  );

  test(
    'liveWorkBeadsFor strips rework suffixes and ignores closed sessions',
    () {
      final snapshot = GraphSnapshot.fromParts(
        beads: [
          Bead(
            id: 'state-1',
            issueType: GridIssueTypes.session,
            metadata: const {SessionBeadKeys.workBead: 'ea-7#r2'},
          ),
          Bead(
            id: 'state-2',
            issueType: GridIssueTypes.session,
            status: BeadStatus.closed,
            metadata: const {SessionBeadKeys.workBead: 'ea-8'},
          ),
          Bead(
            id: 'state-3',
            issueType: GridIssueTypes.session,
            metadata: const {SessionBeadKeys.workBead: 'moon-1'},
          ),
        ],
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime.utc(2026),
      );

      expect(
        liveWorkBeadsFor(
          SubstationWorkSpec(name: 'earth', root: root, prefix: 'ea'),
          snapshot,
        ),
        {'ea-7'},
      );
    },
  );

  test(
    'GridDelegate mirrors attached seats into its live status roster',
    () async {
      final delegate = _Delegate();
      addTearDown(delegate.dispose);
      delegate.resolveArmedRoster(
        coded: [SubstationWorkSpec(name: 'coded', root: root, prefix: 'co')],
        appended: const [],
        onSkip: (_) {},
      );
      provisioner.owned.addAll({'coded', 'co'});
      delegate.observeSubstationRoster(roster);

      await roster.attach(name: 'earth', root: root);

      expect(delegate.attachedRoster.map((seat) => seat.name), ['earth']);
      expect(delegate.liveRoster.map((seat) => seat.name), ['coded', 'earth']);
      expect(delegate.armedRoster.map((seat) => seat.name), ['coded']);
    },
  );

  test('settleDrains resolves no probe when no seat is draining', () async {
    await roster.attach(name: 'earth', root: root);
    var resolved = 0;

    await roster.settleDrains(() async {
      resolved++;
      return (_) => const <String>{};
    });

    expect(resolved, 0, reason: 'an idle roster costs no store read');
    expect(current.seats, hasLength(1));
    expect(provisioner.decommissioned, isEmpty);
  });

  test(
    'settleDrains resolves the probe once when a seat is draining',
    () async {
      await roster.attach(name: 'earth', root: root);
      await roster.detach(
        name: 'earth',
        force: true,
        inFlightOf: (_) => {'earth-1'},
      );
      var resolved = 0;

      await roster.settleDrains(() async {
        resolved++;
        return (_) => const <String>{};
      });

      expect(resolved, 1, reason: 'the laziness must not be vacuous');
      expect(current.seats, isEmpty);
      expect(provisioner.decommissioned, ['earth']);
    },
  );

  test(
    'a post-flush settle performs zero state-store requeries when idle',
    () async {
      var refreshes = 0;
      final bd = _FakeBd();
      final handler = StationCommandHandler(
        stateSource: _StateSource(_emptyState()),
        refreshState: () async => refreshes++,
        stateWriter: StationBeadWriter(
          bd: BdCliService(bd),
          reader: bd,
          ownership: BeadOwnershipPredicate({'state'}),
        ),
        stateOwnership: BeadOwnershipPredicate({'state'}),
        workStoresByIdentity: const <String, WorkCommandStore>{},
      )..bindRoster(roster);
      await roster.attach(name: 'earth', root: root);

      await handler.settleRosterDrains();
      expect(refreshes, 0, reason: 'no seat drains — no store round trip');

      await roster.detach(
        name: 'earth',
        force: true,
        inFlightOf: (_) => {'earth-1'},
      );
      await handler.settleRosterDrains();

      expect(refreshes, 1, reason: 'a draining seat costs exactly one requery');
      expect(provisioner.decommissioned, ['earth']);
    },
  );
}
