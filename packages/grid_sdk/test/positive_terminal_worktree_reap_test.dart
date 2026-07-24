@Tags(<String>['git'])
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _NoopPrOpener implements PrOpener {
  const _NoopPrOpener();

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => throw StateError('worktree reap never opens a PR');
}

class _RepoSourceControl implements SourceControl {
  const _RepoSourceControl(this.dir);

  final String dir;

  @override
  String get baseBranch => 'main';

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}

  @override
  String workspaceFor(String beadId) => dir;
}

Future<ProcessResult> _git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return result;
}

const _terminalCircuit = Circuit(
  id: 'done',
  terminalStepId: 'finish',
  steps: [CapabilityStep(stepId: 'finish', capabilityId: 'finish')],
);

Future<void> _pump(TreeOwner owner) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    owner.flush();
  }
}

SessionProjection _projection(bool complete) => SessionProjection(
  workBeadId: 'tg-live',
  sessionId: 'tgdog-session',
  isTerminal: false,
  cursor: complete
      ? const {'tg-live/finish': NodeCursor(state: StepState.complete)}
      : const {},
);

void main() {
  late Directory temp;
  late String root;
  late StationGitService git;
  late RootCheckout rootCheckout;
  late BeadWorktree worktree;
  const beadId = 'tg-live';

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('grid-live-reap-');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final origin = '${temp.path}/origin.git';
    root = '${temp.path}/root';
    await _git(temp.path, ['init', '--bare', origin]);
    await _git(temp.path, ['clone', origin, root]);
    await _git(root, ['config', 'user.email', 'grid@example.test']);
    await _git(root, ['config', 'user.name', 'Grid Test']);
    File('$root/README.md').writeAsStringSync('root\n');
    await _git(root, ['add', 'README.md']);
    await _git(root, ['commit', '-m', 'initial']);
    await _git(root, ['branch', '-M', 'main']);
    await _git(root, ['push', '-u', 'origin', 'main']);

    git = StationGitService(
      runner: SystemGitRunner(),
      prOpener: const _NoopPrOpener(),
    );
    rootCheckout = RootCheckout(
      path: root,
      defaultBranch: 'main',
      substation: 'pow',
    );
    worktree = await git.provisionWorktree(root: rootCheckout, beadId: beadId);
    await _git(worktree.path, ['config', 'user.email', 'grid@example.test']);
    await _git(worktree.path, ['config', 'user.name', 'Grid Test']);
    File('${worktree.path}/result.txt').writeAsStringSync('done\n');
    await _git(worktree.path, ['add', 'result.txt']);
    await _git(worktree.path, ['commit', '-m', 'complete work']);
    await _git(worktree.path, ['push', '-u', 'origin', 'grid/$beadId']);
  });

  ({TreeOwner owner, RecordingExplorationTransport transport}) mountTerminal() {
    const sessionId = 'tgdog-session';
    final owner = TreeOwner();
    final transport = RecordingExplorationTransport();
    final fakes = buildFakes(createdId: sessionId);
    final session = _projection(false);
    final graph = GraphSnapshot.fromParts(
      beads: [
        Bead(
          id: beadId,
          issueType: IssueType.task,
          status: BeadStatus.open,
          metadata: const {'rig': 'tg'},
        ),
      ],
      dependencies: const [],
      readyIds: const {beadId},
      capturedAt: DateTime(2026),
    );
    final joined = JoinedSnapshotNotifier(
      JoinedSnapshot(graph: graph, sessionsByWorkBead: {beadId: session}),
    );
    owner.mountRoot(
      InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(
              sourceControl: _RepoSourceControl(worktree.path),
              transport: transport,
            ),
            child: InheritedSeed<CapabilityRegistry>(
              value: RecordingCapabilityRegistry(),
              child: InheritedSeed<SessionResolver>(
                value: CircuitResolver(
                  (_) => _terminalCircuit,
                  reapWorktree: git.reap,
                  workRoot: rootCheckout,
                ),
                child: Station([
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(
                      const SubstationConfig(
                        substationId: 'tg',
                        ownedSubstations: {'tg'},
                      ),
                    ),
                    services: ServiceBundle(
                      sourceControl: _RepoSourceControl(worktree.path),
                      transport: transport,
                    ),
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    joined.push(
      JoinedSnapshot(
        graph: graph,
        sessionsByWorkBead: {beadId: _projection(true)},
      ),
    );
    owner.flush();
    addTearDown(owner.dispose);
    return (owner: owner, transport: transport);
  }

  test('clear gates remove worktree and branch without restart', () async {
    final mounted = mountTerminal();
    await _pump(mounted.owner);

    expect(Directory(worktree.path).existsSync(), isFalse);
    final branches = await _git(root, ['branch', '--list', 'grid/$beadId']);
    expect((branches.stdout as String).trim(), isEmpty);
  });

  test('held gate preserves worktree and branch with named flare', () async {
    File('${worktree.path}/result.txt').writeAsStringSync('dirty\n');
    final mounted = mountTerminal();
    await _pump(mounted.owner);

    expect(Directory(worktree.path).existsSync(), isTrue);
    final branches = await _git(root, ['branch', '--list', 'grid/$beadId']);
    expect((branches.stdout as String).trim(), isNotEmpty);
    final held = mounted.transport.named('session.worktreeReapHeld').toList();
    expect(held, hasLength(1));
    expect(held.first.data, containsPair('uncommitted', 'present'));
    expect(
      held.first.data.keys,
      containsAll(<String>['uncommitted', 'unpushed', 'stashes']),
    );
  });
}
