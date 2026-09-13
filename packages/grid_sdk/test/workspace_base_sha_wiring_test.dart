@Tags(<String>['git'])
library;

import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _beadId = 'pow-1';
const _circuit = Circuit(
  id: 'workspace-probe',
  terminalStepId: 'probe',
  steps: [CapabilityStep(stepId: 'probe', capabilityId: 'probe')],
);

/// Repository-backed source control over the real runtime git provisioner.
final class _GitBackedSourceControl implements SourceControl {
  _GitBackedSourceControl({required this.root, required this.repository});

  final RootCheckout root;
  final StationGitRepository repository;

  @override
  String get baseBranch => root.defaultBranch;

  @override
  String? baseShaFor(String beadId) => repository.baseShaFor(beadId);

  @override
  String branchFor(String beadId) => WorktreeLayout.branchFor(beadId);

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    if (Directory(workspaceDir).existsSync()) return;
    await repository.provisionWorktree(root: root, beadId: beadId);
  }

  @override
  String workspaceFor(String beadId) =>
      WorktreeLayout.worktreePath(root.path, root.substation, beadId);
}

/// Conservative source control for the nullable configured-branch control.
final class _UnknownBaseSourceControl implements SourceControl {
  const _UnknownBaseSourceControl({required this.baseBranch});

  @override
  final String baseBranch;

  @override
  String? baseShaFor(String beadId) => null;

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}

  @override
  String workspaceFor(String beadId) => '/tmp/$beadId';
}

/// The real engine capability read: the dependent asset's committee receives
/// this same ambient Workspace value.
final class _WorkspaceProbeCapability extends ServiceCapability {
  _WorkspaceProbeCapability(this.seen);

  final Completer<Workspace> seen;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    seen.complete(context.getInheritedSeedOfExactType<Workspace>()!);
    return const Ok();
  }
}

/// Fake PR boundary; workspace provisioning never opens a remote or PR.
final class _FakePrOpener implements PrOpener {
  const _FakePrOpener();

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => throw StateError('workspace provisioning never opens a PR');
}

Future<Workspace> _mountExistingSession(ServiceBundle services) async {
  final seen = Completer<Workspace>();
  final fakes = buildFakes();
  addTearDown(fakes.provider.close);
  addTearDown(fakes.ctx.dispose);
  final owner = TreeOwner();
  addTearDown(owner.dispose);
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<StationServices>(
        value: fakes.ctx,
        child: InheritedSeed<ServiceBundle>(
          value: services,
          child: InheritedSeed<CapabilityRegistry>(
            value: DefaultCapabilityRegistry(
              capabilities: {'probe': _WorkspaceProbeCapability(seen)},
            ),
            child: SessionScope(
              bead: Bead(
                id: _beadId,
                issueType: IssueType.task,
                status: BeadStatus.open,
              ),
              circuit: _circuit,
              existingSession: const SessionProjection(
                workBeadId: _beadId,
                sessionId: 'tgdog-session',
                isMolecule: true,
                moleculeBeads: [
                  Bead(
                    id: 'tgdog-probe',
                    issueType: GridIssueTypes.step,
                    status: BeadStatus.open,
                    metadata: {
                      'rig': stateSubstation,
                      MoleculeStepKeys.stepId: 'probe',
                      MoleculeStepKeys.capability: 'probe',
                      MoleculeStepKeys.kind: 'job',
                      MoleculeStepKeys.path: '$_beadId/probe',
                      MoleculeStepKeys.session: 'tgdog-session',
                      MoleculeStepKeys.state: 'pending',
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (var i = 0; i < 200 && !seen.isCompleted; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
  return seen.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw StateError('workspace probe capability did not run'),
  );
}

void main() {
  late Directory temp;
  late Map<String, String> gitEnvironment;
  late SystemGitRunner runner;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-workspace-base-sha-');
    final isolatedHome = Directory(p.join(temp.path, 'home'))..createSync();
    gitEnvironment = {
      'PATH': Platform.environment['PATH'] ?? '',
      'HOME': isolatedHome.path,
      'GIT_CONFIG_GLOBAL': p.join(isolatedHome.path, '.gitconfig'),
      'GIT_AUTHOR_NAME': 'grid-test',
      'GIT_AUTHOR_EMAIL': 'grid-test@example.test',
      'GIT_COMMITTER_NAME': 'grid-test',
      'GIT_COMMITTER_EMAIL': 'grid-test@example.test',
    };
    runner = SystemGitRunner(parentEnvironment: gitEnvironment);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Future<GitRunResult> git(String workingDirectory, List<String> args) async {
    final result = await runner.run(
      workingDirectory: workingDirectory,
      args: args,
    );
    if (!result.ok) {
      throw StateError('git ${args.join(' ')} failed: ${result.output}');
    }
    return result;
  }

  test('provision-time HEAD reaches the capability Workspace', () async {
    final rootPath = p.join(temp.path, 'root');
    Directory(rootPath).createSync();
    await git(rootPath, const ['init', '--initial-branch=main']);
    File(p.join(rootPath, 'README.md')).writeAsStringSync('base\n');
    await git(rootPath, const ['add', '-A']);
    await git(rootPath, const ['commit', '-m', 'initial']);

    final service = StationGitService(
      runner: runner,
      prOpener: const _FakePrOpener(),
    );
    final repository = StationGitRepository(service: service);
    addTearDown(repository.dispose);
    final realRoot = RootCheckout(
      path: rootPath,
      defaultBranch: 'main',
      substation: 'power_station',
    );
    final worktree = await repository.provisionWorktree(
      root: realRoot,
      beadId: _beadId,
    );
    final expected = (await git(worktree.path, const [
      'rev-parse',
      'HEAD',
    ])).output.trim();

    final observed = await _mountExistingSession(
      ServiceBundle(
        sourceControl: _GitBackedSourceControl(
          root: realRoot,
          repository: repository,
        ),
      ),
    );

    expect(expected, hasLength(40));
    expect(observed.baseSha, expected);
    expect(observed.baseBranch, 'main');
    expect(observed.workspaceDir, worktree.path);
  });

  test('unknown SHA preserves the configured base branch', () async {
    final observed = await _mountExistingSession(
      const ServiceBundle(
        sourceControl: _UnknownBaseSourceControl(baseBranch: 'trunk'),
      ),
    );

    expect(observed.baseSha, isNull);
    expect(observed.baseBranch, 'trunk');
  });

  test(
    'absent source control preserves the main fallback with no SHA',
    () async {
      final observed = await _mountExistingSession(const ServiceBundle());

      expect(observed.baseSha, isNull);
      expect(observed.baseBranch, 'main');
    },
  );
}
