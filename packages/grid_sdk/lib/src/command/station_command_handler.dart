import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'bead_board.dart';
import 'bead_round.dart';
import 'command_operation.dart';

/// The resident read/write rails for one substation work store.
final class WorkCommandStore {
  /// Creates one resident work-store command binding.
  const WorkCommandStore({
    required this.substation,
    required this.root,
    required this.source,
    required this.refresh,
    required this.writer,
  });

  /// The substation NAME this binding serves — the board's `store` column.
  final String substation;

  /// That substation's single absolute work-store root.
  final String root;

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
    StationTrajectoryRecorder? recorder,
    TrajectoryStepSnapshot Function()? stepSnapshot,
    DualReadMode dualReadMode = DualReadMode.off,
    DualReadAccounting? dualReadAccounting,
  }) : _stateSource = stateSource,
       _refreshState = refreshState,
       _stateWriter = stateWriter,
       _stateOwnership = stateOwnership,
       _recorder = recorder ?? StationTrajectoryRecorder.disabled(),
       _stepSnapshot = stepSnapshot,
       _dualReadMode = dualReadMode,
       _dualReadAccounting = dualReadAccounting,
       _workStoresByIdentity = Map.unmodifiable(workStoresByIdentity);

  final SnapshotSource _stateSource;
  final Future<void> Function() _refreshState;
  final StationBeadWriter _stateWriter;
  final BeadOwnershipPredicate _stateOwnership;

  /// The Stage-1 derivation layer (stage1-wiring §2.3's `attempt.round.retired`
  /// row). `grid rework` is where an operator RETIRES a round, and this
  /// handler is the code that makes the re-key — so it is one of that record's
  /// two observation sites. Absent it is a counting no-op.
  final StationTrajectoryRecorder _recorder;

  /// THE STEP AXIS'S PRE-FETCHED READ (cut-wiring C4) — the P2 mirror, for
  /// CONSUMER 3: `grid rework`'s park check.
  ///
  /// The check is the one cursor consumer with NO [SessionProjection] to hang
  /// a `trajCursor` on — it reads raw state beads off the resident snapshot —
  /// so the posture reaches it by constructor rather than structurally. The
  /// three inputs are exactly what the bridge derives its own engagement
  /// from, and they are read the same way: `primary`, snapshot health `live`,
  /// and a boot that has not disengaged.
  final TrajectoryStepSnapshot Function()? _stepSnapshot;
  final DualReadMode _dualReadMode;

  /// The boot's SHARED accounting — the same object the bridge's passes use,
  /// so the disengage latch is one fact and the p2Miss/stepLag this site sees
  /// land in the same durable round summary.
  final DualReadAccounting? _dualReadAccounting;

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
    GridBeadBoard(
      :final stores,
      :final statuses,
      :final blockedOnly,
      :final approved,
    ) =>
      _board(
        BoardFilter(
          stores: stores,
          statuses: statuses,
          blockedOnly: blockedOnly,
          approved: approved,
        ),
      ),
    GridBeadRound(:final beadId) => _beadRound(beadId),
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
    final linked = sessions
        .where((bead) => _meta(bead, SessionBeadKeys.workBead) == beadId)
        .toList(growable: false);
    if (linked.isEmpty) {
      return _refused(
        'session_not_found',
        'No session is linked to "$beadId".',
      );
    }
    // REWORK KEYS ON OPEN SESSIONS ONLY (tg-83k1). A CLOSED row is never
    // adoptable under A48 (its done/held/voided disposition separately governs
    // the mount boundary), so counting closed history toward this live-session
    // ambiguity refusal made `grid rework` unusable on any bead with mint
    // history. The refusal survives for the ONE genuinely ambiguous shape: two
    // or more OPEN rows, which is two live agents and a human's call.
    final open = linked.where((bead) => !bead.isClosed).toList(growable: false);
    if (open.length > 1) {
      return _refused(
        'session_ambiguous',
        '${open.length} sessions are linked to "$beadId".',
      );
    }
    // All-terminal: retire the row the JOIN publishes, resolved through the
    // engine's ONE ordering rule rather than a second recency rule beside it —
    // so the operator verb and the frontier never disagree about which round is
    // current. That row is the newest dead key, or the BLOCKING terminal when
    // one is present, which is precisely the row an operator runs `grid rework`
    // to unstick.
    final session = open.length == 1 ? open.single : _publishedRow(linked);
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
      final beadCursor =
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
      // CONSUMER 3 of the step dual read (cut-wiring C4) — the park check.
      // The site's today-read IS the bead recompute, so the unengaged branch
      // is the identity and `observe` leaves this verb byte-identical.
      final cursor = _effectiveParkCursor(session.id, beadCursor);
      final states = cursor.values.map((node) => node.state);
      // THE PARK PREDICATE KEYS ON THE OPEN GATE, NEVER ON CURSOR ABSENCE
      // (tg-aec / tg-ehht / tg-xpgx). Minting a gate bead whose `blocks`
      // names the session IS the park — the invariant
      // `SessionScope._parkFailedMoleculePour` establishes and
      // `StationBeadWriter.createGate` stamps. A pour failure never leaves a
      // gated STEP to find, and its cursor is not reliably empty either: the
      // pour dies BEFORE `applyGraph` (zero step beads — tg-ehht) or AFTER it
      // while stamping crumbs (every step bead lands, all `pending` —
      // tg-xpgx, 5 molecules + 28 steps live). The old `cursor.isEmpty`
      // conjunct described only the first shape and refused the second,
      // leaving a session that was neither driving nor reworkable with no
      // sanctioned operator exit. This is A48's rule on the park axis: the
      // MARKER, not the cursor, is the evidence.
      final gateParked = state.beads.any(
        (bead) =>
            bead.issueType == GridIssueTypes.gate &&
            !bead.isClosed &&
            _meta(bead, 'blocks') == session.id,
      );
      // A `running` step REFUSES even under an open gate — the mid-flight
      // guard the widening must not spend. A settled park has nothing running
      // by construction (OPERATIONS §2.3: "an open-but-gated session with
      // nothing running is the one safe retire"), so a live runner beside an
      // open gate means the park has not settled and the retire would race it.
      if (states.contains(StepState.running) ||
          !(gateParked || states.contains(StepState.gated))) {
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
      // §2.3's `attempt.round.retired` row, after the re-key landed. [round]
      // is the round being MINTED, so the one retired is `round - 1` — the
      // same `old_round` `SessionScope`'s retired-round close derives from the
      // `#rN` key it later observes. Two observers, ONE record: the idem key
      // is `round-retired:<session>:<oldRound>`, so whichever lands first
      // wins and the other dedupes.
      _recorder.roundRetired(
        sessionId: session.id,
        cause: RoundRetireCause.rework,
        oldRound: round - 1,
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

  /// The row `JoinedSnapshot` would publish for [linked], resolved through the
  /// engine's own `orderLinkedSessions` over `projectSession`.
  static Bead _publishedRow(List<Bead> linked) {
    final published = orderLinkedSessions(linked.map(projectSession)).first;
    return linked.firstWhere((bead) => bead.id == published.sessionId);
  }

  /// The BOARD — every resident work store's open beads, one projection.
  ///
  /// READ-ONLY: an operator one-shot serviced inside the resident loop
  /// (ADR-0014 D-C4), touching no writer and opening no store. A store that
  /// cannot be projected contributes its own row; it is never dropped.
  Future<GridCommandResult> _board(BoardFilter filter) async {
    // The bindings map is keyed by BOTH name and prefix (work_assembly), so
    // one store appears twice — dedupe by identity or every bead emits twice.
    final bindings = <WorkCommandStore>[];
    for (final binding in _workStoresByIdentity.values) {
      if (!bindings.any((seen) => identical(seen, binding))) {
        bindings.add(binding);
      }
    }
    bindings.sort((a, b) => a.substation.compareTo(b.substation));
    final rows = <BoardRow>[];
    for (final binding in bindings) {
      if (filter.stores.isNotEmpty &&
          !filter.stores.contains(binding.substation)) {
        continue;
      }
      try {
        await binding.refresh();
      } on Object catch (error) {
        rows.add(
          BoardRow.storeUnreadable(
            store: binding.substation,
            root: binding.root,
            reason: 'refresh failed: $error',
          ),
        );
        continue;
      }
      final snapshot = binding.source.current;
      if (snapshot == null) {
        rows.add(
          BoardRow.storeUnreadable(
            store: binding.substation,
            root: binding.root,
            reason: 'the resident store has no current snapshot',
          ),
        );
        continue;
      }
      rows.addAll(
        projectBoard(
          store: binding.substation,
          root: binding.root,
          snapshot: snapshot,
          filter: filter,
        ),
      );
    }
    return GridCommandResult.completed(
      message: '${rows.length} board row(s).',
      value: {
        'operation': 'grid/bead/board',
        'rows': [for (final row in rows) row.toJson()],
      },
    );
  }

  /// One bead's current-round identity — the bead-side half of `bead round`.
  ///
  /// READ-ONLY, same posture as [_board]. A bead with no round is a COMPLETED
  /// result carrying a `no_round` context, never a refusal.
  Future<GridCommandResult> _beadRound(String beadId) async {
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
    await Future.wait(<Future<void>>[_refreshState(), workStore.refresh()]);
    final state = _stateSource.current;
    final work = workStore.source.current;
    if (state == null || work == null) {
      return _refused(
        'snapshot_unavailable',
        'A resident store has no current snapshot.',
      );
    }
    final bead = work.bead(beadId);
    if (bead == null) {
      return _refused(
        'work_bead_missing',
        'Work bead "$beadId" is absent from its resident store.',
      );
    }
    final context = projectRoundContext(
      workBead: bead,
      stateBeads: state.beads,
    );
    return GridCommandResult.completed(
      message: switch (context) {
        BeadRoundFound(:final round) => 'Round $round for "$beadId".',
        BeadRoundAbsent(:final reason) => reason,
      },
      value: {'operation': 'grid/bead/round', 'context': context.toJson()},
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

  /// The park check's EFFECTIVE cursor (cut-wiring C4, consumer 3).
  ///
  /// The bridge's own engagement rule, re-derived here because this verb has
  /// no [SessionProjection] to carry a `trajCursor`: `primary`, snapshot
  /// health `live`, and a boot that has not disengaged. Anything else returns
  /// [beadCursor] unchanged — which is today's read, so the rollback claim
  /// holds at this site the same way it does at the other six.
  ///
  /// The merge itself is the ENGINE's, unchanged and unduplicated: the
  /// identity-matched `byP2SessionId` rows, the per-node P2-miss rule, the
  /// monotone guard, and the never-creates rule all come from
  /// `mergeStepCursor`. The counters land on the boot's SHARED accounting, so
  /// a `grid rework` issued mid-round shows up in the same durable summary the
  /// gates read.
  CircuitCursor _effectiveParkCursor(
    String sessionId,
    CircuitCursor beadCursor,
  ) {
    final read = _stepSnapshot;
    if (read == null || _dualReadMode != DualReadMode.primary) {
      return beadCursor;
    }
    if (_dualReadAccounting?.overlayDisengaged ?? false) return beadCursor;
    final snapshot = read();
    if (snapshot.health != TrajectorySnapshotHealth.live) return beadCursor;
    final rows = snapshot.byP2SessionId(sessionId).toList(growable: false);
    if (rows.isEmpty) {
      // No same-session rows: the P2-miss rule applied wholesale — the legacy
      // bead for every node, never a sibling session's rows (the OVERLAY
      // IDENTITY RULE, step axis).
      _dualReadAccounting?.p2Miss += beadCursor.length;
      return beadCursor;
    }
    final merge = mergeStepCursor(
      sessionId: sessionId,
      legacy: beadCursor,
      traj: trajCursorOf(rows),
      collapsed: collapseStepCursors(rows),
    );
    final accounting = _dualReadAccounting;
    if (accounting != null) {
      for (final node in merge.nodes) {
        switch (node.classification) {
          case StepNodeClass.p2Miss:
            accounting.p2Miss += 1;
          case StepNodeClass.p2Orphan:
            accounting.p2Orphan += 1;
          case StepNodeClass.stepLag:
            accounting.openStepLag += 1;
          case StepNodeClass.divergence:
            if (accounting.noteEvent(
              'stepDivergence:$sessionId:${node.stepPath}',
            )) {
              accounting.stepDivergences += 1;
            }
          case StepNodeClass.match:
            break;
        }
      }
    }
    return merge.cursor;
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
