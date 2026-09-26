import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
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
  DateTime? capturedAt,
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: ready,
    capturedAt: capturedAt ?? DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
);

/// An ADOPTED live molecule session whose steps sit in [agentState] / pending —
/// the re-adopted-at-boot shape tg-t4k9 measured holding a slot while driving
/// nothing.
SessionProjection _moleculeSession(
  String workBeadId, {
  required String sessionId,
  StepState agentState = StepState.pending,
}) => SessionProjection(
  workBeadId: workBeadId,
  sessionId: sessionId,
  isMolecule: true,
  moleculeBeads: [
    for (final step in const ['agent', 'land'])
      Bead(
        id: '$sessionId-$step',
        issueType: GridIssueTypes.step,
        metadata: {
          'rig': 'tg',
          MoleculeStepKeys.stepId: step,
          MoleculeStepKeys.capability: step,
          MoleculeStepKeys.kind: StepKind.job.name,
          MoleculeStepKeys.path: '$workBeadId/$step',
          MoleculeStepKeys.session: sessionId,
          MoleculeStepKeys.state: step == 'agent'
              ? agentState.name
              : StepState.pending.name,
        },
      ),
  ],
);

List<({String name, Map<String, String> data})> _named(
  _RecordingTransport transport,
  String name,
) => transport.flares.where((flare) => flare.name == name).toList();

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
  test(
    'terminal skip reports once per observation and again after an intervening mount',
    () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final bead = _bead('tg-1');
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [bead],
          ready: {'tg-1'},
          sessions: {
            'tg-1': _session(
              'tg-1',
              sessionId: 'tgdog-done-1',
              isTerminal: true,
              completed: true,
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
            services: ServiceBundle(transport: transport),
          ),
        ),
      );

      JoinedSnapshot done(String sessionId) => _joined(
        beads: [bead],
        ready: {'tg-1'},
        sessions: {
          'tg-1': _session(
            'tg-1',
            sessionId: sessionId,
            isTerminal: true,
            completed: true,
          ),
        },
      );
      joined.push(done('tgdog-done-1'));
      owner.flush();
      joined.push(
        _joined(
          beads: [bead],
          ready: {'tg-1'},
          sessions: {'tg-1': _session('tg-1', sessionId: 'tgdog-live')},
        ),
      );
      owner.flush();
      expect(recorder.handedSessionIds, ['tgdog-live']);
      joined.push(done('tgdog-done-2'));
      owner.flush();

      final skipped = transport.flares.where(
        (flare) => flare.name == 'work.terminalSkip',
      );
      expect(skipped, hasLength(2));
      for (final flare in skipped) {
        expect(
          flare.data.keys,
          unorderedEquals(['beadId', 'sessionId', 'disposition', 'reason']),
        );
      }
    },
  );

  test('pause reports once per park and again after an intervening mount', () {
    final recorder = _Recorder();
    final transport = _RecordingTransport();
    final bead = _bead('tg-1');
    SessionProjection session(SessionPauseState pauseState) =>
        _session('tg-1', sessionId: 'tgdog-s1', pauseState: pauseState);
    JoinedSnapshot snapshot(SessionPauseState pauseState) => _joined(
      beads: [bead],
      ready: {'tg-1'},
      sessions: {'tg-1': session(pauseState)},
    );
    final joined = JoinedSnapshotNotifier(snapshot(SessionPauseState.none));
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
          services: ServiceBundle(transport: transport),
        ),
      ),
    );
    expect(recorder.handedSessionIds, ['tgdog-s1']);

    joined.push(snapshot(SessionPauseState.paused));
    owner.flush();
    joined.push(snapshot(SessionPauseState.paused));
    owner.flush();
    joined.push(snapshot(SessionPauseState.resumed));
    owner.flush();
    expect(recorder.handedSessionIds, ['tgdog-s1', 'tgdog-s1']);
    joined.push(snapshot(SessionPauseState.paused));
    owner.flush();

    final paused = transport.flares.where(
      (flare) => flare.name == 'work.paused',
    );
    expect(paused, hasLength(2));
    for (final flare in paused) {
      expect(
        flare.data.keys,
        unorderedEquals(['beadId', 'sessionId', 'reason']),
      );
    }
  });

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

  group('paused slots are released and resumed rows re-compete (tg-t4k9)', () {
    test('pausing one of cap-many live sessions frees exactly its slot, and a '
        'pending bead is admitted into it', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      const cap = 3;
      final beads = [for (var i = 1; i <= cap + 1; i++) _bead('tg-$i')];
      final ready = {for (final bead in beads) bead.id};
      Map<String, SessionProjection> sessions({String? paused}) => {
        for (var i = 1; i <= cap; i++)
          'tg-$i': _session(
            'tg-$i',
            sessionId: 'tgdog-s$i',
            pauseState: paused == 'tg-$i'
                ? SessionPauseState.paused
                : SessionPauseState.none,
          ),
      };
      final joined = JoinedSnapshotNotifier(
        _joined(beads: beads, ready: ready, sessions: sessions()),
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
                maxConcurrentWork: cap,
              ),
            ),
            services: ServiceBundle(transport: transport),
            stationServices: _stationServices(maxConcurrentWork: cap),
          ),
        ),
      );
      // Cap-many live sessions hold every slot; the pending bead is throttled
      // and the throttle names slot contention.
      expect(recorder.events.toSet(), {
        for (var i = 1; i <= cap; i++) 'START work(tg-$i)',
      });
      final throttled = _named(transport, 'work.throttled');
      expect(throttled, isNotEmpty);
      expect(throttled.last.data['beadIds'], 'tg-${cap + 1}');
      expect(throttled.last.data['cause'], WorkThrottleCause.slotsFull);

      // Pause ONE of them: exactly one slot frees and exactly one more bead is
      // admitted — the paused session is not counted as mounted.
      joined.push(
        _joined(
          beads: beads,
          ready: ready,
          sessions: sessions(paused: 'tg-2'),
        ),
      );
      owner.flush();
      expect(recorder.events.skip(cap).toSet(), {
        'STOP work(tg-2)',
        'START work(tg-${cap + 1})',
      });
      expect(recorder.events, hasLength(cap + 2));
      final pausedFlares = _named(transport, 'work.paused');
      expect(pausedFlares.single.data['beadId'], 'tg-2');
    });

    test('a resumed session at cap joins the pending competition (no bypass) '
        'and is admitted within a bounded number of flushes once a slot '
        'frees, with no unbounded work.throttled streak', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      const cap = 2;
      final beads = [_bead('tg-1'), _bead('tg-2'), _bead('tg-3')];
      final ready = {for (final bead in beads) bead.id};
      SessionProjection s2(SessionPauseState pauseState) =>
          _session('tg-2', sessionId: 'tgdog-s2', pauseState: pauseState);
      // Two ADOPTED live sessions hold the cap (the re-adopted-at-boot shape
      // the bead measured) and the third is paused.
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: beads,
          ready: ready,
          sessions: {
            'tg-1': _session('tg-1', sessionId: 'tgdog-s1'),
            'tg-2': s2(SessionPauseState.paused),
            'tg-3': _session('tg-3', sessionId: 'tgdog-s3'),
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
                maxConcurrentWork: cap,
              ),
            ),
            services: ServiceBundle(transport: transport),
            stationServices: _stationServices(maxConcurrentWork: cap),
          ),
        ),
      );
      // The paused session occupies no slot: tg-1 and tg-3 fill the cap.
      expect(recorder.events.toSet(), {'START work(tg-1)', 'START work(tg-3)'});

      // RESUME at cap: per pause-is-a-non-terminal-blocking-disposition the
      // resumed row re-enters the ordinary pending bin and WAITS — it does not
      // displace live work — and the wait is named slots-full.
      transport.flares.clear();
      joined.push(
        _joined(
          beads: beads,
          ready: ready,
          sessions: {
            'tg-1': _session('tg-1', sessionId: 'tgdog-s1'),
            'tg-2': s2(SessionPauseState.resumed),
            'tg-3': _session('tg-3', sessionId: 'tgdog-s3'),
          },
        ),
      );
      owner.flush();
      expect(recorder.events, hasLength(2), reason: 'no eviction, no bypass');
      final resumedHold = _named(transport, 'work.throttled');
      expect(resumedHold, isNotEmpty);
      expect(resumedHold.last.data['beadIds'], 'tg-2');
      expect(resumedHold.last.data['cause'], WorkThrottleCause.slotsFull);

      // A slot frees (tg-3 completes). Under correct accounting the resumed
      // row WINS it within a bounded number of flushes.
      transport.flares.clear();
      joined.push(
        _joined(
          beads: beads,
          ready: ready,
          sessions: {
            'tg-1': _session('tg-1', sessionId: 'tgdog-s1'),
            'tg-2': s2(SessionPauseState.resumed),
            'tg-3': _session(
              'tg-3',
              sessionId: 'tgdog-s3',
              isTerminal: true,
              completed: true,
            ),
          },
        ),
      );
      const flushBound = 3;
      var flushes = 0;
      while (flushes < flushBound &&
          !recorder.events.contains('START work(tg-2)')) {
        owner.flush();
        flushes += 1;
      }
      expect(
        recorder.events,
        containsAll(<String>['STOP work(tg-3)', 'START work(tg-2)']),
        reason:
            'the resumed session was not admitted within $flushBound '
            'flushes of the slot freeing',
      );
      expect(recorder.handedSessionIds.last, 'tgdog-s2');
      // The throttle streak after the slot freed is bounded by the flushes it
      // took to admit — never an open-ended repeat against a free slot.
      expect(
        _named(
          transport,
          'work.throttled',
        ).where((flare) => flare.data['beadIds']!.contains('tg-2')).length,
        lessThanOrEqualTo(flushBound),
      );
    });

    test('an adopted session that drives nothing for '
        'kAdoptedSessionQuietSnapshots snapshots flares '
        'work.adoptedSessionQuiet ONCE, naming session, bead and substation; '
        'a step transition resets the watch', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final beads = [_bead('tg-1')];
      var tick = 0;
      JoinedSnapshot snapshotAt({StepState agentState = StepState.pending}) =>
          _joined(
            beads: beads,
            ready: {'tg-1'},
            sessions: {
              'tg-1': _moleculeSession(
                'tg-1',
                sessionId: 'tgdog-s1',
                agentState: agentState,
              ),
            },
            capturedAt: DateTime(2026, 9, 22, 9, 30, tick++),
          );
      final joined = JoinedSnapshotNotifier(snapshotAt());
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
            services: ServiceBundle(transport: transport),
            stationServices: _stationServices(maxConcurrentWork: 2),
          ),
        ),
      );
      expect(recorder.handedSessionIds, ['tgdog-s1'], reason: 'adopted');

      // Snapshots 2..k-1 quiet: no flare yet. Rebuilds over the SAME snapshot
      // are not ticks and never advance the count.
      for (var i = 2; i < kAdoptedSessionQuietSnapshots; i++) {
        joined.push(snapshotAt());
        owner.flush();
        owner.flush();
      }
      expect(_named(transport, 'work.adoptedSessionQuiet'), isEmpty);

      // The k-th quiet snapshot: exactly one named flare.
      joined.push(snapshotAt());
      owner.flush();
      final quiet = _named(transport, 'work.adoptedSessionQuiet');
      expect(quiet, hasLength(1));
      expect(quiet.single.data, {
        'sessionId': 'tgdog-s1',
        'beadId': 'tg-1',
        'substation': 'tg',
        'snapshots': '$kAdoptedSessionQuietSnapshots',
      });

      // Still quiet: no repeat.
      joined.push(snapshotAt());
      owner.flush();
      expect(_named(transport, 'work.adoptedSessionQuiet'), hasLength(1));

      // The first step transition resets the watch…
      joined.push(snapshotAt(agentState: StepState.running));
      owner.flush();
      // …so a fresh quiet streak needs the full bound again before it flares.
      for (var i = 1; i <= kAdoptedSessionQuietSnapshots; i++) {
        joined.push(snapshotAt());
        owner.flush();
        expect(
          _named(transport, 'work.adoptedSessionQuiet'),
          hasLength(i < kAdoptedSessionQuietSnapshots ? 1 : 2),
          reason: 'quiet snapshot $i after the reset',
        );
      }
    });
  });
}
