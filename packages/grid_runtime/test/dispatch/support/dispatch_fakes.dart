import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// A fake [ReadyWorkSource] (Fakes, not mocks): a programmable ready set + a
/// synthetic `GraphEvent` stream. A consumer reacts to the events and resolves
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
  /// event shape beads_dart emits when the ready set changes.
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

/// A fake [GitRunner] (Fakes, not mocks): returns canned [GitRunResult]s keyed
/// by the leading git subcommand so the REAL [StationGitService] runs end-to-end
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
