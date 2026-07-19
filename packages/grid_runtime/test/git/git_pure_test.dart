import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// A scripted fake [GitRunner] (Fakes, not mocks): returns a programmed
/// [GitRunResult] keyed by the first arg of the git command, so the
/// fail-closed-on-probe-error invariant is proven with NO real `git` and NO
/// filesystem — the runner can deterministically make any probe ERROR.
class _ScriptedGitRunner implements GitRunner {
  _ScriptedGitRunner(this._byVerb);

  /// Keyed by `args.first` (the git subcommand: status/log/stash/worktree/…).
  final Map<String, GitRunResult> _byVerb;

  /// Every command run, recorded as the joined argv (for asserting that
  /// `worktree remove` was NEVER reached on a fail-closed path).
  final List<String> calls = <String>[];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(args.join(' '));
    final verb = args.isEmpty ? '' : args.first;
    return _byVerb[verb] ?? const GitRunResult(exitCode: 0, output: '');
  }
}

/// A result that simulates a git PROBE ERROR (non-zero exit) — the input to the
/// fail-closed gates.
const _probeError = GitRunResult(
  exitCode: 128,
  output: 'fatal: not a git repository',
);

/// Pure, IO-free unit tests for Track 3's load-bearing logic that does NOT need
/// the `git` binary: the GIT_* env blacklist, the worktree-list parser, the
/// `<root>/.grid/worktrees/<rig>/<beadId>` layout + bead-id round-trip, and the
/// scope gate. (The real-git behaviour is exercised in
/// `station_git_service_test.dart` against temp repos.)
void main() {
  group('cleanGitEnvironment — the GIT_* blacklist', () {
    test('strips every blacklisted GIT_* var, keeps everything else', () {
      final parent = <String, String>{
        'PATH': '/usr/bin',
        'HOME': '/home/me',
        // Every blacklist entry, set to a poison value:
        'GIT_DIR': '/poison/.git',
        'GIT_WORK_TREE': '/poison',
        'GIT_COMMON_DIR': '/poison/common',
        'GIT_INDEX_FILE': '/poison/index',
        'GIT_OBJECT_DIRECTORY': '/poison/objects',
        'GIT_CONFIG': '/poison/config',
        'GIT_PREFIX': 'sub/',
      };
      final clean = cleanGitEnvironment(parent);

      expect(clean['PATH'], '/usr/bin');
      expect(clean['HOME'], '/home/me');
      for (final key in gitEnvBlacklist) {
        expect(
          clean.containsKey(key),
          isFalse,
          reason: '$key must be stripped before every git exec',
        );
      }
    });

    test('blacklist contains the exact gc set (verbatim port)', () {
      // gc's gitEnvBlacklist (internal/git/git.go:285-301).
      expect(gitEnvBlacklist, <String>{
        'GIT_COMMON_DIR',
        'GIT_CONFIG',
        'GIT_CONFIG_COUNT',
        'GIT_CONFIG_PARAMETERS',
        'GIT_DIR',
        'GIT_GRAFT_FILE',
        'GIT_IMPLICIT_WORK_TREE',
        'GIT_WORK_TREE',
        'GIT_INDEX_FILE',
        'GIT_OBJECT_DIRECTORY',
        'GIT_ALTERNATE_OBJECT_DIRECTORIES',
        'GIT_NO_REPLACE_OBJECTS',
        'GIT_PREFIX',
        'GIT_REPLACE_REF_BASE',
        'GIT_SHALLOW_FILE',
      });
    });
  });

  group('parseWorktreeList', () {
    test('parses multiple porcelain blocks with branch ref stripping', () {
      const output = '''
worktree /root
HEAD abc123
branch refs/heads/main

worktree /root/.grid/worktrees/tgdog/lenny-1
HEAD def456
branch refs/heads/grid/lenny-1
''';
      final list = parseWorktreeList(output);
      expect(list, hasLength(2));
      expect(list[0].path, '/root');
      expect(list[0].branch, 'main');
      expect(list[1].path, '/root/.grid/worktrees/tgdog/lenny-1');
      expect(list[1].branch, 'grid/lenny-1');
    });

    test('handles a final block with no trailing blank line', () {
      const output = 'worktree /only\nHEAD aaa\nbranch refs/heads/x';
      final list = parseWorktreeList(output);
      expect(list, hasLength(1));
      expect(list.single.branch, 'x');
    });
  });

  group('WorktreeLayout — path + branch + bead-id round-trip', () {
    const root = '/workspace/example-substation';
    const rig = 'tgdog';

    test('worktree path mirrors gc .gc/worktrees/<rig>/<name>', () {
      expect(
        WorktreeLayout.worktreePath(root, rig, 'lenny-abc'),
        '$root/.grid/worktrees/tgdog/lenny-abc',
      );
    });

    test('branch is grid/<beadId>', () {
      expect(WorktreeLayout.branchFor('lenny-abc'), 'grid/lenny-abc');
    });

    test('the dir name encodes the bead id and round-trips on restart', () {
      const beadId = 'lenny-wisp-9h557';
      final path = WorktreeLayout.worktreePath(root, rig, beadId);
      // basename of the worktree path is the dir name the reaper sees.
      final dirName = path.split('/').last;
      expect(WorktreeLayout.beadIdFromName(dirName), beadId);
    });

    test('empty dir name recovers no bead id', () {
      expect(WorktreeLayout.beadIdFromName('   '), isNull);
    });
  });

  group('isStrictlyUnderDir — the reaper scope gate', () {
    test('accepts a path strictly under the dir', () {
      expect(
        isStrictlyUnderDir('/root/.grid/worktrees', '/root/.grid/worktrees/t/b'),
        isTrue,
      );
    });

    test('rejects the dir itself', () {
      expect(isStrictlyUnderDir('/root/wt', '/root/wt'), isFalse);
    });

    test('rejects an escaping path', () {
      expect(isStrictlyUnderDir('/root/wt', '/root/other'), isFalse);
      expect(isStrictlyUnderDir('/root/wt', '/etc/passwd'), isFalse);
    });
  });

  group('gateBlocks', () {
    test('only clear permits; present and probeError both block', () {
      expect(gateBlocks(GateOutcome.clear), isFalse);
      expect(gateBlocks(GateOutcome.present), isTrue);
      // The load-bearing invariant: a probe ERROR fails closed (blocks).
      expect(gateBlocks(GateOutcome.probeError), isTrue);
    });
  });

  group('the three gates fail closed on a PROBE ERROR (no real git)', () {
    test('hasUncommittedWork: a `git status` error → probeError', () async {
      final ops = GitOps(
        _ScriptedGitRunner(<String, GitRunResult>{'status': _probeError}),
      );
      expect(await ops.hasUncommittedWork('/wt'), GateOutcome.probeError);
    });

    test('hasUnpushedCommits: a `git log` error → probeError', () async {
      final ops = GitOps(
        _ScriptedGitRunner(<String, GitRunResult>{'log': _probeError}),
      );
      expect(await ops.hasUnpushedCommits('/wt'), GateOutcome.probeError);
    });

    test('hasStashes: a `git stash list` error → probeError', () async {
      final ops = GitOps(
        _ScriptedGitRunner(<String, GitRunResult>{'stash': _probeError}),
      );
      expect(await ops.hasStashes('/wt'), GateOutcome.probeError);
    });

    test('a NON-LAUNCH (git binary missing) is also a probeError', () async {
      // launched:false is how SystemGitRunner reports a missing/unexecutable
      // git — it must fail closed, not read as "clean".
      const nonLaunch = GitRunResult(exitCode: -1, output: '', launched: false);
      final ops = GitOps(
        _ScriptedGitRunner(<String, GitRunResult>{'status': nonLaunch}),
      );
      expect(await ops.hasUncommittedWork('/wt'), GateOutcome.probeError);
    });
  });

  group('StationGitService.reap fails closed on probe error (scripted runner)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('grid_reap_pe_');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test(
      'every gate probe errors → reap REFUSES and never removes the worktree',
      () async {
        // A real on-disk worktree dir under the root (so the scope gate passes),
        // but a runner that makes EVERY git probe error — proving the
        // fail-closed-on-probe-error path refuses without a `worktree remove`.
        final rootPath = tmp.path;
        final wtPath = WorktreeLayout.worktreePath(rootPath, 'tgdog', 'lenny-pe');
        Directory(wtPath).createSync(recursive: true);

        final runner = _ScriptedGitRunner(<String, GitRunResult>{
          'status': _probeError,
          'log': _probeError,
          'stash': _probeError,
        });
        final svc = StationGitService(runner: runner, prOpener: _NeverPrOpener());

        final root = RootCheckout(
          path: rootPath,
          defaultBranch: 'main',
          substation: 'tgdog',
        );
        final wt = BeadWorktree(
          beadId: 'lenny-pe',
          path: wtPath,
          branch: 'grid/lenny-pe',
        );

        final reap = await svc.reap(root: root, worktree: wt);
        expect(reap.refused, isTrue);
        expect(reap.uncommitted, GateOutcome.probeError);
        expect(reap.unpushed, GateOutcome.probeError);
        expect(reap.stashed, GateOutcome.probeError);
        expect(reap.refusedReason, contains('uncommitted=probeError'));
        // The worktree dir is NOT removed, and `worktree remove` is never run.
        expect(
          runner.calls.any((c) => c.startsWith('worktree remove')),
          isFalse,
        );
        expect(Directory(wtPath).existsSync(), isTrue);
      },
    );
  });

  group(
    'StationGitService.provisionWorktree self-heals a WEDGED branch '
    '(tg-e0p, scripted runner)',
    () {
      late Directory tmp;

      setUp(() {
        tmp = Directory.systemTemp.createTempSync('grid_provision_wedge_');
      });
      tearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      RootCheckout rootIn(Directory dir) =>
          RootCheckout(path: dir.path, defaultBranch: 'main', substation: 'tgdog');

      test('a branch that does not exist yet is MINTED FRESH (with -b)', () async {
        final runner = _ScriptedGitRunner(<String, GitRunResult>{
          // `git show-ref --verify` exits 1 when the ref is absent — this is
          // ordinary git behaviour, not a probe error.
          'show-ref': const GitRunResult(exitCode: 1, output: ''),
          'worktree': const GitRunResult(exitCode: 0, output: ''),
        });
        final svc = StationGitService(runner: runner, prOpener: _NeverPrOpener());

        final wt = await svc.provisionWorktree(
          root: rootIn(tmp),
          beadId: 'lenny-fresh',
        );
        expect(wt.branch, 'grid/lenny-fresh');
        expect(
          runner.calls,
          contains('worktree add -b grid/lenny-fresh ${wt.path} main'),
        );
      });

      test(
        'a WEDGED branch (already exists, no worktree) is ADOPTED — never '
        're-minted with -b',
        () async {
          final runner = _ScriptedGitRunner(<String, GitRunResult>{
            'show-ref': const GitRunResult(exitCode: 0, output: ''),
            'worktree': const GitRunResult(exitCode: 0, output: ''),
          });
          final svc = StationGitService(
            runner: runner,
            prOpener: _NeverPrOpener(),
          );

          final wt = await svc.provisionWorktree(
            root: rootIn(tmp),
            beadId: 'lenny-wedged',
          );
          expect(wt.branch, 'grid/lenny-wedged');
          expect(
            runner.calls,
            contains('worktree add ${wt.path} grid/lenny-wedged'),
          );
          expect(
            runner.calls.any((c) => c.startsWith('worktree add -b')),
            isFalse,
            reason:
                'a pre-existing branch must be ADOPTED, never re-minted with '
                '-b (that is the exact "already exists" wedge, '
                'tg-rm5/tg-457)',
          );
        },
      );

      test(
        'when even the adopt attempt fails, the thrown message names the '
        'leftover state LOUD (branch pre-existed, target path)',
        () async {
          final runner = _ScriptedGitRunner(<String, GitRunResult>{
            'show-ref': const GitRunResult(exitCode: 0, output: ''),
            'worktree': const GitRunResult(
              exitCode: 128,
              output: 'fatal: some other worktree already checked it out',
            ),
          });
          final svc = StationGitService(
            runner: runner,
            prOpener: _NeverPrOpener(),
          );

          await expectLater(
            () =>
                svc.provisionWorktree(root: rootIn(tmp), beadId: 'lenny-stuck'),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('lenny-stuck'),
                  contains('grid/lenny-stuck'),
                  contains('already existed'),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// A [PrOpener] that must never be called in the reap tests; throws if it is.
class _NeverPrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    throw StateError('PrOpener must not be called from a reap path');
  }
}
