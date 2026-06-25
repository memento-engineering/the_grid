// Track E/F — the LAND capability: commit → push → open the PR, record the PR
// url on the session bead through the chokepoint, then close it (the positive
// terminal). Land is git/PR ORCHESTRATION, NOT a supervised process — a
// separate guard-bearing Seed, never an EffectSeed.
//
// Offline only — FAKES (recording GitOps + PrOpener + the bd chokepoint), no
// live git/GitHub/tg. The load-bearing cases: the ordered happy path, a PR-open
// failure (no record / no close), and a dispose mid-land (no write after).
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

/// Mounts a [LandEffectSeed] for [workBead] under
/// `InheritedSeed<EffectContext>(value: ctx)` with the linked [session], and
/// returns the owner so the test can dispose on demand.
TreeOwner _mountLand(
  EffectContext ctx,
  Bead workBead,
  SessionProjection session,
) {
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<EffectContext>(
      value: ctx,
      child: LandEffectSeed(
        bead: workBead,
        session: session,
        key: ValueKey('${workBead.id}.land'),
      ),
    ),
  );
  return owner;
}

const _session = SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-sess1',
  phase: WorkPhase.land,
);

void main() {
  group('LandEffectSeed — the happy path orchestrates and records', () {
    test('commitAll → pushSetUpstream → PrOpener.open in order; pr_url recorded '
        'on the session bead via the chokepoint; session closed', () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      f.pr.url = 'https://github.com/memento/genesis/pull/7';
      final owner = _mountLand(f.ctx, bead('tg-1'), _session);
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);

      await pumpEventQueue();

      // commit (add -A, commit -m) then push (-u origin grid/tg-1), in order.
      expect(
        f.git.subcommands,
        ['add', 'commit', 'push'],
        reason: 'commitAll (add+commit) then pushSetUpstream (push), in order',
      );
      final pushCall = f.git.calls.last;
      expect(
        pushCall.args,
        containsAllInOrder(['push', '-u', 'origin', 'grid/tg-1']),
      );

      // The PR was opened against the base branch for the land branch, AFTER
      // commit+push.
      expect(f.pr.opened, hasLength(1));
      final open = f.pr.opened.single;
      expect(open.branch, 'grid/tg-1');
      expect(open.baseBranch, 'main');
      expect(open.title, 'grid: tg-1');

      // The pr_url was recorded on the SESSION bead through the chokepoint...
      final updates = f.runner.callsFor('update');
      final prUpdate = updates.lastWhere(
        (c) =>
            c.contains('--metadata') &&
            c[c.indexOf('--metadata') + 1].contains('pr_url'),
      );
      expect(prUpdate, containsAllInOrder(['update', 'tgdog-sess1']));
      final i = prUpdate.indexOf('--metadata');
      expect(
        prUpdate[i + 1],
        contains('https://github.com/memento/genesis/pull/7'),
      );

      // ...and then the session bead was closed (the positive terminal).
      final closes = f.runner.callsFor('close');
      expect(closes, hasLength(1));
      expect(closes.single, containsAllInOrder(['close', 'tgdog-sess1']));

      // The chokepoint discipline holds: no bd show / SQL; the close carries the
      // grid actor.
      expect(f.runner.neverShowOrSql, isTrue);
    });

    test('land is a no-op when git/PR ops are not wired (offline build)',
        () async {
      // An EffectContext with NO gitOps / prOpener (the offline-not-wired case).
      final runner = RecordingBdRunner();
      final provider = FakeRuntimeProvider();
      final ctx = EffectContext(
        provider: provider,
        writer: GridBeadWriter(
          bd: BdCliService(runner),
          ownership: BeadOwnershipPredicate(const {stateRig}),
        ),
        stateRig: stateRig,
      );
      addTearDown(provider.close);
      final owner = _mountLand(ctx, bead('tg-1'), _session);
      addTearDown(owner.dispose);

      await pumpEventQueue();

      // No commit/push/PR, no pr_url, no close — land cleanly no-ops.
      expect(runner.callsFor('update'), isEmpty);
      expect(runner.callsFor('close'), isEmpty);
    });
  });

  group('LandEffectSeed — a PR-open failure records nothing and does not close',
      () {
    test('PrOpener failure ⇒ no pr_url update, no session close (honest)',
        () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      f.pr.failNext = true;
      final owner = _mountLand(f.ctx, bead('tg-1'), _session);
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);

      await pumpEventQueue();

      // commit + push still ran (the failure is at the PR boundary)...
      expect(f.git.subcommands, ['add', 'commit', 'push']);
      expect(f.pr.opened, hasLength(1));

      // ...but the PR failed: NO pr_url recorded, and the session is NOT closed
      // (the cursor stays so a retry is possible).
      final prUpdates = f.runner.callsFor('update').where(
        (c) =>
            c.contains('--metadata') &&
            c[c.indexOf('--metadata') + 1].contains('pr_url'),
      );
      expect(prUpdates, isEmpty);
      expect(f.runner.callsFor('close'), isEmpty);
    });
  });

  group('LandEffectSeed — dispose mid-land writes nothing after', () {
    test('dispose while the push is in-flight ⇒ no PR open, no pr_url, no close',
        () async {
      // Gate the git runner so the FIRST push parks, letting us dispose between
      // push and open.
      final git = _GatedGitRunner(gateOn: 'push');
      final provider = FakeRuntimeProvider();
      final runner = RecordingBdRunner(createdId: 'tgdog-sess1');
      final pr = FakePrOpener();
      final ctx = EffectContext(
        provider: provider,
        writer: GridBeadWriter(
          bd: BdCliService(runner),
          ownership: BeadOwnershipPredicate(const {stateRig}),
        ),
        stateRig: stateRig,
        gitOps: GitOps(git),
        prOpener: pr,
      );
      addTearDown(provider.close);

      final owner = _mountLand(ctx, bead('tg-1'), _session);

      // _land() runs: add + commit complete, push is parked on the gate.
      await pumpEventQueue();
      expect(git.gatePending, isTrue, reason: 'push should be in-flight');

      // Dispose mid-land.
      owner.dispose();
      // Release the push — the post-push guard must abort before opening the PR.
      git.releaseGate();
      await pumpEventQueue();

      expect(pr.opened, isEmpty, reason: 'no PR opened after dispose');
      expect(runner.callsFor('update'), isEmpty, reason: 'no pr_url recorded');
      expect(runner.callsFor('close'), isEmpty, reason: 'session not closed');
    });

    test(
      'dispose between commit and push ⇒ NO push, no PR open, no pr_url, no '
      'close (the commit→push window guard)',
      () async {
        // Gate the COMMIT so we can dispose in the window AFTER commitAll returns
        // but BEFORE pushSetUpstream is issued — the guard after commitAll must
        // abort the land before any push/PR/write.
        final git = _GatedGitRunner(gateOn: 'commit');
        final provider = FakeRuntimeProvider();
        final runner = RecordingBdRunner(createdId: 'tgdog-sess1');
        final pr = FakePrOpener();
        final ctx = EffectContext(
          provider: provider,
          writer: GridBeadWriter(
            bd: BdCliService(runner),
            ownership: BeadOwnershipPredicate(const {stateRig}),
          ),
          stateRig: stateRig,
          gitOps: GitOps(git),
          prOpener: pr,
        );
        addTearDown(provider.close);

        final owner = _mountLand(ctx, bead('tg-1'), _session);

        // _land() runs: add completes, commit is parked on the gate.
        await pumpEventQueue();
        expect(git.gatePending, isTrue, reason: 'commit should be in-flight');

        // Dispose mid-land, then release the commit — the post-commit guard must
        // abort before pushing.
        owner.dispose();
        git.releaseGate();
        await pumpEventQueue();

        // The push was NEVER issued (the guard fired right after commitAll)...
        expect(
          git.subcommands,
          ['add', 'commit'],
          reason: 'no push after a dispose between commit and push',
        );
        // ...and nothing downstream of it ran.
        expect(pr.opened, isEmpty, reason: 'no PR opened after dispose');
        expect(runner.callsFor('update'), isEmpty, reason: 'no pr_url recorded');
        expect(runner.callsFor('close'), isEmpty, reason: 'session not closed');
      },
    );
  });
}

/// A [GitRunner] whose first invocation of the [gateOn] subcommand (`commit` or
/// `push`) parks until [releaseGate] is called, so a test can drive a dispose
/// into a specific window of the land orchestration. Every other subcommand
/// completes immediately, and each invocation is recorded so the test can assert
/// exactly which steps ran.
class _GatedGitRunner implements GitRunner {
  _GatedGitRunner({required this.gateOn});

  /// The leading subcommand whose first invocation parks (`commit` | `push`).
  final String gateOn;

  /// Every (workDir, args) `git` invocation that actually ran, in call order.
  final List<({String workDir, List<String> args})> calls = [];

  Completer<void>? _gate;

  /// True while the gated subcommand is parked awaiting [releaseGate].
  bool get gatePending => _gate != null && !_gate!.isCompleted;

  /// Resolves the in-flight gated invocation.
  void releaseGate() => _gate!.complete();

  /// The leading subcommands of every recorded `git` call, in order.
  List<String> get subcommands =>
      [for (final c in calls) c.args.isNotEmpty ? c.args.first : ''];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workDir: workingDirectory, args: List.unmodifiable(args)));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == gateOn) {
      _gate = Completer<void>();
      await _gate!.future;
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}
