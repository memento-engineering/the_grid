import 'dart:io';

/// The result of one `git` invocation — stdout (combined with stderr, gc's
/// `CombinedOutput`), the exit code, and a flag for whether the process even
/// launched. Modelled as a plain value type (predictable-flutter: value types
/// are plain).
class GitRunResult {
  const GitRunResult({
    required this.exitCode,
    required this.output,
    this.stderr = '',
    this.launched = true,
  });

  /// The process exit code. For a launch failure ([launched] == false) this is
  /// a non-zero sentinel so `ok` is false.
  final int exitCode;

  /// stdout and stderr combined, mirroring gc's `cmd.CombinedOutput()`
  /// (`internal/git/git.go:321`). Trimmed by callers where they care.
  final String output;

  /// The error stream ALONE, when the runner can separate it (empty otherwise).
  ///
  /// [output] stays combined (gc fidelity — error text must survive in the one
  /// field callers report), but a caller that PARSES structured stdout needs to
  /// know whether any of it came from stderr. `git status --porcelain` can exit
  /// **0** while warning on stderr (`warning: could not open directory …:
  /// Permission denied`), and such a line is NOT a porcelain entry: parsing it as
  /// one would fabricate a phantom change. [GitOps.hasUncommittedWork] fails
  /// closed on a non-empty stderr instead — the scan was incomplete, so the
  /// answer is "couldn't tell", never an invented one.
  final String stderr;

  /// False when the `git` binary could not be exec'd at all (not found, not
  /// executable). The probe gates treat a non-launch as an error → fail closed.
  final bool launched;

  /// Whether the command succeeded (launched AND exit 0).
  bool get ok => launched && exitCode == 0;
}

/// The git-command SEAM — the single point where [StationGitService] shells out to
/// `git`. A reference type (carries the `Runner` role name; predictable-flutter).
///
/// Mirrors grid_runtime's
/// [SubprocessSpawner] / [ProcessGroupController]: [SystemGitRunner] does the
/// real `dart:io` work; tests inject a fake (or, for the worktree integration
/// tier, the real runner against temp repos) so the gate/land/reap LOGIC runs
/// offline (Fakes, not mocks). The Dart port of gc's `Git.runCtx`
/// (`gascity/internal/git/git.go:311-326`).
abstract interface class GitRunner {
  /// Runs `git [args]` with [workingDirectory] as the cwd. The implementation
  /// MUST strip the [gitEnvBlacklist] keys from the inherited environment
  /// before exec (gc's clean-env build, `git.go:314-320`) so a parent
  /// `GIT_DIR`/`GIT_WORK_TREE`/… from a melos/hook context can never redirect
  /// the command to the wrong repository. Never throws — a launch failure is
  /// reported as [GitRunResult.launched] == false.
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  });
}

/// The git environment variables that MUST be stripped before every `git` exec
/// so a subprocess git command uses the intended cwd, not a parent repo's
/// `GIT_DIR`/`GIT_WORK_TREE`. Verbatim from gc's `gitEnvBlacklist`
/// (`gascity/internal/git/git.go:285-301`). the_grid is itself a git repo
/// invoked from melos/hooks, so this leak is real, not theoretical.
const Set<String> gitEnvBlacklist = <String>{
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
};

/// Builds the clean child environment for a `git` exec: every entry of
/// [parentEnv] EXCEPT the [gitEnvBlacklist] keys (gc's `git.go:314-320`). Pure
/// over an injected map so the blacklist is unit-tested with a fake env.
Map<String, String> cleanGitEnvironment(Map<String, String> parentEnv) {
  final out = <String, String>{};
  parentEnv.forEach((key, value) {
    if (gitEnvBlacklist.contains(key)) return;
    out[key] = value;
  });
  return out;
}

/// The real seam: execs `git` with the blacklist stripped and combines
/// stdout+stderr. The ONLY place this file touches `dart:io` process spawning.
class SystemGitRunner implements GitRunner {
  SystemGitRunner({Map<String, String>? parentEnvironment})
    : _parentEnv =
          parentEnvironment ?? Map<String, String>.from(Platform.environment);

  final Map<String, String> _parentEnv;

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    final env = cleanGitEnvironment(_parentEnv);
    final ProcessResult result;
    try {
      result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
        environment: env,
        includeParentEnvironment: false,
        runInShell: false,
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      );
    } on ProcessException {
      // git binary not found / not executable — a non-launch. Probe gates
      // treat this as an error and fail closed.
      return const GitRunResult(exitCode: -1, output: '', launched: false);
    }
    final stdout = (result.stdout as String);
    final stderr = (result.stderr as String);
    // gc combines stdout+stderr (CombinedOutput); preserve that so error text
    // is visible to callers/tests. The error stream is ALSO surfaced alone, so a
    // caller parsing structured stdout can refuse to read a warning as data.
    final combined = stderr.isEmpty ? stdout : '$stdout$stderr';
    return GitRunResult(
      exitCode: result.exitCode,
      output: combined,
      stderr: stderr,
    );
  }
}
