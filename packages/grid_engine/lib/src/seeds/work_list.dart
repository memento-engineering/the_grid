import 'dart:async';
import 'dart:math' as math;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:state_notifier/state_notifier.dart';

import '../bridge/trust_guard.dart';
import '../diagnostics/diagnosable.dart';
import '../diagnostics/state_store_deadline.dart';
import '../domain/joined_snapshot.dart';
import '../domain/linked_sessions.dart';
import '../domain/external_dep.dart';
import '../domain/mount_attempt.dart';
import '../domain/mount_eligibility.dart';
import '../domain/rework.dart';
import '../domain/session_bead.dart';
import '../domain/session_disposition.dart';
import '../domain/session_projection.dart';
import '../domain/substation_config.dart';
import '../domain/worktree_outstanding.dart';
import '../kernel/admission_barrier.dart';
import '../kernel/state_store_write_governor.dart';
import '../kernel/station_admission_authority.dart';
import '../kernel/station_services.dart';
import '../kernel/trajectory_scope.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import '../sdk/capability.dart';
import 'work_bead.dart';

/// The work-axis observer and projection of the station admission authority.
///
/// This remains the sole joined-snapshot subscriber. It derives structural
/// candidates from the settled graph, asks the station-owned authority, and
/// renders only reservations the authority has admitted. A composition with
/// no station services retains the synchronous, write-free offline fallback.
class WorkList extends StatefulSeed with GridDiagnosticable {
  const WorkList({required this.substationConfig, super.key});

  final SubstationConfig substationConfig;

  @override
  State<WorkList> createState() => _WorkListState();

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties.addTyped(
      ReferenceProperty(
        'substation',
        substationConfig.substationId,
        kind: ReferenceKind.substation,
      ),
    );
  }
}

enum _WorkRefusalReport { terminalSkip, paused }

class _WorkListState extends State<WorkList>
    with Diagnosticable, GridDiagnosticable {
  RemoveListener? _removeSnapshotListener;
  void Function()? _removeAdmissionListener;
  JoinedSnapshotNotifier? _notifier;
  StationAdmissionAuthority? _admission;
  TrajectoryAdmissionHalt? _offlineTrajectoryAdmissionHalt;
  void Function()? _removeTrajectoryAdmissionHaltListener;
  late JoinedSnapshot _snapshot;

  final Map<String, WorkBead> _mountedWorkBeadsById = <String, WorkBead>{};
  Map<String, _WorkRefusalReport> _lastReportableRefusalByBeadId = const {};

  StationTrajectoryRecorder _recorder =
      TrajectoryRecorderScope.disabled.recorder;

  /// True while a terminal-write drain is outstanding (tg-gxp6). The terminal
  /// projection runs from [build], so a store whose gate closes are slow gets
  /// the SAME still-terminal sessions re-swept on every rebuild; without this
  /// guard each rebuild would start another drain and the overlapping drains
  /// would re-form the very herd the bound exists to prevent. One drain at a
  /// time — the next build re-derives what is still terminal and sweeps the
  /// remainder.
  bool _terminalDrainInFlight = false;

  /// Sessions whose terminal write has already SUCCEEDED this boot (tg-gxp6).
  /// A terminal session stays terminal forever and a closed gate stays closed,
  /// so re-issuing the settle or gate-close on every rebuild is pure store
  /// load: measured on lunar, ~94 done sessions re-swept every build produced
  /// ~46 gate.autoCloseFailed per minute for 48 minutes against a store that
  /// held ZERO open gates, and that contention pushed every molecule pour
  /// past its deadline. A FAILED write is deliberately not recorded, so it is
  /// retried on the next build; a fresh WorkList (a new boot) starts empty and
  /// sweeps once, which is the behaviour the restart reconciler expects.
  final Set<String> _settledTerminalSessions = <String>{};

  /// How many terminal writes this WorkList has dispatched per session this
  /// boot (tg-66w8) — the `attempt` a `gate.autoCloseFailed` flare carries, so
  /// a one-off store blip is distinguishable on the board from a session whose
  /// every re-drive keeps dying in a burst. Cleared with the memo on success.
  final Map<String, int> _terminalWriteAttemptsBySession = <String, int>{};

  /// The barrier's observer (§W2.4 W2-B) — the offline path's own handle to
  /// the counting arm and the refusal derivation. Null composes the clause in
  /// its observe form over a disarmed read, which refuses nothing.
  AdmissionBarrier? _barrier;

  static SessionProjection? _latestRetiredSession(
    String beadId,
    Iterable<SessionProjection> sessions,
  ) {
    SessionProjection? latest;
    var latestRound = 0;
    for (final session in sessions) {
      final round = reworkRoundOf(beadId, session.workBeadId);
      if (round != null && round > latestRound) {
        latest = session;
        latestRound = round;
      }
    }
    return latest;
  }

  WorkBead _workBeadFor(StationAdmissionReservation reservation) {
    final candidate = reservation.candidate;
    final bead = candidate.bead;
    final cached = _mountedWorkBeadsById[bead.id];
    final carriedReservation = reservation.reservationToken == null
        ? cached?.admissionReservation ?? reservation
        : reservation;
    final priorSession = cached?.session;
    var mountToken =
        carriedReservation.reservationToken ??
        WorkBead.nullReservationMountToken;
    if (cached != null &&
        priorSession != null &&
        !priorSession.isTerminal &&
        reworkRoundOf(bead.id, priorSession.workBeadId) == null &&
        candidate.session == null &&
        cached.admissionReservation?.reservationToken == null) {
      // A live row disappearing without a durable #rN projection is not a
      // rework grant. Keep that live scope mounted so its state can refuse the
      // malformed disappearance loudly; its prior release token was null, so
      // watching the newly held value cannot make a stale token authoritative.
      mountToken = cached.effectiveAdmissionReservationMountToken;
    } else if (cached != null &&
        identical(
          cached.admissionReservation?.reservationToken,
          carriedReservation.reservationToken,
        )) {
      mountToken = cached.effectiveAdmissionReservationMountToken;
    }
    if (cached != null &&
        cached.bead == bead &&
        cached.session == candidate.session &&
        identical(
          cached.admissionReservation?.reservationToken,
          carriedReservation.reservationToken,
        ) &&
        identical(cached.effectiveAdmissionReservationMountToken, mountToken)) {
      return cached;
    }
    return _mountedWorkBeadsById[bead.id] = WorkBead(
      bead: bead,
      session: candidate.session,
      admissionReservation: carriedReservation,
      admissionReservationMountToken: mountToken,
      key: ValueKey(bead.id),
    );
  }

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties.addTyped(
      IntProperty('mountedWorkCount', _mountedWorkBeadsById.length),
    );
  }

  @override
  void didChangeDependencies() {
    // Always watch both dependencies before either identity guard. Their
    // listener lifetimes are independent.
    final stationServices = context.watch<StationServices>();
    final notifier = context.watch<JoinedSnapshotNotifier>();
    final trajectoryScope = context.watch<TrajectoryRecorderScope>();
    assert(
      notifier != null,
      'WorkList requires an ambient JoinedSnapshotNotifier',
    );

    if (!identical(stationServices?.admission, _admission)) {
      _removeAdmissionListener?.call();
      _admission = stationServices?.admission;
      _removeAdmissionListener = _admission?.addInvalidationListener(() {
        if (!context.mounted) return;
        setState(() {});
      });
    }

    final offlineHalt = stationServices == null
        ? trajectoryScope?.admissionHalt
        : null;
    if (!identical(offlineHalt, _offlineTrajectoryAdmissionHalt)) {
      _removeTrajectoryAdmissionHaltListener?.call();
      _offlineTrajectoryAdmissionHalt = offlineHalt;
      _removeTrajectoryAdmissionHaltListener = offlineHalt?.addListener(() {
        if (!context.mounted) return;
        setState(() {});
      });
    }
    _recorder =
        trajectoryScope?.recorder ?? TrajectoryRecorderScope.disabled.recorder;
    _barrier = trajectoryScope?.barrier;

    if (!identical(notifier, _notifier)) {
      _removeSnapshotListener?.call();
      _notifier = notifier;
      var first = true;
      _removeSnapshotListener = notifier!.addListener((snapshot) {
        if (first) {
          first = false;
          _snapshot = snapshot;
          return;
        }
        setState(() => _snapshot = snapshot);
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _removeSnapshotListener?.call();
    _removeSnapshotListener = null;
    _removeAdmissionListener?.call();
    _removeAdmissionListener = null;
    _removeTrajectoryAdmissionHaltListener?.call();
    _removeTrajectoryAdmissionHaltListener = null;
  }

  @override
  Seed build(TreeContext context) {
    final stationServices = context.watch<StationServices>();
    final services = context.watch<ServiceBundle>() ?? const ServiceBundle();
    final ownership = BeadOwnershipPredicate(
      seed.substationConfig.ownedSubstations,
    );

    final candidates = <StationAdmissionCandidate>[];
    for (final bead in _snapshot.graph.beadsById.values) {
      if (!ownership.owns(bead)) continue;
      final linked = _snapshot.linkedSessions(bead.id);
      final retired = linked.isEmpty
          ? _latestRetiredSession(bead.id, _snapshot.sessionsByWorkBead.values)
          : null;
      final participates =
          _snapshot.graph.readyIds.contains(bead.id) ||
          hasStampedOpenExternalTargetHold(_snapshot.graph, bead) ||
          linked.isNotEmpty ||
          retired != null ||
          _mountedWorkBeadsById.containsKey(bead.id);
      if (!participates) continue;
      candidates.add(
        StationAdmissionCandidate(
          bead: bead,
          session: _snapshot.sessionsByWorkBead[bead.id] ?? retired,
        ),
      );
    }

    final batch = stationServices == null
        ? _admitOffline(services, ownership, candidates)
        : stationServices.admission.admitPending(
            _snapshot,
            seed.substationConfig,
            services,
            candidates,
          );
    if (stationServices != null) {
      _projectTerminalAnswers(stationServices, services, candidates);
    }
    final currentReportableRefusalByBeadId = <String, _WorkRefusalReport>{};
    for (final refusal in batch.refused) {
      final report = switch (refusal.clause) {
        'done' || 'held' => _WorkRefusalReport.terminalSkip,
        'paused' => _WorkRefusalReport.paused,
        _ => null,
      };
      if (report == null) continue;
      final beadId = refusal.candidate.bead.id;
      if (currentReportableRefusalByBeadId.containsKey(beadId)) continue;
      currentReportableRefusalByBeadId[beadId] = report;
      if (_lastReportableRefusalByBeadId[beadId] == report) continue;
      switch (report) {
        case _WorkRefusalReport.terminalSkip:
          _reportTerminalSkip(
            services,
            beadId,
            refusal.candidate.session?.sessionId ?? '',
            refusal.clause,
            refusal.detail,
          );
        case _WorkRefusalReport.paused:
          _reportPaused(
            services,
            beadId,
            refusal.candidate.session?.sessionId ?? '',
            refusal.detail,
          );
      }
    }
    _lastReportableRefusalByBeadId = Map.unmodifiable(
      currentReportableRefusalByBeadId,
    );

    // Keep already-rendered keyed siblings ahead of newly admitted branches.
    // The authority's priority/id ordering governs pending reservations; this
    // stable projection avoids perturbing an unchanged mounted branch.
    final mountedOrder = <String, int>{};
    var mountedIndex = 0;
    for (final beadId in _mountedWorkBeadsById.keys) {
      mountedOrder[beadId] = mountedIndex++;
    }
    final projected = batch.admitted.toList()
      ..sort((left, right) {
        final leftIndex = mountedOrder[left.candidate.bead.id];
        final rightIndex = mountedOrder[right.candidate.bead.id];
        if (leftIndex != null && rightIndex != null) {
          return leftIndex.compareTo(rightIndex);
        }
        if (leftIndex != null) return -1;
        if (rightIndex != null) return 1;
        final leftCarriesLive =
            left.candidate.session != null &&
            !left.candidate.session!.isTerminal;
        final rightCarriesLive =
            right.candidate.session != null &&
            !right.candidate.session!.isTerminal;
        if (leftCarriesLive != rightCarriesLive) {
          return leftCarriesLive ? -1 : 1;
        }
        return 0;
      });
    final mounted = [
      for (final reservation in projected) _workBeadFor(reservation),
    ];
    final emitted = {for (final work in mounted) work.bead.id};
    _mountedWorkBeadsById.removeWhere((id, _) => !emitted.contains(id));

    return Nest(
      children: [
        Provider<JoinedSnapshot>.value(_snapshot),
        Provider<SubstationConfig>.value(seed.substationConfig),
      ],
      child: _WorkBeads(mounted),
    );
  }

  /// Preserves the pre-authority composition used by offline tree tests.
  ///
  /// This branch owns no station-wide state: it evaluates the same pure gate,
  /// trust policy, linked-session disposition, deterministic ordering, and
  /// substation ceiling as the former WorkList, but deliberately skips the
  /// authority-only reservation and durable mount-attempt write.
  StationAdmissionBatch _admitOffline(
    ServiceBundle services,
    BeadOwnershipPredicate ownership,
    List<StationAdmissionCandidate> candidates,
  ) {
    final mountEligibility = composeMountEligibility([
      trajectoryAdmissionHaltedClause(
        halted: _offlineTrajectoryAdmissionHalt?.halted ?? false,
      ),
      dispatchableWorkClause(resident: seed.substationConfig.resident),
      driveListClause(seed.substationConfig.driveList),
      // A per-candidate refusal is orthogonal to the pending bin's
      // priority-then-bead-id ordering below. It cannot admit a terminal or
      // paused row; the linked-session disposition still decides those after
      // this pure gate.
      sameStoreDependencyExclusionClause(
        _snapshot.graph,
        ownership,
        _snapshot.sessionsByWorkBead,
      ),
      externalDepOpenTargetClause(_snapshot.graph),
      mountAttemptClause(_snapshot.mountAttemptsByWorkBead),
      // THE WORKTREE-OUTSTANDING BARRIER (cut-wiring §W2.4 W2-B), composed at
      // BOTH `composeMountEligibility` sites. Under shadow it runs in its
      // OBSERVE form: it evaluates, its findings are counted, and eligibility
      // changes for no candidate.
      worktreeOutstandingClause(
        read: _snapshot.worktreeOutstanding,
        linkedSessionsOf: _snapshot.linkedSessions,
        snapshotRevOf: _snapshot.eligibilityBasisRevisionOf,
        observeForm: _barrier?.observeForm ?? true,
        onFinding: _barrier?.observe,
        // The offline path owns no clock; the barrier's is the one instant
        // both composition sites judge the heartbeat against.
        clock: _barrier?.clock,
      ),
    ], services.mountEligibility);
    final mounted = <StationAdmissionReservation>[];
    final pending = <StationAdmissionCandidate>[];
    final refused = <StationAdmissionRefusal>[];

    for (final candidate in candidates) {
      final bead = candidate.bead;
      // This is the join-selected frontier row (or a retired re-key). It makes
      // eligibility advisory for lifecycle preservation without bypassing the
      // linked-session verdict below.
      final retiredRound =
          candidate.session != null &&
          reworkRoundOf(bead.id, candidate.session!.workBeadId) != null;
      final staysMounted =
          candidate.session?.isTerminal == false ||
          retiredRound ||
          _mountedWorkBeadsById.containsKey(bead.id);
      late final MountEligibilityDecision eligibility;
      try {
        eligibility = mountEligibility(bead);
      } on Object catch (error) {
        eligibility = MountEligibilityDecision.refused(
          clause:
              'mount eligibility evaluation failed: '
              '${truncateReason('$error')}',
        );
      }
      switch (eligibility) {
        case MountRefused(:final clause):
          if (!staysMounted) {
            refused.add(
              StationAdmissionRefusal(
                candidate: candidate,
                clause: _clauseName(clause),
                detail: clause,
              ),
            );
            continue;
          }
        case MountEligible():
      }

      if (services.trust != null) {
        final reasons = <String>[];
        final trusted = applyTrustGuard(
          candidates: {bead.id},
          beadsById: _snapshot.graph.beadsById,
          floor: services.trustFloor,
          trustConfigured: true,
          onUnresolved: reasons.add,
        );
        if (!trusted.contains(bead.id)) {
          refused.add(
            StationAdmissionRefusal(
              candidate: candidate,
              clause: 'trust',
              detail: reasons.single,
            ),
          );
          continue;
        }
      }

      final verdict = linkedSessionVerdictOf(_snapshot.linkedSessions(bead.id));
      if (bead.isClosed) {
        final disposition = sessionDispositionOf(verdict.winner);
        final clause = switch (disposition) {
          HeldSession() => 'held',
          DoneSession() => 'done',
          NoSession() ||
          LiveSession() ||
          VoidedSession() ||
          PausedSession() => 'work-terminal',
        };
        refused.add(
          StationAdmissionRefusal(
            candidate: candidate,
            clause: clause,
            detail: 'the work bead is terminal',
          ),
        );
        continue;
      }
      switch (verdict) {
        case AdoptLinkedSession(:final session, :final rivals):
          if (rivals.isNotEmpty) {
            refused.add(
              StationAdmissionRefusal(
                candidate: candidate,
                clause: 'duplicate-live',
                detail: 'more than one live durable session links this bead',
              ),
            );
            continue;
          }
          final awaitsReadmission =
              session.pauseState == SessionPauseState.resumed &&
              !_mountedWorkBeadsById.containsKey(bead.id);
          if (awaitsReadmission) break;
          mounted.add(
            StationAdmissionReservation(
              candidate: StationAdmissionCandidate(
                bead: bead,
                session: session,
              ),
              substationId: seed.substationConfig.substationId,
              mountAttempt: null,
              sessionId: session.sessionId,
              adopted: session.sessionId?.isNotEmpty == true,
              reservationToken: null,
            ),
          );
          continue;
        case BlockedLinkedSession(:final session):
          final disposition = sessionDispositionOf(session);
          final clause = switch (disposition) {
            HeldSession() => 'held',
            PausedSession() => 'paused',
            DoneSession() => 'done',
            NoSession() ||
            LiveSession() ||
            VoidedSession() => 'blocked-session',
          };
          refused.add(
            StationAdmissionRefusal(
              candidate: candidate,
              clause: clause,
              detail: 'the linked session is a blocking terminal ($clause)',
            ),
          );
          continue;
        case NoLinkedSession() || RemintLinkedSession():
          break;
      }

      if (!_snapshot.graph.readyIds.contains(bead.id) && !staysMounted) {
        continue;
      }
      if (staysMounted) {
        mounted.add(_offlineReservation(candidate));
      } else {
        pending.add(candidate);
      }
    }

    int compareCandidates(
      StationAdmissionCandidate left,
      StationAdmissionCandidate right,
    ) {
      final byPriority = left.bead.priority.compareTo(right.bead.priority);
      return byPriority != 0
          ? byPriority
          : left.bead.id.compareTo(right.bead.id);
    }

    pending.sort(compareCandidates);
    final cap =
        seed.substationConfig.maxConcurrentWork ?? kDefaultMaxConcurrentWork;
    final slots = math.max(0, cap - mounted.length);
    final newlyAdmitted = pending.take(slots).toList(growable: false);
    final waiting = pending.skip(slots).toList(growable: false);
    mounted.addAll(newlyAdmitted.map(_offlineReservation));
    mounted.sort(
      (left, right) => compareCandidates(left.candidate, right.candidate),
    );
    if (waiting.isNotEmpty) {
      final beadIds = waiting.map((candidate) => candidate.bead.id);
      _flare(services, 'work.throttled', {
        'count': '${waiting.length}',
        'beadIds': beadIds.join(','),
        'cause': WorkThrottleCause.slotsFull,
        'causes': beadIds
            .map((id) => '$id=${WorkThrottleCause.slotsFull}')
            .join(','),
      });
    }
    return StationAdmissionBatch(
      admitted: mounted,
      waiting: waiting,
      refused: refused,
    );
  }

  StationAdmissionReservation _offlineReservation(
    StationAdmissionCandidate candidate,
  ) => StationAdmissionReservation(
    candidate: candidate,
    substationId: seed.substationConfig.substationId,
    mountAttempt: null,
    sessionId: candidate.session?.sessionId,
    adopted: candidate.session?.sessionId?.isNotEmpty == true,
    reservationToken: null,
  );

  static String _clauseName(String detail) {
    final colon = detail.indexOf(':');
    return colon < 0 ? detail : detail.substring(0, colon);
  }

  void _projectTerminalAnswers(
    StationServices station,
    ServiceBundle services,
    List<StationAdmissionCandidate> candidates,
  ) {
    if (_terminalDrainInFlight) return;
    // ONE CLOSURE PER TERMINAL ANSWER, drained under the STATION-WIDE
    // concurrency bound rather than dispatched all at once (tg-gxp6, tg-66w8).
    // A store carrying hundreds of closed sessions used to get one unawaited
    // write per session fired simultaneously at every boot; the tail of that
    // burst blew DoltQueryService.queryTimeout, and the failed gate closes then
    // cancelled the first mint of every ready bead - leaving the station UP and
    // ARMED with `ready > 0, mounted 0` and no retry, because the mint failure
    // is latched per scope.
    //
    // The terminal answer is derived from the candidate's OWN session
    // disposition, not from the admission refusal clause. A done session owes
    // its gate close whether or not its work bead is currently eligible to
    // re-mount: the eligibility clauses (the attempt cap, the worktree barrier,
    // a same-store dependency hold) refuse under their own names, and keying
    // the sweep on the `done` clause let any of them silently cancel the
    // re-drive of a close that had already failed once (tg-66w8 AC-2).
    final terminalWrites = <Future<void> Function()>[];
    for (final candidate in candidates) {
      final bead = candidate.bead;
      final session = candidate.session;
      final sessionId = session?.sessionId ?? '';
      if (sessionId.isEmpty) continue;
      if (_settledTerminalSessions.contains(sessionId)) continue;
      final disposition = sessionDispositionOf(session);
      if (bead.isClosed && disposition is LiveSession) {
        terminalWrites.add(
          () => _settleTerminalWorkBead(
            station: station,
            services: services,
            candidate: candidate,
            sessionId: sessionId,
          ),
        );
        continue;
      }
      if (disposition is DoneSession) {
        terminalWrites.add(
          () => _closeTerminalGates(
            station: station,
            services: services,
            sessionId: sessionId,
          ),
        );
      }
    }
    if (terminalWrites.isEmpty) return;
    _terminalDrainInFlight = true;
    unawaited(_runTerminalDrain(station.terminalWrites, terminalWrites));
  }

  /// Owns the [_terminalDrainInFlight] latch for one drain, so the flag is
  /// cleared even when a write escapes its own error handling.
  Future<void> _runTerminalDrain(
    StateStoreWriteGovernor governor,
    List<Future<void> Function()> writes,
  ) async {
    try {
      await _drainTerminalWrites(governor, writes);
    } finally {
      _terminalDrainInFlight = false;
    }
  }

  /// Hands every write to the station's shared [governor], which admits at
  /// most `kTerminalWriteConcurrency` at a time ACROSS THE STATION - not per
  /// WorkList (tg-66w8). Every closure swallows and flares its own failure, so
  /// one bad write never halts the drain and the sweep still reaches every
  /// terminal session.
  static Future<void> _drainTerminalWrites(
    StateStoreWriteGovernor governor,
    List<Future<void> Function()> writes,
  ) async {
    await Future.wait(<Future<void>>[
      for (final write in writes) governor.run(write),
    ]);
  }

  /// Counts one more dispatch of a terminal write for [sessionId] and returns
  /// the attempt ordinal it carries.
  int _nextTerminalWriteAttempt(String sessionId) {
    final attempt = (_terminalWriteAttemptsBySession[sessionId] ?? 0) + 1;
    _terminalWriteAttemptsBySession[sessionId] = attempt;
    return attempt;
  }

  void _memoizeTerminalWrite(String sessionId) {
    _settledTerminalSessions.add(sessionId);
    _terminalWriteAttemptsBySession.remove(sessionId);
  }

  Future<void> _settleTerminalWorkBead({
    required StationServices station,
    required ServiceBundle services,
    required StationAdmissionCandidate candidate,
    required String sessionId,
  }) async {
    final attempt = _nextTerminalWriteAttempt(sessionId);
    try {
      await station.admission.settleWorkTerminalSession(
        terminalWorkBead: candidate.bead,
        sessionId: sessionId,
        services: services,
      );
      _recorder.sessionSettled(
        sessionId: sessionId,
        workBeadId: candidate.bead.id,
        workTerminalReason: StationBeadWriter.workTerminalReasonWorkBeadClosed,
      );
      _memoizeTerminalWrite(sessionId);
    } on Object catch (error) {
      _reportTerminalWriteFailed(
        services,
        sessionId: sessionId,
        cause: GateCloseCause.workBeadClosed,
        attempt: attempt,
        error: error,
      );
    }
  }

  Future<void> _closeTerminalGates({
    required StationServices station,
    required ServiceBundle services,
    required String sessionId,
  }) async {
    final attempt = _nextTerminalWriteAttempt(sessionId);
    try {
      await station.admission.closeTerminalGates(
        sessionId: sessionId,
        cause: GateCloseCause.sessionTerminal,
        disposition: GateSweepSessionDisposition.done,
        services: services,
      );
      _memoizeTerminalWrite(sessionId);
    } on Object catch (error) {
      _reportTerminalWriteFailed(
        services,
        sessionId: sessionId,
        cause: GateCloseCause.sessionTerminal,
        attempt: attempt,
        error: error,
      );
    }
  }

  /// The one `gate.autoCloseFailed` shape both terminal writes flare
  /// (tg-66w8 AC-3): the owning substation and the attempt ordinal ride beside
  /// the deadline provenance, so a one-off is distinguishable from a burst and
  /// a session whose close keeps failing is visible rather than quiet.
  void _reportTerminalWriteFailed(
    ServiceBundle services, {
    required String sessionId,
    required GateCloseCause cause,
    required int attempt,
    required Object error,
  }) {
    _flare(services, 'gate.autoCloseFailed', {
      'sessionId': sessionId,
      'substation': seed.substationConfig.substationId,
      'attempt': '$attempt',
      'cause': cause.wireValue,
      'reason': truncateReason('$error'),
      ...stateStoreDeadlineMetadata(error),
    });
  }

  void _reportTerminalSkip(
    ServiceBundle services,
    String beadId,
    String sessionId,
    String disposition,
    String reason,
  ) {
    _flare(services, 'work.terminalSkip', {
      'beadId': beadId,
      'sessionId': sessionId,
      'disposition': disposition,
      'reason': truncateReason(reason),
    });
  }

  void _reportPaused(
    ServiceBundle services,
    String beadId,
    String sessionId,
    String reason,
  ) {
    _flare(services, 'work.paused', {
      'beadId': beadId,
      'sessionId': sessionId,
      'reason': truncateReason(reason),
    });
  }

  static void _flare(
    ServiceBundle services,
    String name,
    Map<String, String> data,
  ) {
    try {
      services.transport?.flare(name, data);
    } on Object {
      // A throwing transport never breaks reconciliation.
    }
  }
}

class _WorkBeads extends MultiChildSeed {
  _WorkBeads(List<WorkBead> beads) : super(children: beads);
}
