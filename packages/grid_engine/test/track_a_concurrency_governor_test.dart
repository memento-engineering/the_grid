// Track A — the concurrency governor (tg-42f, declare-and-check; ADR-0008 D8's
// general per-leaf `DartEnvironment` permit governor is a separate, deferred
// track): `WorkList` mounts at most N work beads per substation, with a
// station-wide cap ABOVE that. A bead beyond the budget stays ready-unmounted
// (no session, no spawn, no cost) and mounts on the natural reconcile once a
// slot frees — a LOUD flare (count + which beads wait) fires whenever a build
// throttles. Zero I/O — fakes only.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _Recorder {
  final List<String> events = [];
  void record(String event) => events.add(event);
}

class _FakeSessionResolver implements SessionResolver {
  _FakeSessionResolver(this.recorder);
  final _Recorder recorder;

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      _FakeEffect(
        recorder: recorder,
        beadId: bead.id,
        key: ValueKey('${bead.id}:work'),
      );
}

class _FakeEffect extends StatefulSeed {
  const _FakeEffect({required this.recorder, required this.beadId, super.key});
  final _Recorder recorder;
  final String beadId;

  @override
  State<_FakeEffect> createState() => _FakeEffectState();
}

class _FakeEffectState extends State<_FakeEffect> {
  @override
  void initState() => seed.recorder.record('START work(${seed.beadId})');

  @override
  void dispose() => seed.recorder.record('STOP work(${seed.beadId})');

  @override
  Seed build(TreeContext context) => const Idle();
}

/// A recording emit-only transport — records every flare in call order.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];
  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

Bead _bead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: ready,
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
);

Seed _root({
  required JoinedSnapshotNotifier joined,
  required SessionResolver resolver,
  required SubstationConfigNotifier substationConfig,
  ServiceBundle services = const ServiceBundle(),
  StationServices? stationServices,
}) {
  Seed root = InheritedSeed<JoinedSnapshotNotifier>(
    value: joined,
    child: InheritedSeed<SessionResolver>(
      value: resolver,
      child: Station([
        SubstationScope(
          configNotifier: substationConfig,
          services: services,
          key: const ValueKey('scope.tg'),
        ),
      ]),
    ),
  );
  if (stationServices != null) {
    root = InheritedSeed<StationServices>(value: stationServices, child: root);
  }
  return root;
}

void main() {
  group('Track A — the concurrency governor (tg-42f)', () {
    test('N+2 ready beads (no session) -> only N mount, LOUD flare names the '
        'count + the waiting beads', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2'), _bead('tg-3'), _bead('tg-4')],
          ready: {'tg-1', 'tg-2', 'tg-3', 'tg-4'},
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeSessionResolver(recorder),
          substationConfig: SubstationConfigNotifier(
            const SubstationConfig(
              substationId: 'tg',
              ownedSubstations: {'tg'},
              maxConcurrentWork: 2,
            ),
          ),
          services: ServiceBundle(transport: transport),
        ),
      );

      // Only the two LOWEST-id beads mount — deterministic admission order.
      expect(recorder.events, ['START work(tg-1)', 'START work(tg-2)']);
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.throttled');
      expect(transport.flares.single.data, {
        'count': '2',
        'beadIds': 'tg-3,tg-4',
      });
    });

    test('a mounted session closing frees a slot — the next waiting bead mounts '
        'on the natural reconcile; a bead with a STILL-live session is never '
        'evicted for budget reasons', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final beads = [
        _bead('tg-1'),
        _bead('tg-2'),
        _bead('tg-3'),
        _bead('tg-4'),
      ];
      final joined = JoinedSnapshotNotifier(
        _joined(beads: beads, ready: {'tg-1', 'tg-2', 'tg-3', 'tg-4'}),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeSessionResolver(recorder),
          substationConfig: SubstationConfigNotifier(
            const SubstationConfig(
              substationId: 'tg',
              ownedSubstations: {'tg'},
              maxConcurrentWork: 2,
            ),
          ),
          services: ServiceBundle(transport: transport),
        ),
      );
      expect(recorder.events, ['START work(tg-1)', 'START work(tg-2)']);
      recorder.events.clear();
      transport.flares.clear();

      // tg-1's session closes (a positive terminal); tg-2 carries a STILL-live
      // session (proving it is preserved regardless of id order, not just
      // because it happens to sort first).
      joined.push(
        _joined(
          beads: beads,
          ready: {'tg-1', 'tg-2', 'tg-3', 'tg-4'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              isTerminal: true,
            ),
            'tg-2': const SessionProjection(
              workBeadId: 'tg-2',
              isTerminal: false,
            ),
          },
        ),
      );
      owner.flush();

      // tg-1 unmounts (positive terminal); tg-3 — the lowest-id WAITING bead —
      // takes the freed slot. tg-2 is untouched: no STOP/START for it (its
      // WorkBead reconciles in place, same key, live session preserved). Order
      // between the mount and the unmount is the reconciler's own detail, not
      // the governor's contract — assert the SET of events, not the order.
      expect(recorder.events.toSet(), {'STOP work(tg-1)', 'START work(tg-3)'});
      expect(recorder.events, hasLength(2));
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.throttled');
      expect(transport.flares.single.data, {'count': '1', 'beadIds': 'tg-4'});
    });

    test('a substation override CANNOT raise the station-wide ceiling — the '
        'ambient StationServices default/ceiling wins the min()', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2'), _bead('tg-3')],
          ready: {'tg-1', 'tg-2', 'tg-3'},
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeSessionResolver(recorder),
          substationConfig: SubstationConfigNotifier(
            const SubstationConfig(
              substationId: 'tg',
              ownedSubstations: {'tg'},
              // The substation asks for 5 — well above the station ceiling.
              maxConcurrentWork: 5,
            ),
          ),
          services: ServiceBundle(transport: transport),
          stationServices: StationServices(
            provider: FakeRuntimeProvider(),
            writer: StationBeadWriter(
              bd: BdCliService(RecordingBdRunner()),
              ownership: BeadOwnershipPredicate(const {'tg'}),
            ),
            stateSubstation: 'tg',
            maxConcurrentWork: 2,
          ),
        ),
      );

      expect(recorder.events, ['START work(tg-1)', 'START work(tg-2)']);
      expect(transport.flares.single.data, {'count': '1', 'beadIds': 'tg-3'});
    });

    test('no throttling ⇒ no flare at all (the quiet path)', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_bead('tg-1')], ready: {'tg-1'}),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeSessionResolver(recorder),
          substationConfig: SubstationConfigNotifier(
            const SubstationConfig(
              substationId: 'tg',
              ownedSubstations: {'tg'},
              maxConcurrentWork: 2,
            ),
          ),
          services: ServiceBundle(transport: transport),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);
      expect(transport.flares, isEmpty);
    });
  });
}
