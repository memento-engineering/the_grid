// tg-eli phase 1 — the RestartReconciler's MOLECULE crash-recovery pass.
//
// A molecule session's process identity does NOT ride `session.cursor` (which
// is EMPTY for it); it lives in vendor-owned `grid.lease.*` breadcrumbs on its
// step beads. Before this pass, a station death mid-molecule left live agent
// process groups orphaned with NOTHING tested to kill them. This suite proves
// the reconciler reconciles molecule survivors through the vendor-exposed
// sweep (Nico's 2026-07-19 ruling: the reconciler stays lease-schema-ignorant
// — structurally pinned in the last group):
//  (a) an orphaned live JOB group is killed via the REAL guarded terminateGroup
//      + its breadcrumb cleared + LOUD;
//  (a2) ARMED-BY-CONSTRUCTION — the kill gate rides the reconciler's OWN
//      controller, so the kill still fires with the vendor's adopt-liveness at
//      its production never-adopt default (the reviewer-confirmed inertness
//      defect, pinned as a regression);
//  (b) NEGATIVE CONTROL — a live DAEMON whose proveFresh holds is NOT killed,
//      and its breadcrumb still ADOPTS through the vendor's own lease;
//  (c) NEGATIVE CONTROL — a dead group (the controller cannot prove the
//      leader alive) triggers no kill and its breadcrumb is LEFT (the
//      documented contract);
//  (d) a COMPLETED step is untouched — no kill, no respawn side effects;
//  (e) SelfManagedProcessVendor's sweep no-ops through the same wiring;
// plus the scope pins (terminal / worktree-less sessions out of scope, no
// vendor wired ⇒ no sweep) and the structural lease-literal falsifier.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes (Fakes, not mocks) — the same offline shapes restart_reconciler_test
// establishes: narrow worktree seams, a fake ProcessGroupController the REAL
// terminateGroup runs over, a synthetic state snapshot, and the recording bd
// chokepoint. The vendor is the REAL StationProcessLeaseVendor.
// ---------------------------------------------------------------------------

/// Serves a programmed worktree list; records reaps (never expected here).
class _FakeGit {
  _FakeGit({required this.worktrees});

  final List<BeadWorktree>? worktrees;
  final List<String> reaped = [];

  Future<List<BeadWorktree>?> listWorktrees(RootCheckout root) async =>
      worktrees;

  Future<ReapOutcome> reapWorktree({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
    reaped.add(worktree.beadId);
    return ReapOutcome.removed();
  }
}

/// Records every group signal; a SIGTERM/SIGKILL kills the whole (single)
/// group, so terminateGroup's poll observes the exit (exitedOnTerm).
class _FakeProcessGroupController implements ProcessGroupController {
  _FakeProcessGroupController({Set<int> alivePids = const {}})
    : _alive = {...alivePids};

  final Set<int> _alive;
  final List<(int, ProcessSignal)> signals = [];

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool processAlive(int pid) => _alive.contains(pid);

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.clear();
    }
    return true;
  }

  @override
  int currentGroupId() => 999;
}

({StationBeadWriter writer, RecordingBdRunner bd}) _chokepoint() {
  final bd = RecordingBdRunner();
  return (
    writer: StationBeadWriter(
      bd: BdCliService(bd),
      ownership: BeadOwnershipPredicate(const {stateSubstation}),
    ),
    bd: bd,
  );
}

/// A MOLECULE-model session bead: the explicit `grid.session.model=molecule`
/// discriminator, an EMPTY cursor (the drain guarantee — a molecule session
/// never writes `grid.cursor.*`), no scalar pgid.
Bead _moleculeSession({
  required String id,
  required String workBead,
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    SessionBeadKeys.model: kSessionModelMolecule,
  },
);

/// A `type=step` bead stamped for [sessionId], optionally carrying the
/// vendor-owned lease breadcrumb (exactly what a crashed prior incarnation
/// leaves behind).
Bead _stepBead({
  required String id,
  required String sessionId,
  StepKind kind = StepKind.job,
  StepState? state = StepState.running,
  ProcessHandle? lease,
}) => Bead(
  id: id,
  issueType: IssueType.step,
  status: BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': stateSubstation,
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.kind: kind.name,
    MoleculeStepKeys.path: 'tg-w1/${kind.name}',
    if (state != null) MoleculeStepKeys.state: state.name,
    if (lease != null) ...leaseBreadcrumb(lease),
  },
);

GraphSnapshot _stateSnapshotOf(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026, 7, 19),
);

BeadWorktree _wt(String beadId) => BeadWorktree(
  beadId: beadId,
  path: '/workspace/example-substation/.grid/worktrees/tgdog/$beadId',
  branch: 'grid/$beadId',
);

const _workRoot = RootCheckout(
  path: '/workspace/example-substation',
  defaultBranch: 'main',
  substation: 'tgdog',
);

Future<ProcessHandle> _neverSpawn(
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('spawn must not be called'));

Future<StepOutcome> _neverDispatch(
  ProcessHandle handle,
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('dispatch must not be called'));

void _ignoreAllocationReport(AllocationReport report) {}

/// A literal [ProcessLeaseRequest] (the process_lease_vendor_test shape) —
/// only used by test (b)'s adoption-preserved proof.
ProcessLeaseRequest _request(String stepBeadId) => ProcessLeaseRequest(
  stepBeadId: stepBeadId,
  capability: const _FakeProcessCap(),
  allocation: AllocationContext(
    treeContext: FakeTreeContext(),
    args: stepArgs('tg-w1/daemon'),
    transport: FakeRuntimeProvider(),
    address: const AllocationAddress('tgdog-s', 'tg-w1/daemon'),
    env: const {},
    sink: _ignoreAllocationReport,
  ),
);

class _FakeProcessCap extends ProcessCapability {
  const _FakeProcessCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => const RuntimeConfig(
    workDir: '/w/tg-w1',
    command: 'sh',
    args: ['-c', 'echo hi'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => StepSignal.none;
}

/// The harness: a molecule session + its step beads in the state store, one
/// surviving worktree, the REAL vendor over the recording chokepoint, and the
/// REAL guarded terminateGroup over the fake controller.
({
  RestartReconciler reconciler,
  _FakeGit git,
  _FakeProcessGroupController groups,
  RecordingBdRunner bd,
  List<String> loud,
  StationProcessLeaseVendor vendor,
})
_harness({
  required List<Bead> stateBeads,
  required Set<int> alivePids,
  required Set<int> alivePgids,
  List<BeadWorktree>? worktrees,
  ProcessLeaseVendor? vendorOverride,
  bool wireVendor = true,
}) {
  final git = _FakeGit(worktrees: worktrees ?? [_wt('tg-w1')]);
  final groups = _FakeProcessGroupController(alivePids: alivePids);
  final cp = _chokepoint();
  final loud = <String>[];
  final vendor = StationProcessLeaseVendor(
    writer: cp.writer,
    spawn: _neverSpawn,
    dispatch: _neverDispatch,
    // Serves the CURRENT store metadata — what test (b)'s adoption-preserved
    // proof reads back after the sweep left the breadcrumb intact.
    metadataOf: (stepBeadId) async {
      for (final bead in stateBeads) {
        if (bead.id != stepBeadId) continue;
        return {
          for (final e in bead.metadata.entries)
            if (e.value != null) e.key: '${e.value}',
        };
      }
      return null;
    },
    // The ADOPT-freshness proof (proveFresh's fence) — what test (b)'s daemon
    // preserve gates on. The sweep's KILL gate never rides this: the
    // reconciler binds it to the fake controller's processAlive ([alivePids]).
    liveness: (fence) => alivePgids.contains(fence.pgid),
  );
  final state = _stateSnapshotOf(stateBeads);
  final reconciler = RestartReconciler(
    listWorktrees: git.listWorktrees,
    reapWorktree: git.reapWorktree,
    workRoot: _workRoot,
    groups: groups,
    writer: cp.writer,
    freshnessBarrier: () async {},
    stateSnapshot: () => state,
    leaseVendor: wireVendor ? (vendorOverride ?? vendor) : null,
    onOrphan: loud.add,
  );
  return (
    reconciler: reconciler,
    git: git,
    groups: groups,
    bd: cp.bd,
    loud: loud,
    vendor: vendor,
  );
}

const _jobLease = ProcessHandle(pgid: 4242, pid: 4243, token: 'tok-job');
const _daemonLease = ProcessHandle(pgid: 5252, pid: 5253, token: 'tok-daemon');

void main() {
  group('RestartReconciler — molecule crash recovery (tg-eli phase 1)', () {
    test(
      '(a) an orphaned live JOB group: killed through the REAL guarded '
      'terminateGroup, breadcrumb cleared through the chokepoint, reported '
      'LOUD — and the worktree stays respawn-pending for the frontier '
      '(respawn-or-skip, never adoption for a job)',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              lease: _jobLease,
            ),
          ],
          alivePids: {4243},
          alivePgids: {4242},
        );

        final report = await h.reconciler.reconcile();

        // The kill went through the REAL guarded path: SIGTERM to the group.
        expect(h.groups.signals.first, (4242, ProcessSignal.sigterm));

        // The vendor's own clearing write, on the step bead, nothing else.
        final updates = h.bd.callsFor('update');
        expect(updates, hasLength(1));
        expect(updates.single[1], 'tgdog-step-1');
        expect(h.bd.metadataOfUpdate(0), kClearedLeaseKeys);
        expect(h.bd.neverShowOrSql, isTrue);

        // LOUD, and on the report.
        expect(h.loud.single, contains('tgdog-step-1'));
        expect(report.sweptLeases, hasLength(1));
        expect(
          report.sweptLeases.single.disposition,
          LeaseSweepDisposition.killed,
        );

        // The flat pass saw nothing for the molecule session (empty cursor ⇒
        // no kill target): the worktree is respawn-pending, never reaped —
        // the frontier re-mounts and the job lease respawns FRESH.
        expect(report.respawnPending.map((e) => e.beadId), ['tg-w1']);
        expect(h.git.reaped, isEmpty);
        expect(report.reaped, isEmpty, reason: 'no flat zombies here');
      },
    );

    test(
      '(a2) ARMED BY CONSTRUCTION — the sweep\'s kill gate rides the '
      'reconciler\'s OWN controller, never the vendor\'s adopt-liveness: with '
      'adoption UNARMED (the adopt proof refutes everything — the live '
      'assembly\'s production posture) a live orphaned JOB group is STILL '
      'killed on reboot',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              lease: _jobLease,
            ),
          ],
          alivePids: {4243},
          alivePgids: const {}, // adopt-liveness proves NOTHING — neverLive.
        );

        final report = await h.reconciler.reconcile();

        expect(h.groups.signals.first, (4242, ProcessSignal.sigterm));
        expect(h.bd.metadataOfUpdate(0), kClearedLeaseKeys);
        expect(report.sweptLeases, hasLength(1));
        expect(
          report.sweptLeases.single.disposition,
          LeaseSweepDisposition.killed,
        );
        expect(h.loud, isNotEmpty);
      },
    );

    test(
      '(b) NEGATIVE CONTROL — a live DAEMON whose proveFresh holds is NOT '
      'killed, its breadcrumb survives, and the vendor\'s own lease still '
      'ADOPTS it afterwards (the re-mounting tree\'s reattach is preserved)',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-d',
              sessionId: 'tgdog-m1',
              kind: StepKind.daemon,
              state: StepState.ready,
              lease: _daemonLease,
            ),
          ],
          alivePids: {5253},
          alivePgids: {5252},
        );

        final report = await h.reconciler.reconcile();

        // The kill did NOT fire — no signal of any kind, no clearing write.
        expect(h.groups.signals, isEmpty);
        expect(h.bd.callsFor('update'), isEmpty);
        expect(h.loud, isEmpty);
        expect(
          report.sweptLeases.single.disposition,
          LeaseSweepDisposition.leftAdoptable,
        );

        // Adoption preserved end-to-end: the SAME vendor's lease for this step
        // still reads the intact breadcrumb and proves it fresh — exactly what
        // the re-mounted tree's startOrAdopt reattaches (D4).
        final lease = h.vendor.leaseFor(_request('tgdog-step-d'));
        final ctx = FakeTreeContext();
        final args = stepArgs('tg-w1/daemon');
        final prior = await lease.adoptable(ctx, args);
        expect(prior, isNotNull);
        expect(prior!.handle, _daemonLease);
        expect(await lease.proveFresh(prior.handle, ctx, args), isTrue);
      },
    );

    test(
      '(c) NEGATIVE CONTROL — a DEAD group (the controller cannot prove the '
      'leader alive): no kill is even attempted, and the stale breadcrumb is '
      'LEFT per the documented contract (it is inert; the fresh respawn '
      'overwrites it)',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              lease: _jobLease,
            ),
          ],
          alivePids: const {},
          alivePgids: const {},
        );

        final report = await h.reconciler.reconcile();

        expect(h.groups.signals, isEmpty);
        expect(h.bd.callsFor('update'), isEmpty);
        expect(h.loud, isEmpty);
        expect(report.sweptLeases, isEmpty);
        // The step stays with the frontier: respawn-pending, fresh respawn.
        expect(report.respawnPending, hasLength(1));
      },
    );

    test(
      '(d) a COMPLETED step (grid.step.state=complete) is untouched — no '
      'kill, no clearing write, no respawn side effects, even with a live '
      'breadcrumb still on it',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              state: StepState.complete,
              lease: _jobLease,
            ),
          ],
          alivePids: {4243},
          alivePgids: {4242},
        );

        final report = await h.reconciler.reconcile();

        expect(h.groups.signals, isEmpty);
        expect(h.bd.callsFor('update'), isEmpty);
        expect(report.sweptLeases, isEmpty);
        expect(h.loud, isEmpty);
      },
    );

    test(
      '(e) SelfManagedProcessVendor wired as the sweep vendor no-ops: the '
      'same candidates, no kill, no write, an empty sweep',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              lease: _jobLease,
            ),
          ],
          alivePids: {4243},
          alivePgids: {4242},
          vendorOverride: const SelfManagedProcessVendor(
            spawn: _neverSpawn,
            dispatch: _neverDispatch,
          ),
        );

        final report = await h.reconciler.reconcile();

        expect(h.groups.signals, isEmpty);
        expect(h.bd.callsFor('update'), isEmpty);
        expect(report.sweptLeases, isEmpty);
      },
    );
  });

  group('molecule sweep — scope and arming', () {
    test(
      'no vendor wired ⇒ no sweep (the cross-repo ctor default keeps '
      'compiling and the flat pass is unchanged); hasLeaseSweep says so',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              lease: _jobLease,
            ),
          ],
          alivePids: {4243},
          alivePgids: {4242},
          wireVendor: false,
        );

        expect(h.reconciler.hasLeaseSweep, isFalse);
        final report = await h.reconciler.reconcile();
        expect(report.sweptLeases, isEmpty);
        expect(h.groups.signals, isEmpty);
      },
    );

    test('a vendor that reached the pass reads armed', () {
      final h = _harness(
        stateBeads: const [],
        alivePids: const {},
        alivePgids: const {},
      );
      expect(h.reconciler.hasLeaseSweep, isTrue);
    });

    test(
      'a TERMINAL molecule session is out of the sweep\'s scope (the '
      'documented phase-1 deferral: its worktree goes to the skip branch; '
      'its lingering daemon breadcrumbs are a later rung)',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1', closed: true),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              lease: _jobLease,
            ),
          ],
          alivePids: {4243},
          alivePgids: {4242},
        );

        final report = await h.reconciler.reconcile();

        expect(report.skipped, hasLength(1), reason: 'the skip branch fired');
        expect(report.sweptLeases, isEmpty);
        // No clearing write — the only bd traffic would be the sweep's.
        expect(h.bd.callsFor('update'), isEmpty);
      },
    );

    test(
      'a molecule session with NO surviving worktree is out of scope — the '
      'same bounded-boot rationale as the zombie reap',
      () async {
        final h = _harness(
          stateBeads: [
            _moleculeSession(id: 'tgdog-m1', workBead: 'tg-w1'),
            _stepBead(
              id: 'tgdog-step-1',
              sessionId: 'tgdog-m1',
              lease: _jobLease,
            ),
          ],
          alivePids: {4243},
          alivePgids: {4242},
          worktrees: const [],
        );

        final report = await h.reconciler.reconcile();

        expect(report.sweptLeases, isEmpty);
        expect(h.groups.signals, isEmpty);
        expect(h.bd.callsFor('update'), isEmpty);
      },
    );
  });

  group('STRUCTURAL — the reconciler is lease-schema-ignorant', () {
    test(
      'restart_reconciler.dart never touches a grid.lease literal or the '
      'lease helpers — the vendor sweep API is its ONLY touchpoint (Nico\'s '
      '2026-07-19 ruling)',
      () {
        // Runs from the package root (dart test's cwd contract).
        final file = File('lib/src/restart/restart_reconciler.dart');
        expect(file.existsSync(), isTrue);
        // Strip comment lines so a doc reference never trips the scan — only
        // CODE counts (the process_lease_vendor_test falsifier's discipline).
        final code = file
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code, isNot(contains('grid.lease')));
        expect(code, isNot(contains('LeaseKeys')));
        expect(code, isNot(contains('leaseBreadcrumb')));
        expect(code, isNot(contains('kClearedLeaseKeys')));
      },
    );
  });
}
