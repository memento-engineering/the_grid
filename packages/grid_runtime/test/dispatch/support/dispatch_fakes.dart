import 'dart:async';
import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// A fake [ReadyWorkSource] (Fakes, not mocks): a programmable ready set + a
/// synthetic `GraphEvent` stream, mirroring grid_reconciler's
/// `FakeConvergenceSource`. The dispatcher reacts to the events and resolves
/// entered ids via [bead] / [readyBeads] — both backed by the same in-memory
/// map so a test can stage a ready bead then fire a `readySetChanged` for it.
class FakeReadyWorkSource implements ReadyWorkSource {
  final StreamController<GraphEvent> _events =
      StreamController<GraphEvent>.broadcast();

  /// The current snapshot's beads keyed by id (ready set + lookup table).
  final Map<String, Bead> _beads = {};

  /// Stages [bead] into the current ready set (so [readyBeads]/[bead] see it).
  void addReady(Bead bead) => _beads[bead.id] = bead;

  /// Fires a `readySetChanged` carrying [entered] (and optional [exited]) — the
  /// event shape grid_controller emits when the ready set changes.
  void fireReady(Set<String> entered, {Set<String> exited = const {}}) {
    _events.add(GraphEvent.readySetChanged(entered: entered, exited: exited));
  }

  /// Fires an arbitrary non-ready event (to prove the dispatcher ignores it).
  void fire(GraphEvent event) => _events.add(event);

  @override
  Stream<GraphEvent> get events => _events.stream;

  @override
  List<Bead> get readyBeads => _beads.values.toList(growable: false);

  @override
  Bead? bead(String id) => _beads[id];

  Future<void> close() => _events.close();
}

/// A fake [RuntimeProvider] (Fakes, not mocks): records every `start`/`stop`
/// call and the config it was handed, never spawns a real process, and lets a
/// test drive the lifecycle by emitting `RuntimeEvent`s on its own `events`
/// stream (the same stream the bound [RuntimeActuator] listens to).
class FakeRuntimeProvider implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();

  /// (name, config) of every `start` call, in order.
  final List<({String name, RuntimeConfig config})> starts = [];

  /// Every `stop`ped name, in order.
  final List<String> stops = [];

  final Set<String> _running = {};

  /// Set false to make the next `start` throw [SessionAlreadyExists] for a
  /// name already started (the real provider rejects a duplicate live name).
  bool rejectDuplicateStart = true;

  /// How many times a session [name] was started (proves no double-spawn).
  int startCountFor(String name) => starts.where((s) => s.name == name).length;

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (rejectDuplicateStart && _running.contains(name)) {
      throw SessionAlreadyExists(name);
    }
    starts.add((name: name, config: config));
    _running.add(name);
  }

  @override
  Future<void> stop(String name) async {
    stops.add(name);
    _running.remove(name);
  }

  @override
  Future<void> interrupt(String name) async {}

  /// Emits [event] on the provider's stream (the actuator + dispatcher react).
  void emit(RuntimeEvent event) => _events.add(event);

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream.empty();

  @override
  bool isRunning(String name) => _running.contains(name);

  @override
  bool processAlive(String name) => _running.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _running.where((n) => n.startsWith(prefix)).toList();

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> close() => _events.close();
}

/// A fake [GitRunner] (Fakes, not mocks): returns canned [GitRunResult]s keyed
/// by the leading git subcommand so the REAL [GridGitService] runs end-to-end
/// with no real `git`. `worktree add`/`remove` succeed; the three reap gates
/// (`status`/`rev-list`/`stash list`) report CLEAN by default, and a test can
/// flip [unpushed] to prove the fail-closed reaper refuses an unpushed
/// worktree. Records every invocation's argv for assertions.
class FakeGitRunner implements GitRunner {
  /// When true, the unpushed gate (`git log HEAD --oneline --not --remotes`)
  /// reports unpushed commits → the reaper must refuse (fail-closed).
  bool unpushed = false;

  /// Every `git [args]` invocation, in order.
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    final head = args.isNotEmpty ? args.first : '';
    final sub = args.length >= 2 ? args[1] : '';

    // rev-parse --git-dir (isRepo) — yes.
    if (head == 'rev-parse') {
      return const GitRunResult(exitCode: 0, output: '.git');
    }
    // status --porcelain (uncommitted gate) — clean.
    if (head == 'status') {
      return const GitRunResult(exitCode: 0, output: '');
    }
    // log HEAD --oneline --not --remotes (unpushed gate) — empty (clean) unless
    // `unpushed`, in which case the gate reads `present` → the reaper refuses.
    if (head == 'log') {
      return GitRunResult(
        exitCode: 0,
        output: unpushed ? 'deadbeef WIP\n' : '',
      );
    }
    // stash list (stash gate) — empty.
    if (head == 'stash') {
      return const GitRunResult(exitCode: 0, output: '');
    }
    if (head == 'worktree') {
      // worktree add / remove — succeed AND mirror the on-disk effect so the
      // reaper's scope-gate canonicalization (which resolves symlinks where the
      // path exists, e.g. macOS /var→/private/var) is consistent between the
      // worktrees root and the leaf. `worktree add -b <br> <path> <base>` →
      // create args[4]; `worktree remove <path>` → delete args[2]; list → empty.
      if (sub == 'add' && args.length >= 5) {
        Directory(args[4]).createSync(recursive: true);
      } else if (sub == 'remove' && args.length >= 3) {
        final dir = Directory(args[2]);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
      return const GitRunResult(exitCode: 0, output: '');
    }
    // commit/push/anything else — succeed.
    if (sub.isNotEmpty || head.isNotEmpty) {
      return const GitRunResult(exitCode: 0, output: '');
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}

/// A fake [PrOpener] (Fakes, not mocks): never runs `gh`; returns a canned PR.
class FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    return PullRequestResult.opened(
      PullRequestRef(url: 'https://example.test/pr/1', number: 1),
    );
  }
}
