// tg-eli phase 1 — the vendor-exposed crash-restart lease sweep
// (ProcessLeaseVendor.sweepOrphanedLeases; Nico's 2026-07-19 ruling:
// grid.lease.* has ONE owner, so the reconciler hands the vendor candidate
// step-bead metadata + a guarded terminate seam and never parses a lease key
// itself).
//
// Vendor-level, offline, Fakes-not-mocks (mirrors process_lease_vendor_test):
//  - the KILL rung: a live JOB group is an orphan — terminated through the
//    caller's guarded seam, breadcrumb cleared, reported LOUD — and the kill
//    GATE is the caller-bound `alive` probe, NOT the vendor's adopt-liveness:
//    kills fire while adoption stays UNARMED (the production posture — the
//    reviewer-confirmed inertness defect, pinned);
//  - the NEGATIVE CONTROLS this lane exists to pin: a live DAEMON whose
//    freshness proof holds is left adoptable (never killed), and a group the
//    caller's probe cannot prove alive is never killed at all (even when the
//    adopt proof would hold);
//  - the latched-step skip, the no-breadcrumb skip, the guard refusal (no
//    clear, LOUD), the dropped-clear LOUD-but-non-fatal posture, and the
//    no-provable-kind orphan (no-adopt-on-faith starts at the metadata read);
//  - SelfManagedProcessVendor's degraded sweep is a strict no-op.
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

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

/// The guarded-terminate seam, faked: records every call and returns the
/// per-pgid programmed outcome (default `exitedOnTerm`, the clean kill).
class _RecordingTerminator {
  _RecordingTerminator({Map<int, GroupTerminateResult> results = const {}})
    : _results = results;

  final Map<int, GroupTerminateResult> _results;

  /// Every (pgid, leaderPid) the sweep asked to terminate, in call order.
  final List<({int pgid, int leaderPid})> calls = [];

  Future<GroupTerminateResult> call({
    required int pgid,
    required int leaderPid,
  }) async {
    calls.add((pgid: pgid, leaderPid: leaderPid));
    return _results[pgid] ?? GroupTerminateResult.exitedOnTerm;
  }
}

/// A candidate step bead's (id, metadata) pair — the shape the reconciler
/// projects and the vendor interprets. [kind]/[state] null ⇒ key absent.
LeaseSweepCandidate _candidate(
  String stepBeadId, {
  StepKind? kind = StepKind.job,
  StepState? state = StepState.running,
  ProcessHandle? lease,
}) => (
  stepBeadId: stepBeadId,
  metadata: {
    if (kind != null) MoleculeStepKeys.kind: kind.name,
    if (state != null) MoleculeStepKeys.state: state.name,
    if (lease != null) ...leaseBreadcrumb(lease),
  },
);

/// The real vendor over the recording chokepoint, with a programmable
/// ADOPT-liveness (proveFresh's fence — the daemon preserve gate; the sweep's
/// KILL gate is the caller-bound `alive` probe, passed per call).
StationProcessLeaseVendor _vendor(
  Fakes fakes, {
  AllocationLiveness liveness = neverLive,
}) => StationProcessLeaseVendor(
  writer: fakes.ctx.writer,
  spawn: _neverSpawn,
  dispatch: _neverDispatch,
  metadataOf: (stepBeadId) async => null,
  liveness: liveness,
);

/// The caller's kill gate, programmed both ways.
bool _alwaysAlive({required int pgid, required int leaderPid}) => true;
bool _neverAlive({required int pgid, required int leaderPid}) => false;

const _live = ProcessHandle(pgid: 4242, pid: 4243, token: 'tok-live');

void main() {
  group('StationProcessLeaseVendor.sweepOrphanedLeases — the kill rung', () {
    test(
      'an orphaned live JOB group is terminated through the guarded seam, its '
      'breadcrumb cleared, and the kill reported LOUD — with the vendor\'s '
      'adopt-liveness UNARMED (neverLive, the production posture): the kill '
      'gate is the caller-bound probe, so the sweep is never inert',
      () async {
        final fakes = buildFakes();
        final terminator = _RecordingTerminator();
        final loud = <String>[];

        final swept = await _vendor(fakes).sweepOrphanedLeases(
          candidates: [_candidate('tgdog-step-1', lease: _live)],
          alive: ({required int pgid, required int leaderPid}) =>
              pgid == _live.pgid,
          terminate: terminator.call,
          onOrphan: loud.add,
        );

        expect(terminator.calls, [(pgid: 4242, leaderPid: 4243)]);
        final updates = fakes.runner.callsFor('update');
        expect(updates, hasLength(1));
        expect(updates.single[1], 'tgdog-step-1');
        expect(fakes.runner.metadataOfUpdate(0), kClearedLeaseKeys);
        expect(loud, hasLength(1));
        expect(loud.single, contains('tgdog-step-1'));
        expect(loud.single, contains('terminated'));

        expect(swept, hasLength(1));
        expect(swept.single.disposition, LeaseSweepDisposition.killed);
        expect(swept.single.handle, _live);
        expect(
          swept.single.terminateResult,
          GroupTerminateResult.exitedOnTerm,
        );
        expect(swept.single.clearFailure, isNull);
      },
    );

    test(
      'a step with NO provable daemon kind (key absent) is an orphan too — '
      'no-adopt-on-faith starts at the metadata read',
      () async {
        final fakes = buildFakes();
        final terminator = _RecordingTerminator();

        final swept = await _vendor(fakes).sweepOrphanedLeases(
          candidates: [_candidate('tgdog-step-1', kind: null, lease: _live)],
          alive: _alwaysAlive,
          terminate: terminator.call,
          onOrphan: (_) {},
        );

        expect(terminator.calls, hasLength(1));
        expect(swept.single.disposition, LeaseSweepDisposition.killed);
      },
    );

    test(
      'a live DAEMON is killed too while adoption is UNARMED (the adopt proof '
      'refutes it — nothing would re-adopt it, so leaving it running would '
      'leak; the flat path\'s never-adopt kill, D4/D5)',
      () async {
        final fakes = buildFakes();
        final terminator = _RecordingTerminator();

        final swept = await _vendor(fakes).sweepOrphanedLeases(
          candidates: [
            _candidate(
              'tgdog-step-d',
              kind: StepKind.daemon,
              state: StepState.ready,
              lease: _live,
            ),
          ],
          alive: _alwaysAlive,
          terminate: terminator.call,
          onOrphan: (_) {},
        );

        expect(terminator.calls, hasLength(1));
        expect(swept.single.disposition, LeaseSweepDisposition.killed);
        expect(fakes.runner.metadataOfUpdate(0), kClearedLeaseKeys);
      },
    );

    test(
      'an alreadyGone terminate outcome still lands in the killed bucket '
      '(no-double-run holds) with its breadcrumb cleared and the exact '
      'result preserved',
      () async {
        final fakes = buildFakes();
        final terminator = _RecordingTerminator(
          results: {4242: GroupTerminateResult.alreadyGone},
        );

        final swept = await _vendor(fakes).sweepOrphanedLeases(
          candidates: [_candidate('tgdog-step-1', lease: _live)],
          alive: _alwaysAlive,
          terminate: terminator.call,
          onOrphan: (_) {},
        );

        expect(swept.single.disposition, LeaseSweepDisposition.killed);
        expect(swept.single.terminateResult, GroupTerminateResult.alreadyGone);
        expect(fakes.runner.metadataOfUpdate(0), kClearedLeaseKeys);
      },
    );
  });

  group('sweepOrphanedLeases — NEGATIVE CONTROLS (the kill must NOT fire)', () {
    test(
      'a live DAEMON whose freshness proof holds (the adopt wire IS armed) is '
      'LEFT for the re-mounting tree to adopt — no terminate, no clearing '
      'write, nothing loud',
      () async {
        final fakes = buildFakes();
        final terminator = _RecordingTerminator();
        final loud = <String>[];

        final swept = await _vendor(fakes, liveness: (fence) => true)
            .sweepOrphanedLeases(
              candidates: [
                _candidate(
                  'tgdog-step-d',
                  kind: StepKind.daemon,
                  state: StepState.ready,
                  lease: _live,
                ),
              ],
              alive: _alwaysAlive,
              terminate: terminator.call,
              onOrphan: loud.add,
            );

        expect(terminator.calls, isEmpty, reason: 'adoption preserved — D4');
        expect(fakes.runner.callsFor('update'), isEmpty);
        expect(loud, isEmpty, reason: 'a preserved daemon is not an orphan');
        expect(swept, hasLength(1));
        expect(swept.single.disposition, LeaseSweepDisposition.leftAdoptable);
        expect(swept.single.terminateResult, isNull);
      },
    );

    test(
      'a group the caller\'s probe cannot PROVE alive is never killed — '
      'negative evidence only withholds, even when the ADOPT proof would '
      'hold (that seam never gates a kill); the stale breadcrumb is LEFT '
      '(it is inert: adoption gates on the freshness proof and the next '
      'acquire overwrites it)',
      () async {
        final fakes = buildFakes();
        final terminator = _RecordingTerminator();
        final loud = <String>[];

        final swept = await _vendor(fakes, liveness: (fence) => true)
            .sweepOrphanedLeases(
              candidates: [_candidate('tgdog-step-1', lease: _live)],
              alive: _neverAlive,
              terminate: terminator.call,
              onOrphan: loud.add,
            );

        expect(terminator.calls, isEmpty, reason: 'no kill without proof');
        expect(
          fakes.runner.callsFor('update'),
          isEmpty,
          reason: 'the documented contract: a dead group\'s breadcrumb is LEFT',
        );
        expect(loud, isEmpty);
        expect(swept, isEmpty, reason: 'nothing happened — nothing reported');
      },
    );

    test(
      'a LATCHED step (complete/failed/gated) is untouched even with a live '
      'breadcrumb — its group is not this sweep\'s business',
      () async {
        for (final state in [
          StepState.complete,
          StepState.failed,
          StepState.gated,
        ]) {
          final fakes = buildFakes();
          final terminator = _RecordingTerminator();

          final swept = await _vendor(fakes).sweepOrphanedLeases(
            candidates: [
              _candidate('tgdog-step-1', state: state, lease: _live),
            ],
            alive: _alwaysAlive,
            terminate: terminator.call,
            onOrphan: (_) {},
          );

          expect(terminator.calls, isEmpty, reason: '$state must skip');
          expect(fakes.runner.callsFor('update'), isEmpty, reason: '$state');
          expect(swept, isEmpty, reason: '$state');
        }
      },
    );

    test('no breadcrumb / a cleared breadcrumb parses to nothing — skipped', () async {
      final fakes = buildFakes();
      final terminator = _RecordingTerminator();

      final swept = await _vendor(fakes).sweepOrphanedLeases(
        candidates: [
          _candidate('tgdog-step-a'), // no lease keys at all
          (
            stepBeadId: 'tgdog-step-b', // the cleared sentinel
            metadata: {
              MoleculeStepKeys.kind: StepKind.job.name,
              MoleculeStepKeys.state: StepState.running.name,
              ...kClearedLeaseKeys,
            },
          ),
        ],
        alive: _alwaysAlive,
        terminate: terminator.call,
        onOrphan: (_) {},
      );

      expect(terminator.calls, isEmpty);
      expect(fakes.runner.callsFor('update'), isEmpty);
      expect(swept, isEmpty);
    });
  });

  group('sweepOrphanedLeases — the guarded-refusal and dropped-clear rungs', () {
    test(
      'a guard-refused terminate sends NO signal, leaves the breadcrumb (the '
      'operator\'s only record), and reports the refusal LOUD',
      () async {
        final fakes = buildFakes();
        final terminator = _RecordingTerminator(
          results: {4242: GroupTerminateResult.refusedUnsafe},
        );
        final loud = <String>[];

        final swept = await _vendor(fakes).sweepOrphanedLeases(
          candidates: [_candidate('tgdog-step-1', lease: _live)],
          alive: _alwaysAlive,
          terminate: terminator.call,
          onOrphan: loud.add,
        );

        expect(swept.single.disposition, LeaseSweepDisposition.refusedUnsafe);
        expect(
          fakes.runner.callsFor('update'),
          isEmpty,
          reason: 'a refused kill never clears the breadcrumb',
        );
        expect(loud.single, contains('REFUSED'));
      },
    );

    test(
      'a DROPPED breadcrumb clear (a bd blip) is recorded on the entry, '
      'reported LOUD, and the pass CONTINUES to the next candidate',
      () async {
        final writer = StationBeadWriter(
          bd: BdCliService(_ThrowingBdRunner()),
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        );
        final vendor = StationProcessLeaseVendor(
          writer: writer,
          spawn: _neverSpawn,
          dispatch: _neverDispatch,
          metadataOf: (stepBeadId) async => null,
        );
        final terminator = _RecordingTerminator();
        final loud = <String>[];

        final swept = await vendor.sweepOrphanedLeases(
          candidates: [
            _candidate('tgdog-step-1', lease: _live),
            _candidate(
              'tgdog-step-2',
              lease: const ProcessHandle(pgid: 5252, pid: 5253, token: 't2'),
            ),
          ],
          alive: _alwaysAlive,
          terminate: terminator.call,
          onOrphan: loud.add,
        );

        // BOTH orphans were still killed — the drop never aborts the pass.
        expect(terminator.calls, hasLength(2));
        expect(swept, hasLength(2));
        for (final entry in swept) {
          expect(entry.disposition, LeaseSweepDisposition.killed);
          expect(entry.clearFailure, contains('bd unavailable'));
        }
        // Each kill logged its kill line AND its dropped-clear line.
        expect(loud.where((m) => m.contains('DROPPED')), hasLength(2));
      },
    );
  });

  group('SelfManagedProcessVendor — the degraded sweep is a strict no-op', () {
    test(
      'even a live job breadcrumb in the candidates is ignored: no terminate, '
      'nothing loud, an empty report (this vendor never wrote a breadcrumb, '
      'so none is its to interpret)',
      () async {
        final vendor = SelfManagedProcessVendor(
          spawn: _neverSpawn,
          dispatch: _neverDispatch,
        );
        final terminator = _RecordingTerminator();
        final loud = <String>[];

        final swept = await vendor.sweepOrphanedLeases(
          candidates: [_candidate('tgdog-step-1', lease: _live)],
          alive: _alwaysAlive,
          terminate: terminator.call,
          onOrphan: loud.add,
        );

        expect(swept, isEmpty);
        expect(terminator.calls, isEmpty);
        expect(loud, isEmpty);
      },
    );
  });
}

/// A [BdRunner] whose every call fails — the transient-bd-blip seam (mirrors
/// restart_reconciler_test's).
class _ThrowingBdRunner implements BdRunner {
  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) =>
      Future<BdResult>.error(StateError('bd unavailable'));
}
