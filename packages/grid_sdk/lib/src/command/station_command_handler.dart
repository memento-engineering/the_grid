import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'bead_board.dart';
import 'bead_round.dart';
import 'command_operation.dart';
import 'work_bead_keys.dart';
import '../roster/roster_outcome.dart';
import '../roster/substation_roster.dart';
import '../work/work_assembly.dart' show SubstationWorkSpec;

/// Sets a resident authority's ceiling and returns its resolved snapshot.
typedef StationAdmissionCeilingSetter =
    StationAdmissionStatus? Function(int maxAgents);

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
    ListBeadWorktrees? listBeadWorktrees,
    ReapWorktree? reapWorktree,
    Map<String, RootCheckout> workRootsByIdentity = const {},
    StationTrajectoryRecorder? recorder,
    TrajectoryStepSnapshot Function()? stepSnapshot,
    int Function(String sessionId)? headEpochForSession,
    StationAdmissionCeilingSetter? setAdmissionCeiling,
    StationAdmissionAuthority? admission,
    DualReadMode dualReadMode = DualReadMode.off,
    DualReadAccounting? dualReadAccounting,
  }) : _stateSource = stateSource,
       _refreshState = refreshState,
       _stateWriter = stateWriter,
       _stateOwnership = stateOwnership,
       _recorder = recorder ?? StationTrajectoryRecorder.disabled(),
       _stepSnapshot = stepSnapshot,
       _headEpochForSession = headEpochForSession,
       _setAdmissionCeiling = setAdmissionCeiling,
       _admission = admission,
       _dualReadMode = dualReadMode,
       _dualReadAccounting = dualReadAccounting,
       _listBeadWorktrees = listBeadWorktrees,
       _reapWorktree = reapWorktree,
       _workStoresByIdentity = Map<String, WorkCommandStore>.of(
         workStoresByIdentity,
       ),
       _workRootsByIdentity = Map<String, RootCheckout>.of(workRootsByIdentity);

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
  final int Function(String sessionId)? _headEpochForSession;
  final StationAdmissionCeilingSetter? _setAdmissionCeiling;

  /// The resident's in-process admission owner, for `grid session void`
  /// (tg-5snt): its in-memory runtime census (a step the resident has started
  /// whose `running` state is not yet durable) and the sanction that lets a
  /// MOUNTED session's bead drop its stale scope and re-compete. Null off the
  /// resident (a test or offline door): the void then consults the durable
  /// cursor alone and the bead re-mounts on the next fresh admission pass.
  final StationAdmissionAuthority? _admission;
  final DualReadMode _dualReadMode;

  /// The boot's SHARED accounting — the same object the bridge's passes use,
  /// so the disengage latch is one fact and the p2Miss/stepLag this site sees
  /// land in the same durable round summary.
  final DualReadAccounting? _dualReadAccounting;

  final Map<String, WorkCommandStore> _workStoresByIdentity;
  final ListBeadWorktrees? _listBeadWorktrees;
  final ReapWorktree? _reapWorktree;
  final Map<String, RootCheckout> _workRootsByIdentity;
  SubstationRoster? _roster;
  Future<void> _tail = Future<void>.value();

  /// Capabilities already shipped from an observed close, keyed
  /// `<substation>/<bead>/<capability>` — the rising edge that keeps ONE
  /// `bd ship` per observed owing bead however often the station flushes
  /// before the store's snapshot re-reads the new `provides:` label.
  final Set<String> _shippedCapabilities = {};

  /// Binds the runtime-attached roster exactly once.
  void bindRoster(SubstationRoster roster) {
    if (_roster != null) {
      throw StateError(
        'StationCommandHandler.bindRoster: a roster is already bound.',
      );
    }
    _roster = roster;
  }

  /// Registers [spec]'s work-store rails under both identity axes.
  void registerWorkStore(
    SubstationWorkSpec spec,
    WorkCommandStore store, {
    RootCheckout? workRoot,
  }) {
    if (_workStoresByIdentity.containsKey(spec.name) ||
        _workStoresByIdentity.containsKey(spec.prefix) ||
        _workRootsByIdentity.containsKey(spec.name) ||
        _workRootsByIdentity.containsKey(spec.prefix)) {
      throw StateError(
        'StationCommandHandler.registerWorkStore: "${spec.name}" collides '
        'with an existing work-store identity.',
      );
    }
    _workStoresByIdentity[spec.name] = store;
    _workStoresByIdentity[spec.prefix] = store;
    if (workRoot != null) {
      _workRootsByIdentity[spec.name] = workRoot;
      _workRootsByIdentity[spec.prefix] = workRoot;
    }
  }

  /// Unregisters [spec]'s work-store rails under both identity axes.
  void unregisterWorkStore(SubstationWorkSpec spec) {
    _workStoresByIdentity
      ..remove(spec.name)
      ..remove(spec.prefix);
    _workRootsByIdentity
      ..remove(spec.name)
      ..remove(spec.prefix);
  }

  /// Finalises draining roster seats that have become idle.
  Future<void> settleRosterDrains() {
    final completer = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        await _settleRosterDrains();
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _settleRosterDrains() async {
    final roster = _roster;
    if (roster == null) return;
    // The requery is LAZY: it rides the resolver the roster invokes only once
    // it has established that a seat is draining. The station settles drains
    // after EVERY tree flush on this handler's serialized tail, so an eager
    // refresh here would queue a state-store round trip in front of every
    // operator command.
    await roster.settleDrains(() async {
      await _refreshState();
      final snapshot = _stateSource.current;
      if (snapshot == null) return null;
      return (SubstationWorkSpec spec) => liveWorkBeadsFor(spec, snapshot);
    });
  }

  /// Publishes every capability an observed CLOSED work bead still owes — the
  /// second half of tg-xh5d's publish-on-close ruling
  /// (`the_grid#capability-edges-are-bd-native-and-link-is-sugar`).
  ///
  /// [StationBeadWriter.close] publishes on the spot for every core bead the
  /// station itself closes. This is the other producer: a bead closed by an
  /// operator is published by the same writer path the next time the station
  /// observes the close. The station observes through each work store's
  /// resident snapshot, so this pass handles both explicit `export:` labels
  /// and id-shaped external rows whose exact target is CLOSED but lacks its
  /// `provides:<id>` fact. Both delegate to
  /// [StationBeadWriter.shipExports] — one path, not a second spelling of the
  /// publication contract.
  ///
  /// Rising-edge, like the frontier's refusal log: a capability is shipped ONCE
  /// per observation of the bead owing it, and its key is dropped the moment
  /// the snapshot stops reporting it owed — so a capability that is later
  /// un-shipped is shipped again rather than remembered forever.
  ///
  /// Runs on the same serialized tail as every operator command, after each
  /// tree flush.
  Future<void> settleCapabilityExports() {
    final completer = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        await _settleCapabilityExports();
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _settleCapabilityExports() async {
    final observed = <String>{};
    // The map is keyed on BOTH identity axes, so the same binding appears
    // twice. Canonicalise it by substation before taking the settled view used
    // by both publication sweeps.
    final storesBySubstation = <String, WorkCommandStore>{};
    for (final store in _workStoresByIdentity.values) {
      storesBySubstation[store.substation] = store;
    }
    final substations = storesBySubstation.keys.toList()..sort();
    final snapshotsByProject = <String, GraphSnapshot>{};
    for (final substation in substations) {
      final snapshot = storesBySubstation[substation]!.source.current;
      if (snapshot != null) snapshotsByProject[substation] = snapshot;
    }

    for (final substation in substations) {
      final store = storesBySubstation[substation]!;
      final snapshot = snapshotsByProject[substation];
      if (snapshot == null) continue;
      for (final owed in unshippedExports(snapshot.beadsById.values).entries) {
        final keys = [
          for (final capability in owed.value)
            '${store.substation}/${owed.key}/$capability',
        ];
        observed.addAll(keys);
        if (keys.every(_shippedCapabilities.contains)) continue;
        await store.writer.shipExports(owed.key);
        _shippedCapabilities.addAll(keys);
      }
    }

    // Consumer-driven bare-close healing. The admission classifier owns the
    // exact-id/CLOSED/core scope; this rail owns only the existing serialized
    // publication and rising-edge suppression.
    for (final target in healableExternalDepTargets(snapshotsByProject)) {
      final store = storesBySubstation[target.project]!;
      final key = '${target.project}/${target.capability}/${target.capability}';
      observed.add(key);
      if (_shippedCapabilities.contains(key)) continue;
      await store.writer.shipExports(target.capability, [target.capability]);
      _shippedCapabilities.add(key);
    }
    _shippedCapabilities.retainAll(observed);
  }

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
    GridSessionLs() => _listHeldSessions(),
    GridSessionCollect(
      :final sessionIds,
      :final act,
      :final bulk,
      :final overrideUnsafe,
    ) =>
      _collectHeldSessions(
        sessionIds: sessionIds,
        act: act,
        bulk: bulk,
        overrideUnsafe: overrideUnsafe,
      ),
    GridSetBeadText(
      :final beadId,
      :final field,
      :final content,
      :final append,
      :final allowNotesReplacement,
    ) =>
      _setBeadText(
        beadId: beadId,
        field: field,
        content: content,
        append: append,
        allowNotesReplacement: allowNotesReplacement,
      ),
    GridMountAttemptRearm(:final beadId, :final actor, :final reason) =>
      _rearmMountAttempt(beadId: beadId, actor: actor, reason: reason),
    GridPauseSession(:final beadId) => _setPauseState(
      beadId: beadId,
      pause: true,
    ),
    GridResumeSession(:final beadId) => _setPauseState(
      beadId: beadId,
      pause: false,
    ),
    GridSessionVoid(:final sessionId, :final reason) => _voidSession(
      sessionId: sessionId,
      reason: reason,
    ),
    GridSetAdmissionCeiling(:final maxAgents) => _setAdmissionCeilingCommand(
      maxAgents,
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
    GridAttachSubstation(:final name, :final root, :final prefix) =>
      _attachSubstation(name: name, root: root, prefix: prefix),
    GridDetachSubstation(:final name, :final force) => _detachSubstation(
      name: name,
      force: force,
    ),
  };

  Future<GridCommandResult> _setAdmissionCeilingCommand(int maxAgents) async {
    if (maxAgents <= 0) {
      return _refused(
        'invalid_max_agents',
        'The admission ceiling must be greater than zero.',
      );
    }
    final status = _setAdmissionCeiling?.call(maxAgents);
    if (status == null) {
      return _refused(
        'admission_unavailable',
        'This station cannot change its admission ceiling.',
      );
    }
    return GridCommandResult.completed(
      message: 'Admission ceiling set to ${status.maxAgents}.',
      value: {
        'maxAgents': status.maxAgents,
        'maxAgentsSource': status.maxAgentsSource.name,
      },
    );
  }

  Future<GridCommandResult> _listHeldSessions() async {
    final listBeadWorktrees = _listBeadWorktrees;
    if (listBeadWorktrees == null) {
      return _refused(
        'source_control_unavailable',
        'This station composes no source-control listing seam.',
      );
    }
    try {
      await _refreshState();
    } on Object catch (error) {
      return _refused(
        'snapshot_unavailable',
        'The resident state snapshot could not be refreshed: $error',
      );
    }
    final state = _stateSource.current;
    if (state == null) {
      return _refused(
        'snapshot_unavailable',
        'The resident state store has no current snapshot.',
      );
    }
    final sessions =
        state.beads
            .where(
              (bead) =>
                  bead.issueType == GridIssueTypes.session &&
                  bead.isClosed &&
                  _sessionDispositionOf(bead) ==
                      GateSweepSessionDisposition.held,
            )
            .toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
    final projections =
        <({Bead session, String workBeadId, RootCheckout root})>[];
    for (final session in sessions) {
      final workBeadId = _normalizedWorkBeadIdOf(session);
      final root = _workRootFor(workBeadId);
      if (workBeadId.isEmpty || root == null) {
        return _refused(
          'work_store_not_owned',
          'Held session "${session.id}" does not map to an owned mounted '
              'work store.',
        );
      }
      projections.add((session: session, workBeadId: workBeadId, root: root));
    }
    final worktreesByRoot = <RootCheckout, List<BeadWorktree>>{};
    for (final root in projections.map((row) => row.root).toSet()) {
      final List<BeadWorktree>? worktrees;
      try {
        worktrees = await listBeadWorktrees(root);
      } on Object catch (error) {
        return _refused(
          'worktree_probe_failed',
          'Could not list worktrees under "${root.path}": $error',
        );
      }
      if (worktrees == null) {
        return _refused(
          'worktree_probe_failed',
          'Could not list worktrees under "${root.path}".',
        );
      }
      worktreesByRoot[root] = worktrees;
    }
    final rows = <Map<String, Object?>>[];
    for (final projection in projections) {
      final matches = worktreesByRoot[projection.root]!
          .where((worktree) => worktree.beadId == projection.workBeadId)
          .toList(growable: false);
      if (matches.length > 1) {
        return _refused(
          'worktree_probe_failed',
          'Held session "${projection.session.id}" maps to '
              '${matches.length} worktrees; refusing an ambiguous listing.',
        );
      }
      if (matches.isEmpty) continue;
      rows.add(
        _heldSessionRow(
          session: projection.session,
          workBeadId: projection.workBeadId,
          worktree: matches.single,
        ),
      );
    }
    return GridCommandResult.completed(
      message: '${rows.length} held session(s) with preserved worktrees.',
      value: {'operation': 'grid/session/ls', 'sessions': rows},
    );
  }

  Future<GridCommandResult> _collectHeldSessions({
    required List<String> sessionIds,
    required bool act,
    required bool bulk,
    required bool overrideUnsafe,
  }) async {
    if (sessionIds.isEmpty || sessionIds.any((id) => id.trim().isEmpty)) {
      return _refused(
        'session_not_found',
        'At least one nonblank session id is required.',
      );
    }
    if (sessionIds.toSet().length != sessionIds.length) {
      return _refused('duplicate_session', 'Every session id must be unique.');
    }
    if (sessionIds.length > 1 && !bulk) {
      return _refused(
        'bulk_required',
        'Collecting more than one session requires explicit bulk '
            'authorization.',
      );
    }
    final listBeadWorktrees = _listBeadWorktrees;
    final reapWorktree = _reapWorktree;
    if (listBeadWorktrees == null || reapWorktree == null) {
      return _refused(
        'source_control_unavailable',
        'This station composes no source-control collection seams.',
      );
    }
    try {
      await _refreshState();
    } on Object catch (error) {
      return _refused(
        'snapshot_unavailable',
        'The resident state snapshot could not be refreshed: $error',
      );
    }
    final state = _stateSource.current;
    if (state == null) {
      return _refused(
        'snapshot_unavailable',
        'The resident state store has no current snapshot.',
      );
    }
    final sortedIds = List<String>.of(sessionIds)..sort();
    final candidates =
        <({Bead session, String workBeadId, RootCheckout root})>[];
    final claimedWorkBeads = <String>{};
    for (final sessionId in sortedIds) {
      final session = state.bead(sessionId);
      if (session == null) {
        return _refused(
          'session_not_found',
          'Session "$sessionId" was not found.',
        );
      }
      if (session.issueType != GridIssueTypes.session) {
        return _refused('not_a_session', '"$sessionId" is not a session.');
      }
      if (!session.isClosed) {
        return _refused(
          'session_not_closed',
          'Session "$sessionId" is not closed.',
        );
      }
      if (_sessionDispositionOf(session) != GateSweepSessionDisposition.held) {
        return _refused(
          'session_not_held',
          'Session "$sessionId" does not derive to held.',
        );
      }
      if (!_stateOwnership.owns(session)) {
        return _refused(
          'ownership_refused',
          'Session "$sessionId" is outside this station ownership set.',
        );
      }
      final workBeadId = _normalizedWorkBeadIdOf(session);
      final root = _workRootFor(workBeadId);
      if (workBeadId.isEmpty || root == null) {
        return _refused(
          'work_store_not_owned',
          'Session "$sessionId" does not map to an owned mounted work '
              'store.',
        );
      }
      if (!claimedWorkBeads.add(workBeadId)) {
        return _refused(
          'worktree_in_use',
          'Worktree "$workBeadId" is targeted by more than one requested '
              'session.',
        );
      }
      final liveSuccessor = state.beads.any(
        (candidate) =>
            candidate.id != sessionId &&
            candidate.issueType == GridIssueTypes.session &&
            !candidate.isClosed &&
            _normalizedWorkBeadIdOf(candidate) == workBeadId,
      );
      if (liveSuccessor) {
        return _refused(
          'worktree_in_use',
          'Worktree "$workBeadId" is used by another open session.',
        );
      }
      candidates.add((session: session, workBeadId: workBeadId, root: root));
    }

    final worktreesByRoot = <RootCheckout, List<BeadWorktree>>{};
    for (final root in candidates.map((candidate) => candidate.root).toSet()) {
      final List<BeadWorktree>? worktrees;
      try {
        worktrees = await listBeadWorktrees(root);
      } on Object catch (error) {
        return _refused(
          'worktree_probe_failed',
          'Could not list worktrees under "${root.path}": $error',
        );
      }
      if (worktrees == null) {
        return _refused(
          'worktree_probe_failed',
          'Could not list worktrees under "${root.path}".',
        );
      }
      worktreesByRoot[root] = worktrees;
    }
    final targets =
        <
          ({
            Bead session,
            String workBeadId,
            RootCheckout root,
            BeadWorktree worktree,
          })
        >[];
    for (final candidate in candidates) {
      final matches = worktreesByRoot[candidate.root]!
          .where((worktree) => worktree.beadId == candidate.workBeadId)
          .toList(growable: false);
      if (matches.isEmpty) {
        return _refused(
          'worktree_not_found',
          'Session "${candidate.session.id}" has no preserved worktree.',
        );
      }
      if (matches.length != 1) {
        return _refused(
          'worktree_probe_failed',
          'Session "${candidate.session.id}" maps to ${matches.length} '
              'worktrees; refusing an ambiguous target.',
        );
      }
      targets.add((
        session: candidate.session,
        workBeadId: candidate.workBeadId,
        root: candidate.root,
        worktree: matches.single,
      ));
    }

    for (final target in targets) {
      final ReapOutcome outcome;
      try {
        outcome = await reapWorktree(
          root: target.root,
          worktree: target.worktree,
          dryRun: true,
          overrideUnsafe: overrideUnsafe,
        );
      } on Object catch (error) {
        return _refused(
          'worktree_reap_refused',
          'Session "${target.session.id}" preflight failed: $error',
        );
      }
      if (outcome.refused) {
        return _refused(
          'worktree_reap_refused',
          'Session "${target.session.id}" preflight refused: '
              '${outcome.refusedReason}',
        );
      }
    }

    if (!act) {
      return GridCommandResult.completed(
        message: '${targets.length} held session(s) would be collected.',
        value: {
          'operation': 'grid/session/collect',
          'sessions': [
            for (final target in targets)
              {
                ..._heldSessionRow(
                  session: target.session,
                  workBeadId: target.workBeadId,
                  worktree: target.worktree,
                ),
                'status': 'would_collect',
              },
          ],
        },
      );
    }

    final rows = <Map<String, Object?>>[];
    for (final target in targets) {
      final ReapOutcome outcome;
      try {
        outcome = await reapWorktree(
          root: target.root,
          worktree: target.worktree,
          dryRun: false,
          overrideUnsafe: overrideUnsafe,
        );
      } on Object catch (error) {
        _recordWorktreeHeld(target, null);
        return _refused(
          'worktree_reap_refused',
          'Session "${target.session.id}" acted reap failed: $error',
        );
      }
      if (!outcome.removed) {
        _recordWorktreeHeld(target, outcome);
        return _refused(
          'worktree_reap_refused',
          'Session "${target.session.id}" acted reap refused: '
              '${outcome.refusedReason ?? 'worktree was not removed'}',
        );
      }
      _recorder.worktreeReaped(
        sessionId: target.session.id,
        worktree: target.worktree.path,
        branch: target.worktree.branch,
        uncommitted: _gateEvidence(outcome.uncommitted),
        unpushed: _gateEvidence(outcome.unpushed),
        stashes: _gateEvidence(outcome.stashed),
      );
      rows.add({
        ..._heldSessionRow(
          session: target.session,
          workBeadId: target.workBeadId,
          worktree: target.worktree,
        ),
        'status': 'collected',
      });
    }
    return GridCommandResult.completed(
      message: '${rows.length} held session(s) collected.',
      value: {'operation': 'grid/session/collect', 'sessions': rows},
    );
  }

  GateSweepSessionDisposition _sessionDispositionOf(Bead session) =>
      sessionDispositionOfMetadata(session.metadata);

  String _normalizedWorkBeadIdOf(Bead session) {
    final raw = _meta(session, SessionBeadKeys.workBead) ?? '';
    return StationTrajectoryRecorder.parseLegacyWorkKey(raw).workBeadId;
  }

  RootCheckout? _workRootFor(String workBeadId) {
    final identity = BeadOwnershipPredicate.ownedPrefixOf(
      workBeadId,
      _workRootsByIdentity.keys,
    );
    return identity == null ? null : _workRootsByIdentity[identity];
  }

  Map<String, Object?> _heldSessionRow({
    required Bead session,
    required String workBeadId,
    required BeadWorktree worktree,
  }) => {
    'workBeadId': workBeadId,
    'sessionId': session.id,
    'worktree': worktree.path,
    'branch': worktree.branch,
    'heldReason': _heldReason(session),
  };

  String _heldReason(Bead session) => [
    for (final key in const [
      SessionBeadKeys.escalation,
      SessionBeadKeys.reworkDeclined,
    ])
      if (session.metadata[key] case final value?) '$key=$value',
  ].join('; ');

  void _recordWorktreeHeld(
    ({
      Bead session,
      String workBeadId,
      RootCheckout root,
      BeadWorktree worktree,
    })
    target,
    ReapOutcome? outcome,
  ) {
    _recorder.worktreeHeld(
      sessionId: target.session.id,
      worktree: target.worktree.path,
      branch: target.worktree.branch,
      uncommitted: _gateEvidence(outcome?.uncommitted),
      unpushed: _gateEvidence(outcome?.unpushed),
      stashes: _gateEvidence(outcome?.stashed),
    );
  }

  Future<GridCommandResult> _attachSubstation({
    required String name,
    required String root,
    required String? prefix,
  }) async {
    final roster = _roster;
    if (roster == null) {
      return _refused(
        'roster_unavailable',
        'This station composes no SubstationRoster; attach/detach are '
            'unavailable.',
      );
    }
    final outcome = await roster.attach(name: name, root: root, prefix: prefix);
    return switch (outcome) {
      RosterAttached(:final prefix, :final root) => GridCommandResult.completed(
        message: 'Attached substation "$name" at $root (prefix $prefix).',
        value: {
          'operation': 'grid/substation/attach',
          'name': name,
          'prefix': prefix,
          'root': root,
        },
      ),
      RosterRefused(:final code, :final message) => _refused(code, message),
      RosterDetached() || RosterDraining() => _refused(
        'roster_invariant',
        'attach "$name" returned a detach outcome.',
      ),
    };
  }

  Future<GridCommandResult> _detachSubstation({
    required String name,
    required bool force,
  }) async {
    final roster = _roster;
    if (roster == null) {
      return _refused(
        'roster_unavailable',
        'This station composes no SubstationRoster; attach/detach are '
            'unavailable.',
      );
    }
    await _refreshState();
    final snapshot = _stateSource.current;
    if (snapshot == null) {
      return _refused(
        'snapshot_unavailable',
        'The resident state store has no current snapshot.',
      );
    }
    final outcome = await roster.detach(
      name: name,
      force: force,
      inFlightOf: (spec) => liveWorkBeadsFor(spec, snapshot),
    );
    return switch (outcome) {
      RosterDetached(:final reapedWorktrees) => GridCommandResult.completed(
        message:
            'Detached substation "$name" '
            '($reapedWorktrees worktree(s) reaped).',
        value: {
          'operation': 'grid/substation/detach',
          'name': name,
          'reapedWorktrees': reapedWorktrees,
        },
      ),
      RosterDraining(:final inFlight) => GridCommandResult.completed(
        message:
            'Draining substation "$name": ${inFlight.length} in-flight '
            'bead(s); no new work will mount.',
        value: {
          'operation': 'grid/substation/detach',
          'name': name,
          'draining': true,
          'inFlight': inFlight.toList(growable: false)..sort(),
        },
      ),
      RosterRefused(:final code, :final message) => _refused(code, message),
      RosterAttached() => _refused(
        'roster_invariant',
        'detach "$name" returned an attach outcome.',
      ),
    };
  }

  Future<GridCommandResult> _setBeadText({
    required String beadId,
    required OperatorBeadTextField field,
    required String content,
    required bool append,
    required bool allowNotesReplacement,
  }) async {
    if (append && field != OperatorBeadTextField.notes) {
      return _refused('append_invalid', '--append is valid only for notes.');
    }
    if (allowNotesReplacement && field != OperatorBeadTextField.notes) {
      return _refused(
        'notes_replacement_invalid',
        '--allow-notes-replacement is valid only for notes.',
      );
    }
    if (allowNotesReplacement && append) {
      return _refused(
        'notes_replacement_invalid',
        '--allow-notes-replacement cannot be combined with --append.',
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
        allowNotesReplacement: allowNotesReplacement,
      );
    } on OwnershipRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on OwnershipGuardRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on BdGuardrailRefused catch (error) {
      return _refused('bd_guardrail_refused', error.toString());
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

  /// Resets the exhausted singleton mount-attempt counter on the state store.
  Future<GridCommandResult> _rearmMountAttempt({
    required String beadId,
    required String actor,
    required String reason,
  }) async {
    final normalizedActor = actor.trim();
    if (normalizedActor.isEmpty) {
      return _refused(
        'actor_required',
        'Mount-attempt rearm requires a nonblank actor.',
      );
    }
    if (reason.trim().isEmpty) {
      return _refused(
        'reason_required',
        'Mount-attempt rearm requires a nonblank reason.',
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

    final matches = state.beads
        .where(
          (bead) =>
              !bead.isClosed &&
              bead.issueType == GridIssueTypes.mountAttempt &&
              _meta(bead, MountAttemptKeys.workBead) == beadId,
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      return _refused(
        'mount_attempt_not_found',
        'No open mount-attempt record exists for "$beadId"; current count 0.',
      );
    }
    if (matches.length > 1) {
      final ids = matches.map((bead) => bead.id).toList(growable: false)
        ..sort();
      return _refused(
        'mount_attempt_ambiguous',
        'Multiple open mount-attempt records exist for "$beadId": '
            '${ids.join(', ')}.',
      );
    }

    final bead = matches.single;
    final record = projectMountAttempt(bead)!;
    if (!record.isExhausted) {
      return _refused(
        'mount_attempt_not_exhausted',
        'Mount-attempt record "${record.recordId}" has current count '
            '${record.count}; cap $kMaxMountAttempts has not been reached.',
      );
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final receipt =
        '--- grid mount-attempt RE-ARM ($timestamp) ---\n'
        'actor: $normalizedActor\n'
        'work bead: $beadId\n'
        'prior attempt count: ${record.count}\n'
        'reason:\n'
        '$reason';
    try {
      await _stateWriter.update(
        record.recordId,
        metadata: const {MountAttemptKeys.count: '0'},
        appendNotes: receipt,
        ifAssignee: bead.assignee,
        ifStatus: bead.status,
      );
    } on OwnershipRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on OwnershipGuardRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    }
    await _refreshState();
    return GridCommandResult.completed(
      message:
          'Rearmed mount-attempt record "${record.recordId}" for "$beadId".',
      value: {
        'operation': 'grid/mount-attempt/rearm',
        'beadId': beadId,
        'recordId': record.recordId,
        'priorCount': record.count,
        'actor': normalizedActor,
      },
    );
  }

  /// Sets the operator pause axis on the_grid's owned session bead.
  Future<GridCommandResult> _setPauseState({
    required String beadId,
    required bool pause,
  }) async {
    final verb = pause ? 'pause' : 'resume';
    await _refreshState();
    final state = _stateSource.current;
    if (state == null) {
      return _refused(
        'snapshot_unavailable',
        'The resident state store has no current snapshot.',
      );
    }
    final linked = state.beads
        .where(
          (bead) =>
              bead.issueType == GridIssueTypes.session &&
              linkedWorkBeadKeyOf(projectSession(bead)) == beadId,
        )
        .toList(growable: false);
    if (linked.isEmpty) {
      return _refused(
        'session_not_found',
        'No session is linked to "$beadId".',
      );
    }
    if (linked.length != 1) {
      return _refused(
        'session_ambiguous',
        '${linked.length} sessions are linked to "$beadId".',
      );
    }
    final session = linked.single;
    if (session.isClosed) {
      return _refused(
        'session_terminal',
        'Session "${session.id}" is CLOSED — $verb applies only to a live '
            'session (use `grid rework` to retire a round).',
      );
    }
    final current = pauseStateOf(session.metadata);
    final target = pause ? SessionPauseState.paused : SessionPauseState.resumed;
    if (current == target) {
      return GridCommandResult.completed(
        message: 'Session "${session.id}" is already ${target.name}.',
        value: {
          'operation': 'grid/session/$verb',
          'beadId': beadId,
          'sessionId': session.id,
          'pauseState': target.name,
          'changed': false,
        },
      );
    }
    if (!pause && current == SessionPauseState.none) {
      return _refused(
        'session_not_paused',
        'Session "${session.id}" was never paused; there is nothing to resume.',
      );
    }
    try {
      await _stateWriter.update(
        session.id,
        metadata: {SessionBeadKeys.pauseState: target.name},
      );
    } on OwnershipRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on OwnershipGuardRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    }
    await _refreshState();
    return GridCommandResult.completed(
      message: pause
          ? 'Paused session "${session.id}" — cursor preserved, slot freed.'
          : 'Resumed session "${session.id}" — it re-competes for a slot, then '
                'adopts its preserved cursor.',
      value: {
        'operation': 'grid/session/$verb',
        'beadId': beadId,
        'sessionId': session.id,
        'pauseState': target.name,
        'changed': true,
      },
    );
  }

  /// `grid session void` — THE OPERATOR EXIT FOR AN OPEN, UNGATED SESSION
  /// (tg-5snt).
  ///
  /// [_rework] refuses this exact shape (`session_not_parked`), and that
  /// refusal is load-bearing: rework retires a round AT A GATE, spends round
  /// budget, closes the gates that parked it, and waits on a successor. A
  /// session that never parked has none of that to account for — yet closing
  /// it by hand leaves its bare `work_bead` key behind and the bead never
  /// re-mounts (the trap this verb exists to replace). So this door performs
  /// ONLY the gate-less tail of [_rework], through the SAME writes: re-key the
  /// round through the same `update` onto the engine's own void payload
  /// ([voidRetireMetadata] — `<bead>#void-<session>` plus the reason, which by
  /// construction never matches the rework-round pattern and so never spends
  /// the cap), retire the session through the SAME close chokepoint
  /// (`closeSessionAndOpenGatesForTerminal`), then clear the work bead's
  /// specify-authored spec through the SAME work-store leg
  /// (`clearRoundAuthoredSpec`). No round-cap accounting, no gate-close
  /// logic, no successor observation: the frontier mints the next round the
  /// way it mints over any unlinked bead.
  ///
  /// THE ORDER IS THE SAFETY (tg-5snt): the re-key lands BEFORE the close —
  /// the engine's own void order — so no failure at any later point can leave
  /// a CLOSED session on its bare `work_bead` key. A failed close rolls the
  /// re-key back, but only onto a session that is still open.
  ///
  /// A GATED session is refused and pointed at `grid rework`, so the two exits
  /// stay distinct and neither becomes a synonym for the other. A step that
  /// is running is refused on TWO readings: the durable molecule cursor (the
  /// `type=step` beads of a molecule-model session), and — on the resident —
  /// the admission owner's IN-MEMORY runtime census, which names a step the
  /// resident has started before its `running` state is durable and covers a
  /// session that has no molecule step beads at all.
  ///
  /// On the resident the door also SANCTIONS the disappearance with the
  /// admission owner before its first write, so a session the resident has
  /// already mounted (re-adopted, never stepped) has its stale scope dropped
  /// and its bead re-offered on the next admission pass, rather than parked
  /// `rework_declined` by the scope's malformed-disappearance guard.
  Future<GridCommandResult> _voidSession({
    required String sessionId,
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      return _refused(
        'reason_required',
        '--reason is required: a void must say why the round is abandoned.',
      );
    }
    await _refreshState();
    final state = _stateSource.current;
    if (state == null) {
      return _refused(
        'snapshot_unavailable',
        'The resident state store has no current snapshot.',
      );
    }
    final session = state.bead(sessionId);
    if (session == null) {
      return _refused(
        'session_not_found',
        'Session "$sessionId" was not found in the resident state store.',
      );
    }
    if (session.issueType != GridIssueTypes.session) {
      return _refused('not_a_session', '"$sessionId" is not a session.');
    }
    if (session.isClosed) {
      return _refused(
        'session_terminal',
        'Session "$sessionId" is already CLOSED. A closed dead key is retired '
            'by the engine on its next admission pass; a closed gated round is '
            'retired by `grid rework`.',
      );
    }
    final rawKey = _meta(session, SessionBeadKeys.workBead);
    if (rawKey == null) {
      return _refused(
        'session_unlinked',
        'Session "$sessionId" names no work bead; there is no round to re-key.',
      );
    }
    final workBeadId = StationTrajectoryRecorder.parseLegacyWorkKey(
      rawKey,
    ).workBeadId;
    final workStoreIdentity = BeadOwnershipPredicate.ownedPrefixOf(
      workBeadId,
      _workStoresByIdentity.keys,
    );
    final workStore = workStoreIdentity == null
        ? null
        : _workStoresByIdentity[workStoreIdentity];

    // THE GATE REFUSAL. The park marker is the gate bead whose `blocks` names
    // the session (the same evidence [_rework]'s park predicate keys on), and
    // a `gated` step is the cursor-side spelling of the same park. Either one
    // means rework owns the exit — say which gate, and say so.
    final openBlockingGates =
        state.beads
            .where(
              (bead) =>
                  bead.issueType == GridIssueTypes.gate &&
                  !bead.isClosed &&
                  _meta(bead, 'blocks') == sessionId,
            )
            .toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
    if (openBlockingGates.isNotEmpty) {
      final gates = openBlockingGates
          .map(
            (gate) => '${gate.id} (${_meta(gate, 'node') ?? 'unknown node'})',
          )
          .join(', ');
      return _refused(
        'session_gated',
        'Session "$sessionId" is parked at gate $gates; `grid session void` '
            'voids only an ungated session — use `grid rework $workBeadId` to '
            'retire a gated round.',
      );
    }
    final beadCursor =
        _meta(session, SessionBeadKeys.model) == kSessionModelMolecule
        ? projectMoleculeCursor(
            state.beads.where(
              (bead) =>
                  bead.issueType == GridIssueTypes.step &&
                  _meta(bead, MoleculeStepKeys.session) == sessionId,
            ),
            dependencies: state.dependencies,
          ).cursor
        : const <String, NodeCursor>{};
    final cursor = _effectiveParkCursor(sessionId, beadCursor);
    final gatedNodes = [
      for (final entry in cursor.entries)
        if (entry.value.state == StepState.gated) entry.key,
    ]..sort();
    if (gatedNodes.isNotEmpty) {
      return _refused(
        'session_gated',
        'Session "$sessionId" is gated at ${gatedNodes.join(', ')}; '
            '`grid session void` voids only an ungated session — use '
            '`grid rework $workBeadId` to retire a gated round.',
      );
    }
    final runningNodes = [
      for (final entry in cursor.entries)
        if (entry.value.state == StepState.running) entry.key,
    ]..sort();
    if (runningNodes.isNotEmpty) {
      return _refused(
        'session_running',
        'Session "$sessionId" has a running step '
            '(${runningNodes.join(', ')}); a live round is never voided from '
            'under itself — pause it or wait for it to park.',
      );
    }

    // THE IN-MEMORY GUARD (tg-5snt). The cursor above is DURABLE: a step the
    // resident has already STARTED — its agent process spawning or running —
    // reaches it only once the host's `running` write lands, and a session
    // with no molecule step beads has no durable cursor at all. The resident's
    // process transport holds the in-memory truth; a void is refused while it
    // names any runtime under this session, so a voided session never keeps a
    // live agent process under it.
    final admission = _admission;
    final liveRuntimes =
        admission?.liveRuntimesOf(sessionId) ?? const <String>[];
    if (liveRuntimes.isNotEmpty) {
      return _refused(
        'session_step_live',
        'Session "$sessionId" has a step the resident has STARTED in memory '
            '(${liveRuntimes.join(', ')}), whether or not its durable cursor '
            'shows it yet; a live agent process is never voided from under '
            'itself — pause it or wait for the step to settle.',
      );
    }

    final retiredKey = voidKeyFor(workBeadId, sessionId);
    // THE SANCTION, before the first durable write: the resident's admission
    // owner learns this disappearance is an operator void, so a scope it has
    // already MOUNTED over this session (re-adopted, never stepped) is dropped
    // and the bead re-offered, instead of the scope reading the re-key as a
    // malformed disappearance and parking the bead `rework_declined`.
    admission?.beginOperatorVoid(workBeadId: workBeadId, sessionId: sessionId);
    var landed = false;
    String? specClearFailure;
    String? reapFailure;
    try {
      // THE RE-KEY FIRST — the same `update` [_rework] re-keys through,
      // carrying the engine's own void payload (the metadata the engine's
      // automatic void retire writes, in the engine's own order: its
      // `_voidCreatedSession` re-keys, then closes). Re-keying BEFORE the close
      // is what shuts the failure window: no later throw can leave a CLOSED
      // session on its bare `work_bead` key, which is the hand-close trap this
      // verb exists to replace. A throw here changed nothing.
      try {
        await _stateWriter.update(
          sessionId,
          metadata: voidRetireMetadata(
            workBeadId: workBeadId,
            deadSessionId: sessionId,
            reason: normalizedReason,
          ),
        );
      } on OwnershipRefused catch (error) {
        return _refused('ownership_refused', error.toString());
      } on OwnershipGuardRefused catch (error) {
        return _refused('ownership_refused', error.toString());
      } on Object catch (error) {
        return _refused(
          'void_rekey_failed',
          'Could not re-key session "$sessionId" for void; nothing changed: '
              '$error',
        );
      }
      // THE RETIRE — the same chokepoint [_rework] uses, unchanged. The sweep
      // finds no gate to close (the refusal above guarantees it), so this is
      // the session close alone, in the writer's causal order.
      try {
        await _stateWriter.closeSessionAndOpenGatesForTerminal(
          sessionId: sessionId,
          closeReason: 'voided',
          trigger: GateCloseCause.supersededRound,
        );
      } on Object catch (error) {
        final rollback = await _rollBackVoidRekey(
          sessionId: sessionId,
          rawKey: rawKey,
        );
        // Unless the restore landed, the session is off its bare key (closed
        // or open on the void key) and the bead's mount must still be dropped
        // and re-offered: the sanction stays.
        landed = rollback != _VoidRollback.restored;
        final code = error is OwnershipRefused || error is OwnershipGuardRefused
            ? 'ownership_refused'
            : 'void_close_failed';
        return _refused(code, switch (rollback) {
          _VoidRollback.restored =>
            'Could not close session "$sessionId" for void: $error. The '
                're-key was rolled back — the session is open on "$rawKey" '
                'exactly as before.',
          _VoidRollback.closed =>
            'Session "$sessionId" was closed on its void key "$retiredKey" '
                'but the close did not complete cleanly: $error. No bare '
                '`work_bead` key remains; "$workBeadId" re-mounts from the '
                'frontier.',
          _VoidRollback.failed =>
            'Could not close session "$sessionId" for void ($error), and '
                'its re-key could not be rolled back: it is OPEN on '
                '"$retiredKey", unlinked from "$workBeadId", so the bead '
                're-mounts from the frontier. The row is no longer the '
                'bead\'s round; close it by hand.',
        });
      }
      landed = true;
      // THE WORK-STORE LEG — the SAME `clearRoundAuthoredSpec` [_rework] runs,
      // AFTER the retire, as rework runs it. A voided round that reached
      // specify would otherwise carry its machine-authored AC/design into the
      // fresh round, which is exactly what rework's clear prevents; the two
      // retire paths must not drift on it. The writer clears only a
      // `spec.author == specify` stamp and preserves operator prose. A work
      // bead no resident work store owns is skipped: `writeSpecifyAuthoredSpec`
      // refuses foreign prefixes, so no specify stamp can exist there. It runs
      // AFTER the re-key and the close, so a throw here leaves the session
      // closed on its VOID key — never on a bare key — and is reported loud.
      if (workStore != null) {
        try {
          await workStore.writer.clearRoundAuthoredSpec(workBeadId);
        } on Object catch (error) {
          specClearFailure = '$error';
        }
      }
      // §2.3's `attempt.round.retired` row, cause `void`: the round this
      // session held is derived from its own key, exactly as the engine's
      // void retire derives it — a bare key is a round no counter names.
      _recorder.roundRetired(
        sessionId: sessionId,
        cause: RoundRetireCause.voided,
        oldRound: StationTrajectoryRecorder.parseLegacyWorkKey(rawKey).round,
      );
      // Collect the retired round's molecule, as rework does — a never-driven
      // round can still have poured every step bead (all `pending`), and
      // leaving them open is the orphan bloat tg-ehht measured. NON-FATAL:
      // the retire and the re-key already landed.
      try {
        await _stateWriter.reapMolecule(sessionId: sessionId);
      } on Object catch (error) {
        reapFailure = '$error';
      }
    } finally {
      admission?.endOperatorVoid(
        workBeadId: workBeadId,
        sessionId: sessionId,
        landed: landed,
      );
    }
    await _refreshState();
    final warnings = [
      if (specClearFailure != null)
        'its specify-authored spec clear FAILED (the fresh round may read the '
            'retired round\'s AC/design; clear them): $specClearFailure',
      if (reapFailure != null)
        'its molecule reap FAILED (open step beads remain; sweep them): '
            '$reapFailure',
    ];
    return GridCommandResult.completed(
      message:
          'Voided session "$sessionId"; "$workBeadId" returns to the '
          'frontier as "$retiredKey"'
          '${warnings.isEmpty ? '.' : ' — but ${warnings.join('; and ')}'}',
      value: {
        'operation': 'grid/session/void',
        'sessionId': sessionId,
        'workBeadId': workBeadId,
        'retiredKey': retiredKey,
        'closedSession': {
          'sessionId': sessionId,
          'reason': 'voided',
          'disposition': 'voided',
        },
        if (specClearFailure != null) 'specClearFailure': specClearFailure,
        if (reapFailure != null) 'reapFailure': reapFailure,
      },
    );
  }

  /// Undoes a void's re-key after its close failed, restoring [rawKey] ONLY
  /// on a session that is still OPEN (tg-5snt). Restoring the bare key onto a
  /// session the failed close did in fact close would manufacture the exact
  /// hand-close trap the re-key-first order exists to prevent, so a session
  /// the refreshed snapshot reads closed is left on its void key, and the
  /// restore itself is guarded `--if-status open` so a close that lands
  /// between the read and the write refuses it.
  Future<_VoidRollback> _rollBackVoidRekey({
    required String sessionId,
    required String rawKey,
  }) async {
    try {
      await _refreshState();
      final session = _stateSource.current?.bead(sessionId);
      if (session == null) return _VoidRollback.failed;
      if (session.isClosed) return _VoidRollback.closed;
      await _stateWriter.update(
        sessionId,
        metadata: {SessionBeadKeys.workBead: rawKey},
        ifStatus: BeadStatus.open,
      );
      await _refreshState();
      return _VoidRollback.restored;
    } on Object {
      return _VoidRollback.failed;
    }
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
        .where((bead) => linkedWorkBeadKeyOf(projectSession(bead)) == beadId)
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

    final openBlockingGates = state.beads
        .where(
          (bead) =>
              bead.issueType == GridIssueTypes.gate &&
              !bead.isClosed &&
              _meta(bead, 'blocks') == session.id,
        )
        .toList(growable: false);
    final readinessHeld = openBlockingGates.any(
      (gate) => _meta(gate, 'node') == '$beadId/spec_review/readiness-route',
    );
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
      final gateParked = openBlockingGates.isNotEmpty;
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

    final List<GateAutoCloseReceipt> closedGates;
    try {
      closedGates = [
        ...await _stateWriter.closeSessionAndOpenGatesForTerminal(
          sessionId: session.id,
          closeReason: 'reworked',
          trigger: GateCloseCause.supersededRound,
        ),
      ]..sort((left, right) => left.gateId.compareTo(right.gateId));
    } on OwnershipRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on OwnershipGuardRefused catch (error) {
      return _refused('ownership_refused', error.toString());
    } on Object catch (error) {
      return _refused(
        'rework_close_failed',
        'Could not close session "${session.id}" for rework: $error',
      );
    }
    String? reapFailure;
    try {
      await workStore.writer.clearRoundAuthoredSpec(beadId);
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

    StreamSubscription<GraphSnapshot>? stateSubscription;
    Completer<void>? successorObserved;
    GraphSnapshot? latestState;
    try {
      if (readinessHeld) {
        successorObserved = Completer<void>();
        // The snapshot rail and its current value are the restored, persisted
        // session state-of-record (ADR-0013 Rule 5), not a side channel used
        // to reconstruct state missing from a value. Subscribe BEFORE reading
        // `current`: the rail is non-replaying and may publish synchronously
        // during either refresh.
        stateSubscription = _stateSource.snapshots.listen((snapshot) {
          latestState = snapshot;
          if (_openReworkSuccessors(
                    snapshot,
                    beadId: beadId,
                    retiredSessionId: session.id,
                  ).length ==
                  1 &&
              !successorObserved!.isCompleted) {
            successorObserved.complete();
          }
        }, onError: (Object _, StackTrace __) {});
        latestState = _stateSource.current;
      }

      // A resident-internal caller can issue this command inside the current
      // projection/flush turn. Publish both durable mutation rails now: the
      // state re-key lets the join retire beadId#rN, while the work refresh
      // supplies the post-decision ready snapshot required to mint its
      // successor.
      await Future.wait(<Future<void>>[_refreshState(), workStore.refresh()]);
      latestState = _stateSource.current ?? latestState;

      final refreshedWork = workStore.source.current;
      final refreshedWorkBead = refreshedWork?.bead(beadId);
      final approvalRev = refreshedWorkBead == null
          ? null
          : beadMetadataText(refreshedWorkBead, WorkBeadKeys.approvedRev);
      if (readinessHeld && approvalRev == null) {
        return _reworkSuccessorUnobserved(
          predecessorId: session.id,
          retiredKey: reworkKeyFor(beadId, round),
          detail: 'the refreshed filing has no current approval revision',
        );
      }

      List<Bead> successors() => _openReworkSuccessors(
        latestState,
        beadId: beadId,
        retiredSessionId: session.id,
      );

      var observedSuccessors = successors();
      if (readinessHeld && observedSuccessors.length != 1) {
        // A readiness-route hold is the measured race: its successor mint can
        // follow the paired refresh. Give that existing engine path its own
        // freshness window to publish; this observer never mints or retries.
        await successorObserved!.future.timeout(
          SessionScopeState.freshMintSnapshotGrace,
          onTimeout: () {},
        );
        latestState = _stateSource.current ?? latestState;
        observedSuccessors = successors();
      }
      if (readinessHeld) {
        if (observedSuccessors.length > 1) {
          return _reworkSuccessorUnobserved(
            predecessorId: session.id,
            retiredKey: reworkKeyFor(beadId, round),
            detail:
                '${observedSuccessors.length} open successor sessions were '
                'observed for "$beadId"',
          );
        }
        if (observedSuccessors.isEmpty) {
          return _reworkSuccessorUnobserved(
            predecessorId: session.id,
            retiredKey: reworkKeyFor(beadId, round),
            detail: 'no open successor session was observed for "$beadId"',
          );
        }
      }

      final successor = observedSuccessors.length == 1 && approvalRev != null
          ? observedSuccessors.single
          : null;
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
          'closedSession': {
            'sessionId': session.id,
            'reason': 'reworked',
            'disposition': 'voided',
          },
          'closedGates': [
            for (final receipt in closedGates)
              {
                'gateId': receipt.gateId,
                'sessionId': receipt.sessionId,
                'cause': receipt.cause.wireValue,
              },
          ],
          'successorSession': successor == null
              ? 'pending'
              : {
                  'sessionId': successor.id,
                  'workBeadId': beadId,
                  'approvalRev': approvalRev,
                },
          if (reapFailure != null) 'reapFailure': reapFailure,
        },
      );
    } finally {
      await stateSubscription?.cancel();
    }
  }

  static List<Bead> _openReworkSuccessors(
    GraphSnapshot? snapshot, {
    required String beadId,
    required String retiredSessionId,
  }) => snapshot == null
      ? const []
      : snapshot.beads
            .where(
              (bead) =>
                  bead.id != retiredSessionId &&
                  bead.issueType == GridIssueTypes.session &&
                  !bead.isClosed &&
                  linkedWorkBeadKeyOf(projectSession(bead)) == beadId,
            )
            .toList(growable: false);

  static GridCommandResult _reworkSuccessorUnobserved({
    required String predecessorId,
    required String retiredKey,
    required String detail,
  }) => _refused(
    'rework_successor_unobserved',
    'Session "$predecessorId" is already voided and re-keyed to '
        '"$retiredKey", but $detail. Do not run rework again; inspect '
        'resident admission and session state.',
  );

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
  ///
  /// The STATE store is not read: a cross-store blocker is a bd
  /// `external:<project>:<capability>` dependency row on the consumer's own
  /// work bead (tg-xh5d), so it arrives inside the very snapshot each store
  /// already publishes. Nothing about a blocking edge lives in the state store
  /// any more (tg-6t0h).
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
    final readable = <({WorkCommandStore binding, GraphSnapshot snapshot})>[];
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
      readable.add((binding: binding, snapshot: snapshot));
    }

    for (final entry in readable) {
      rows.addAll(
        projectBoard(
          store: entry.binding.substation,
          root: entry.binding.root,
          snapshot: entry.snapshot,
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
    if (node != null) {
      final stepBeads = session == null
          ? const <Bead>[]
          : state.beads
                .where(
                  (bead) =>
                      bead.issueType == GridIssueTypes.step &&
                      _meta(bead, MoleculeStepKeys.session) == session.id,
                )
                .toList(growable: false);
      final projected = projectMoleculeCursor(
        stepBeads,
        dependencies: state.dependencies,
      );
      if (session == null ||
          session.issueType != GridIssueTypes.session ||
          session.isClosed ||
          _meta(session, SessionBeadKeys.model) != kSessionModelMolecule ||
          !projected.beadIdByNodePath.containsKey(node)) {
        final blockedSession = sessionId ?? '<missing>';
        return _refused(
          'gate_resume_unavailable',
          'Session "$blockedSession" has no reachable live scope for gated '
              'node "$node"; use grid rework instead.',
        );
      }

      final stepResults = <String, Map<String, String>>{};
      for (final stepId in projected.beadIdByNodePath.values) {
        final step = state.bead(stepId);
        if (step != null) {
          stepResults.addAll(projectCircuitResults(step));
        }
      }
      var effectiveResults = mergeOperatorRulings(
        stepResults,
        projectCircuitResults(session),
      );
      if (rulings.isNotEmpty) {
        final candidate = Bead(
          id: '$sessionId#gate-resolve-preflight',
          metadata: {
            for (final ruling in rulings)
              ...operatorRulingMetadata(
                ruling.path,
                grade: ruling.grade,
                rationale: rationale!,
                evidenceSession: sessionId!,
              ),
          },
        );
        effectiveResults = mergeOperatorRulings(
          effectiveResults,
          projectCircuitResults(candidate),
        );
      }

      final parent = node.contains('/')
          ? node.substring(0, node.lastIndexOf('/'))
          : '';
      final invalidatingPaths =
          effectiveResults.entries
              .where(
                (entry) =>
                    _isSiblingOf(entry.key, parent) &&
                    (entry.value[ResultKeys.grade] ?? '').toUpperCase() == 'F',
              )
              .map((entry) => entry.key)
              .toList(growable: false)
            ..sort();
      if (invalidatingPaths.isNotEmpty) {
        final invalidatingPath = invalidatingPaths.first;
        return _refused(
          'feeding_grade_f',
          'Session "$sessionId" still has grade F at "$invalidatingPath"; '
              'pass --grade $invalidatingPath=A with --rationale or use '
              'grid rework.',
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
    final headEpoch = _headEpochForSession?.call(sessionId) ?? 0;
    final rows = snapshot.byP2SessionId(sessionId).toList(growable: false);
    if (rows.isEmpty) {
      // No same-session rows: the P2-miss rule applied wholesale — the legacy
      // bead for every node, never a sibling session's rows (the OVERLAY
      // IDENTITY RULE, step axis).
      _dualReadAccounting?.recordP2Misses(
        sessionId: sessionId,
        count: beadCursor.length,
        headEpoch: headEpoch,
      );
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
      accounting.recordP2Misses(
        sessionId: sessionId,
        count: merge.nodes
            .where((node) => node.classification == StepNodeClass.p2Miss)
            .length,
        headEpoch: headEpoch,
      );
      for (final node in merge.nodes) {
        switch (node.classification) {
          case StepNodeClass.p2Miss:
            break;
          case StepNodeClass.p2Orphan:
            accounting.p2Orphan += 1;
          case StepNodeClass.stepLag:
            accounting.openStepLag += 1;
          case StepNodeClass.divergence:
            // This incumbent park-cursor disagreement predates G2 and stays
            // generic: it is a real unexplained divergence, never a G2
            // taxonomy hit and never a projection fallback success.
            accounting.recordStepDivergence(
              sessionId: sessionId,
              stepPath: node.stepPath,
              field: 'state',
              legacyValue: node.legacyState ?? '<no step bead>',
              foldValue: node.foldState ?? '<no P2 row>',
              cause: DualReadDivergenceCause.unexplained,
              headEpoch: headEpoch,
            );
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

int? _gateEvidence(GateOutcome? outcome) => switch (outcome) {
  GateOutcome.clear => 0,
  GateOutcome.present => 1,
  GateOutcome.probeError || null => null,
};

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

/// How a failed void close's rollback ended (tg-5snt).
enum _VoidRollback {
  /// The session is open on its original key again.
  restored,

  /// The session is closed on its void key; there was nothing to restore.
  closed,

  /// The restore did not land: the session is open on its void key.
  failed,
}
