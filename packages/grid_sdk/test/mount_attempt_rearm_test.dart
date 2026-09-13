import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show
        GridCommandCompleted,
        GridCommandRefused,
        GridCommandRequest,
        StationCommandHandler,
        WorkCommandStore;
import 'package:test/test.dart';

const _workBeadId = 'tg-work';
const _recordId = 'tgdog-attempt';
const _lastAt = '2026-09-05T12:00:00.000Z';

Bead _workBead([String id = _workBeadId]) => Bead(
  id: id,
  title: 'work',
  issueType: IssueType.task,
  metadata: const {'rig': 'tg'},
);

Bead _attempt({
  String id = _recordId,
  String workBeadId = _workBeadId,
  int count = kMaxMountAttempts,
  String notes = 'mount attempt history',
}) => Bead(
  id: id,
  title: 'mount attempt',
  issueType: GridIssueTypes.mountAttempt,
  notes: notes,
  metadata: {
    'rig': 'tgdog',
    MountAttemptKeys.workBead: workBeadId,
    MountAttemptKeys.count: '$count',
    MountAttemptKeys.lastAt: _lastAt,
  },
);

GraphSnapshot _snapshot(Iterable<Bead> beads, {Set<String> ready = const {}}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.utc(2026, 9, 13),
    );

final class _Harness {
  _Harness({required List<Bead> stateBeads, List<Bead>? workBeads})
    : stateRunner = _StatefulBdRunner(stateBeads),
      workRunner = _StatefulBdRunner(workBeads ?? [_workBead()]),
      stateSource = FakeSnapshotSource(_snapshot(stateBeads)),
      workSource = FakeSnapshotSource(
        _snapshot(workBeads ?? [_workBead()], ready: {_workBeadId}),
      ) {
    stateWriter = StationBeadWriter(
      bd: BdCliService(stateRunner),
      reader: stateRunner,
      ownership: BeadOwnershipPredicate(const {'tgdog'}),
    );
    workWriter = StationBeadWriter(
      bd: BdCliService(workRunner),
      reader: workRunner,
      ownership: BeadOwnershipPredicate(const {'tg'}),
    );
    handler = StationCommandHandler(
      stateSource: stateSource,
      refreshState: () async => stateSource.push(_snapshot(stateRunner.beads)),
      stateWriter: stateWriter,
      stateOwnership: BeadOwnershipPredicate(const {'tgdog'}),
      workStoresByIdentity: {
        'tg': WorkCommandStore(
          substation: 'tg',
          root: '/work',
          source: workSource,
          refresh: () async => workSource.refreshQuietly(
            _snapshot(workRunner.beads, ready: {_workBeadId}),
          ),
          writer: workWriter,
        ),
      },
    );
  }

  final _StatefulBdRunner stateRunner;
  final _StatefulBdRunner workRunner;
  final FakeSnapshotSource stateSource;
  final FakeSnapshotSource workSource;
  late final StationBeadWriter stateWriter;
  late final StationBeadWriter workWriter;
  late final StationCommandHandler handler;

  Future<void> dispose() async {
    await stateSource.close();
    await workSource.close();
  }
}

final class _StatefulBdRunner implements BdRunner, BeadProbeReader {
  _StatefulBdRunner(Iterable<Bead> beads)
    : _beads = {for (final bead in beads) bead.id: bead};

  final Map<String, Bead> _beads;
  final List<List<String>> calls = [];

  List<Bead> get beads => _beads.values.toList(growable: false);

  List<List<String>> get updateCalls => calls
      .where(
        (call) =>
            call.length > 1 && call.first == 'update' && call[1] != '--help',
      )
      .toList(growable: false);

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    final bead = _beads[id];
    return bead != null && types.contains(bead.issueType) ? bead : null;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => [
    for (final bead in _beads.values)
      if (!bead.isClosed &&
          types.contains(bead.issueType) &&
          metadataAll.entries.every(
            (entry) => bead.metadata[entry.key] == entry.value,
          ) &&
          (metadataAny.isEmpty ||
              metadataAny.entries.any(
                (entry) => bead.metadata[entry.key] == entry.value,
              )))
        bead,
  ];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    if (args.length >= 2 && args[0] == 'update' && args[1] == '--help') {
      return const BdResult(
        exitCode: 0,
        stdout: 'Flags:\n  --if-assignee string\n  --if-status string\n',
        stderr: '',
      );
    }
    if (args.isNotEmpty && args.first == 'query') {
      final id = args.length > 1 && args[1].startsWith('id=')
          ? args[1].substring(3)
          : '';
      final bead = _beads[id];
      return BdResult(
        exitCode: 0,
        stdout: jsonEncode({
          'schema_version': 1,
          'data': [if (bead != null) bead.toJson()],
        }),
        stderr: '',
      );
    }
    if (args.length >= 2 && args.first == 'update') {
      final id = args[1];
      final bead = _beads[id];
      if (bead == null) {
        return const BdResult(
          exitCode: 1,
          stdout: '{"schema_version":1,"data":{"error":"missing bead"}}',
          stderr: '',
        );
      }
      final metadata = Map<String, dynamic>.of(bead.metadata);
      var notes = bead.notes;
      for (var index = 2; index < args.length; index++) {
        if (args[index] == '--set-metadata' && index + 1 < args.length) {
          final entry = args[++index];
          final separator = entry.indexOf('=');
          metadata[entry.substring(0, separator)] = entry.substring(
            separator + 1,
          );
        } else if (args[index] == '--append-notes' && index + 1 < args.length) {
          final appended = args[++index];
          notes = notes.isEmpty ? appended : '$notes\n$appended';
        }
      }
      _beads[id] = bead.copyWith(metadata: metadata, notes: notes);
      return BdResult(
        exitCode: 0,
        stdout: jsonEncode({
          'schema_version': 1,
          'data': {'id': id},
        }),
        stderr: '',
      );
    }
    return const BdResult(
      exitCode: 1,
      stdout: '{"schema_version":1,"data":{"error":"unexpected call"}}',
      stderr: '',
    );
  }
}

final class _RecordingSessionResolver implements SessionResolver {
  final List<String> mounted = [];

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      _MountedWork(
        beadId: bead.id,
        mounted: mounted,
        key: ValueKey('${bead.id}:work'),
      );
}

final class _MountedWork extends StatefulSeed {
  const _MountedWork({required this.beadId, required this.mounted, super.key});

  final String beadId;
  final List<String> mounted;

  @override
  State<_MountedWork> createState() => _MountedWorkState();
}

final class _MountedWorkState extends State<_MountedWork> {
  @override
  void initState() => seed.mounted.add(seed.beadId);

  @override
  Seed build(TreeContext context) => const Idle();
}

Iterable<Branch> _branches(Branch root) sync* {
  yield root;
  final children = <Branch>[];
  root.visitChildren(children.add);
  for (final child in children) {
    yield* _branches(child);
  }
}

Future<void> _settle(TreeOwner owner) async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
    owner.flush();
  }
}

void main() {
  setUp(BdCliService.resetGuardedWriteCapabilityForTesting);

  test('an exhausted record re-arms without a linked session', () async {
    final harness = _Harness(stateBeads: [_attempt()]);
    addTearDown(harness.dispose);

    final result = await harness.handler(
      const GridCommandRequest.rearmMountAttempt(
        beadId: _workBeadId,
        actor: '  operator@example.test  ',
        reason: 'mount conditions repaired',
      ),
    );

    expect(
      result,
      isA<GridCommandCompleted>().having((value) => value.value, 'value', {
        'operation': 'grid/mount-attempt/rearm',
        'beadId': _workBeadId,
        'recordId': _recordId,
        'priorCount': kMaxMountAttempts,
        'actor': 'operator@example.test',
      }),
    );
    expect(harness.stateRunner.updateCalls, hasLength(1));
    expect(
      harness.stateRunner.beads,
      isNot(
        contains(
          isA<Bead>().having(
            (bead) => bead.issueType,
            'issue type',
            GridIssueTypes.session,
          ),
        ),
      ),
    );
  });

  test(
    'actor and reason are mandatory and the receipt is attributable',
    () async {
      final harness = _Harness(stateBeads: [_attempt()]);
      addTearDown(harness.dispose);

      for (final entry in const <(String, String, String)>[
        (' ', 'reason', 'actor_required'),
        ('Nico', ' \n ', 'reason_required'),
      ]) {
        final result = await harness.handler(
          GridCommandRequest.rearmMountAttempt(
            beadId: _workBeadId,
            actor: entry.$1,
            reason: entry.$2,
          ),
        );
        expect(
          result,
          isA<GridCommandRefused>().having(
            (value) => value.code,
            'code',
            entry.$3,
          ),
        );
      }
      expect(harness.stateRunner.calls, isEmpty);

      const reason = 'literal `cmd` and \$(cmd)\n  trailing  ';
      final result = await harness.handler(
        const GridCommandRequest.rearmMountAttempt(
          beadId: _workBeadId,
          actor: '  Nico  ',
          reason: reason,
        ),
      );
      expect(result, isA<GridCommandCompleted>());
      final receipt = harness.stateRunner.beads.single.notes.substring(
        'mount attempt history\n'.length,
      );
      final firstLine = receipt.split('\n').first;
      final timestamp = firstLine
          .replaceFirst('--- grid mount-attempt RE-ARM (', '')
          .replaceFirst(') ---', '');
      expect(DateTime.parse(timestamp).isUtc, isTrue);
      expect(
        receipt.substring(firstLine.length + 1),
        'actor: Nico\n'
        'work bead: $_workBeadId\n'
        'prior attempt count: $kMaxMountAttempts\n'
        'reason:\n'
        '$reason',
      );
    },
  );

  test('non-exhausted and ambiguous records refuse without writes', () async {
    final cases = <(List<Bead>, String)>[
      ([_attempt(count: kMaxMountAttempts - 1)], 'mount_attempt_not_exhausted'),
      (
        [_attempt(id: 'tgdog-b'), _attempt(id: 'tgdog-a')],
        'mount_attempt_ambiguous',
      ),
      (const [], 'mount_attempt_not_found'),
      ([_attempt(id: 'foreign-attempt')], 'ownership_refused'),
    ];

    for (final entry in cases) {
      final harness = _Harness(stateBeads: entry.$1);
      addTearDown(harness.dispose);
      final result = await harness.handler(
        const GridCommandRequest.rearmMountAttempt(
          beadId: _workBeadId,
          actor: 'Nico',
          reason: 'retry',
        ),
      );
      expect(
        result,
        isA<GridCommandRefused>().having(
          (value) => value.code,
          'code',
          entry.$2,
        ),
      );
      expect(harness.stateRunner.calls, isEmpty);
      if (entry.$2 == 'mount_attempt_not_exhausted') {
        expect(
          (result as GridCommandRefused).message,
          allOf(
            contains('current count ${kMaxMountAttempts - 1}'),
            contains('cap $kMaxMountAttempts'),
          ),
        );
      }
      if (entry.$2 == 'mount_attempt_ambiguous') {
        expect(
          (result as GridCommandRefused).message,
          contains('tgdog-a, tgdog-b'),
        );
      }
    }
  });

  test('reset is in place and preserves last_at', () async {
    final harness = _Harness(stateBeads: [_attempt()]);
    addTearDown(harness.dispose);

    await harness.handler(
      const GridCommandRequest.rearmMountAttempt(
        beadId: _workBeadId,
        actor: 'Nico',
        reason: 'repair complete',
      ),
    );

    final attempts = harness.stateRunner.beads
        .where(
          (bead) =>
              !bead.isClosed && bead.issueType == GridIssueTypes.mountAttempt,
        )
        .toList();
    expect(attempts, hasLength(1));
    expect(attempts.single.id, _recordId);
    expect(attempts.single.metadata[MountAttemptKeys.count], '0');
    expect(attempts.single.metadata[MountAttemptKeys.lastAt], _lastAt);
    expect(harness.stateRunner.updateCalls, hasLength(1));
    final update = harness.stateRunner.updateCalls.single;
    expect(update.where((argument) => argument == '--set-metadata').length, 1);
    expect(
      update,
      containsAllInOrder([
        '--set-metadata',
        '${MountAttemptKeys.count}=0',
        '--append-notes',
      ]),
    );
    expect(update, isNot(contains(MountAttemptKeys.lastAt)));
  });

  test('reset snapshot restores the real WorkBead mount', () async {
    final harness = _Harness(stateBeads: [_attempt()]);
    final bridge = StationJoinBridge(
      work: harness.workSource,
      state: harness.stateSource,
    )..start();
    final provider = FakeRuntimeProvider();
    final stationServices = StationServices(
      provider: provider,
      writer: harness.stateWriter,
      stateSubstation: 'tgdog',
      maxConcurrentWork: 100,
    );
    final transport = RecordingExplorationTransport();
    final resolver = _RecordingSessionResolver();
    final owner = TreeOwner();
    addTearDown(() async {
      owner.dispose();
      stationServices.dispose();
      bridge.dispose();
      await provider.close();
      await harness.dispose();
    });

    final root = owner.mountRoot(
      ProviderScope(
        child: InheritedSeed<StationServices>(
          value: stationServices,
          child: InheritedSeed<JoinedSnapshotNotifier>(
            value: bridge.notifier,
            child: InheritedSeed<SessionResolver>(
              value: resolver,
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(
                    const SubstationConfig(
                      substationId: 'tg',
                      ownedSubstations: {'tg'},
                      resident: true,
                      maxConcurrentWork: 100,
                    ),
                  ),
                  services: ServiceBundle(transport: transport),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    await _settle(owner);

    expect(resolver.mounted, isEmpty);
    expect(
      transport.named('work.mountEligibilityRefused').single.data['clause'],
      contains(kMountAttemptCapClause),
    );

    final result = await harness.handler(
      const GridCommandRequest.rearmMountAttempt(
        beadId: _workBeadId,
        actor: 'Nico',
        reason: 'mount conditions repaired',
      ),
    );
    expect(result, isA<GridCommandCompleted>());
    await _settle(owner);

    expect(
      transport.named('work.mountEligibilityRestored').single.data['beadId'],
      _workBeadId,
    );
    expect(resolver.mounted, [_workBeadId]);
    expect(
      _branches(root).where(
        (branch) =>
            branch.seed is WorkBead &&
            (branch.seed as WorkBead).bead.id == _workBeadId,
      ),
      hasLength(1),
    );
  });
}
