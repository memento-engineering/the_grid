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
import 'dart:async';
import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';
import 'package:grid_engine/src/seeds/provider.dart';

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

/// Drains the microtask queue and renders every dirty rebuild it produced,
/// repeating until [condition] is satisfied or [maxRounds] is spent. A
/// molecule mint chains multiple bd round-trips (`createSession`, THEN
/// `createMolecule`'s dedup-probe export + graph-apply pour, each its own
/// async gap) — a single pump/flush pair can settle mid-chain, so polling
/// (rather than a fixed pump count) is what makes this deterministic
/// (tg-eli phase 2: the flat model's one-hop `create` no longer applies).
Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    // A molecule mint's `create --graph` pour writes a REAL temp file
    // (`BdCliService.applyGraph`'s plan.json) — genuine disk I/O, not just
    // microtask chaining — so a short real-time cushion is what makes
    // waiting for it deterministic under load (tg-eli phase 2: the flat
    // model's in-memory-only mint never hit disk).
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
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
  _FailCreateRunner({
    required this.failCreates,
    this.failGraphApplies = 0,
    this.failListsWithTimeout = false,
  });

  final int failCreates;
  final int failGraphApplies;
  final bool failListsWithTimeout;
  final List<List<String>> calls = <List<String>>[];
  int _creates = 0;
  int _graphApplies = 0;
  int _listTimeoutCount = 0;

  /// The `key → id` map a `bd create --graph` pour reports (mirrors
  /// [RecordingBdRunner.graphApplyIds]) — `createMolecule`'s graph-apply pour
  /// throws `BdParseException` on a missing `ids` map, so every successful
  /// mint attempt (this fake's `create --graph` branch) must report one, even
  /// when empty.
  Map<String, String> graphApplyIds = const <String, String>{};

  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

  Map<String, dynamic> metadataOfUpdate(int index) {
    final call = callsFor('update')[index];
    final metadata = <String, dynamic>{};
    for (var i = 0; i < call.length - 1; i++) {
      if (call[i] != '--set-metadata') continue;
      final assignment = call[i + 1];
      final separator = assignment.indexOf('=');
      if (separator < 0) continue;
      metadata[assignment.substring(0, separator)] = assignment.substring(
        separator + 1,
      );
    }
    return metadata;
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'list' &&
        failListsWithTimeout &&
        args.length > 2 &&
        (args[2] == GridIssueTypes.molecule.wire ||
            args[2] == GridIssueTypes.step.wire)) {
      // The full tree can schedule duplicate readiness checks while the first
      // dedup probe is in flight. Keep those pending, as a real 15s process
      // timeout would be, so this regression observes the first terminal park.
      if (_listTimeoutCount >= 2) return Completer<BdResult>().future;
      _listTimeoutCount++;
      throw BdTimeoutException(
        command: args,
        timeout: const Duration(seconds: 15),
      );
    }
    if (sub == 'query') {
      return const BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":[]}',
        stderr: '',
      );
    }
    if (sub == 'list') {
      return const BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":[]}',
        stderr: '',
      );
    }
    final isGraphApply =
        sub == 'create' && args.length > 1 && args[1] == '--graph';
    if (isGraphApply) {
      _graphApplies++;
      if (_graphApplies <= failGraphApplies) {
        throw StateError('fake molecule graph pour refused');
      }
      return BdResult(
        exitCode: 0,
        stdout: jsonEncode({
          'schema_version': 1,
          'data': {'ids': graphApplyIds},
        }),
        stderr: '',
      );
    }
    if (sub == 'create') {
      _creates++;
      if (_creates <= failCreates) {
        throw StateError(
          'fake bd create rejected #$_creates (no types.custom)',
        );
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
StationServices _ctxOver(
  BdRunner runner, {
  BeadProbeReader reader = const EmptyBeadProbeReader(),
}) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: reader,
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
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
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
          runner.calls.every(
            (c) => c.isEmpty || (c.first != 'show' && c.first != 'sql'),
          ),
          isTrue,
        );
      },
    );

    test('a thrown molecule POUR (post-createSession) flares once, parks the '
        'existing session at a durable gate, and never burns the mint budget — '
        'terminal, not retried (tg-aec)', () async {
      final runner = _FailCreateRunner(failCreates: 0, failGraphApplies: 1);
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
      // The park chains createSession → thrown pour → gate create → the
      // gate's blocks/node metadata stamp; settle on the stamp landing.
      await _pumpUntil(m.owner, () {
        final updates = runner.callsFor('update');
        return [
          for (var i = 0; i < updates.length; i++) runner.metadataOfUpdate(i),
        ].any((metadata) => metadata.containsKey('blocks'));
      });

      // LOUD once, with the cause: one moleculePourFailed naming the parked
      // session, its work bead, and the thrown error.
      final parked = transport.named('session.moleculePourFailed').toList();
      expect(parked, hasLength(1));
      expect(parked.single.data['sessionId'], 'tgdog-sess1');
      expect(parked.single.data['workBeadId'], 'tg-1');
      expect(
        parked.single.data['reason'],
        contains('fake molecule graph pour refused'),
      );

      // ONE pour attempt — the park is terminal, never a blind re-pour.
      expect(
        runner.calls.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(1),
      );
      // Exactly two plain creates: the session, then the gate bead.
      expect(
        runner
            .callsFor('create')
            .where((c) => c.length <= 1 || c[1] != '--graph'),
        hasLength(2),
      );
      // The gate stamp carries the re-arm linkage + the cause.
      final updates = runner.callsFor('update');
      final stamps = [
        for (var i = 0; i < updates.length; i++)
          if (runner.metadataOfUpdate(i).containsKey('blocks'))
            runner.metadataOfUpdate(i),
      ];
      expect(stamps, hasLength(1));
      final stamp = stamps.single;
      expect(stamp['blocks'], 'tgdog-sess1');
      expect(stamp['node'], 'tg-1');
      expect(stamp['reason'], contains('fake molecule graph pour refused'));

      // The mint budget is UNTOUCHED: a post-session pour failure is not a
      // mint failure — no retry flares, no exhaustion escalation.
      expect(transport.named('session.mintFailed'), isEmpty);
      expect(transport.named('session.mintExhausted'), isEmpty);

      // INERT: the parked session never inflates the circuit.
      expect(reg.events, isEmpty);
    });

    test('a timed-out molecule dedup read flares and parks without burning the '
        'mint budget', () async {
      final runner = _FailCreateRunner(
        failCreates: 0,
        failListsWithTimeout: true,
      );
      final reader = CliBeadProbeReader(
        BdCliService(runner),
        lifecycleTypes: const {GridIssueTypes.molecule, GridIssueTypes.step},
      );
      final ctx = _ctxOver(runner, reader: reader);
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
      await _pumpUntil(m.owner, () {
        final updates = runner.callsFor('update');
        return [
          for (var i = 0; i < updates.length; i++) runner.metadataOfUpdate(i),
        ].any((metadata) => metadata.containsKey('blocks'));
      });

      expect(transport.named('session.moleculePourFailed'), hasLength(1));
      expect(
        runner
            .callsFor('create')
            .where((call) => call.length <= 1 || call[1] != '--graph'),
        hasLength(2),
      );
      expect(runner.calls.where((call) => call.contains('--graph')), isEmpty);
      final stamps = [
        for (var i = 0; i < runner.callsFor('update').length; i++)
          if (runner.metadataOfUpdate(i).containsKey('blocks'))
            runner.metadataOfUpdate(i),
      ];
      expect(stamps, hasLength(1));
      expect(stamps.single['blocks'], 'tgdog-sess1');
      expect(transport.named('session.mintFailed'), isEmpty);
      expect(transport.named('session.mintExhausted'), isEmpty);
    });

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
        await _pumpUntil(
          m.owner,
          () => reg.events.isNotEmpty && runner.callsFor('create').length >= 3,
        );

        // RETRIED: attempt #1's `createSession` dropped, attempt #2's
        // succeeded — never latched off. `callsFor('create')` also carries
        // the successful attempt's `create --graph` molecule pour (tg-eli
        // phase 2: every fresh mint pours a molecule), so the plain-create
        // count is 2 (the failed + the recovered `createSession`) plus one
        // graph-apply.
        final creates = runner.callsFor('create');
        expect(creates, hasLength(3));
        expect(
          creates.where((c) => c.length > 1 && c[1] == '--graph'),
          hasLength(1),
        );
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
