// tg-6nf — SessionScope mint-failure discipline, WIRING-SHAPED, through the full
// `Station → SubstationScope → WorkList → WorkBead → SessionScope` tree.
//
// FIRST-LIVE-ARM INCIDENT (2026-07-10, boot #1): every `createSession` threw —
// the houston state store rejected `bd create -t session` (no `types.custom`
// configured). `_mint`'s `on Object` catch set `_failed=true` with NO transport
// flare, NO retry, NO surface — the station stood ARMED-but-silently-dead
// (ready 7 / mounted 0 / zero output). Violated LOUD-or-GONE (ADR-0008 D3).
//
// PROVEN HERE:
//   (1) a mint failure FLARES through the emit-only ExplorationTransport (the
//       same sink `_flareRearmFailed` / `CapabilityHost._emitFlare` use) — the
//       dead mint is observable, never an invisible mounted=0.
//   (2) the retry is BOUNDED (`_maxMintAttempts`) then ESCALATES with a distinct
//       terminal flare — never an infinite spin, never a silent permanent latch.
//   (3) a TRANSIENT blip (first attempt throws, then succeeds) RECOVERS with no
//       operator action and NO escalation — proving the fix is not "fail once,
//       give up" but genuine bounded retry.
//
// Zero I/O: fakes + the recording chokepoint + a fake transport.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'agent'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _work(List<Bead> beads, Set<String> ready) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

GraphSnapshot _state(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// An [ExplorationTransport] that records every LOUD flare — the emit-only sink
/// the mint-failed / mint-exhausted signals fire through.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));

  Iterable<({String name, Map<String, String> data})> named(String name) =>
      flares.where((f) => f.name == name);
}

/// A [BdRunner] that THROWS the first [failCreates] `create` calls (as the live
/// store did — `bd create -t session` rejected) then succeeds. `failCreates`
/// larger than the mint budget models the PERSISTENT misconfiguration; `1`
/// models a transient blip. Records every argv in order.
class _FailCreateRunner implements BdRunner {
  _FailCreateRunner({required this.failCreates});

  final int failCreates;
  final List<List<String>> calls = <List<String>>[];
  int _creates = 0;

  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) async {
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'create') {
      _creates++;
      if (_creates <= failCreates) {
        throw StateError('fake bd create rejected #$_creates (no types.custom)');
      }
    }
    final data = switch (sub) {
      'create' => '{"id":"tgdog-sess1"}',
      _ => '{"id":"${args.length >= 2 ? args[1] : ''}"}',
    };
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":$data}',
      stderr: '',
    );
  }
}

/// A [StationServices] whose chokepoint writes through [runner], owning
/// [stateSubstation] — the same shape [buildFakes] builds, over a caller-
/// supplied runner so a test asserts against it directly.
StationServices _ctxOver(BdRunner runner) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ServiceBundle services,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: ctx,
        child: InheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<SessionResolver>(
            value: CircuitResolver((_) => _code),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(
                  const SubstationConfig(
                    substationId: 'tg',
                    ownedSubstations: {'tg'},
                  ),
                ),
                services: services,
                key: const ValueKey('scope.tg'),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

void main() {
  group('SessionScope mint failure (tg-6nf)', () {
    test(
      'a PERSISTENT mint failure FLARES every attempt, retries a BOUNDED number '
      'of times, then ESCALATES loud — never a silent latch, never an inflated '
      'leaf',
      () async {
        final runner = _FailCreateRunner(failCreates: 100); // always rejects.
        final ctx = _ctxOver(runner);
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final bridge = StationJoinBridge(
          work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
          state: FakeSnapshotSource(_state(const [])),
        )..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(
          joined: bridge.notifier,
          ctx: ctx,
          registry: reg,
          services: ServiceBundle(transport: transport),
        );
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        // BOUNDED: exactly the mint budget of createSession attempts — not one
        // (the old give-up-on-first-failure), not an infinite spin.
        expect(
          runner.callsFor('create'),
          hasLength(5),
          reason: 'the mint is retried a bounded number of times (5), no more',
        );

        // LOUD: every attempt under budget flared `session.mintFailed`, and the
        // exhausted attempt flared exactly one terminal `session.mintExhausted`.
        expect(
          transport.named('session.mintFailed'),
          hasLength(4),
          reason: 'attempts 1..4 flare mintFailed while still retrying',
        );
        final exhausted = transport.named('session.mintExhausted').toList();
        expect(
          exhausted,
          hasLength(1),
          reason: 'the spent budget escalates with one terminal flare',
        );
        // VISIBLE: the escalation flare names the dead-minting work bead so an
        // observer can count it — never an anonymous mounted=0.
        expect(exhausted.single.data['workBeadId'], 'tg-1');
        expect(exhausted.single.data['attempt'], '5');
        expect(exhausted.single.data['maxAttempts'], '5');
        expect(exhausted.single.data['reason'], isNotEmpty);

        // INERT: no session minted → no leaf inflated (the scope renders Idle).
        expect(
          reg.events,
          isEmpty,
          reason: 'a failed mint never inflates the circuit',
        );
        // The chokepoint stayed pristine (never `bd show`, never SQL).
        expect(
          runner.calls.every((c) => c.isEmpty || (c.first != 'show' && c.first != 'sql')),
          isTrue,
        );
      },
    );

    test(
      'a TRANSIENT mint blip (first attempt throws, then succeeds) RECOVERS — '
      'flares once, never escalates, and the session mints + inflates',
      () async {
        final runner = _FailCreateRunner(failCreates: 1); // one blip, then ok.
        final ctx = _ctxOver(runner);
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final bridge = StationJoinBridge(
          work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
          state: FakeSnapshotSource(_state(const [])),
        )..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(
          joined: bridge.notifier,
          ctx: ctx,
          registry: reg,
          services: ServiceBundle(transport: transport),
        );
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        // RETRIED: attempt #1 dropped, attempt #2 succeeded — never latched off.
        expect(runner.callsFor('create'), hasLength(2));
        // The single drop was LOUD but there was NO escalation.
        expect(transport.named('session.mintFailed'), hasLength(1));
        expect(
          transport.named('session.mintExhausted'),
          isEmpty,
          reason: 'a recovered blip must not escalate',
        );
        // RECOVERED: the minted session inflated the first step.
        expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
      },
    );
  });
}
