import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

typedef ProbeQuery = ({Set<IssueType> types, Map<String, String> metadataAll});

class _ScaleReader implements BeadProbeReader {
  _ScaleReader(this.exported);

  final List<Bead> exported;
  final List<ProbeQuery> sessionQueries = [];

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    for (final bead in exported) {
      if (bead.id == id && types.contains(bead.issueType)) return bead;
    }
    return null;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async {
    if (types.contains(GridIssueTypes.session)) {
      sessionQueries.add((
        types: Set.of(types),
        metadataAll: Map.of(metadataAll),
      ));
    }
    return exported
        .where(
          (bead) =>
              !bead.isClosed &&
              types.contains(bead.issueType) &&
              metadataAll.entries.every(
                (entry) => bead.metadata[entry.key] == entry.value,
              ) &&
              (metadataAny.isEmpty ||
                  metadataAny.entries.any(
                    (entry) => bead.metadata[entry.key] == entry.value,
                  )),
        )
        .toList();
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
}

class _Groups implements ProcessGroupController {
  @override
  int currentGroupId() => 1;
  @override
  bool processAlive(int pid) => false;
  @override
  Future<int?> resolvePgid(int pid) async => null;
  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
}

Bead _session(String id, {required bool closed}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {'rig': 'tgdog', 'work_bead': 'work-$id'},
);

Bead _step(String id, String sessionId) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {'rig': 'tgdog', 'grid.step.session': sessionId},
);

Bead _molecule(String id, String sessionId) => Bead(
  id: id,
  issueType: GridIssueTypes.molecule,
  status: BeadStatus.open,
  metadata: {'rig': 'tgdog', 'grid.circuit.session': sessionId},
);

Set<String> _closedIds(RecordingBdRunner bd) {
  final ids = <String>{};
  for (var i = 0; i < bd.calls.length; i++) {
    final call = bd.calls[i];
    if (call.isEmpty) continue;
    if (call.first == 'close' && call.length > 1) ids.add(call[1]);
    if (call.first == 'batch') {
      for (final line in (bd.stdins[i] ?? '').split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts.first == 'close') ids.add(parts[1]);
      }
    }
  }
  return ids;
}

void main() {
  test(
    'reaped-store refresh cardinality stays proportional to live graphs',
    () async {
      final beads = <Bead>[];
      final closedOrphanStepIds = <String>{};
      final closedOrphanMoleculeIds = <String>{};
      for (var i = 0; i < 461; i++) {
        final sessionId = 'tgdog-closed-$i';
        beads.add(_session(sessionId, closed: true));
        final stepCount = 10 + (i < 43 ? 1 : 0);
        for (var j = 0; j < stepCount; j++) {
          final id = 'tgdog-orphan-step-$i-$j';
          closedOrphanStepIds.add(id);
          beads.add(_step(id, sessionId));
        }
        final moleculeCount = 1 + (i < 308 ? 1 : 0);
        for (var j = 0; j < moleculeCount; j++) {
          final id = 'tgdog-orphan-molecule-$i-$j';
          closedOrphanMoleculeIds.add(id);
          beads.add(_molecule(id, sessionId));
        }
      }
      final liveChildIds = <String>{};
      for (var i = 0; i < 3; i++) {
        final sessionId = 'tgdog-live-$i';
        beads.add(_session(sessionId, closed: false));
        for (var j = 0; j < 27; j++) {
          final id = 'tgdog-live-step-$i-$j';
          liveChildIds.add(id);
          beads.add(_step(id, sessionId));
        }
        for (var j = 0; j < 5; j++) {
          final id = 'tgdog-live-molecule-$i-$j';
          liveChildIds.add(id);
          beads.add(_molecule(id, sessionId));
        }
      }
      beads.addAll([
        for (var i = 0; i < 20; i++)
          Bead(id: 'tg-work-$i', issueType: IssueType.task),
      ]);

      final reader = _ScaleReader(beads);
      final bd = RecordingBdRunner()..exportBeads = beads;
      var snapshotReads = 0;
      GraphSnapshot snapshot() {
        snapshotReads++;
        return GraphSnapshot.fromParts(
          beads: beads,
          dependencies: const [],
          readyIds: const [],
          capturedAt: DateTime(2026, 8, 13),
        );
      }

      final reconciler = RestartReconciler(
        listWorktrees: (_) async => const [],
        reapWorktree: ({required root, required worktree}) async =>
            ReapOutcome.removed(),
        workRoot: const RootCheckout(
          path: '/workspace/example',
          defaultBranch: 'main',
          substation: 'tgdog',
        ),
        groups: _Groups(),
        writer: StationBeadWriter(
          bd: BdCliService(bd),
          reader: reader,
          ownership: BeadOwnershipPredicate(const {'tgdog'}),
        ),
        freshnessBarrier: () async {},
        stateSnapshot: snapshot,
      );

      await reconciler.replayTeardownTail();

      final closedIds = _closedIds(bd);
      final refreshed = beads.where((bead) => !closedIds.contains(bead.id));
      final refreshedOpenSteps = refreshed
          .where(
            (bead) => bead.issueType == GridIssueTypes.step && !bead.isClosed,
          )
          .toList();
      final refreshedOpenMolecules = refreshed
          .where(
            (bead) =>
                bead.issueType == GridIssueTypes.molecule && !bead.isClosed,
          )
          .toList();

      expect(snapshotReads, 1);
      expect(closedOrphanStepIds, hasLength(4653));
      expect(closedOrphanMoleculeIds, hasLength(769));
      expect(closedIds, containsAll(closedOrphanStepIds));
      expect(closedIds, containsAll(closedOrphanMoleculeIds));
      expect(refreshedOpenSteps, hasLength(81));
      expect(refreshedOpenMolecules, hasLength(15));
      expect(closedIds, isNot(containsAll(liveChildIds)));
      expect(reader.sessionQueries, hasLength(1));
      expect(
        reader.sessionQueries.single.types,
        unorderedEquals(<IssueType>{GridIssueTypes.session}),
      );
      expect(reader.sessionQueries.single.metadataAll, {
        'grid.outcome': 'complete',
      });
    },
  );
}
