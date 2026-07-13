@Tags(<String>['git'])
library;

// The live station's completion fence, END TO END.
//
// Half 1 (the source gate): `buildStationWork` is the ONE composition site of
// `StationServices` for a real run; if it stops binding the work-signal probe the
// engine fence is inert and an INTERRUPTED agent again reads as a completion.
// `buildStationWork` cannot be driven to a successful build offline (it constructs
// Dolt-backed controllers — every `track_j_work_assembly_test` case is a refusal),
// so the WIRE is gated at the source, the same structural technique as
// grid_engine/test/structural_test.dart.
//
// Half 2 (the coupling): the exact probe it binds — `stationWorkSignal(git)` —
// driven against a REAL git worktree that does NOT gitignore `.grid` (the genesis
// / lenny shape) carrying REAL committee residue, through a REAL
// `ProcessAllocation`. Proves the coding agent still COMPLETES, an interrupted one
// FAILS, and a critic is never fenced.
import 'dart:io';

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The coding agent: it DECLARES the commit contract, so its inferred exits are
/// fenced.
class _AgentCap extends ProcessCapability {
  const _AgentCap();

  @override
  CompletionContract get completionContract =>
      CompletionContract.committedWorkspace;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => const RuntimeConfig(
    workDir: '/unused',
    command: 'sh',
    args: ['-c', 'x'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

/// A committee critic: no commit contract (the default) — never fenced.
class _CriticCap extends ProcessCapability {
  const _CriticCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => const RuntimeConfig(
    workDir: '/unused',
    command: 'sh',
    args: ['-c', 'grade'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

/// An ambient [SourceControl] naming the REAL temp repo — its presence arms the
/// fence and its workspace is what the fence probes. Land is unwired.
class _RepoSourceControl implements SourceControl {
  const _RepoSourceControl(this.dir);
  final String dir;

  @override
  String workspaceFor(String beadId) => dir;
  @override
  String branchFor(String beadId) => 'grid/$beadId';
  @override
  String get baseBranch => 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}

}

/// A [PrOpener] the fence never reaches (no land step here) — the real
/// [StationGitService] constructor requires one.
class _NoopPrOpener implements PrOpener {
  const _NoopPrOpener();

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => throw StateError('the completion fence never opens a PR');
}

void main() {
  test('buildStationWork binds the work-signal probe into StationServices', () {
    final src = File('lib/src/work/work_assembly.dart').readAsStringSync();

    expect(
      src.contains('workSignal: stationWorkSignal(git)'),
      isTrue,
      reason:
          'buildStationWork must arm the completion fence by binding '
          'StationServices.workSignal to stationWorkSignal(git). Unwired, the '
          'engine falls back to noWorkSignal and a KILLED coding agent reads as a '
          'COMPLETION — the circuit advances to review over a broken uncommitted '
          'tree.',
    );
  });

  group('the REAL probe over a REAL non-.grid-ignoring worktree', () {
    late Directory tmp;
    late String repo;

    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: repo);
      expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    }

    void write(String rel, String body) {
      File(p.join(repo, rel))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(body);
    }

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('grid-fence-');
      repo = p.join(tmp.path, 'wt');
      Directory(repo).createSync(recursive: true);
      await git(const ['init', '-q']);
      await git(const ['config', 'user.email', 'grid@example.com']);
      await git(const ['config', 'user.name', 'grid']);
      // NOTE: NO .gitignore — `.grid/` is fully visible to `git status` here,
      // exactly as on genesis (live arm #1) and lenny (arm #2).
      write('lib/work.dart', 'void main() {}\n');
      await git(const ['add', '-A']);
      await git(const ['commit', '-q', '-m', 'base']);
      // The grid's own steps left their residue, uncommitted, as they always do.
      write('.grid/critique/pinned.diff', 'diff --git a/x b/x\n');
      write('.grid/critique/correctness.json', '{"grade":"A"}\n');
      write('.grid/spec/respec.json', '{"round":1}\n');
      write('.grid/telemetry/x.usage.json', '{"tokens":1}\n');
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    WorkSignalProbe probe() => stationWorkSignal(
      StationGitService(
        runner: SystemGitRunner(),
        prOpener: const _NoopPrOpener(),
      ),
    );

    ProcessAllocation drive(
      ProcessCapability cap,
      List<AllocationReport> reports,
    ) =>
        cap.createAllocation(
              AllocationContext(
                treeContext: FakeTreeContext(
                  values: {
                    ServiceBundle: ServiceBundle(
                      sourceControl: _RepoSourceControl(repo),
                    ),
                    Workspace: testWorkspace('tg-1', workspaceDir: repo),
                  },
                ),
                args: stepArgs('tg-1/agent'),
                transport: FakeRuntimeProvider(),
                address: const AllocationAddress('tgdog-s', 'tg-1/agent'),
                env: const {},
                sink: reports.add,
                workSignal: probe(),
              ),
            )
            as ProcessAllocation;

    /// Waits for the REAL `git status` probe to settle (each test expects exactly
    /// one report) — a deadline, not a fixed pump, so a slow git is never flaky.
    Future<void> settle(List<AllocationReport> reports) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (reports.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    test('THE WEDGE: a coding agent that COMMITTED its work COMPLETES, even '
        'though the worktree is full of uncommitted .grid residue', () async {
      final reports = <AllocationReport>[];
      // The agent committed — a finished turn.
      write('lib/work.dart', 'void main() { print(0); }\n');
      await git(const ['add', 'lib']);
      await git(const ['commit', '-q', '-m', 'the agent committed']);

      drive(const _AgentCap(), reports).deliverEventForTest(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0, inferred: true),
      );
      await settle(reports);

      expect(reports.whereType<AllocationFailed>(), isEmpty);
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
    });

    test('THE BUG: a coding agent MURDERED mid-edit (uncommitted TRACKED change) '
        'FAILS as interrupted', () async {
      final reports = <AllocationReport>[];
      write('lib/work.dart', 'void main() { // killed mid-\n');

      drive(const _AgentCap(), reports).deliverEventForTest(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0, inferred: true),
      );
      await settle(reports);

      expect(reports.whereType<AllocationCompleted>(), isEmpty);
      expect(
        reports.whereType<AllocationFailed>().single.reason,
        contains('interrupted'),
      );
    });

    test('a CRITIC is never fenced — it completes over a genuinely DIRTY tree',
        () async {
      final reports = <AllocationReport>[];
      write('lib/work.dart', 'void main() { // dirty\n');

      drive(const _CriticCap(), reports).deliverEventForTest(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0, inferred: true),
      );
      await settle(reports);

      expect(reports.whereType<AllocationFailed>(), isEmpty);
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
    });
  });
}
