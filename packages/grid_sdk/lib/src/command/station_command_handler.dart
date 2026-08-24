import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'command_operation.dart';

/// The resident read/write rails for one substation work store.
final class WorkCommandStore {
  /// Creates one resident work-store command binding.
  const WorkCommandStore({
    required this.source,
    required this.refresh,
    required this.writer,
  });

  /// The already-running controller for this work store.
  final SnapshotSource source;

  /// Refreshes the already-running controller before a command reads it.
  final Future<void> Function() refresh;

  /// The work-store chokepoint carrying this substation's ownership set.
  final StationBeadWriter writer;
}

/// Executes operator mutations against the controllers owned by one station.
final class StationCommandHandler implements GridCommandHandler {
  /// Binds commands to the resident controller and writer instances.
  StationCommandHandler({
    required SnapshotSource stateSource,
    required Future<void> Function() refreshState,
    required StationBeadWriter stateWriter,
    required BeadOwnershipPredicate stateOwnership,
    required Map<String, WorkCommandStore> workStoresByIdentity,
  }) : _stateSource = stateSource,
       _refreshState = refreshState,
       _stateWriter = stateWriter,
       _stateOwnership = stateOwnership,
       _workStoresByIdentity = Map.unmodifiable(workStoresByIdentity);

  final SnapshotSource _stateSource;
  final Future<void> Function() _refreshState;
  final StationBeadWriter _stateWriter;
  final BeadOwnershipPredicate _stateOwnership;
  final Map<String, WorkCommandStore> _workStoresByIdentity;
  Future<void> _tail = Future<void>.value();

  @override
  Future<GridCommandResult> call(GridCommandRequest request) {
    final completer = Completer<GridCommandResult>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await _dispatch(request));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<GridCommandResult> _dispatch(
    GridCommandRequest request,
  ) async => switch (request) {
    GridRework(:final beadId, :final note, :final beyondCap, :final actor) =>
      _rework(beadId: beadId, note: note, beyondCap: beyondCap, actor: actor),
    GridGateLs() => _listGates(),
    GridGateResolve(:final gateId, :final grades, :final rationale) =>
      _resolveGate(gateId: gateId, grades: grades, rationale: rationale),
    GridSetBeadText(
      :final beadId,
      :final field,
      :final content,
      :final append,
    ) =>
      _setBeadText(
        beadId: beadId,
        field: field,
        content: content,
        append: append,
      ),
  };

  Future<GridCommandResult> _setBeadText({
    required String beadId,
    required OperatorBeadTextField field,
    required String content,
    required bool append,
  }) async {
    if (append && field != OperatorBeadTextField.notes) {
      return _refused('append_invalid', '--append is valid only for notes.');
    }
    final identity = BeadOwnershipPredicate.ownedPrefixOf(
      beadId,
      _workStoresByIdentity.keys,
    );
    final workStore = identity == null ? null : _workStoresByIdentity[identity];
    if (workStore == null) {
      return _refused(
        'work_store_not_owned',
        'No resident work store owns "$beadId".',
      );
    }
    await workStore.refresh();
    final work = workStore.source.current;
    if (work == null) {
      return _refused(
        'snapshot_unavailable',
        'A resident store has no current snapshot.',
      );
    }
    if (work.bead(beadId) == null) {
      return _refused(
        'work_bead_missing',
        'Work bead "$beadId" is absent from its resident store.',
      );
    }
    try {
      await workStore.writer.writeOperatorText(
        beadId,
        field: field,
        content: content,
        append: append,
      );
    } on OwnershipRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on OwnershipGuardRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on BeadTextRefused catch (error) {
      return _refused('text_refused', error.toString());
    } on BeadTextRoundTripFailure catch (error) {
      return _refused('text_round_trip_failed', error.toString());
    }
    return GridCommandResult.completed(
      message: 'Updated ${field.name} on "$beadId".',
      value: {
        'operation': 'grid/bead/set',
        'beadId': beadId,
        'field': field.name,
      },
    );
  }

  Future<GridCommandResult> _rework({
    required String beadId,
    required String? note,
    required bool beyondCap,
    required String? actor,
  }) async {
    final normalizedActor = actor?.trim();
    final wantsNote = note != null && note.trim().isNotEmpty;
    if (beyondCap && (normalizedActor == null || normalizedActor.isEmpty)) {
      return _refused(
        'actor_required',
        '--actor is required with --beyond-cap '
            '(the human ruling must be attributed).',
      );
    }
    if (beyondCap && !wantsNote) {
      return _refused(
        'note_required',
        '--note is required with --beyond-cap '
            '(the human ruling must carry a reason).',
      );
    }
    final identity = BeadOwnershipPredicate.ownedPrefixOf(
      beadId,
      _workStoresByIdentity.keys,
    );
    final workStore = identity == null ? null : _workStoresByIdentity[identity];
    if (workStore == null) {
      return _refused(
        'work_store_not_owned',
        'No resident work store owns "$beadId".',
      );
    }

    await _refreshState();
    await workStore.refresh();
    final state = _stateSource.current;
    final work = workStore.source.current;
    if (state == null || work == null) {
      return _refused(
        'snapshot_unavailable',
        'A resident store has no current snapshot.',
      );
    }
    if (work.bead(beadId) == null) {
      return _refused(
        'work_bead_missing',
        'Work bead "$beadId" is absent from its resident store.',
      );
    }

    final sessions = state.beads
        .where((bead) => bead.issueType == GridIssueTypes.session)
        .toList(growable: false);
    final current = sessions
        .where((bead) => _meta(bead, SessionBeadKeys.workBead) == beadId)
        .toList(growable: false);
    if (current.isEmpty) {
      return _refused(
        'session_not_found',
        'No session is linked to "$beadId".',
      );
    }
    if (current.length != 1) {
      return _refused(
        'session_ambiguous',
        '${current.length} sessions are linked to "$beadId".',
      );
    }

    final session = current.single;
    final retiredRoundAccounting = sessions
        .map((candidate) {
          final steps = state.beads
              .where((bead) {
                return bead.issueType == GridIssueTypes.step &&
                    _meta(bead, MoleculeStepKeys.session) == candidate.id;
              })
              .toList(growable: false);
          final evidence = reworkVerdictEvidence(
            session: candidate,
            steps: steps,
          );
          return (
            workBeadKey: _meta(candidate, SessionBeadKeys.workBead) ?? '',
            reachedVerdict: evidence.reachedVerdict,
            freeReason: evidence.freeReason,
          );
        })
        .toList(growable: false);
    final retiredRounds = retiredRoundAccounting
        .map(
          (round) => (
            workBeadKey: round.workBeadKey,
            reachedVerdict: round.reachedVerdict,
          ),
        )
        .toList(growable: false);
    final retiredForBead =
        retiredRoundAccounting
            .map(
              (round) => (
                round: reworkRoundOf(beadId, round.workBeadKey),
                reachedVerdict: round.reachedVerdict,
                freeReason: round.freeReason,
              ),
            )
            .where((round) => round.round != null)
            .toList(growable: false)
          ..sort((left, right) => left.round!.compareTo(right.round!));
    final maxRound = maxReworkRound(
      beadId,
      retiredRounds.map((round) => round.workBeadKey),
    );
    final spentRounds = spentReworkRounds(beadId, retiredRounds);
    if (beyondCap && spentRounds < kMaxReworkRounds) {
      return _refused(
        'beyond_cap_premature',
        '--beyond-cap is only valid at or beyond the rework cap '
            '($kMaxReworkRounds); "$beadId" has $spentRounds rounds.',
      );
    }
    if (spentRounds >= kMaxReworkRounds && !beyondCap) {
      final freeRounds = retiredForBead
          .where((round) => !round.reachedVerdict)
          .map((round) => '#r${round.round} (${round.freeReason})')
          .join(', ');
      return _refused(
        'rework_round_cap',
        '"$beadId" has ${retiredForBead.length} rounds retired; '
            '$spentRounds reached a verdict; cap $kMaxReworkRounds; '
            'free rounds: ${freeRounds.isEmpty ? 'none' : freeRounds}.',
      );
    }
    final round = maxRound + 1;

    if (!session.isClosed) {
      final cursor =
          _meta(session, SessionBeadKeys.model) == kSessionModelMolecule
          ? projectMoleculeCursor(
              state.beads.where(
                (bead) =>
                    bead.issueType == GridIssueTypes.step &&
                    _meta(bead, MoleculeStepKeys.session) == session.id,
              ),
              dependencies: state.dependencies,
            ).cursor
          : const <String, NodeCursor>{};
      final states = cursor.values.map((node) => node.state);
      // The SESSION-LEVEL park (tg-aec / tg-ehht): a failed molecule pour
      // leaves a session with NO steps at all, parked by an open gate bead
      // blocking it at the work-bead root. There is no gated STEP to find —
      // recognizing the gate is what makes the pour-failure runbook's
      // "repair the cause, then grid rework" actually executable.
      final pourParked =
          cursor.isEmpty &&
          state.beads.any(
            (bead) =>
                bead.issueType == GridIssueTypes.gate &&
                !bead.isClosed &&
                _meta(bead, 'blocks') == session.id,
          );
      if (!pourParked &&
          (states.contains(StepState.running) ||
              !states.contains(StepState.gated))) {
        return _refused(
          'session_not_parked',
          'Session "${session.id}" is open and not parked at a gate.',
        );
      }
    }

    String? reapFailure;
    try {
      await workStore.writer.clearSpecifyAuthoredSpec(beadId);
      await _stateWriter.update(
        session.id,
        metadata: {SessionBeadKeys.workBead: reworkKeyFor(beadId, round)},
      );
      // The operator finding lands BEFORE collection housekeeping: the note
      // is what the fresh round's architect reads, and losing it to a reap
      // hiccup cost a live round its findings (2026-08-07).
      if (wantsNote) {
        final timestamp = DateTime.now().toUtc().toIso8601String();
        final header = beyondCap
            ? '--- grid rework ROUND $round ($timestamp) '
                  '— BEYOND-CAP by $normalizedActor ---'
            : '--- grid rework ROUND $round ($timestamp) ---';
        await workStore.writer.update(
          beadId,
          metadata: const {},
          appendNotes: '$header\n$note',
        );
      }
      // Reap the retired round's molecule (tg-ehht): the positive-terminal
      // close already collects its own graph; rework is the OTHER designed
      // session exit and left every retired round's step beads open forever
      // — 9,389 orphans across 307 closed sessions by 2026-08-07, the
      // dependency bloat behind the graph-apply pour timeouts. A no-op for a
      // flat or never-poured (pour-parked) session. NON-FATAL: the retire
      // and the note already landed — a collection failure is reported LOUD
      // in the result, never thrown into the control door's generic 500.
      try {
        await _stateWriter.reapMolecule(sessionId: session.id);
      } on Object catch (error) {
        reapFailure = '$error';
      }
    } on OwnershipRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    }

    // A resident-internal caller can issue this command inside the current
    // projection/flush turn. Publish both durable mutation rails now: the
    // state re-key lets the join retire beadId#rN, while the work refresh
    // supplies the post-decision ready snapshot required to mint its successor.
    await Future.wait(<Future<void>>[_refreshState(), workStore.refresh()]);

    return GridCommandResult.completed(
      message: reapFailure == null
          ? 'Rework round $round retired session "${session.id}".'
          : 'Rework round $round retired session "${session.id}" — but its '
                'molecule reap FAILED (open step beads remain; sweep them): '
                '$reapFailure',
      value: {
        'operation': 'grid/rework',
        'beadId': beadId,
        'sessionId': session.id,
        'round': round,
        if (reapFailure != null) 'reapFailure': reapFailure,
      },
    );
  }

  Future<GridCommandResult> _listGates() async {
    await _refreshState();
    final state = _stateSource.current;
    if (state == null) {
      return _refused(
        'snapshot_unavailable',
        'The resident state store has no current snapshot.',
      );
    }
    final gates =
        state.beads
            .where(
              (bead) => bead.issueType == GridIssueTypes.gate && !bead.isClosed,
            )
            .toList(growable: false)
          ..sort((a, b) => a.id.compareTo(b.id));
    return GridCommandResult.completed(
      message: '${gates.length} open gate(s).',
      value: {
        'operation': 'grid/gate/ls',
        'gates': [
          for (final gate in gates)
            {
              'id': gate.id,
              'blocks': _meta(gate, 'blocks'),
              'node': _meta(gate, 'node'),
              'reason': _meta(gate, 'reason'),
              'createdAt': gate.createdAt?.toUtc().toIso8601String(),
              'regateCount':
                  int.tryParse(
                    '${gate.metadata[StationBeadWriter.gateRegateCountKey] ?? ''}',
                  ) ??
                  0,
              'regatedAt': _meta(gate, StationBeadWriter.gateRegatedAtKey),
            },
        ],
      },
    );
  }

  Future<GridCommandResult> _resolveGate({
    required String gateId,
    required Map<String, String> grades,
    required String? rationale,
  }) async {
    await _refreshState();
    final state = _stateSource.current;
    if (state == null) {
      return _refused(
        'snapshot_unavailable',
        'The resident state store has no current snapshot.',
      );
    }
    final gate = state.bead(gateId);
    if (gate == null) {
      return _refused('gate_not_found', 'Gate "$gateId" was not found.');
    }
    if (gate.issueType != GridIssueTypes.gate) {
      return _refused('not_a_gate', '"$gateId" is not a gate.');
    }
    if (gate.isClosed) {
      return _refused('gate_closed', 'Gate "$gateId" is already closed.');
    }
    if (!_stateOwnership.owns(gate)) {
      return _refused(
        'ownership_refused',
        'Gate "$gateId" is outside this station ownership set.',
      );
    }

    final node = _meta(gate, 'node');
    final sessionId = _meta(gate, 'blocks');
    final rulings = <({String path, String grade})>[];
    for (final entry in grades.entries) {
      final lane = entry.key.trim();
      final grade = entry.value.trim().toUpperCase();
      if (lane.isEmpty || !_isGrade(grade)) {
        return _refused(
          'invalid_grade',
          'Every ruling must name a lane and use a grade from A through F.',
        );
      }
      final path = _resolveLanePath(lane: lane, node: node);
      if (path == null) {
        return _refused(
          'lane_unresolvable',
          'Bare lane "$lane" cannot be resolved without a parked node.',
        );
      }
      rulings.add((path: path, grade: grade));
    }
    final hasRationale = rationale != null && rationale.trim().isNotEmpty;
    if (rulings.isNotEmpty && !hasRationale) {
      return _refused(
        'rationale_required',
        'Grade rulings require a rationale.',
      );
    }
    if (rulings.isNotEmpty && sessionId == null) {
      return _refused(
        'session_not_found',
        'Gate "$gateId" has no blocked session for the ruling.',
      );
    }

    final session = sessionId == null ? null : state.bead(sessionId);
    final ruledAway = {
      for (final ruling in rulings)
        if (ruling.grade != 'F') ruling.path,
    };
    if (session != null && node != null) {
      final parent = node.contains('/')
          ? node.substring(0, node.lastIndexOf('/'))
          : '';
      final hasFeedingF = projectCircuitResults(session).entries.any(
        (entry) =>
            entry.key != node &&
            _isSiblingOf(entry.key, parent) &&
            (entry.value[ResultKeys.grade] ?? '').toUpperCase() == 'F' &&
            !ruledAway.contains(entry.key),
      );
      if (hasFeedingF) {
        return _refused(
          'feeding_grade_f',
          'A feeding lane still has grade F; closing would immediately re-gate.',
        );
      }
    }

    try {
      for (final ruling in rulings) {
        await _stateWriter.update(
          sessionId!,
          metadata: operatorRulingMetadata(
            ruling.path,
            grade: ruling.grade,
            rationale: rationale!,
            evidenceSession: sessionId,
          ),
        );
      }
      await _stateWriter.update(
        gateId,
        metadata: {
          StationBeadWriter.gateCloseCauseKey:
              GateCloseCause.adjudicated.wireValue,
        },
        ifAssignee: gate.assignee,
        ifStatus: gate.status,
      );
      await _stateWriter.close(
        gateId,
        reason: rulings.isEmpty
            ? 'resolved via grid gate resolve'
            : 'resolved via grid gate resolve (operator ruling)',
      );
    } on OwnershipRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on OwnershipGuardRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    }

    return GridCommandResult.completed(
      message: 'Resolved gate "$gateId".',
      value: {
        'operation': 'grid/gate/resolve',
        'gateId': gateId,
        'sessionId': sessionId,
        'node': node,
      },
    );
  }
}

GridCommandResult _refused(String code, String message) =>
    GridCommandResult.refused(code: code, message: message);

String? _meta(Bead bead, String key) {
  final value = bead.metadata[key];
  return value is String && value.isNotEmpty ? value : null;
}

bool _isGrade(String value) =>
    value.length == 1 &&
    value.codeUnitAt(0) >= 0x41 &&
    value.codeUnitAt(0) <= 0x46;

String? _resolveLanePath({required String lane, required String? node}) {
  if (lane.contains('/')) return lane;
  if (node == null) return null;
  final slash = node.lastIndexOf('/');
  return slash <= 0 ? lane : '${node.substring(0, slash)}/$lane';
}

bool _isSiblingOf(String path, String parent) {
  if (parent.isEmpty) return !path.contains('/');
  if (!path.startsWith('$parent/')) return false;
  return !path.substring(parent.length + 1).contains('/');
}
