// Shared offline fakes for the grid_engine suite (Fakes, not mocks).
//
// Promoted to a public testing-support library (`package:grid_engine/testing.dart`)
// so BOTH grid_engine's own suite AND downstream asset packages (grid_assets)
// drive the SAME controllable transport + recording chokepoint. The
// code-asset-specific helpers (`kCodeResolver`/`_codeCircuit`) do NOT live here
// — they reference the moved `kCodeCircuit`/`buildCodeRegistry` opinions and so
// belong in grid_assets's test support. Everything here is pure-Dart: no live
// tg/gc/agent/git/network.
import 'dart:async';
import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

// ---------------------------------------------------------------------------
// The runtime transport: a controllable RuntimeProvider whose event stream a
// test emits SessionStarted / Exited / Died on demand, recording every start /
// stop in call order.
// ---------------------------------------------------------------------------

/// Records start/stop calls and exposes a controllable events stream so a test
/// emits SessionStarted/Exited/Died on demand. Only the members the effect
/// touches are meaningful; the rest are honest no-ops over an empty surface.
class FakeRuntimeProvider implements RuntimeProvider {
  /// Creates the fake provider with a broadcast event stream.
  FakeRuntimeProvider() {
    _events = StreamController<RuntimeEvent>.broadcast(
      onListen: () => _eventListeners++,
      onCancel: () => _eventListeners--,
    );
  }

  late final StreamController<RuntimeEvent> _events;

  int _eventListeners = 0;

  /// The number of live subscriptions to [events] (added and not yet
  /// cancelled). Lets a test prove the effect's per-incarnation subscription is
  /// actually torn down on dispose (PDR §7 (f) — the subscription-cancel half).
  int get eventListenerCount => _eventListeners;

  /// (name, config) of every `start`, in call order.
  final List<({String name, RuntimeConfig config})> started = [];

  /// Every `stop`ped session name, in call order.
  final List<String> stopped = [];

  /// A gate the test can hold to delay a `start` (proves the spawn ordering /
  /// races); when null, `start` completes immediately.
  Completer<void>? startGate;

  /// When set, the next `start` throws this (e.g. SessionAlreadyExists).
  Object? throwOnStart;

  /// The live session names — registered by a COMPLETED `start` (the spawn
  /// LANDED), removed by `stop`. What `listRunning`/`isRunning`/`processAlive`
  /// reflect, so a test can prove a spawn landing mid-teardown is visible to
  /// `RestartReconciler.sweepOrphans`.
  final Set<String> _live = <String>{};

  /// Emits [event] to subscribers (after a microtask, like a real stream).
  void emit(RuntimeEvent event) => _events.add(event);

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    started.add((name: name, config: config));
    if (startGate != null) await startGate!.future;
    final t = throwOnStart;
    if (t != null) {
      throwOnStart = null;
      throw t;
    }
    // The spawn LANDED — only now does the transport hold the session.
    _live.add(name);
  }

  @override
  Future<void> stop(String name) async {
    stopped.add(name);
    _live.remove(name);
  }

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream.empty();

  @override
  bool isRunning(String name) => _live.contains(name);

  @override
  bool processAlive(String name) => _live.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _live.where((n) => n.startsWith(prefix)).toList(growable: false);

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  /// Closes the broadcast event stream (call from an `addTearDown`).
  Future<void> close() => _events.close();
}

// ---------------------------------------------------------------------------
// The bd write chokepoint, faked at the BdRunner seam: records full argv +
// stdin so a test asserts the EXACT bd commands, and `create` returns a
// caller-controlled synthetic id so the mint+stamp runs with no real `bd`.
// ---------------------------------------------------------------------------

/// A recording [BdRunner] (the grid_runtime fake shape): records full argv +
/// stdin so a test asserts the EXACT bd commands, and `create` returns a
/// caller-controlled synthetic id so the mint+stamp is exercised with no real
/// `bd`.
class RecordingBdRunner implements BdRunner {
  /// Creates the recorder; `create` returns [createdId].
  RecordingBdRunner({String createdId = 'tgdog-sess1'}) : _createdId = createdId;

  final String _createdId;

  /// Full argv of every recorded `bd` call, in order.
  final List<List<String>> calls = <List<String>>[];

  /// The `--stdin` payload of every recorded call (null when none), in order.
  final List<String?> stdins = <String?>[];

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    stdins.add(stdin);
    final sub = args.isNotEmpty ? args.first : '';
    final data = switch (sub) {
      'create' => '{"id":"$_createdId"}',
      _ => '{"id":"${args.length >= 2 ? args[1] : ''}"}',
    };
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":$data}',
        stderr: '',
      ),
    );
  }

  /// All calls whose leading subcommand is [sub].
  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

  /// The decoded `--metadata` JSON object of the `update` call at [index].
  Map<String, dynamic> metadataOfUpdate(int index) {
    final updates = callsFor('update');
    final c = updates[index];
    final i = c.indexOf('--metadata');
    return jsonDecode(c[i + 1]) as Map<String, dynamic>;
  }

  /// True if no call was `bd show` (forbidden on a controller path) and no call
  /// looks like raw SQL (defense — the chokepoint cannot issue SQL by
  /// construction).
  bool get neverShowOrSql => calls.every(
    (c) => c.isEmpty || (c.first != 'show' && c.first != 'sql'),
  );
}

/// A [BdRunner] whose `create` parks until [releaseCreate] is called, so a test
/// can drive a dispose into the middle of the async mint.
class GatedCreateBdRunner implements BdRunner {
  Completer<String>? _createGate;

  /// True while a `create` is parked awaiting [releaseCreate].
  bool get createPending => _createGate != null && !_createGate!.isCompleted;

  /// Resolves the in-flight `create` with [id].
  void releaseCreate(String id) => _createGate!.complete(id);

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'create') {
      _createGate = Completer<String>();
      final id = await _createGate!.future;
      return BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{"id":"$id"}}',
        stderr: '',
      );
    }
    final id = args.length >= 2 ? args[1] : '';
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$id"}}',
      stderr: '',
    );
  }
}

// ---------------------------------------------------------------------------
// The land-orchestration ops: a recording git runner (wrapped in the REAL
// GitOps so commit/push run their real argv against the fake) + a recording
// PrOpener with a settable success/failure outcome.
// ---------------------------------------------------------------------------

/// A recording [GitRunner]: records every `git` argv (with its cwd) in order,
/// and returns a configurable result so commit/push read `ok`. Wrap it in the
/// real [GitOps] so the land step's real `add -A` / `commit -m` / `push -u`
/// argv is what gets recorded (Fakes, not mocks).
class RecordingGitRunner implements GitRunner {
  /// Every (workDir, args) `git` invocation, in call order.
  final List<({String workDir, List<String> args})> calls = [];

  /// The exit code the next runs return (0 ⇒ `ok`). Settable so a test can make
  /// a step fail.
  int exitCode = 0;

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workDir: workingDirectory, args: List.unmodifiable(args)));
    return GitRunResult(exitCode: exitCode, output: '');
  }

  /// The flattened leading subcommands of every recorded `git` call, in order
  /// (`['add', 'commit', 'push']` for a clean land).
  List<String> get subcommands =>
      [for (final c in calls) c.args.isNotEmpty ? c.args.first : ''];
}

/// A recording [PrOpener]: records every `open` call and returns a settable
/// [PullRequestResult] (success with a configurable url, or a failure). Never
/// touches real GitHub.
class FakePrOpener implements PrOpener {
  /// Creates the recorder; a successful open returns [url].
  FakePrOpener({this.url = 'https://github.com/memento/genesis/pull/42'});

  /// The url a successful open returns; ignored when [failNext] is set.
  String url;

  /// When true, the next `open` returns a [PullRequestResult.failed] (and is
  /// NOT cleared — every open then fails) so a test can assert the no-record /
  /// no-close path.
  bool failNext = false;

  /// Every (workDir, branch, baseBranch, title, body) open, in call order.
  final List<
    ({
      String workDir,
      String branch,
      String baseBranch,
      String title,
      String body,
    })
  >
  opened = [];

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    opened.add((
      workDir: workDir,
      branch: branch,
      baseBranch: baseBranch,
      title: title,
      body: body,
    ));
    if (failNext) {
      return PullRequestResult.failed(const PrOpenFailure('fake: open refused'));
    }
    return PullRequestResult.opened(PullRequestRef(url: url));
  }
}

// ---------------------------------------------------------------------------
// The observable snapshot seam: a fake SnapshotSource (a broadcast controller +
// a settable current), so the join bridge is driven in pure-Dart.
// ---------------------------------------------------------------------------

/// A fake [SnapshotSource]: a broadcast [StreamController] the test pushes
/// through, plus a settable [current] (mirroring the real runtime's
/// last-emitted accessor). `push` updates `current` AND emits, 1:1, like the
/// change-gated runtime.
class FakeSnapshotSource implements SnapshotSource {
  /// Creates the fake source with an optional initial [current].
  FakeSnapshotSource([this._current]);

  final _controller = StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  /// Sets [current] and emits the snapshot to subscribers (after a microtask,
  /// like a real broadcast stream).
  void push(GraphSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  /// Emits an error on the stream WITHOUT touching [current] — a fake
  /// connection blip, so a consumer's absence-≠-deletion handling (tg-nsj
  /// D-Z3) can be proven without retracting the last known snapshot.
  void raiseError(Object error) => _controller.addError(error);

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  /// Closes the stream (call from an `addTearDown`).
  Future<void> close() => _controller.close();
}

// ---------------------------------------------------------------------------
// The bare-drive harness (the context rip-out, 2026-07-02): a fake TreeContext
// so an Allocation/Capability is drivable WITHOUT a mounted tree, plus the
// StepArgs builder. Fakes, not mocks.
// ---------------------------------------------------------------------------

/// A fake [TreeContext] for driving an [Allocation]/[Capability] bare — no
/// mounted tree. Ambient values resolve from [values] by EXACT type (mirroring
/// genesis's exact-type inherited lookup). Flip [mounted] to false to exercise
/// the loud async-gap protection ([getInheritedSeedOfExactType] then throws,
/// like the real handle).
class FakeTreeContext implements TreeContext {
  /// Creates the fake with the ambient [values] (keyed by exact type).
  FakeTreeContext({Map<Type, Object> values = const {}})
    : _values = Map.of(values);

  final Map<Type, Object> _values;

  /// Whether the (fake) branch is still mounted — settable so a test drives
  /// the unmounted-throw path.
  @override
  bool mounted = true;

  @override
  Key? get key => null;

  @override
  String get branchId => 'fake-branch';

  void _checkMounted(String member) {
    if (!mounted) {
      throw StateError('FakeTreeContext.$member used after unmount');
    }
  }

  @override
  T? dependOnInheritedSeedOfExactType<T extends Object>() {
    _checkMounted('dependOnInheritedSeedOfExactType');
    return _values[T] as T?;
  }

  @override
  T? getInheritedSeedOfExactType<T extends Object>() {
    _checkMounted('getInheritedSeedOfExactType');
    return _values[T] as T?;
  }

  @override
  void markNeedsRebuild() {}

  /// Adds/replaces the ambient value for exact type [T].
  void provide<T extends Object>(T value) => _values[T] = value;
}

/// [StepArgs] for a bare-driven capability/allocation (a fresh [CancelToken]
/// unless one is injected).
StepArgs stepArgs(
  String nodePath, {
  Map<String, String> params = const {},
  CancelToken? cancel,
}) => StepArgs(params: params, nodePath: nodePath, cancel: cancel ?? CancelToken());

/// The capture-only flow-telemetry keys (FT-1, tg-pez) a TERMINAL cursor write
/// carries under a FIXED test clock (default [DateTime]`(2026)`): the host
/// captures `startedAt` at its kick and `finishedAt` at the terminal, so under a
/// non-advancing clock they are the SAME instant and `durationMs` is 0. Spread
/// into an exact-map assertion for a terminal transition. Reuses the production
/// codec ([nodeTelemetryMetadata]) so the expectation tracks the wire format —
/// the timing VALUES/ordering are proven independently in the codec + host tests.
Map<String, String> expectedTiming(
  String nodePath, {
  DateTime? clock,
  int durationMs = 0,
}) {
  final t = clock ?? DateTime(2026);
  return nodeTelemetryMetadata(
    nodePath,
    startedAt: t,
    finishedAt: t,
    durationMs: durationMs,
  );
}

/// A monotonically ADVANCING clock (FT-1, tg-pez) — each call returns the next
/// instant [step] apart, starting at [from] (default [DateTime]`(2026)`). Feed to
/// [RecordingCapabilityRegistry.new]'s `nowFn` so the host's kick and terminal
/// read DISTINCT instants, proving `startedAt < finishedAt` and a deterministic
/// `durationMs` (the first two `now()` calls of a clean transition are `step`
/// apart).
DateTime Function() advancingClock({
  DateTime? from,
  Duration step = const Duration(seconds: 1),
}) {
  var next = from ?? DateTime(2026);
  return () {
    final current = next;
    next = next.add(step);
    return current;
  };
}

/// A [Workspace] for a bare-driven test (the synthetic offline shape
/// `SessionScope` mounts when no source control is wired).
Workspace testWorkspace(
  String beadId, {
  String? workspaceDir,
  String branch = '',
  String baseBranch = 'main',
}) => Workspace(
  workspaceDir: workspaceDir ?? '/grid/workspaces/$beadId',
  branch: branch,
  baseBranch: baseBranch,
);

// ---------------------------------------------------------------------------
// Builders: the StationServices + a Bead, over the fakes.
// ---------------------------------------------------------------------------

/// The_grid's owned state substation in the offline fakes.
const stateSubstation = 'tgdog';

/// A bundle of an [StationServices] over the fakes plus the recording collaborators
/// the test asserts against.
typedef Fakes = ({
  StationServices ctx,
  RecordingBdRunner runner,
  FakeRuntimeProvider provider,
  RecordingGitRunner git,
  FakePrOpener pr,
});

/// Builds an [StationServices] over the fakes (the chokepoint writes through a
/// recording bd runner; the transport is a controllable provider; land is wired
/// to the recording git/PR ops) and returns it with the recorders.
Fakes buildFakes({String createdId = 'tgdog-sess1'}) {
  final runner = RecordingBdRunner(createdId: createdId);
  final provider = FakeRuntimeProvider();
  final git = RecordingGitRunner();
  final pr = FakePrOpener();
  final writer = StationBeadWriter(
    bd: BdCliService(runner),
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  );
  return (
    // Station-level ambient only (ADR-0009 D2): transport + chokepoint + state
    // substation. The git/PR recorders are returned separately so a test wires its own
    // per-substation `GitSourceControl`/`ServiceBundle` (the workspace/branch
    // layout is the SourceControl's, not the station's — ADR-0008 D5).
    ctx: StationServices(
      provider: provider,
      writer: writer,
      stateSubstation: stateSubstation,
    ),
    runner: runner,
    provider: provider,
    git: git,
    pr: pr,
  );
}

/// An open task bead with [id].
Bead bead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

/// A `type=session` state bead linking [workBeadId] — the row the join bridge
/// projects + keys by `work_bead`, carrying the OWNED substation marker (the
/// persisted `metadata.rig` key — codec law; so the
/// chokepoint's ownership re-check passes) + the per-node reentrant cursor: each
/// step id in [completed] is marked `complete` at nodePath `'$workBeadId/$step'`
/// (the read half of the cursor the CircuitScope frontier advances on). The
/// `code` circuit's steps are `agent` → `verify` → `land`, so
/// `completed: {'agent'}` makes `verify` eligible, `{'agent','verify'}` makes
/// `land` eligible, and `{'agent','verify','land'}` is the positive terminal.
Bead sessionBead({
  required String id,
  required String workBeadId,
  Set<String> completed = const {},
  bool closed = false,
  bool outcomeComplete = false,
  bool escalated = false,
  Map<String, String> cursorStates = const {},
  Map<String, String> metadata = const {},
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBeadId,
    for (final step in completed)
      ...nodeStateMetadata('$workBeadId/$step', StepState.complete),
    // The I-10 closed-session shapes: the engine's own DONE evidence, a HUMAN
    // marker, and an arbitrary in-flight cursor (`{'agent': 'running'}`).
    if (outcomeComplete) ...sessionCompleteMetadata(),
    if (escalated) SessionBeadKeys.escalation: 'breaker-exhausted',
    for (final entry in cursorStates.entries)
      CursorKeys.keyFor('$workBeadId/${entry.key}', CursorKeys.state):
          entry.value,
    ...metadata,
  },
);

// ---------------------------------------------------------------------------
// The reentrant inflater fakes (Track C/D): a CapabilityRegistry whose `host`
// returns a recording leaf (the spawn proxy, like the Track A _FakeEffect) and
// whose `circuit` resolves from an injected map; a fixed clock keeps the
// frontier predicate deterministic.
// ---------------------------------------------------------------------------

/// A recording [CapabilityRegistry]: `host` mounts a fake leaf that records
/// `START`/`STOP <capabilityId>(<sessionId>/<nodePath>)` so a test asserts the
/// inflation frontier AND the disjoint per-session routing; `circuit` resolves
/// from [circuits]; `now` is a fixed [clock].
class RecordingCapabilityRegistry implements CapabilityRegistry {
  /// Creates the recorder over the injected [circuits] + fixed [clock], or an
  /// ADVANCING [nowFn] (FT-1, tg-pez) that returns a fresh instant per `now()`
  /// call so a test can prove `startedAt < finishedAt` / a non-zero `durationMs`
  /// (use [advancingClock]). [nowFn] wins when both are supplied.
  RecordingCapabilityRegistry({
    Map<String, Circuit> circuits = const {},
    DateTime? clock,
    DateTime Function()? nowFn,
  }) : _circuits = circuits,
       _now = nowFn ?? (() => clock ?? DateTime(2026));

  final Map<String, Circuit> _circuits;
  final DateTime Function() _now;

  /// Leaf lifecycle in mount/unmount order — the observable proxy for
  /// spawn (`START`) / kill (`STOP`).
  final List<String> events = [];

  @override
  Circuit? circuit(String circuitId) => _circuits[circuitId];

  @override
  DateTime now() => _now();

  @override
  Seed host(StepMount mount) => FakeCapabilityHost(registry: this, mount: mount, key: mount.key);
}

/// A recording fake leaf (NOT the real `CapabilityHost`): records its mount /
/// unmount with its capabilityId, session, and path, and is a pure `Idle` leaf.
class FakeCapabilityHost extends StatefulSeed {
  /// Creates the recording leaf bound to [registry] + [mount].
  const FakeCapabilityHost({
    required this.registry,
    required this.mount,
    super.key,
  });

  /// The registry whose `events` log this leaf appends to.
  final RecordingCapabilityRegistry registry;

  /// The step mount this leaf records.
  final StepMount mount;

  @override
  State<FakeCapabilityHost> createState() => _FakeCapabilityHostState();
}

class _FakeCapabilityHostState extends State<FakeCapabilityHost> {
  String get _label =>
      '${seed.mount.step.capabilityId}'
      '(${seed.mount.session.sessionId}/${seed.mount.nodePath})';

  @override
  void initState() => seed.registry.events.add('START $_label');

  @override
  void dispose() => seed.registry.events.add('STOP $_label');

  @override
  Seed build(TreeContext context) => const Idle();
}
