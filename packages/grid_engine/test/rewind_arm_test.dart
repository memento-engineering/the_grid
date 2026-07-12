// tg-o90 — StepOutcome.Rewind: routing as a first-class engine primitive.
//
// The FOLDED spec circuit (`specify` and `route` as SIBLINGS) drives the whole
// arm end-to-end over the REAL tree — joined snapshot → SessionScope →
// CircuitScope → real CapabilityHosts — with the cursor advanced ONLY by the
// hosts' own chokepoint writes, replayed through the REAL codec. Nothing is
// hand-waved: the route's Rewind re-keys the specify sub-DAG, the sub-DAG re-runs
// VIRGIN inside the SAME session (no gate bead, no re-mint), the guidance ledger
// reaches the next specify brief, the parent's build stays withheld, and the loop
// is BOUNDED at kMaxReworkRounds. Plus the two LOUD refusals, the D-7
// non-regression fence, and the distinct allocation report.
//
// Zero I/O: fakes + the recording chokepoint (whose writes ARE what advances the
// cursor).
import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- the FOLDED spec circuit (tg-o90 WHAT #2) --------------------------------

/// `specify` is a SIBLING of `route` in ONE circuit, so the route can NAME it in
/// a Rewind. (Today's asset ships `specify` upstream of the spec circuit; folding
/// it is the asset-side follow-up bead — this is the engine's proof of the shape
/// it enables.)
const _specReview = Circuit(
  id: 'spec_review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'specify', capabilityId: 'specify'),
    CapabilityStep(
      stepId: 'critic',
      capabilityId: 'critic',
      dependsOn: {'specify'},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'critic'},
    ),
  ],
);

/// The parent: the spec circuit gates the build. `agent` must NEVER mount while
/// the spec is being rewound (the sub-circuit's terminal regressed to pending).
const _code = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [
    SubCircuitStep(stepId: 'spec_review', circuitId: 'spec_review'),
    CapabilityStep(
      stepId: 'agent',
      capabilityId: 'agent',
      dependsOn: {'spec_review'},
    ),
  ],
);

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

// --- the fixture capabilities (Fakes, not mocks) -----------------------------

/// The asset's durable correction ledger, modelled in memory (the real one is a
/// file in the workspace — asset-owned, pow-7nm, unchanged by this bead).
class _Ledger {
  final List<String> guidance = [];
}

/// The specify stage: records the BRIEF it was given (the ledger rendered in), so
/// a test can prove round 2 saw round 1's guidance and round 1 saw none.
class _SpecifyCap extends ServiceCapability {
  const _SpecifyCap(this.ledger, this.briefs);
  final _Ledger ledger;
  final List<String> briefs;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    briefs.add(ledger.guidance.join('|'));
    return const Ok();
  }
}

/// A step that just completes (the critic lane / the build agent).
class _OkCap extends ServiceCapability {
  const _OkCap();
  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async =>
      const Ok();
}

/// The route: pow-7nm's SpecRouteVerdict shape — RESPEC actuates as a `Rewind`
/// naming the `specify` SIBLING. It escalates on its OWN policy at the cap
/// (reading its `rewindCount` back through the ambient SiblingView) rather than
/// leaning on the engine belt.
class _RouteCap extends ServiceCapability {
  const _RouteCap(this.ledger, {this.respecRounds = 1});
  final _Ledger ledger;

  /// How many rounds this route asks for before it advances.
  final int respecRounds;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final view =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final rounds = view.cursorOf(args.nodePath).rewindCount;
    if (rounds >= kMaxReworkRounds) {
      return const Gate('spec still failing at the cap — a human decides');
    }
    if (rounds >= respecRounds) return const Ok(); // advance.
    ledger.guidance.add('round ${rounds + 1}: name the exact test command');
    return const Rewind({'specify'}, 'RESPEC: acceptance not falsifiable');
  }
}

/// A RUNAWAY route (a mis-specified asset): rewinds unconditionally, ignoring the
/// cap — the ENGINE BELT must refuse it.
class _RunawayRouteCap extends ServiceCapability {
  const _RunawayRouteCap();
  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async =>
      const Rewind({'specify'}, 'RESPEC: forever');
}

/// A route returning a FIXED outcome (the LOUD-refusal + fence + report cases).
class _FixedCap extends ServiceCapability {
  const _FixedCap(this.outcome);
  final StepOutcome outcome;
  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async => outcome;
}

// --- the RE-KEY isolation fixture (a still-mounted daemon) --------------------

/// The circuit that isolates the RE-KEY half of the arm: `harness` is a DEP-FREE
/// DAEMON, so after a rewind flips it back to `pending` it is STILL ELIGIBLE (no
/// dep withholds it) and its nodePath is unchanged. The ONLY thing that can tear
/// its live process down is the `rewindCount` bump in its reconcile key. Without
/// that bump, keyed reconcile would REUSE the branch and the daemon would be
/// silently left alive under a stale incarnation — the exact failure the arm's
/// doc names.
const _daemonSpec = Circuit(
  id: 'code',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(
      stepId: 'harness',
      capabilityId: 'harness',
      kind: StepKind.daemon,
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'harness'},
    ),
  ],
);

/// A long-lived daemon: `ready` on an activity signal, never completes.
class _HarnessDaemon extends ProcessCapability {
  const _HarnessDaemon();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir:
        context.getInheritedSeedOfExactType<Workspace>()?.workspaceDir ?? '/w',
    command: 'sh',
    args: const ['-c', 'sleep 999'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    ActivityChanged(:final active) when active => StepSignal.ready,
    _ => StepSignal.none,
  };
}

/// The route in the re-key fixture: rewinds the DAEMON itself once, then
/// advances.
class _DaemonRouteCap extends ServiceCapability {
  const _DaemonRouteCap();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final view =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    if (view.cursorOf(args.nodePath).rewindCount >= 1) return const Ok();
    return const Rewind({'harness'}, 'RESPEC: re-run the rig from scratch');
  }
}

// --- the harness: the hosts' OWN writes advance the cursor --------------------

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Replays every `bd update <sessionId> --metadata {...}` the chokepoint recorded
/// onto ONE session bead (bd's `--metadata` MERGE), then projects it with the
/// REAL codec — so the tree advances on the hosts' OWN writes, never on a
/// hand-authored cursor. Gate beads (`create -t gate` + their `blocks`/`node`
/// stamp) are modelled too, so `openGateNodes` is honest and SessionScope's D-7
/// re-arm behaves exactly as it does live.
class _Store {
  _Store(this.runner, {required this.sessionId, required this.workBeadId});

  final RecordingBdRunner runner;
  final String sessionId;
  final String workBeadId;

  final Map<String, String> _metadata = {};
  final Set<String> _openGates = {};

  /// Whether the chokepoint closed this session (the D-2 positive terminal).
  bool get isClosed => runner
      .callsFor('close')
      .any((c) => c.length > 1 && c[1] == sessionId);

  SessionProjection project() {
    for (final call in runner.callsFor('update')) {
      final i = call.indexOf('--metadata');
      if (i < 0 || call.length < 2) continue;
      final decoded = jsonDecode(call[i + 1]) as Map<String, dynamic>;
      if (call[1] == sessionId) {
        decoded.forEach((k, v) => _metadata[k] = '$v');
        continue;
      }
      // A GATE bead's birth stamp (`blocks` = the session, `node` = the parked
      // path) — the join surfaces it as an OPEN gate. Nothing closes gates in
      // these tests, so a minted gate stays open (D-7: the node stays parked).
      if (decoded['blocks'] == sessionId && decoded['node'] is String) {
        _openGates.add(decoded['node']! as String);
      }
    }
    final projected = projectSession(
      Bead(
        id: sessionId,
        issueType: IssueType.session,
        status: isClosed ? BeadStatus.closed : BeadStatus.open,
        metadata: {
          'rig': stateSubstation,
          SessionBeadKeys.workBead: workBeadId,
          ..._metadata,
        },
      ),
    );
    return projected.copyWith(openGateNodes: {..._openGates});
  }
}

class _Rig {
  _Rig(
    Map<String, Capability> capabilities, {
    Circuit root = _code,
    Map<String, Circuit> circuits = const {'spec_review': _specReview},
  }) : _root = root,
       fakes = buildFakes(),
       owner = TreeOwner(),
       joined = JoinedSnapshotNotifier(JoinedSnapshot.empty()) {
    store = _Store(fakes.runner, sessionId: _sessionId, workBeadId: beadId);
    registry = DefaultCapabilityRegistry(
      capabilities: capabilities,
      circuits: circuits,
      clock: () => DateTime(2026),
    );
  }

  final Circuit _root;

  static const _sessionId = 'tgdog-s';

  /// The work bead this rig drives (the circuit's root nodePath).
  static const beadId = 'tg-1';
  final Fakes fakes;
  final TreeOwner owner;
  final JoinedSnapshotNotifier joined;
  late final _Store store;
  late final DefaultCapabilityRegistry registry;

  void mount() {
    // Seed the join with the session the scope ADOPTS (no mint), so every later
    // `bd create` is unambiguously a GATE mint.
    _push(
      const SessionProjection(
        workBeadId: 'tg-1',
        sessionId: _sessionId,
        cursor: {},
      ),
    );
    owner.mountRoot(
      InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: registry,
            child: InheritedSeed<SessionResolver>(
              value: CircuitResolver((_) => _root),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(_tgConfig),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// One turn of the loop: let the in-flight effects write, replay those writes
  /// into the join, re-flush the tree, and let the newly-mounted hosts kick.
  Future<void> tick() async {
    await _pump();
    _push(store.project());
    owner.flush();
    await _pump();
  }

  /// Ticks until the chokepoint goes QUIET (a whole turn with no new bd call) —
  /// the honest quiescence signal, so no test hard-codes a tick count.
  Future<void> settle({int maxTicks = 40}) async {
    for (var i = 0; i < maxTicks; i++) {
      final before = fakes.runner.calls.length;
      await tick();
      if (fakes.runner.calls.length == before) return;
    }
    fail('the tree never settled within $maxTicks ticks');
  }

  /// Ticks until [done] holds — so a test can probe the tree at a DELIBERATE
  /// moment (e.g. the instant the rewind write lands) without hard-coding ticks.
  Future<void> tickUntil(bool Function() done, {int maxTicks = 40}) async {
    for (var i = 0; i < maxTicks; i++) {
      if (done()) return;
      await tick();
    }
    if (!done()) fail('the condition never held within $maxTicks ticks');
  }

  void _push(SessionProjection session) {
    joined.push(
      JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [bead(beadId)],
          dependencies: const [],
          readyIds: {beadId},
          capturedAt: DateTime(2026),
        ),
        sessionsByWorkBead: {beadId: session},
      ),
    );
  }

  /// Every `bd create` the chokepoint issued. The session is ADOPTED, so a
  /// `type=gate` mint is the only thing that can appear here — EMPTY therefore
  /// proves "no gate bead AND no session re-mint" in one assertion.
  List<List<String>> get creates => fakes.runner.callsFor('create');
  List<List<String>> get closes => fakes.runner.callsFor('close');

  /// The merged cursor as the store currently holds it.
  CircuitCursor get cursor => store.project().cursor;

  /// Every `--metadata` payload written to the SESSION bead, as raw JSON, in call
  /// order — the ground truth for "what the hosts actually wrote, and when".
  List<String> get sessionWrites => [
    for (final call in fakes.runner.callsFor('update'))
      if (call.contains('--metadata') &&
          call.length > 1 &&
          call[1] == _sessionId)
        call[call.indexOf('--metadata') + 1],
  ];

  /// The decoded metadata of every session write carrying a REWIND (the axis bump
  /// is written by exactly one payload — `nodeRewoundMetadata`), in order.
  List<Map<String, dynamic>> get rewindWrites => [
    for (final write in sessionWrites)
      if (write.contains(CursorKeys.rewindCount))
        jsonDecode(write) as Map<String, dynamic>,
  ];

  /// Every cursor STATE transition the hosts wrote, as `<nodePath>=<state>`, in
  /// call order — the ordered ground truth a cumulative cursor projection cannot
  /// give (it only ever shows the latest value per node).
  List<String> get stateTrace => [
    for (final write in sessionWrites)
      for (final entry in (jsonDecode(write) as Map<String, dynamic>).entries)
        if (entry.key.startsWith(CursorKeys.prefix) &&
            entry.key.endsWith('.${CursorKeys.state}'))
          '${entry.key.substring(CursorKeys.prefix.length, entry.key.length - CursorKeys.state.length - 1)}'
              '=${entry.value}',
  ];

  void dispose() {
    owner.dispose();
    unawaited(fakes.provider.close());
  }
}

String _spec(String step) => 'tg-1/spec_review/$step';

/// A bare-mounted REAL CapabilityHost over [capability] at the spec circuit's
/// `route` node, with [node] as its cursor entry — the shape the belt / refusal /
/// fence cases need (no join, no SessionScope; just the host's own actuation).
({TreeOwner owner, Fakes fakes}) _bareRoute(
  Capability capability, {
  NodeCursor node = const NodeCursor(),
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: DateTime(2026)),
        child: InheritedSeed<SiblingView>(
          value: const SiblingView(),
          child: CapabilityHost(
            capability: capability,
            mount: StepMount(
              step: const CapabilityStep(stepId: 'route', capabilityId: 'route'),
              nodePath: 'tg-1/spec_review/route',
              circuit: _specReview,
              circuitPath: 'tg-1/spec_review',
              session: const SessionHandle('tgdog-s'),
              node: node,
              key: ValueKey(
                'tg-1/spec_review/route#${node.restartCount}.${node.rewindCount}',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

/// Every `--metadata` payload of every recorded `update`, as raw JSON.
Iterable<String> _allWrites(RecordingBdRunner runner) sync* {
  for (final call in runner.callsFor('update')) {
    final i = call.indexOf('--metadata');
    if (i >= 0) yield call[i + 1];
  }
}

void main() {
  group('tg-o90 — the sub-DAG re-runs with NO gate bead and NO session re-mint',
      () {
    test('the route names its specify SIBLING; the sub-DAG re-runs virgin, the '
        'parent build stays withheld, and the guidance ledger reaches the next '
        'specify brief', () async {
      final ledger = _Ledger();
      final briefs = <String>[];
      final rig = _Rig({
        'specify': _SpecifyCap(ledger, briefs),
        'critic': const _OkCap(),
        'route': _RouteCap(ledger), // respecs once, then advances
        'agent': const _OkCap(),
      })..mount();
      addTearDown(rig.dispose);

      // Drive round 1 up to the INSTANT the rewind write lands (the tree has not
      // yet re-projected it), so the probe below is deliberate, not tick-counted.
      await rig.tickUntil(() => rig.rewindWrites.isNotEmpty);

      // ONE chokepoint write flipped the WHOLE sub-DAG — the named sibling, its
      // transitive dependent, and the rewinding node itself — back to `pending`
      // with a bumped rewind axis AND a fresh restart budget. Asserted as an
      // EXACT map against the production codec, so nothing extra rides along and
      // the crash-restart budget is provably NOT spent (`restartCount: 0`).
      expect(rig.rewindWrites, hasLength(1), reason: 'exactly one rewind write');
      expect(rig.rewindWrites.single, {
        ...nodeRewoundMetadata(_spec('specify'), rewindCount: 1),
        ...nodeRewoundMetadata(_spec('critic'), rewindCount: 1),
        ...nodeRewoundMetadata(_spec('route'), rewindCount: 1),
        // The rewinding node's own terminal telemetry rides the same write.
        ...expectedTiming(_spec('route')),
      });

      // At this instant: NO gate bead minted and NO session re-mint or close —
      // the whole point. The round happens INSIDE the live session. (A session
      // mint is a `bd create`, exactly like a gate mint, so an EMPTY `creates`
      // rules out both.)
      expect(rig.creates, isEmpty, reason: 'no gate bead, no session re-mint');
      expect(rig.closes, isEmpty, reason: 'the session was never retired');

      // Drive round 2 home: the route now advances → the spec terminal is
      // positive → the build finally mounts. The POSITIVE CONTROL — it proves the
      // withholding below was the BARRIER, not a structural dead end.
      await rig.settle();
      expect(rig.cursor['tg-1/agent']!.state, StepState.complete);
      expect(rig.creates, isEmpty, reason: 'no gate bead was ever minted');

      // The sub-DAG genuinely RE-RAN: a SECOND, freshly-keyed `specify`
      // incarnation ran — and its brief carries the guidance the route recorded
      // (round 1's brief was empty). This is the fixable-spec-fail loop closing.
      expect(briefs, hasLength(2), reason: 'specify ran twice (a virgin re-run)');
      expect(briefs.first, isEmpty);
      expect(briefs.last, contains('round 1: name the exact test command'));

      // The parent's build NEVER mounted DURING the rewound round: its first
      // cursor write comes strictly AFTER the rewind (its dep is the sub-circuit
      // terminal, which had regressed to pending). Asserted on write ORDER, so a
      // cumulative cursor can never mask it.
      final writes = rig.sessionWrites;
      final rewindAt = writes.indexWhere(
        (w) => w.contains(CursorKeys.rewindCount),
      );
      final agentAt = writes.indexWhere((w) => w.contains('tg-1/agent.state'));
      expect(rewindAt, isNonNegative);
      expect(
        agentAt,
        greaterThan(rewindAt),
        reason: 'the build is withheld while the spec is being rewound',
      );
    });
  });

  group('tg-o90 — the RE-KEY: a rewound node that is still MOUNTED is KILLED and '
      're-run virgin', () {
    test('a dep-free DAEMON — still ELIGIBLE after the rewind, same nodePath — '
        'is torn down (dispose = KILL) and RE-SPAWNED, because the rewindCount '
        'bump changed its reconcile key', () async {
      final rig = _Rig(
        {'harness': const _HarnessDaemon(), 'route': const _DaemonRouteCap()},
        root: _daemonSpec,
        circuits: const {},
      )..mount();
      addTearDown(rig.dispose);

      const daemon = 'tgdog-s/tg-1/harness';
      List<String> startsOfDaemon() => [
        for (final s in rig.fakes.provider.started)
          if (s.name == daemon) s.name,
      ];

      // The daemon spawns, then signals READY — it is LIVE and MOUNTED.
      await rig.tick();
      expect(startsOfDaemon(), hasLength(1), reason: 'the daemon spawned');
      rig.fakes.provider.emit(
        const RuntimeEvent.activityChanged(name: daemon, active: true),
      );

      // Its `ready` satisfies the route's dep, the route runs, and it REWINDS the
      // daemon itself. Drive to the instant that rewind write lands.
      await rig.tickUntil(() => rig.rewindWrites.isNotEmpty);
      expect(
        rig.stateTrace.first,
        'tg-1/harness=ready',
        reason: 'the daemon really was LIVE and READY when the route rewound it '
            '(so what follows is a rewind of a MOUNTED effect, not of an idle '
            'node)',
      );
      expect(rig.rewindWrites.single, {
        ...nodeRewoundMetadata('tg-1/harness', rewindCount: 1),
        ...nodeRewoundMetadata('tg-1/route', rewindCount: 1),
        ...expectedTiming('tg-1/route'),
      });

      // THE NEGATIVE CONTROL: the rewind WRITE alone kills nothing — the daemon is
      // still mounted and still running at this instant. Only the reconcile that
      // follows can tear it down.
      expect(rig.fakes.provider.stopped, isEmpty);

      // Now the rewind is projected. The daemon reads `pending` with NO deps → it
      // is STILL ELIGIBLE, at the SAME nodePath — so the ONLY thing that can move
      // it is its KEY (the rewindCount bump). It was KILLED (ADR-0009 D4: dispose
      // = kill) and RE-SPAWNED virgin.
      await rig.tick();
      expect(
        rig.fakes.provider.stopped,
        contains(daemon),
        reason: 'the re-key DISPOSED the live daemon (dispose = KILL)',
      );
      expect(
        startsOfDaemon(),
        hasLength(2),
        reason: 'a FRESH incarnation spawned — the daemon was not left alive '
            'under a stale one',
      );

      // And the loop closes: the fresh daemon re-readies, the route advances, and
      // the session reaches its positive terminal (the positive control).
      rig.fakes.provider.emit(
        const RuntimeEvent.activityChanged(name: daemon, active: true),
      );
      await rig.settle();
      expect(rig.cursor['tg-1/route']!.state, StepState.complete);
      expect(rig.creates, isEmpty, reason: 'no gate bead, no session re-mint');
    });
  });

  group('tg-o90 — BOUNDED at the rework cap', () {
    test('(a) the route escalates on its OWN policy at the cap: Gate, never '
        'another Rewind', () async {
      final rig = _Rig({
        'specify': const _OkCap(),
        'critic': const _OkCap(),
        // Always wants a respec — so only the cap can stop it.
        'route': _RouteCap(_Ledger(), respecRounds: 99),
        'agent': const _OkCap(),
      })..mount();
      addTearDown(rig.dispose);

      await rig.settle();

      // Exactly kMaxReworkRounds rounds were admitted, then the route gated.
      expect(rig.cursor[_spec('route')]!.rewindCount, kMaxReworkRounds);
      expect(rig.cursor[_spec('route')]!.state, StepState.gated);
      final gates = rig.creates;
      expect(gates, hasLength(1), reason: 'exactly one human gate');
      expect(gates.single, containsAllInOrder(['--type', 'gate']));
      // The build never ran — the spec never reached a positive terminal.
      expect(rig.cursor.containsKey('tg-1/agent'), isFalse);
    });

    test('(b) the ENGINE BELT refuses a RUNAWAY route at the cap: a human Gate, '
        'never another Rewind', () async {
      // A mis-specified asset: the route returns Rewind unconditionally, and its
      // node is ALREADY at the cap.
      final h = _bareRoute(
        const _RunawayRouteCap(),
        node: const NodeCursor(rewindCount: kMaxReworkRounds),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      // It parked at a human gate (state=gated + a real type=gate bead)...
      expect(
        h.fakes.runner.metadataOfUpdate(
          0,
        )['grid.cursor.tg-1/spec_review/route.state'],
        'gated',
      );
      final creates = h.fakes.runner.callsFor('create');
      expect(creates, hasLength(1));
      expect(creates.single, containsAllInOrder(['--type', 'gate']));

      // ...and NOTHING was rewound: no `pending` write, no axis bump anywhere.
      for (final write in _allWrites(h.fakes.runner)) {
        expect(write.contains('pending'), isFalse);
        expect(write.contains('rewindCount'), isFalse);
      }
    });
  });

  group('tg-o90 — LOUD refusal (a rewind naming nothing real)', () {
    test('an UNKNOWN step id routes to supervision as Failed, with no pending '
        'write and no gate bead', () async {
      final h = _bareRoute(const _FixedCap(Rewind({'nope'}, 'typo')));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/spec_review/route.state'], 'failed');
      expect(meta['grid.cursor.tg-1/spec_review/route.restartCount'], '1');
      expect(
        meta['grid.cursor.tg-1/spec_review/route.failureReason'],
        contains('unknown step(s) nope'),
      );
      expect(h.fakes.runner.callsFor('create'), isEmpty, reason: 'no gate bead');
      for (final write in _allWrites(h.fakes.runner)) {
        expect(write.contains('pending'), isFalse);
      }
    });

    test('an EMPTY stepIds routes to supervision as Failed — never a silent '
        '"re-run only myself, forever"', () async {
      final h = _bareRoute(const _FixedCap(Rewind({}, 'oops')));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/spec_review/route.state'], 'failed');
      expect(
        meta['grid.cursor.tg-1/spec_review/route.failureReason'],
        contains('rewind named no steps'),
      );
      expect(h.fakes.runner.callsFor('create'), isEmpty);
    });
  });

  group('tg-o90 — the FENCE: an existing D-7 human Gate parks exactly as today',
      () {
    test('a Gate from the SAME circuit writes gated + mints a gate bead and '
        'rewinds NOTHING', () async {
      final h = _bareRoute(const _FixedCap(Gate('human ultimatum')));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      expect(
        h.fakes.runner.metadataOfUpdate(
          0,
        )['grid.cursor.tg-1/spec_review/route.state'],
        'gated',
      );
      final creates = h.fakes.runner.callsFor('create');
      expect(creates, hasLength(1));
      expect(creates.single, containsAllInOrder(['--type', 'gate']));

      // The park is NOT a rewind: no sibling was touched, no axis bumped.
      for (final write in _allWrites(h.fakes.runner)) {
        expect(write.contains('specify'), isFalse);
        expect(write.contains('rewindCount'), isFalse);
      }
    });
  });

  group('tg-o90 — the allocation layer maps a Rewind to a DISTINCT report', () {
    test('ServiceAllocation reports AllocationRewound (never Gated/Failed)',
        () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final alloc = ServiceAllocation(
        const _FixedCap(Rewind({'specify'}, 'respec')),
        AllocationContext(
          treeContext: FakeTreeContext(),
          args: stepArgs('tg-1/spec_review/route'),
          transport: provider,
          address: const AllocationAddress('tgdog-s', 'tg-1/spec_review/route'),
          env: const {},
          sink: reports.add,
        ),
      );
      await alloc.startOrAdopt();

      expect(reports, hasLength(1));
      final report = reports.single;
      expect(report, isA<AllocationRewound>());
      expect((report as AllocationRewound).stepIds, {'specify'});
      expect(report.reason, 'respec');
    });
  });
}
