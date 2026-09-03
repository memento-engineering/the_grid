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
import 'package:grid_engine/src/seeds/provider.dart';

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

Bead _bead(String id, {int priority = 0}) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.open,
  priority: priority,
);

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  Map<String, SessionProjection> sessions = const {},
  Map<String, MountAttemptRecord> mountAttempts = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: ready,
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
  mountAttemptsByWorkBead: mountAttempts,
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

/// Two sibling substations under one `Station`, sharing the SAME ambient
/// [JoinedSnapshotNotifier] and [StationServices] — the shape needed to prove
/// the station-wide cap is a TOTAL across substations, not a per-substation
/// ceiling applied independently to each.
Seed _twoSubstationRoot({
  required JoinedSnapshotNotifier joined,
  required SessionResolver resolver,
  required SubstationConfigNotifier substationA,
  required SubstationConfigNotifier substationB,
  required StationServices stationServices,
  ServiceBundle servicesA = const ServiceBundle(),
  ServiceBundle servicesB = const ServiceBundle(),
}) {
  return InheritedSeed<StationServices>(
    value: stationServices,
    child: InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<SessionResolver>(
        value: resolver,
        child: Station([
          SubstationScope(
            configNotifier: substationA,
            services: servicesA,
            key: const ValueKey('scope.a'),
          ),
          SubstationScope(
            configNotifier: substationB,
            services: servicesB,
            key: const ValueKey('scope.b'),
          ),
        ]),
      ),
    ),
  );
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
        ProviderScope(
          child: _root(
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
        ),
      );

      // Only the two LOWEST-id beads mount: all four are the same priority, so
      // the lowest-id tie-break decides admission (tg-lohr).
      expect(recorder.events, ['START work(tg-1)', 'START work(tg-2)']);
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.throttled');
      expect(transport.flares.single.data, {
        'count': '2',
        'beadIds': 'tg-3,tg-4',
      });
    });

    test('mount-attempt records do not consume capacity or narrow the ready '
        'frontier', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final attempts = <String, MountAttemptRecord>{
        for (var i = 1; i <= 9; i++)
          'tg-$i': MountAttemptRecord(
            recordId: 'tgdog-att-$i',
            workBeadId: 'tg-$i',
            count: 1,
          ),
      };
      final snapshot = _joined(
        beads: [_bead('tg-1'), _bead('tg-2'), _bead('tg-3'), _bead('tg-4')],
        ready: {'tg-1', 'tg-2', 'tg-3', 'tg-4'},
        mountAttempts: attempts,
      );
      final joined = JoinedSnapshotNotifier(snapshot);
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
                maxConcurrentWork: 2,
              ),
            ),
            services: ServiceBundle(transport: transport),
          ),
        ),
      );

      expect(snapshot.graph.readyIds, {'tg-1', 'tg-2', 'tg-3', 'tg-4'});
      expect(recorder.events, ['START work(tg-1)', 'START work(tg-2)']);
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
        ProviderScope(
          child: _root(
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
              // A POSITIVE terminal: the engine's close path stamps
              // `grid.outcome=complete` (tg-4rw / I-10) — that marker is what
              // makes a closed session BLOCKING. Without it this row is a dead
              // key, the bead correctly re-mints, and it would re-occupy the very
              // slot this test asserts is freed.
              completed: true,
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
        ProviderScope(
          child: _root(
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
                reader: RecordingBdRunner(),
                ownership: BeadOwnershipPredicate(const {'tg'}),
              ),
              stateSubstation: 'tg',
              maxConcurrentWork: 2,
            ),
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
        ProviderScope(
          child: _root(
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
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);
      expect(transport.flares, isEmpty);
    });

    test('nothing configured at all -> the PURE kDefaultMaxConcurrentWork '
        'fallback binds — no substation override, no ambient StationServices', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      // kDefaultMaxConcurrentWork + 2 ready beads, no session yet.
      final beadIds = List.generate(
        kDefaultMaxConcurrentWork + 2,
        (i) => 'tg-${i + 1}',
      );
      final joined = JoinedSnapshotNotifier(
        _joined(beads: beadIds.map(_bead).toList(), ready: beadIds.toSet()),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _root(
            joined: joined,
            resolver: _FakeSessionResolver(recorder),
            // No `maxConcurrentWork` override — falls all the way through to
            // the compile-time default.
            substationConfig: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'tg',
                ownedSubstations: {'tg'},
              ),
            ),
            services: ServiceBundle(transport: transport),
            // No ambient `StationServices` at all — the offline-test default
            // this file's other cases wire deliberately, exercised here as the
            // genuinely-nothing-configured case.
          ),
        ),
      );

      expect(
        recorder.events,
        List.generate(
          kDefaultMaxConcurrentWork,
          (i) => 'START work(tg-${i + 1})',
        ),
      );
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.throttled');
      expect(transport.flares.single.data, {
        'count': '2',
        'beadIds':
            'tg-${kDefaultMaxConcurrentWork + 1},tg-${kDefaultMaxConcurrentWork + 2}',
      });
    });

    test('a rework re-key (tg-zat): a bead whose session becomes momentarily '
        'unkeyed (its retired session still counts, live, under a DIFFERENT '
        'key) is NOT evicted for budget reasons even though `liveSession` '
        'reads false this build — A40 covers the branch, not just the key', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              isTerminal: false,
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
            stationServices: StationServices(
              provider: FakeRuntimeProvider(),
              writer: StationBeadWriter(
                bd: BdCliService(RecordingBdRunner()),
                reader: RecordingBdRunner(),
                ownership: BeadOwnershipPredicate(const {'tg'}),
              ),
              stateSubstation: 'tg',
              // A tight station-wide ceiling: the retired session (still open,
              // now keyed 'tg-1#r1') fills the ONLY slot on its own.
              maxConcurrentWork: 1,
            ),
          ),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);
      recorder.events.clear();

      // `grid rework` re-keys the session's `work_bead` off 'tg-1' (D-2's
      // close-then-mint has not run yet) — `sessionsByWorkBead['tg-1']`
      // reads null, but the retired session is STILL non-terminal, still
      // present in the joined map under its round-suffixed key, and STILL
      // consumes the station-wide budget.
      joined.push(
        _joined(
          beads: [_bead('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1#r1': const SessionProjection(
              workBeadId: 'tg-1#r1',
              isTerminal: false,
            ),
          },
        ),
      );
      owner.flush();

      // Pre-fix, `liveSession` alone reclassified 'tg-1' as a budget-gated
      // `pending` candidate; with the ONE slot already "spent" by its own
      // orphaned retired session, it was evicted (a STOP with no matching
      // START) — killing the very branch that would close the retired
      // session and mint the fresh round. Fixed: the branch stays mounted.
      expect(recorder.events, isEmpty);
    });

    test('a durable retired round remounts after mounted membership was '
        'cleared, even when no fresh-work budget remains', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1')],
          ready: {'tg-1'},
          sessions: const {
            'tg-1': SessionProjection(workBeadId: 'tg-1', isTerminal: false),
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
            stationServices: StationServices(
              provider: FakeRuntimeProvider(),
              writer: StationBeadWriter(
                bd: BdCliService(RecordingBdRunner()),
                reader: RecordingBdRunner(),
                ownership: BeadOwnershipPredicate(const {'tg'}),
              ),
              stateSubstation: 'tg',
              maxConcurrentWork: 0,
            ),
          ),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);

      joined.push(
        _joined(
          beads: [_bead('tg-1')],
          ready: const {},
          sessions: const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              isTerminal: true,
              completed: true,
            ),
          },
        ),
      );
      owner.flush();
      recorder.events.clear();

      final retiredSnapshot = _joined(
        beads: [_bead('tg-1')],
        ready: {'tg-1'},
        sessions: const {
          'tg-1#r1': SessionProjection(workBeadId: 'tg-1#r1', isTerminal: true),
        },
      );
      joined.push(retiredSnapshot);
      owner.flush();

      expect(recorder.events, ['START work(tg-1)']);
      expect(
        transport.flares.where(
          (flare) =>
              flare.name == 'work.throttled' &&
              flare.data['beadIds']!.split(',').contains('tg-1'),
        ),
        isEmpty,
      );
      recorder.events.clear();
      joined.push(retiredSnapshot);
      owner.flush();
      expect(recorder.events, isEmpty);
    });

    test('the station-wide cap is a TOTAL across substations — a busy '
        'substation starves a quiet sibling of slots even though the '
        "sibling's own substation cap is untouched", () {
      final recorder = _Recorder();
      final transportA = _RecordingTransport();
      final transportB = _RecordingTransport();
      // Substation `a` already has 3 live (non-terminal) sessions; substation
      // `b` has 2 freshly-ready beads and no sessions of its own. The station
      // ceiling is 3 — already exhausted by `a` alone.
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [
            _bead('a-1'),
            _bead('a-2'),
            _bead('a-3'),
            _bead('b-1'),
            _bead('b-2'),
          ],
          ready: {'b-1', 'b-2'},
          sessions: {
            'a-1': const SessionProjection(
              workBeadId: 'a-1',
              isTerminal: false,
            ),
            'a-2': const SessionProjection(
              workBeadId: 'a-2',
              isTerminal: false,
            ),
            'a-3': const SessionProjection(
              workBeadId: 'a-3',
              isTerminal: false,
            ),
          },
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _twoSubstationRoot(
            joined: joined,
            resolver: _FakeSessionResolver(recorder),
            substationA: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'a',
                ownedSubstations: {'a'},
              ),
            ),
            substationB: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'b',
                ownedSubstations: {'b'},
              ),
            ),
            servicesA: ServiceBundle(transport: transportA),
            servicesB: ServiceBundle(transport: transportB),
            stationServices: StationServices(
              provider: FakeRuntimeProvider(),
              writer: StationBeadWriter(
                bd: BdCliService(RecordingBdRunner()),
                reader: RecordingBdRunner(),
                ownership: BeadOwnershipPredicate(const {'a', 'b'}),
              ),
              stateSubstation: 'a',
              maxConcurrentWork: 3,
            ),
          ),
        ),
      );

      // `a`'s 3 already-live sessions mount (never evicted; they were never
      // "pending" against the budget), leaving zero slots station-wide.
      expect(recorder.events, [
        'START work(a-1)',
        'START work(a-2)',
        'START work(a-3)',
      ]);
      // `a` itself never throttles — it had nothing genuinely WAITING (its
      // ready beads all already carry a live session).
      expect(transportA.flares, isEmpty);
      // `b`'s two ready beads both wait: the station-wide total is already
      // exhausted by `a`, even though `b`'s OWN substation cap (3, the
      // station default) was never touched.
      expect(transportB.flares, hasLength(1));
      expect(transportB.flares.single.name, 'work.throttled');
      expect(transportB.flares.single.data, {
        'count': '2',
        'beadIds': 'b-1,b-2',
      });
    });

    test('the cap binds: the HIGHEST-priority pending beads are admitted — a '
        'P0 mounts ahead of an alphabetically EARLIER P4, and the lowest-id '
        'tie-break still decides WITHIN one priority (tg-lohr)', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      // Ids chosen adversarially against the OLD lowest-id-first order: under
      // it `tg-aaa` (P4) and `tg-bbb` (P1) would have taken both slots and the
      // two P0s would have waited.
      final beads = [
        _bead('tg-aaa', priority: 4),
        _bead('tg-bbb', priority: 1),
        _bead('tg-mmm', priority: 0),
        _bead('tg-zzz', priority: 0),
      ];
      final joined = JoinedSnapshotNotifier(
        _joined(beads: beads, ready: {'tg-aaa', 'tg-bbb', 'tg-mmm', 'tg-zzz'}),
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
                maxConcurrentWork: 2,
              ),
            ),
            services: ServiceBundle(transport: transport),
          ),
        ),
      );

      // Both P0s take the slots, in lowest-id order within that priority.
      expect(recorder.events, ['START work(tg-mmm)', 'START work(tg-zzz)']);
      // The LOUD line keeps its shape and membership; the held beads are now
      // listed in the same admission order, next-up (P1) first.
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.throttled');
      expect(transport.flares.single.data, {
        'count': '2',
        'beadIds': 'tg-bbb,tg-aaa',
      });
    });

    test('the mixed case — two substations x two priorities, one slot each: '
        'each substation admits its OWN highest-priority bead and holds the '
        'rest; the station ceiling is untouched (tg-lohr)', () {
      final recorder = _Recorder();
      final transportA = _RecordingTransport();
      final transportB = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [
            _bead('a-ace', priority: 3),
            _bead('a-zed', priority: 0),
            _bead('b-cat', priority: 4),
            _bead('b-yak', priority: 1),
          ],
          ready: {'a-ace', 'a-zed', 'b-cat', 'b-yak'},
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _twoSubstationRoot(
            joined: joined,
            resolver: _FakeSessionResolver(recorder),
            substationA: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'a',
                ownedSubstations: {'a'},
                maxConcurrentWork: 1,
              ),
            ),
            substationB: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'b',
                ownedSubstations: {'b'},
                maxConcurrentWork: 1,
              ),
            ),
            servicesA: ServiceBundle(transport: transportA),
            servicesB: ServiceBundle(transport: transportB),
            stationServices: StationServices(
              provider: FakeRuntimeProvider(),
              writer: StationBeadWriter(
                bd: BdCliService(RecordingBdRunner()),
                reader: RecordingBdRunner(),
                ownership: BeadOwnershipPredicate(const {'a', 'b'}),
              ),
              stateSubstation: 'a',
              // Generous station ceiling (4 > the 2 admissions below), so the
              // PER-SUBSTATION cap of 1 is what binds — A43's `min()` is
              // exercised unchanged.
              maxConcurrentWork: 4,
            ),
          ),
        ),
      );

      // Each substation admits its own top-priority bead, never the
      // alphabetically-first one. Ordering stays PER-SUBSTATION: this bead
      // adds no cross-substation weighting, so assert the SET (which
      // substation flushes first is the reconciler's detail).
      expect(recorder.events.toSet(), {
        'START work(a-zed)',
        'START work(b-yak)',
      });
      expect(recorder.events, hasLength(2));
      expect(transportA.flares, hasLength(1));
      expect(transportA.flares.single.name, 'work.throttled');
      expect(transportA.flares.single.data, {'count': '1', 'beadIds': 'a-ace'});
      expect(transportB.flares, hasLength(1));
      expect(transportB.flares.single.name, 'work.throttled');
      expect(transportB.flares.single.data, {'count': '1', 'beadIds': 'b-cat'});
    });

    test('a MOUNTED P4 is never evicted for a pending P0 — the P0 waits and '
        'takes the next NATURAL slot when that session closes done '
        '(tg-lohr)', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final beads = [
        _bead('tg-aaa', priority: 4),
        _bead('tg-zzz', priority: 0),
      ];
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: beads,
          ready: {'tg-aaa', 'tg-zzz'},
          sessions: {
            'tg-aaa': const SessionProjection(
              workBeadId: 'tg-aaa',
              isTerminal: false,
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
                maxConcurrentWork: 1,
              ),
            ),
            services: ServiceBundle(transport: transport),
          ),
        ),
      );

      // The live P4 keeps the only slot; the P0 is HELD, never swapped in.
      expect(recorder.events, ['START work(tg-aaa)']);
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.data, {'count': '1', 'beadIds': 'tg-zzz'});
      recorder.events.clear();
      transport.flares.clear();

      // The P4's session closes as a POSITIVE terminal — the engine's own
      // `grid.outcome=complete` marker (I-10 / A48), the only close that frees
      // a slot rather than re-minting a dead key. Now the P0 mounts.
      joined.push(
        _joined(
          beads: beads,
          ready: {'tg-aaa', 'tg-zzz'},
          sessions: {
            'tg-aaa': const SessionProjection(
              workBeadId: 'tg-aaa',
              isTerminal: true,
              completed: true,
            ),
          },
        ),
      );
      owner.flush();

      // Mount-vs-unmount order within one flush is the reconciler's detail,
      // not the governor's contract — assert the SET.
      expect(recorder.events.toSet(), {
        'STOP work(tg-aaa)',
        'START work(tg-zzz)',
      });
      expect(recorder.events, hasLength(2));
      // Nothing waits any more, so the governor stays quiet.
      expect(transport.flares, isEmpty);
    });
  });
}
