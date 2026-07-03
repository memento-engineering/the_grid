// tg-9fl — adopt-across-restart co-wiring (ADR-0009 D4). Adopt is TWO
// cooperating halves: the RestartReconciler's AdoptProof (leave a proven
// survivor running, pre-mount) and the Host's AllocationLiveness (reattach it
// at mount, via StationServices.liveness). This file locks the RUNNER contract:
//
//  a. `--adopt` exists and is REFUSED with --dry-run (StationRefusal, exit 64);
//  b. `--adopt` (live) arms BOTH halves off the SAME ProcessGroupController —
//     it is impossible to arm one half without the other through the runner
//     (the double-run footgun), proven structurally (both non-null / both null)
//     AND behaviorally (the composed reconciler ADOPTS iff armed);
//  c. omitting --adopt leaves BOTH at their offline never-adopt defaults
//     (byte-compatible with every pre-adopt run).
//
// FULLY offline — Fakes, not mocks; no real process/git/bd is touched (the
// REAL live adopt arm — a detached survivor across a real controller restart —
// is the human-gated live arm, explicitly out of scope).
import 'dart:io';

import 'package:args/args.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

// --- fakes -------------------------------------------------------------------

/// A recording [ProcessGroupController]: every `processAlive` probe lands in
/// [probes], so a test can prove BOTH adopt halves consulted THIS instance
/// (the same-controller half of the all-or-nothing contract). Liveness is
/// programmed via [alivePids]; a SIGTERM/SIGKILL to a group clears the alive
/// set (the group dies), so the REAL guarded `terminateGroup` completes.
class _RecordingGroups implements ProcessGroupController {
  _RecordingGroups({Set<int> alivePids = const {}}) : _alive = {...alivePids};

  final Set<int> _alive;

  /// Every pid `processAlive` was asked about, in order.
  final List<int> probes = [];

  /// Every (pgid, signal) sent, in order — empty proves "adopt never kills".
  final List<(int, ProcessSignal)> signals = [];

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool processAlive(int pid) {
    probes.add(pid);
    return _alive.contains(pid);
  }

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.clear();
    }
    return true;
  }

  @override
  int currentGroupId() => 99999;
}

/// A [StationGitService] over no-op runners that serves a programmed survivor
/// list (the restart probe) and records reaps — no real `git`.
class _SurvivorGitService extends StationGitService {
  _SurvivorGitService(this.worktrees)
    : super(runner: _NoOpGitRunner(), prOpener: _NoOpPrOpener());

  final List<BeadWorktree> worktrees;
  final List<String> reaped = [];

  @override
  Future<List<BeadWorktree>?> listBeadWorktrees(RootCheckout root) async =>
      worktrees;

  @override
  Future<ReapOutcome> reap({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
    reaped.add(worktree.beadId);
    return ReapOutcome.removed();
  }
}

class _NoOpGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => const GitRunResult(exitCode: 0, output: '');
}

class _NoOpPrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.failed(const PrOpenFailure('offline: no PR'));
}

// --- builders ------------------------------------------------------------------

/// A live-armed [StationArgs] with [adopt]; every live gate is satisfied via
/// the injected seams (`rootInjected`/`stateInjected` in `validateArming`).
StationArgs _liveArgs({bool adopt = false}) => StationArgs(
  substations: const {'tgdog'},
  stateSubstation: 'tgdog',
  dryRun: false,
  adopt: adopt,
  targetBeads: const {'tgdog-live'},
);

const _root = RootCheckout(
  path: '/tmp/grid-adopt-root',
  defaultBranch: 'main',
  substation: 'tgdog',
);

BeadWorktree _wt(String beadId) => BeadWorktree(
  beadId: beadId,
  path: '${_root.path}/.grid/worktrees/tgdog/$beadId',
  branch: 'grid/$beadId',
);

/// A STATE-store session bead whose per-node cursor carries one RUNNING group
/// (pgid 42, leader pid 4201) — the survivor the reconcile pass decides over.
Bead _liveSessionBead() => Bead(
  id: 'tgdog-s1',
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': 'tgdog',
    'work_bead': 'tgdog-live',
    ...nodeCursorMetadata(
      'tgdog-live/harness',
      const NodeCursor(
        state: StepState.running,
        pgid: 42,
        pid: 4201,
        token: 't',
      ),
    ),
  },
);

/// Runs `buildLiveWiring` over fully-faked seams (offline; nothing live).
Future<StationWiring> _wire(
  StationArgs args, {
  required _RecordingGroups groups,
  StationGitService? git,
  StationSources? sources,
}) => buildLiveWiring(
  args: args,
  sources: sources ?? StationSources(work: FakeSnapshotSource()),
  onRefusal: (_) {},
  stateBdOverride: BdCliService(RecordingBdRunner()),
  providerOverride: FakeRuntimeProvider(),
  gitServiceOverride: git ?? _SurvivorGitService(const []),
  groupsOverride: groups,
  rootCheckoutOverride: _root,
  freshnessBarrierOverride: () async {},
);

// --- a minimal asset (composeStation requires resolver + registry) -------------

const Circuit _stubCircuit = Circuit(
  id: 'stub',
  terminalStepId: 'stub',
  steps: [
    CapabilityStep(stepId: 'stub', capabilityId: 'stub', kind: StepKind.job),
  ],
);

Circuit _stubCircuitFor(Bead bead) => _stubCircuit;

void main() {
  group('--adopt: the flag + the arming gate (ADR-0009 D4)', () {
    test('addStationFlags grows --adopt; StationArgs.from parses it '
        '(default: off; negatable: false)', () {
      final parser = ArgParser();
      addStationFlags(parser);

      expect(
        StationArgs.from(parser.parse(['--substation', 'tgdog'])).adopt,
        isFalse,
        reason: 'adopt is OFF by default (the offline never-adopt posture)',
      );
      expect(
        StationArgs.from(
          parser.parse(['--substation', 'tgdog', '--adopt']),
        ).adopt,
        isTrue,
      );
      expect(
        () => parser.parse(['--no-adopt']),
        throwsA(isA<FormatException>()),
        reason:
            'negatable: false — arming is explicit, never a double negative',
      );
    });

    test('--adopt with --dry-run is REFUSED (StationRefusal, exit 64) — adopt '
        'reattaches real processes; a dry run touches nothing', () {
      expect(
        () => validateArming(
          const StationArgs(substations: {'tgdog'}, dryRun: true, adopt: true),
        ),
        throwsA(
          isA<StationRefusal>()
              .having((r) => r.code, 'code', 64)
              .having(
                (r) => r.message,
                'message',
                allOf(
                  contains('--adopt cannot be combined with --dry-run'),
                  contains('ADR-0009 D4'),
                ),
              ),
        ),
      );
    });

    test('--adopt on a LIVE arm passes the gates (root/state injected, one '
        'blessed bead)', () {
      expect(
        () => validateArming(
          _liveArgs(adopt: true),
          rootInjected: true,
          stateInjected: true,
        ),
        returnsNormally,
      );
    });
  });

  group('--adopt co-wires BOTH halves off the SAME ProcessGroupController '
      '(all-or-nothing, ADR-0009 D4)', () {
    test('armed (live): liveness AND adoptProof are BOTH non-null, and BOTH '
        'probe the ONE injected controller via processAlive', () async {
      final groups = _RecordingGroups(alivePids: {4201});
      final live = await _wire(_liveArgs(adopt: true), groups: groups);

      // Structurally: both halves armed together.
      final liveness = live.stationServices.liveness;
      final adoptProof = live.adoptProof;
      expect(liveness, isNotNull, reason: 'the Host (mount) half is armed');
      expect(adoptProof, isNotNull, reason: 'the reconciler half is armed');

      // The Host half probes THE injected controller (pgid+pid alive → true).
      expect(
        liveness!(const AdoptFence(pgid: 42, pid: 4201, token: 't')),
        isTrue,
      );
      expect(groups.probes, [
        4201,
      ], reason: 'the liveness half consulted the shared controller');

      // The reconciler half probes THE SAME controller instance.
      final adopted = await adoptProof!(
        _wt('tgdog-live'),
        const SessionProjection(workBeadId: 'tgdog-live'),
        'tgdog-live/harness',
        const NodeCursor(state: StepState.running, pgid: 42, pid: 4201),
      );
      expect(adopted, isTrue);
      expect(
        groups.probes,
        [4201, 4201],
        reason: 'both halves share ONE controller — same probe subject',
      );

      // A dead leader fails BOTH halves (kill-and-respawn, never adopt).
      expect(liveness(const AdoptFence(pgid: 43, pid: 9999)), isFalse);
      expect(
        await adoptProof(
          _wt('tgdog-live'),
          const SessionProjection(workBeadId: 'tgdog-live'),
          'tgdog-live/harness',
          const NodeCursor(state: StepState.running, pgid: 43, pid: 9999),
        ),
        isFalse,
      );
    });

    test('a PARTIAL prior identity fails CLOSED in both halves — a live pid '
        'without a recorded pgid (or vice versa) is never adopted '
        '(no-adopt-on-faith)', () async {
      final groups = _RecordingGroups(alivePids: {4201});
      final live = await _wire(_liveArgs(adopt: true), groups: groups);

      expect(
        live.stationServices.liveness!(const AdoptFence(pid: 4201)),
        isFalse,
        reason: 'no pgid → no full identity → no adopt',
      );
      expect(
        live.stationServices.liveness!(const AdoptFence(pgid: 42)),
        isFalse,
        reason: 'no pid → nothing to probe → no adopt',
      );
      expect(
        await live.adoptProof!(
          _wt('tgdog-live'),
          const SessionProjection(workBeadId: 'tgdog-live'),
          'tgdog-live/harness',
          const NodeCursor(state: StepState.running, pid: 4201),
        ),
        isFalse,
      );
    });

    test('UNARMED (no --adopt): BOTH halves stay at their offline never-adopt '
        'defaults — liveness null AND adoptProof null', () async {
      final live = await _wire(_liveArgs(), groups: _RecordingGroups());

      expect(live.stationServices.liveness, isNull);
      expect(live.adoptProof, isNull);
    });

    test('fail-closed mirror of armLand: adopt requested but DRY (a caller '
        'that skipped validateArming) arms NEITHER half', () async {
      // validateArming refuses this combination; buildLiveWiring must not
      // trust that it ran.
      final live = await _wire(
        const StationArgs(
          substations: {'tgdog'},
          stateSubstation: 'tgdog',
          dryRun: true,
          adopt: true,
        ),
        groups: _RecordingGroups(),
      );

      expect(live.stationServices.liveness, isNull);
      expect(live.adoptProof, isNull);
    });
  });

  group('the composed reconciler (buildLiveWiring → composeStation): the '
      'proof reaches RestartReconciler', () {
    /// Composes the full runner path over one live survivor (worktree
    /// `tgdog-live`, session cursor RUNNING with pgid 42 / pid 4201 alive) and
    /// runs the restart pass.
    Future<
      ({RestartReport report, _RecordingGroups groups, _SurvivorGitService git})
    >
    reconcileSurvivor({required bool adopt}) async {
      final groups = _RecordingGroups(alivePids: {4201});
      final git = _SurvivorGitService([_wt('tgdog-live')]);
      final state = FakeSnapshotSource(
        GraphSnapshot.fromParts(
          beads: [_liveSessionBead()],
          dependencies: const [],
          readyIds: const [],
          capturedAt: DateTime(2026, 7, 3),
        ),
      );
      final sources = StationSources(work: FakeSnapshotSource(), state: state);
      final live = await _wire(
        _liveArgs(adopt: adopt),
        groups: groups,
        git: git,
        sources: sources,
      );

      final wiring = composeStation(
        work: sources.work,
        state: sources.state,
        stationServices: live.stationServices,
        substations: const [
          SubstationConfig(
            substationId: 'tgdog',
            ownedSubstations: {'tgdog'},
            driveList: {'tgdog-live'},
          ),
        ],
        git: live.git,
        workRoot: live.workRoot,
        groups: live.groups,
        freshnessBarrier: live.freshnessBarrier,
        resolver: const CircuitResolver(_stubCircuitFor),
        registry: RecordingCapabilityRegistry(clock: DateTime(2026, 7, 3)),
        // The pair threads AS ONE (the doc example's rule): liveness rides
        // stationServices, the reconciler half rides this passthrough.
        adoptProof: live.adoptProof,
      );

      // Only the restart half runs — the kernel is never started (offline;
      // nothing is spawned or mounted).
      final report = await wiring.restart.reconcile();
      return (report: report, groups: groups, git: git);
    }

    test('ARMED: the live survivor is ADOPTED — left running (no signal), not '
        'reaped, not respawned', () async {
      final r = await reconcileSurvivor(adopt: true);

      expect(r.report.adopted.map((e) => e.beadId), ['tgdog-live']);
      expect(r.report.respawnCount, 0, reason: 'adopt is respawn-free');
      expect(r.groups.signals, isEmpty, reason: 'adopt never kills');
      expect(r.git.reaped, isEmpty, reason: 'adopt never reaps');
      expect(
        r.groups.probes,
        contains(4201),
        reason: 'the adopt decision probed the shared controller',
      );
    });

    test(
      'UNARMED sanity control: the SAME survivor is KILLED-and-respawned '
      '(the never-adopt default) — the armed case above is non-vacuous',
      () async {
        final r = await reconcileSurvivor(adopt: false);

        expect(r.report.adopted, isEmpty);
        expect(r.report.killed.map((e) => e.beadId), ['tgdog-live']);
        expect(r.report.respawnCount, 1);
        expect(
          r.groups.signals.map((s) => s.$1),
          contains(42),
          reason: 'the unproven orphan group is terminated before respawn',
        );
      },
    );
  });
}
