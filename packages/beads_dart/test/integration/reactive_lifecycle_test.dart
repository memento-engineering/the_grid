@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import 'support/hermetic_workspace.dart';

/// Criterion 1 (PDR §6.1): a hermetic reactive lifecycle.
///
/// temp dir → `bd init` → build a [GridControllerRuntime] over a real
/// [BdCliService]/[CliSnapshotReader] with an injected [ManualDirtySource] for
/// deterministic refresh triggering → mutate via the real `bd` binary → assert
/// the typed [GraphEvent]s arrive, ordered, within a generous ≤2s budget, and
/// print the measured per-event reaction latency (`stats.lastReaction`).
///
/// The mutation sequence exercises every lifecycle event the criterion names:
/// * create a `molecule` titled "tron lives" → [BeadCreated] (a molecule is a
///   container, so it does NOT enter the ready set — `bd ready` excludes it);
/// * create a `task` → [BeadCreated] *and* [ReadySetChanged] (a task with no
///   blockers is immediately claimable, so it enters the ready set);
/// * close the task → [BeadClosed] *and* [ReadySetChanged] (it exits ready).
void main() {
  late HermeticWorkspace ws;
  late GridControllerRuntime runtime;
  late ManualDirtySource manual;

  setUp(() async {
    ws = await HermeticWorkspace.create(prefix: 'grid_it_lifecycle_');

    // Real bd CLI against the hermetic workspace; CLI read path (embedded mode).
    final bd = BdCliService(ProcessBdRunner(workspaceRoot: ws.rootPath));
    final reader = CliSnapshotReader(bd);

    // Inject a ManualDirtySource so refreshes are driven deterministically right
    // after each mutation — no dependence on file-watch latency for ordering.
    // A short quiet period keeps the reaction-latency measurement meaningful.
    manual = ManualDirtySource();
    runtime = GridControllerRuntime(
      reader: reader,
      dirtySources: [manual],
      quietPeriod: const Duration(milliseconds: 20),
    );
    await runtime.start(); // takes the baseline snapshot (empty graph)
  });

  tearDown(() async {
    await runtime.dispose();
    await ws.dispose();
  });

  test(
    'create + close lifecycle emits ordered typed events within budget '
    '(BeadCreated, ReadySetChanged, BeadClosed) with measured latency',
    () async {
      final bd = BdCliService(ProcessBdRunner(workspaceRoot: ws.rootPath));

      // Collect events off the runtime stream for assertions; collect ready-set
      // transitions separately so we can correlate them with the latency print.
      final events = <GraphEvent>[];
      final sub = runtime.events.listen(events.add);
      addTearDown(sub.cancel);

      // A reusable "mutate → trigger → wait for the next refresh to complete →
      // report latency" step. Each call returns the events observed *by this
      // refresh* (the delta since the previous wait).
      var seen = 0;
      Future<List<GraphEvent>> mutateAndReact(
        String label,
        Future<void> Function() mutate,
      ) async {
        final before = runtime.stats.refreshCount;
        await mutate();
        manual.trigger(detail: label);
        await _waitFor(
          () => runtime.stats.refreshCount > before,
          timeout: const Duration(seconds: 2),
          reason: 'refresh after $label did not complete within 2s',
        );
        // Give the broadcast stream a microtask to flush the buffered events.
        await Future<void>.delayed(Duration.zero);
        final delta = events.sublist(seen);
        seen = events.length;
        final reaction = runtime.stats.lastReaction;
        _report(
          '$label → reaction latency '
          '${reaction?.inMilliseconds ?? '?'}ms '
          '(${delta.map((e) => e.runtimeType).join(', ')})',
        );
        return delta;
      }

      // 1) Create the molecule "tron lives" → BeadCreated (NOT ready).
      String? moleculeId;
      final afterMolecule = await mutateAndReact('create molecule', () async {
        moleculeId = await bd.create(
          title: 'tron lives',
          type: IssueType.molecule,
          priority: 1,
        );
      });
      expect(moleculeId, isNotNull);
      final created = afterMolecule.whereType<BeadCreated>().toList();
      expect(
        created,
        hasLength(1),
        reason: 'exactly one BeadCreated for the molecule',
      );
      expect(created.single.bead.id, moleculeId);
      expect(created.single.bead.title, 'tron lives');
      expect(created.single.bead.issueType, IssueType.molecule);
      // A molecule is a container — it must not have entered the ready set.
      expect(
        afterMolecule.whereType<ReadySetChanged>(),
        isEmpty,
        reason: 'a molecule is not claimable ready work',
      );

      // 2) Create a task → BeadCreated + ReadySetChanged(entered).
      String? taskId;
      final afterTask = await mutateAndReact('create task', () async {
        taskId = await bd.create(
          title: 'flynn enters',
          type: IssueType.task,
          priority: 1,
        );
      });
      expect(taskId, isNotNull);
      final taskCreated = afterTask.whereType<BeadCreated>().toList();
      expect(taskCreated, hasLength(1));
      expect(taskCreated.single.bead.id, taskId);
      final entered = afterTask.whereType<ReadySetChanged>().toList();
      expect(
        entered,
        hasLength(1),
        reason: 'an unblocked task enters the ready set',
      );
      expect(entered.single.entered, contains(taskId));
      expect(entered.single.exited, isEmpty);

      // Ordering within the refresh: BeadCreated precedes ReadySetChanged
      // (the bead must exist before the ready-set delta references it).
      final createdIdx = afterTask.indexWhere((e) => e is BeadCreated);
      final readyIdx = afterTask.indexWhere((e) => e is ReadySetChanged);
      expect(
        createdIdx,
        lessThan(readyIdx),
        reason: 'BeadCreated is ordered before ReadySetChanged',
      );

      // 3) Close the task → BeadClosed + ReadySetChanged(exited).
      final afterClose = await mutateAndReact('close task', () async {
        await bd.close(taskId!);
      });
      final closed = afterClose.whereType<BeadClosed>().toList();
      expect(closed, hasLength(1));
      expect(closed.single.after.id, taskId);
      expect(closed.single.after.isClosed, isTrue);
      final exited = afterClose.whereType<ReadySetChanged>().toList();
      expect(exited, hasLength(1));
      expect(exited.single.exited, contains(taskId));
      expect(exited.single.entered, isEmpty);

      // Every signal-driven refresh recorded a reaction latency; it is the
      // number the two-terminal demo reports against the ≤500ms budget. We use
      // a generous ≤2s integration budget (the bd spawn dominates in CI).
      expect(runtime.stats.lastReaction, isNotNull);
      expect(
        runtime.stats.lastReaction!.inMilliseconds,
        lessThan(2000),
        reason: 'reaction latency must stay within the 2s integration budget',
      );
      expect(runtime.stats.refreshCount, greaterThanOrEqualTo(3));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'the workspace file-watcher alone drives a refresh (no manual trigger)',
    () async {
      // A second runtime wired with ONLY the real .beads/ watcher proves the
      // push path end-to-end: a bd mutation writes `last-touched`, the watcher
      // fires, and a refresh observes the new bead — within a bounded wait.
      final bd = BdCliService(ProcessBdRunner(workspaceRoot: ws.rootPath));
      final watched = GridControllerRuntime(
        reader: CliSnapshotReader(bd),
        dirtySources: [WorkspaceBeadsWatcher(ws.beadsDir)],
        quietPeriod: const Duration(milliseconds: 50),
      );
      addTearDown(watched.dispose);
      await watched.start();

      final baselineRefreshes = watched.stats.refreshCount;
      final id = await bd.create(
        title: 'rinzler',
        type: IssueType.task,
        priority: 2,
      );

      await _waitFor(
        () => watched.bead(id) != null,
        timeout: const Duration(seconds: 2),
        reason:
            'file-watcher-driven refresh did not observe the new bead '
            'within 2s',
      );
      expect(watched.stats.refreshCount, greaterThan(baselineRefreshes));
      expect(watched.bead(id)!.title, 'rinzler');
      _report(
        'watcher-driven reaction latency '
        '${watched.stats.lastReaction?.inMilliseconds ?? '?'}ms',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

/// Emits a measured-latency diagnostic line. Criterion 1 requires the runtime's
/// reaction latency (`stats.lastReaction`) to be printed per event; this is the
/// one sanctioned `print` in the suite (test diagnostics, not production code).
void _report(String message) {
  // ignore: avoid_print
  print('[reactive-lifecycle] $message');
}

/// Polls [condition] until it holds or [timeout] elapses, failing with [reason].
/// Used instead of a fixed sleep so the bounded wait returns as soon as the
/// reactive path converges (and the latency print reflects the real cost).
Future<void> _waitFor(
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
