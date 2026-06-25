// Shared offline fakes for the grid_engine suite (Fakes, not mocks).
//
// Extracted from effect_seed_test.dart so the kernel reactive-loop test, the
// land test, and the effect-seed test all drive the SAME controllable
// transport + recording chokepoint. Everything here is pure-Dart: no live
// tg/gc/claude/git/network.
import 'dart:async';
import 'dart:convert';

import 'package:grid_controller/grid_controller.dart';
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
  final _events = StreamController<RuntimeEvent>.broadcast();

  /// (name, config) of every `start`, in call order.
  final List<({String name, RuntimeConfig config})> started = [];

  /// Every `stop`ped session name, in call order.
  final List<String> stopped = [];

  /// A gate the test can hold to delay a `start` (proves the spawn ordering /
  /// races); when null, `start` completes immediately.
  Completer<void>? startGate;

  /// When set, the next `start` throws this (e.g. SessionAlreadyExists).
  Object? throwOnStart;

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
  }

  @override
  Future<void> stop(String name) async => stopped.add(name);

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream.empty();

  @override
  bool isRunning(String name) => false;

  @override
  bool processAlive(String name) => false;

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) => const [];

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
  RecordingBdRunner({String createdId = 'tgdog-sess1'}) : _createdId = createdId;

  final String _createdId;
  final List<List<String>> calls = <List<String>>[];
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
  FakeSnapshotSource([this._current]);

  final _controller = StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  /// Sets [current] and emits the snapshot to subscribers (after a microtask,
  /// like a real broadcast stream).
  void push(GraphSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  /// Closes the stream (call from an `addTearDown`).
  Future<void> close() => _controller.close();
}

// ---------------------------------------------------------------------------
// Builders: the EffectContext + a Bead, over the fakes.
// ---------------------------------------------------------------------------

/// The_grid's owned state rig in the offline fakes.
const stateRig = 'tgdog';

/// A bundle of an [EffectContext] over the fakes plus the recording collaborators
/// the test asserts against.
typedef Fakes = ({
  EffectContext ctx,
  RecordingBdRunner runner,
  FakeRuntimeProvider provider,
  RecordingGitRunner git,
  FakePrOpener pr,
});

/// Builds an [EffectContext] over the fakes (the chokepoint writes through a
/// recording bd runner; the transport is a controllable provider; land is wired
/// to the recording git/PR ops) and returns it with the recorders.
Fakes buildFakes({
  String createdId = 'tgdog-sess1',
  String? worktreeRoot,
  String workRig = '',
  String baseBranch = 'main',
}) {
  final runner = RecordingBdRunner(createdId: createdId);
  final provider = FakeRuntimeProvider();
  final git = RecordingGitRunner();
  final pr = FakePrOpener();
  final writer = GridBeadWriter(
    bd: BdCliService(runner),
    ownership: BeadOwnershipPredicate(const {stateRig}),
  );
  return (
    ctx: EffectContext(
      provider: provider,
      writer: writer,
      stateRig: stateRig,
      gitOps: GitOps(git),
      prOpener: pr,
      worktreeRoot: worktreeRoot,
      workRig: workRig,
      baseBranch: baseBranch,
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
