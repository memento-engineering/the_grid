@TestOn('vm')
@Tags(['integration'])
library;

// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/molecule/molecule_codec.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

final class _RecordingProcessBdRunner implements BdRunner {
  _RecordingProcessBdRunner(ProcessBdRunner delegate) : _delegate = delegate;

  final ProcessBdRunner _delegate;
  final List<List<String>> calls = [];

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    return _delegate.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _HermeticWorkspace {
  _HermeticWorkspace._(this.root, this.environment);

  final Directory root;
  final Map<String, String> environment;

  static Future<_HermeticWorkspace> create() async {
    final environment = <String, String>{
      for (final name in ['PATH', 'HOME', 'TMPDIR', 'USER', 'LOGNAME'])
        if (Platform.environment[name] case final value?) name: value,
      'BD_JSON_ENVELOPE': '1',
      'BD_NON_INTERACTIVE': '1',
    };
    final version = await Process.run(
      'bd',
      const ['version'],
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    if (version.exitCode != 0) {
      fail(
        'bd version failed (${version.exitCode}): '
        '${version.stderr}\n${version.stdout}',
      );
    }

    final created = await Directory.systemTemp.createTemp(
      'grid_engine_result_persist_',
    );
    final root = Directory(created.resolveSymbolicLinksSync());
    final init = await Process.run(
      'bd',
      const ['init', '--prefix', 'smoke', '--skip-hooks', '--skip-agents'],
      workingDirectory: root.path,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    if (init.exitCode != 0) {
      await root.delete(recursive: true);
      fail(
        'bd init --prefix smoke failed (${init.exitCode}): '
        '${init.stderr}\n${init.stdout}',
      );
    }
    final configureTypes = await Process.run(
      'bd',
      const ['config', 'set', 'types.custom', 'session,molecule,step,gate'],
      workingDirectory: root.path,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    if (configureTypes.exitCode != 0) {
      await root.delete(recursive: true);
      fail(
        'bd config set types.custom failed (${configureTypes.exitCode}): '
        '${configureTypes.stderr}\n${configureTypes.stdout}',
      );
    }

    final workspace = BeadsWorkspace.discover(start: root.path);
    if (workspace == null || workspace.endpoint != null) {
      await root.delete(recursive: true);
      fail('hermetic bd init did not produce an endpoint-free embedded store');
    }
    return _HermeticWorkspace._(root, environment);
  }

  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

final class _ManualAdvanceCapability extends Capability {
  const _ManualAdvanceCapability();

  @override
  Allocation createAllocation(AllocationInputs inputs) =>
      _ManualAdvanceAllocation(inputs);
}

final class _ManualAdvanceAllocation extends Allocation {
  _ManualAdvanceAllocation(super.inputs);

  @override
  Future<void> startOrAdopt(TreeContext treeContext) async {
    state = AllocationState.live;
  }

  @override
  Future<void> dispose() async {
    inputs.args.cancel.cancel();
    state = AllocationState.gone;
  }
}

final class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: data));
  }
}

Branch _hostBranch(Branch root) {
  Branch? found;
  void walk(Branch branch) {
    if (branch.seed is CapabilityHost) found = branch;
    branch.visitChildren(walk);
  }

  walk(root);
  return found ?? (throw StateError('CapabilityHost did not mount'));
}

Future<void> _waitUntil(
  bool Function() predicate, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail(reason);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Set<String> _metadataKeys(Iterable<List<String>> calls) {
  final keys = <String>{};
  for (final call in calls) {
    for (var i = 0; i + 1 < call.length; i++) {
      if (call[i] == '--set-metadata') {
        final pair = call[i + 1];
        final equals = pair.indexOf('=');
        if (equals > 0) keys.add(pair.substring(0, equals));
      } else if (call[i] == '--metadata') {
        keys.addAll((jsonDecode(call[i + 1]) as Map<String, dynamic>).keys);
      }
    }
  }
  return keys;
}

void main() {
  test(
    'a fresh resident session persists a legal result and refuses an invalid '
    'field before bd',
    () async {
      final workspace = await _HermeticWorkspace.create();
      addTearDown(workspace.dispose);

      final process = ProcessBdRunner(
        workspaceRoot: workspace.root.path,
        environment: workspace.environment,
      );
      final runner = _RecordingProcessBdRunner(process);
      final bd = BdCliService(runner);
      final reader = CliBeadProbeReader(
        bd,
        lifecycleTypes: const {
          GridIssueTypes.session,
          GridIssueTypes.molecule,
          GridIssueTypes.step,
          GridIssueTypes.gate,
        },
      );
      final writer = StationBeadWriter(
        bd: bd,
        reader: reader,
        ownership: BeadOwnershipPredicate(const {'smoke'}),
      );
      final provider = FakeRuntimeProvider();
      final station = StationServices(
        provider: provider,
        writer: writer,
        stateSubstation: 'smoke',
      );
      addTearDown(() async {
        station.dispose();
        await provider.close();
      });

      Future<
        ({Bead step, _RecordingTransport transport, List<List<String>> calls})
      >
      drive({
        required String workBeadId,
        required Map<String, String> payload,
        required StepState expectedState,
      }) async {
        final sessionId = await writer.createSession(
          substation: 'smoke',
          title: 'resident result persistence $workBeadId',
          workBeadId: workBeadId,
          metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
        );
        final circuit = Circuit(
          id: 'resident-result-$workBeadId',
          terminalStepId: 'route',
          steps: const [
            CapabilityStep(stepId: 'route', capabilityId: 'manual-advance'),
          ],
        );
        final rootKey = BeadPathKey([workBeadId, sessionId]);
        final molecule = instantiateMolecule(
          circuit,
          sessionId: sessionId,
          root: rootKey,
          nodePath: workBeadId,
        );
        final ids = await writer.createMolecule(
          molecule.toGraphApplyPlan(),
          substation: 'smoke',
          sessionId: sessionId,
          rootCrumbs: rootKey.crumbs,
        );
        final nodePath = '$workBeadId/route';
        final stepId = ids[nodePath];
        if (stepId == null) fail('bd graph apply returned no id for $nodePath');
        final initialStep = await reader.beadById(
          stepId,
          types: const {GridIssueTypes.step},
        );
        if (initialStep == null) fail('fresh step $stepId was not readable');
        final cursor = projectMoleculeCursor([initialStep]).cursor;
        final registry = DefaultCapabilityRegistry(
          capabilities: const {'manual-advance': _ManualAdvanceCapability()},
          circuits: {circuit.id: circuit},
          clock: () => DateTime.utc(2026, 9, 21),
        );
        final transport = _RecordingTransport();
        final callStart = runner.calls.length;
        final owner = TreeOwner();
        final root = owner.mountRoot(
          ProviderScope(
            child: InheritedSeed<StationServices>(
              value: station,
              child: InheritedSeed<CapabilityRegistry>(
                value: registry,
                child: InheritedSeed<ServiceBundle>(
                  value: ServiceBundle(transport: transport),
                  child: InheritedSeed<Bead>(
                    value: Bead(id: workBeadId, issueType: IssueType.task),
                    child: InheritedSeed<Workspace>(
                      value: Workspace(
                        workspaceDir: workspace.root.path,
                        branch: 'grid/$workBeadId',
                        baseBranch: 'main',
                      ),
                      child: InheritedSeed<SessionHandle>(
                        value: SessionHandle(sessionId),
                        child: InheritedSeed<InheritedCircuit>(
                          value: InheritedCircuit(
                            root: rootKey,
                            beadIdByNodePath: {nodePath: stepId},
                            cursor: cursor,
                          ),
                          child: CircuitScope(
                            circuit: circuit,
                            cursor: cursor,
                            nodePath: workBeadId,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        try {
          await Future<void>.delayed(Duration.zero);
          final host = _hostBranch(root);
          final state = (host as StatefulBranch).state as CapabilityHostState;
          state.deliverReportForTest(AllocationAdvanced(payload));

          Bead? persisted;
          await _waitUntil(() {
            final matching = transport.flares.where(
              (flare) =>
                  flare.name == 'step.${expectedState.name}' ||
                  (expectedState == StepState.failed &&
                      flare.name == 'step.failed'),
            );
            return matching.isNotEmpty;
          }, reason: '$nodePath never reached ${expectedState.name}');
          persisted = await reader.beadById(
            stepId,
            types: const {GridIssueTypes.step},
          );
          if (persisted == null) fail('persisted step $stepId disappeared');
          return (
            step: persisted,
            transport: transport,
            calls: runner.calls.sublist(callStart),
          );
        } finally {
          owner.dispose();
        }
      }

      final legal = await drive(
        workBeadId: 'work-legal',
        payload: const {'source_state': 'accepted'},
        expectedState: StepState.complete,
      );
      expect(legal.step.metadata[MoleculeStepKeys.state], 'complete');
      expect(
        legal.step.metadata[ResultKeys.keyFor(
          'work-legal/route',
          'source_state',
        )],
        'accepted',
      );

      final invalid = await drive(
        workBeadId: 'work-invalid',
        payload: const {'source-state': 'accepted'},
        expectedState: StepState.failed,
      );
      expect(invalid.step.metadata[MoleculeStepKeys.state], 'failed');
      expect(
        invalid.step.metadata.keys.where(
          (key) => key.startsWith(ResultKeys.prefix),
        ),
        isEmpty,
      );
      expect(
        invalid.transport.flares
            .where((flare) => flare.name == 'step.persistFailed')
            .single
            .data['error'],
        allOf(
          contains('source-state'),
          contains('work-invalid/route'),
          contains('"-"'),
          contains('[a-z0-9_]+'),
        ),
      );
      expect(
        _metadataKeys(invalid.calls),
        isNot(contains('grid.result.work_hinvalid_sroute.source-state')),
        reason: 'the illegal metadata key must never reach bd',
      );
      expect(
        invalid.calls.where((call) {
          final keys = _metadataKeys([call]);
          return keys.contains(MoleculeStepKeys.state) &&
              call.any((arg) => arg.endsWith('=complete'));
        }),
        isEmpty,
        reason: 'the invalid result must not partially persist complete',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
