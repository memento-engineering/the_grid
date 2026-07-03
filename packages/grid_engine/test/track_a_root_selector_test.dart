// Track A — the per-bead ROOT MATCH at the mount boundary (tg-7gm,
// `SCRATCH-grid-alignment.md` §6 amendment): a bead selects a registered root
// via `metadata.grid.root`, defaulting to its own substation.
// `SubstationConfig.registeredRoots` gates `WorkList`: EMPTY is
// UNCONSTRAINED (no `--root` wired — the pre-multi-root default, dry-run's
// shape); NON-EMPTY activates the gate — an owned bead whose resolved root is
// unregistered is an ARMING-CLASS refusal: a LOUD skip (flared through the
// reserved `ExplorationTransport`, D-8), never a station-wide gate. Zero I/O —
// fakes only.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
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

/// A transport that throws on every flare (the non-blocking proof).
class _ThrowingTransport implements ExplorationTransport {
  @override
  void flare(String name, Map<String, String> data) =>
      throw StateError('transport boom');
}

Bead _bead(String id, {Map<String, dynamic> metadata = const {}}) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.open,
  metadata: metadata,
);

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: ready,
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: const {},
);

Seed _root({
  required JoinedSnapshotNotifier joined,
  required SessionResolver resolver,
  required SubstationConfigNotifier substationConfig,
  ServiceBundle services = const ServiceBundle(),
}) => InheritedSeed<JoinedSnapshotNotifier>(
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

void main() {
  group('Track A — the per-bead root match (tg-7gm)', () {
    test('empty registeredRoots is UNCONSTRAINED — every owned bead mounts '
        'regardless of rooting (the pre-multi-root default)', () {
      final recorder = _Recorder();
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
            ),
          ),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);
    });

    test(
      'a bead defaulting to its own substation mounts when that name is registered',
      () {
        final recorder = _Recorder();
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
                registeredRoots: {'tg'},
              ),
            ),
          ),
        );
        expect(recorder.events, ['START work(tg-1)']);
      },
    );

    test('`metadata.grid.root` selects a DIFFERENT registered root than the '
        'owning substation (a `tg` bead building `power_station`)', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [
            _bead('tg-1', metadata: {'grid.root': 'power_station'}),
          ],
          ready: {'tg-1'},
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
              // "tg" itself is NOT registered — only the selected root is.
              registeredRoots: {'power_station'},
            ),
          ),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);
    });

    test('an owned bead whose resolved root has NO registered root is a LOUD '
        'skip — never a station-wide gate (a sibling with a registered root '
        'still mounts)', () {
      final recorder = _Recorder();
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [
            _bead('tg-1'), // defaults to substation "tg" — unregistered.
            _bead('tg-2', metadata: {'grid.root': 'power_station'}),
          ],
          ready: {'tg-1', 'tg-2'},
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
              registeredRoots: {'power_station'},
            ),
          ),
          services: ServiceBundle(transport: transport),
        ),
      );

      expect(recorder.events, ['START work(tg-2)']);
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.rootMissing');
      expect(transport.flares.single.data, {'beadId': 'tg-1', 'root': 'tg'});
    });

    test(
      'a THROWING transport does NOT break the mount reconcile (non-blocking '
      'proof) — the registered sibling still mounts',
      () {
        final recorder = _Recorder();
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [
              _bead('tg-1'),
              _bead('tg-2', metadata: {'grid.root': 'power_station'}),
            ],
            ready: {'tg-1', 'tg-2'},
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
                registeredRoots: {'power_station'},
              ),
            ),
            services: ServiceBundle(transport: _ThrowingTransport()),
          ),
        );
        expect(recorder.events, ['START work(tg-2)']);
      },
    );
  });
}
