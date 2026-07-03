// tg-7gm rework r2 item (2): direct coverage for `buildStationStatus` /
// `_countsFor` / `SubstationStatus` — the r1 per-substation status logic the
// test-coverage critique found at ZERO coverage (only incidentally exercised,
// single-substation, through `station_control_wiring_test.dart`'s HTTP
// round-trip).
//
// `buildStationStatus` reads exactly one thing off `TreeRunWiring`:
// `wiring.kernel.bridge.latest`, which `StationJoinBridge`'s factory
// constructor seeds SYNCHRONOUSLY from `work.current`/`state.current` — no
// `wiring.start()` (no tree mount, no spawns, no timers) is ever needed to
// exercise it. So `_statusFor` below composes a wiring purely to obtain that
// seeded bridge, then calls `buildStationStatus` directly.
import 'dart:io' show ProcessSignal;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/station_control.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('buildStationStatus — per-substation status (tg-7gm)', () {
    test('ready/mounted narrow to each OWNED substation, the per-substation '
        'list is sorted alphabetically regardless of --substation order, and '
        'each slice looks up its OWN registered root', () {
      final status = _statusFor(
        // Insertion order 'tgdog' then 'power' — the OPPOSITE of alphabetical,
        // so the sort assertion below cannot pass by insertion-order accident.
        substations: {'tgdog', 'power'},
        roots: {'power': const RootSpec(path: '/repo/power')}, // tgdog: none
        beads: [
          _task('tgdog-ready1'),
          _task('power-ready1'),
          _task('otherrig-ready1'),
        ],
        readyIds: {'tgdog-ready1', 'power-ready1', 'otherrig-ready1'},
      );

      expect(
        status.ready,
        2,
        reason:
            'otherrig-ready1 is owned by neither substation — it must '
            'never inflate the aggregate',
      );
      expect(status.mounted, 2);
      expect(
        status.perSubstation.map((s) => s.substation).toList(),
        ['power', 'tgdog'],
        reason: 'alphabetical, NOT insertion order',
      );

      final power = status.perSubstation[0];
      expect(power.root, '/repo/power');
      expect(power.ready, 1);
      expect(power.mounted, 1);

      final tgdog = status.perSubstation[1];
      expect(
        tgdog.root,
        isNull,
        reason: 'no --root named tgdog was registered',
      );
      expect(tgdog.ready, 1);
      expect(tgdog.mounted, 1);
    });

    test('mounted counts a bead carrying a LIVE (non-terminal) session even '
        'after it has fallen out of readyIds', () {
      final status = _statusFor(
        substations: {'tgdog'},
        beads: [_task('tgdog-live1')],
        sessions: [
          _session('tgdog-sess1', workBead: 'tgdog-live1', closed: false),
        ],
      );
      expect(status.ready, 0);
      expect(status.mounted, 1);
    });

    test('mounted EXCLUDES a bead whose session is TERMINAL (closed), even '
        'while the bead itself still surfaces in readyIds — the ready loop '
        'does not re-check session terminality (the existing _countsFor '
        'asymmetry, locked in as-is)', () {
      final status = _statusFor(
        substations: {'tgdog'},
        beads: [_task('tgdog-donebutready1')],
        readyIds: {'tgdog-donebutready1'},
        sessions: [
          _session(
            'tgdog-sess1',
            workBead: 'tgdog-donebutready1',
            closed: true,
          ),
        ],
      );
      expect(status.ready, 1);
      expect(status.mounted, 0);
    });

    test('a bead that is neither ready nor sessioned never mounts', () {
      final status = _statusFor(
        substations: {'tgdog'},
        beads: [_task('tgdog-idle1')],
      );
      expect(status.ready, 0);
      expect(status.mounted, 0);
    });

    group('the tg-8p9 isCore/isDriveable mounted-narrowing fold', () {
      test('non-resident: a core-but-non-driveable epic counts (ready + '
          'mounted)', () {
        final status = _statusFor(
          substations: {'tgdog'},
          beads: [_bead('tgdog-epic1', IssueType.epic)],
          readyIds: {'tgdog-epic1'},
        );
        expect(status.ready, 1);
        expect(status.mounted, 1);
      });

      test('resident: the SAME epic is excluded — organizational work is '
          'never part of the all-ready drive set', () {
        final status = _statusFor(
          substations: {'tgdog'},
          resident: true,
          beads: [_bead('tgdog-epic1', IssueType.epic)],
          readyIds: {'tgdog-epic1'},
        );
        expect(status.ready, 0);
        expect(status.mounted, 0);
      });

      test('a non-core type is excluded regardless of resident arming', () {
        for (final resident in [false, true]) {
          final status = _statusFor(
            substations: {'tgdog'},
            resident: resident,
            beads: [_bead('tgdog-mol1', IssueType.molecule)],
            readyIds: {'tgdog-mol1'},
          );
          expect(status.ready, 0, reason: 'resident=$resident');
          expect(status.mounted, 0, reason: 'resident=$resident');
        }
      });
    });
  });
}

// --- test data builders ------------------------------------------------------

Bead _bead(String id, IssueType type) =>
    Bead(id: id, issueType: type, status: BeadStatus.open);

Bead _task(String id) => _bead(id, IssueType.task);

Bead _session(String id, {required String workBead, required bool closed}) =>
    Bead(
      id: id,
      issueType: IssueType.session,
      status: closed ? BeadStatus.closed : BeadStatus.open,
      metadata: {'work_bead': workBead},
    );

/// Composes a [TreeRunWiring] (never started — no mount, no spawn, no I/O)
/// purely to seed its bridge, then calls [buildStationStatus] over it.
StationStatus _statusFor({
  required Set<String> substations,
  required List<Bead> beads,
  Set<String> readyIds = const {},
  List<Bead> sessions = const [],
  Map<String, RootSpec> roots = const {},
  bool resident = false,
}) {
  final capturedAt = DateTime.utc(2026, 7, 3);
  final work = _StaticSnapshotSource(
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: readyIds,
      capturedAt: capturedAt,
    ),
  );
  final state = sessions.isEmpty
      ? const EmptySnapshotSource()
      : _StaticSnapshotSource(
          GraphSnapshot.fromParts(
            beads: sessions,
            dependencies: const [],
            readyIds: const {},
            capturedAt: capturedAt,
          ),
        );

  final wiring = composeStation(
    work: work,
    state: state,
    stationServices: StationServices(
      provider: DryRunProvider(),
      writer: StationBeadWriter(
        bd: BdCliService(NoOpBdRunner()),
        ownership: BeadOwnershipPredicate(substations),
      ),
      stateSubstation: substations.isNotEmpty ? substations.first : '',
    ),
    // Never mounted (the wiring is never `start()`ed below) — the config
    // scopes buildStationStatus reads from are `args.substations`/`args.roots`
    // directly, not this list.
    substations: const [],
    git: buildDryTreeGitService(),
    workRoot: const RootCheckout(
      path: '',
      defaultBranch: 'main',
      substation: '',
    ),
    groups: const _NeverAliveGroups(),
    freshnessBarrier: () async {},
    resolver: const CircuitResolver(_neverCircuitFor),
    registry: DefaultCapabilityRegistry(),
  );

  return buildStationStatus(
    args: StationArgs(
      substations: substations,
      roots: roots,
      resident: resident,
    ),
    sources: StationSources(work: work),
    wiring: wiring,
    startedAt: capturedAt,
  );
}

/// A [SnapshotSource] whose [current] is fixed at construction — never
/// listened to (the wiring above is never started).
class _StaticSnapshotSource implements SnapshotSource {
  const _StaticSnapshotSource(this.current);

  @override
  final GraphSnapshot? current;

  @override
  Stream<GraphSnapshot> get snapshots => const Stream<GraphSnapshot>.empty();
}

/// Never invoked (the composed tree is never mounted) — required only to
/// satisfy [composeStation]'s `resolver` parameter type.
Circuit _neverCircuitFor(Bead bead) => throw UnimplementedError(
  'unreached — buildStationStatus never mounts the tree',
);

/// A [ProcessGroupController] that reports everything gone — never actually
/// invoked (the `RestartReconciler` built inside `composeStation` is never
/// `.reconcile()`d here), just required to construct it.
class _NeverAliveGroups implements ProcessGroupController {
  const _NeverAliveGroups();

  @override
  int currentGroupId() => 99999;

  @override
  bool processAlive(int pid) => false;

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
}
