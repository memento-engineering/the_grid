import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _root = RootCheckout(
  path: '/repo',
  defaultBranch: 'main',
  substation: 'tg',
);

const _worktree = BeadWorktree(
  beadId: 'tg-held',
  path: '/repo/.grid/worktrees/tg/tg-held',
  branch: 'grid/tg-held',
);

final class _CannedGitRunner implements GitRunner {
  _CannedGitRunner({
    this.uncommitted = GateOutcome.clear,
    this.unpushed = GateOutcome.clear,
    this.stashed = GateOutcome.clear,
  });

  final GateOutcome uncommitted;
  final GateOutcome unpushed;
  final GateOutcome stashed;
  final List<({String workingDirectory, List<String> args})> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workingDirectory: workingDirectory, args: List.of(args)));
    if (args case ['rev-parse', '--show-toplevel', '--show-prefix']) {
      return GitRunResult(exitCode: 0, output: '$workingDirectory\n\n');
    }
    if (args case ['status', '--porcelain']) {
      return _gate(uncommitted, presentOutput: '?? held.txt\n');
    }
    if (args case ['log', 'HEAD', '--oneline', '--not', '--remotes']) {
      return _gate(unpushed, presentOutput: 'abc local only\n');
    }
    if (args case ['stash', 'list']) {
      return _gate(stashed, presentOutput: 'stash@{0}: WIP\n');
    }
    if (args case ['worktree', 'remove', _, ...]) {
      return const GitRunResult(exitCode: 0, output: '');
    }
    if (args case ['branch', '-D', _]) {
      return const GitRunResult(exitCode: 0, output: '');
    }
    return const GitRunResult(exitCode: 1, output: 'unexpected command');
  }

  GitRunResult _gate(GateOutcome outcome, {required String presentOutput}) =>
      switch (outcome) {
        GateOutcome.clear => const GitRunResult(exitCode: 0, output: ''),
        GateOutcome.present => GitRunResult(exitCode: 0, output: presentOutput),
        GateOutcome.probeError => const GitRunResult(
          exitCode: 1,
          output: 'probe failed',
        ),
      };

  List<List<String>> get removeCalls => calls
      .map((call) => call.args)
      .where(
        (args) =>
            args.length >= 2 && args[0] == 'worktree' && args[1] == 'remove',
      )
      .toList(growable: false);
}

final class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => throw StateError('operator reap never opens a pull request');
}

StationGitService _service(_CannedGitRunner runner) =>
    StationGitService(runner: runner, prOpener: _FakePrOpener());

void main() {
  test('clear preview preserves gates and issues no removal', () async {
    final runner = _CannedGitRunner();

    final outcome = await _service(
      runner,
    ).reap(root: _root, worktree: _worktree, dryRun: true);

    expect(outcome.wouldRemove, isTrue);
    expect(outcome.refused, isFalse);
    expect(outcome.removed, isFalse);
    expect(outcome.uncommitted, GateOutcome.clear);
    expect(outcome.unpushed, GateOutcome.clear);
    expect(outcome.stashed, GateOutcome.clear);
    expect(runner.removeCalls, isEmpty);
  });

  for (final axis in ['uncommitted', 'unpushed', 'stashed']) {
    _presentGateTests(axis);
  }

  test('probe errors are never overridden', () async {
    for (final runner in [
      _CannedGitRunner(uncommitted: GateOutcome.probeError),
      _CannedGitRunner(unpushed: GateOutcome.probeError),
      _CannedGitRunner(stashed: GateOutcome.probeError),
    ]) {
      final outcome = await _service(
        runner,
      ).reap(root: _root, worktree: _worktree, overrideUnsafe: true);
      expect(outcome.refused, isTrue);
      expect(outcome.refusedReason, contains('probeError'));
      expect(runner.removeCalls, isEmpty);
    }
  });

  test('scope refusal runs before probes and is never overridden', () async {
    final runner = _CannedGitRunner();
    const outside = BeadWorktree(
      beadId: 'foreign',
      path: '/foreign/worktree',
      branch: 'grid/foreign',
    );

    final outcome = await _service(
      runner,
    ).reap(root: _root, worktree: outside, dryRun: true, overrideUnsafe: true);

    expect(outcome.refused, isTrue);
    expect(outcome.refusedReason, contains('not strictly under'));
    expect(runner.calls, isEmpty);
  });

  test('default automatic removal remains unforced', () async {
    final runner = _CannedGitRunner();

    final outcome = await _service(
      runner,
    ).reap(root: _root, worktree: _worktree);

    expect(outcome.removed, isTrue);
    expect(runner.removeCalls, [
      ['worktree', 'remove', _worktree.path],
    ]);
  });

  test(
    'an acted explicit override is forced even when gates are clear',
    () async {
      final runner = _CannedGitRunner();

      final outcome = await _service(
        runner,
      ).reap(root: _root, worktree: _worktree, overrideUnsafe: true);

      expect(outcome.removed, isTrue);
      expect(runner.removeCalls, [
        ['worktree', 'remove', _worktree.path, '--force'],
      ]);
    },
  );
}

void _presentGateTests(String axis) {
  _CannedGitRunner runner() => _CannedGitRunner(
    uncommitted: axis == 'uncommitted'
        ? GateOutcome.present
        : GateOutcome.clear,
    unpushed: axis == 'unpushed' ? GateOutcome.present : GateOutcome.clear,
    stashed: axis == 'stashed' ? GateOutcome.present : GateOutcome.clear,
  );

  test('$axis present refuses without override', () async {
    final fake = runner();
    final outcome = await _service(
      fake,
    ).reap(root: _root, worktree: _worktree, dryRun: true);
    expect(outcome.refused, isTrue);
    expect(
      outcome.refusedReason,
      contains('${axis == 'stashed' ? 'stashes' : axis}=present'),
    );
    expect(fake.removeCalls, isEmpty);
  });

  test('$axis present previews with override', () async {
    final fake = runner();
    final outcome = await _service(fake).reap(
      root: _root,
      worktree: _worktree,
      dryRun: true,
      overrideUnsafe: true,
    );
    expect(outcome.wouldRemove, isTrue);
    expect(fake.removeCalls, isEmpty);
  });

  test('$axis present acts once with force', () async {
    final fake = runner();
    final outcome = await _service(
      fake,
    ).reap(root: _root, worktree: _worktree, overrideUnsafe: true);
    expect(outcome.removed, isTrue);
    expect(fake.removeCalls, [
      ['worktree', 'remove', _worktree.path, '--force'],
    ]);
  });
}
