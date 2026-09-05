import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:state_notifier/state_notifier.dart';

import '../diagnostics/diagnosable.dart';
import '../domain/joined_snapshot.dart';
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
/// renders only reservations the authority has admitted.
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
      stationServices != null,
      'WorkList requires ambient StationServices',
    );
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
    assert(
      stationServices != null,
      'WorkList requires ambient StationServices',
    );
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
          retired != null;
      if (!participates) continue;
      candidates.add(
        StationAdmissionCandidate(
          bead: bead,
          session: _snapshot.sessionsByWorkBead[bead.id] ?? retired,
        ),
      );
    }

    final batch = stationServices!.admission.admitPending(
      _snapshot,
      seed.substationConfig,
      services,
      candidates,
    );
    _projectTerminalAnswers(stationServices, services, candidates, batch);
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

    // Retain already-rendered siblings ahead of newly admitted branches. The
    // authority has already applied priority/id ordering to the pending set;
    // stable placement here keeps a new sibling from perturbing an unchanged
    // mounted branch in genesis_tree's keyed reconcile.
    final projected = batch.admitted.toList()
      ..sort((left, right) {
        final leftMounted = _mountedWorkBeadsById.containsKey(
          left.candidate.bead.id,
        );
        final rightMounted = _mountedWorkBeadsById.containsKey(
          right.candidate.bead.id,
        );
        if (leftMounted == rightMounted) return 0;
        return leftMounted ? -1 : 1;
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
