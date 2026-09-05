import 'dart:async';
import 'dart:math' as math;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:state_notifier/state_notifier.dart';

import '../bridge/trust_guard.dart';
import '../diagnostics/diagnosable.dart';
import '../domain/joined_snapshot.dart';
import '../domain/linked_sessions.dart';
import '../domain/mount_attempt.dart';
import '../domain/mount_eligibility.dart';
import '../domain/rework.dart';
import '../domain/session_bead.dart';
import '../domain/session_disposition.dart';
import '../domain/session_projection.dart';
import '../domain/substation_config.dart';
import '../kernel/station_admission_authority.dart';
import '../kernel/station_services.dart';
import '../kernel/trajectory_scope.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import '../sdk/capability.dart';
import 'provider.dart';
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

class _WorkListState extends State<WorkList>
    with Diagnosticable, GridDiagnosticable {
  RemoveListener? _removeSnapshotListener;
  void Function()? _removeAdmissionListener;
  JoinedSnapshotNotifier? _notifier;
  StationAdmissionAuthority? _admission;
  late JoinedSnapshot _snapshot;

  final Map<String, WorkBead> _mountedWorkBeadsById = <String, WorkBead>{};
  final Set<String> _terminalSkipReported = <String>{};

  StationTrajectoryRecorder _recorder =
      TrajectoryRecorderScope.disabled.recorder;

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

  WorkBead _workBeadFor(StationAdmissionCandidate candidate) {
    final bead = candidate.bead;
    final cached = _mountedWorkBeadsById[bead.id];
    if (cached != null &&
        cached.bead == bead &&
        cached.session == candidate.session) {
      return cached;
    }
    return _mountedWorkBeadsById[bead.id] = WorkBead(
      bead: bead,
      session: candidate.session,
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
  }

  @override
  Seed build(TreeContext context) {
    final stationServices = context.watch<StationServices>();
    final services = context.watch<ServiceBundle>() ?? const ServiceBundle();
    _recorder = trajectoryRecorderOf(context);
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
          _snapshot.frontierExclusionsByBeadId.containsKey(bead.id) ||
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
        ? _admitOffline(services, candidates)
        : stationServices.admission.admitPending(
            _snapshot,
            seed.substationConfig,
            services,
            candidates,
          );
    if (stationServices != null) {
      _projectTerminalAnswers(stationServices, services, candidates, batch);
    }
    for (final refusal in batch.refused) {
      if (refusal.clause == 'done' || refusal.clause == 'held') {
        _reportTerminalSkip(
          services,
          refusal.candidate.bead.id,
          refusal.candidate.session?.sessionId ?? '',
          refusal.clause,
          refusal.detail,
        );
      }
    }

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
      for (final reservation in projected) _workBeadFor(reservation.candidate),
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
    List<StationAdmissionCandidate> candidates,
  ) {
    final mountEligibility = composeMountEligibility([
      dispatchableWorkClause(resident: seed.substationConfig.resident),
      driveListClause(seed.substationConfig.driveList),
      crossLinkExclusionClause(
        _snapshot.frontierExclusionsByBeadId,
        _snapshot.sessionsByWorkBead,
      ),
      mountAttemptClause(_snapshot.mountAttemptsByWorkBead),
    ], services.mountEligibility);
    final mounted = <StationAdmissionReservation>[];
    final pending = <StationAdmissionCandidate>[];
    final refused = <StationAdmissionRefusal>[];

    for (final candidate in candidates) {
      final bead = candidate.bead;
      final MountEligibilityDecision eligibility;
      try {
        eligibility = mountEligibility(bead);
      } on Object catch (error) {
        refused.add(
          StationAdmissionRefusal(
            candidate: candidate,
            clause: 'mount eligibility evaluation failed',
            detail:
                'mount eligibility evaluation failed: '
                '${truncateReason('$error')}',
          ),
        );
        continue;
      }
      if (eligibility case MountRefused(:final clause)) {
        refused.add(
          StationAdmissionRefusal(
            candidate: candidate,
            clause: _clauseName(clause),
            detail: clause,
          ),
        );
        continue;
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
          NoSession() || LiveSession() || VoidedSession() => 'work-terminal',
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
            ),
          );
          continue;
        case BlockedLinkedSession(:final session):
          final disposition = sessionDispositionOf(session);
          final clause = disposition is HeldSession ? 'held' : 'done';
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

      final retiredRound =
          candidate.session != null &&
          reworkRoundOf(bead.id, candidate.session!.workBeadId) != null;
      final staysMounted =
          retiredRound || _mountedWorkBeadsById.containsKey(bead.id);
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
      _flare(services, 'work.throttled', {
        'count': '${waiting.length}',
        'beadIds': waiting.map((candidate) => candidate.bead.id).join(','),
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
  );

  static String _clauseName(String detail) {
    final colon = detail.indexOf(':');
    return colon < 0 ? detail : detail.substring(0, colon);
  }

  void _projectTerminalAnswers(
    StationServices station,
    ServiceBundle services,
    List<StationAdmissionCandidate> candidates,
    StationAdmissionBatch batch,
  ) {
    final refusedById = {
      for (final refusal in batch.refused) refusal.candidate.bead.id: refusal,
    };
    for (final candidate in candidates) {
      final bead = candidate.bead;
      final session = candidate.session;
      final sessionId = session?.sessionId ?? '';
      if (sessionId.isEmpty) continue;
      final disposition = sessionDispositionOf(session);
      if (bead.isClosed && disposition is LiveSession) {
        unawaited(
          station.admission
              .settleWorkTerminalSession(
                terminalWorkBead: bead,
                sessionId: sessionId,
                services: services,
              )
              .then((_) {
                _recorder.sessionSettled(
                  sessionId: sessionId,
                  workBeadId: bead.id,
                  workTerminalReason:
                      StationBeadWriter.workTerminalReasonWorkBeadClosed,
                );
              })
              .catchError((Object error) {
                _flare(services, 'gate.autoCloseFailed', {
                  'sessionId': sessionId,
                  'cause': GateCloseCause.workBeadClosed.wireValue,
                  'reason': truncateReason('$error'),
                });
              }),
        );
        continue;
      }
      final refusal = refusedById[bead.id];
      if (refusal?.clause == 'done') {
        unawaited(
          station.admission
              .closeTerminalGates(
                sessionId: sessionId,
                cause: GateCloseCause.sessionTerminal,
                disposition: GateSweepSessionDisposition.done,
                services: services,
              )
              .catchError((Object error) {
                _flare(services, 'gate.autoCloseFailed', {
                  'sessionId': sessionId,
                  'cause': GateCloseCause.sessionTerminal.wireValue,
                  'reason': truncateReason('$error'),
                });
              }),
        );
      }
    }
  }

  void _reportTerminalSkip(
    ServiceBundle services,
    String beadId,
    String sessionId,
    String disposition,
    String reason,
  ) {
    if (!_terminalSkipReported.add(beadId)) return;
    _flare(services, 'work.terminalSkip', {
      'beadId': beadId,
      'sessionId': sessionId,
      'disposition': disposition,
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
