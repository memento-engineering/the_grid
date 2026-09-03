import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _Recorder {
  final List<String> events = [];
  final List<String?> handedSessionIds = [];
}

class _FakeSessionResolver implements SessionResolver {
  _FakeSessionResolver(this.recorder);

  final _Recorder recorder;

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) {
    recorder.handedSessionIds.add(session?.sessionId);
    return _FakeEffect(
      recorder: recorder,
      beadId: bead.id,
      key: ValueKey('${bead.id}:work'),
    );
  }
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
  void initState() => seed.recorder.events.add('START work(${seed.beadId})');

  @override
  void dispose() => seed.recorder.events.add('STOP work(${seed.beadId})');

  @override
  Seed build(TreeContext context) => const Idle();
}

class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

Bead _bead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

SessionProjection _session(
  String workBeadId, {
  required String sessionId,
  SessionPauseState pauseState = SessionPauseState.none,
  bool isTerminal = false,
  bool completed = false,
}) => SessionProjection(
  workBeadId: workBeadId,
  sessionId: sessionId,
  pauseState: pauseState,
  isTerminal: isTerminal,
  completed: completed,
);

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

StationServices _stationServices({required int maxConcurrentWork}) =>
    StationServices(
      provider: FakeRuntimeProvider(),
      writer: StationBeadWriter(
        bd: BdCliService(RecordingBdRunner()),
        reader: RecordingBdRunner(),
        ownership: BeadOwnershipPredicate(const {'tg'}),
      ),
      stateSubstation: 'tg',
      maxConcurrentWork: maxConcurrentWork,
    );

void main() {
  group('pause and resume at the mount boundary', () {
    test('pause unmounts the branch and frees its slot', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2')],
          ready: {'tg-1', 'tg-2'},
          sessions: {'tg-1': _session('tg-1', sessionId: 'tgdog-s1')},
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _root(
            joined: joined,
            resolver: _FakeSessionResolver(recorder),
            substationConfig: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'tg',
                ownedSubstations: {'tg'},
                maxConcurrentWork: 1,
              ),
            ),
            services: ServiceBundle(transport: transport),
            stationServices: _stationServices(maxConcurrentWork: 1),
          ),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);
      expect(
        transport.flares.map((flare) => flare.name),
        contains('work.throttled'),
      );

      joined.push(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2')],
          ready: {'tg-1', 'tg-2'},
          sessions: {
            'tg-1': _session(
              'tg-1',
              sessionId: 'tgdog-s1',
              pauseState: SessionPauseState.paused,
            ),
          },
        ),
      );
      owner.flush();

      expect(recorder.events, hasLength(3));
      expect(recorder.events.first, 'START work(tg-1)');
      expect(
        recorder.events,
        containsAll(<String>['STOP work(tg-1)', 'START work(tg-2)']),
      );
      final paused = transport.flares.where(
        (flare) => flare.name == 'work.paused',
      );
      expect(paused, hasLength(1));
      expect(paused.single.data['beadId'], 'tg-1');
      expect(paused.single.data['sessionId'], 'tgdog-s1');
    });

    test('a paused session does not consume the station-wide ceiling', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2')],
          ready: {'tg-1', 'tg-2'},
          sessions: {
            'tg-1': _session(
              'tg-1',
              sessionId: 'tgdog-s1',
              pauseState: SessionPauseState.paused,
            ),
          },
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _root(
            joined: joined,
            resolver: _FakeSessionResolver(recorder),
            substationConfig: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'tg',
                ownedSubstations: {'tg'},
              ),
            ),
            stationServices: _stationServices(maxConcurrentWork: 1),
          ),
        ),
      );

      expect(recorder.events, ['START work(tg-2)']);
    });

    test('resume waits for a slot and adopts the same session', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      SessionProjection resumed() => _session(
        'tg-1',
        sessionId: 'tgdog-s1',
        pauseState: SessionPauseState.resumed,
      );
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2')],
          ready: {'tg-1', 'tg-2'},
          sessions: {
            'tg-1': resumed(),
            'tg-2': _session('tg-2', sessionId: 'tgdog-s2'),
          },
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _root(
            joined: joined,
            resolver: _FakeSessionResolver(recorder),
            substationConfig: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'tg',
                ownedSubstations: {'tg'},
                maxConcurrentWork: 1,
              ),
            ),
            services: ServiceBundle(transport: transport),
            stationServices: _stationServices(maxConcurrentWork: 1),
          ),
        ),
      );

      expect(recorder.events, ['START work(tg-2)']);
      expect(
        transport.flares
            .where((flare) => flare.name == 'work.throttled')
            .last
            .data['beadIds'],
        'tg-1',
      );

      joined.push(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2')],
          ready: {'tg-1', 'tg-2'},
          sessions: {
            'tg-1': resumed(),
            'tg-2': _session(
              'tg-2',
              sessionId: 'tgdog-s2',
              isTerminal: true,
              completed: true,
            ),
          },
        ),
      );
      owner.flush();

      expect(recorder.events, hasLength(3));
      expect(recorder.events.first, 'START work(tg-2)');
      expect(
        recorder.events,
        containsAll(<String>['STOP work(tg-2)', 'START work(tg-1)']),
      );
      expect(recorder.handedSessionIds.last, 'tgdog-s1');
    });
  });
}
