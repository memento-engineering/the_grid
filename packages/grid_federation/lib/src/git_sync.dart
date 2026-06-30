/// Git-over-LAN code/asset SYNC — the federation-native distribution channel,
/// DISTINCT from the lease bus (ADR-0011 D7, spike finding #1).
///
/// The lease bus ([StationClient]/[StationServer]) carries *coordination*
/// (lossy, low-frequency: request → grant → release). It does NOT carry code.
/// Distributing the actual code/assets to a peer rides **git**: a station pushes
/// to a peer's **bare repo** over a configured remote — SSH for real
/// cross-machine ("stations as git peers"), a LOCAL bare repo over a file-path
/// remote for offline tests. Ad-hoc `rsync` of the tree is correctly blocked as
/// exfiltration; a push to a configured remote is the sanctioned path.
///
/// This is a small, self-contained capability: [GitSyncService] formalizes the
/// spike's manual `git remote add` + `git push` into [ensureRemote] + [push]
/// (+ the [distribute] convenience that composes them). It shells out through an
/// INJECTABLE [GitCommandRunner] (the default runs real `git` via `Process.run`
/// with the parent's `GIT_DIR`/`GIT_WORK_TREE`/… stripped so a melos/hook
/// context can never redirect the push to the wrong repo); tests inject a fake
/// (or drive the default against temp repos) so the sync LOGIC runs offline.
/// Acts return [Future]s and throw [GitSyncException] on a git failure. Lib stays
/// print-free — wire [GitSyncService.new]'s `onLog` to observe events.
library;

import 'dart:io';

import 'package:meta/meta.dart';

/// The git environment variables stripped before every `git` exec by the default
/// [GitCommandRunner], so a parent `GIT_DIR`/`GIT_WORK_TREE`/… (from a melos or
/// hook context) can never redirect a sync push to the wrong repository. Mirrors
/// gascity's `gitEnvBlacklist` (grid_runtime keeps the canonical copy; this
/// package stays standalone `dart:io`-only, so it carries its own).
const Set<String> gitSyncEnvBlacklist = <String>{
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

/// The result of one `git` invocation: the exit code, stdout, stderr, and a flag
/// for whether the `git` binary launched at all. A plain value type
/// (predictable-flutter: value types are plain).
@immutable
class GitCommandResult {
  /// Creates a git result.
  const GitCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.launched = true,
  });

  /// The process exit code. For a launch failure ([launched] == false) this is a
  /// non-zero sentinel so [ok] is false.
  final int exitCode;

  /// The command's stdout.
  final String stdout;

  /// The command's stderr (git writes ref-update/progress lines here).
  final String stderr;

  /// False when the `git` binary could not be exec'd at all (not found / not
  /// executable) — a non-launch fails closed.
  final bool launched;

  /// Whether the command succeeded (launched AND exit 0).
  bool get ok => launched && exitCode == 0;

  /// stderr + stdout combined and trimmed, for logs and error messages.
  String get output {
    final parts = <String>[
      if (stderr.trim().isNotEmpty) stderr.trim(),
      if (stdout.trim().isNotEmpty) stdout.trim(),
    ];
    return parts.join('\n');
  }
}

/// The git-command SEAM — the single point [GitSyncService] shells out to `git`.
/// Runs `git [args]` with [workingDirectory] as the cwd and reports a
/// [GitCommandResult]; it MUST NOT throw on a non-zero exit or a missing binary
/// (those surface as [GitCommandResult.ok] == false). The default impl
/// ([processGitCommandRunner]) runs real `git`; tests inject a fake (Fakes, not
/// mocks).
typedef GitCommandRunner =
    Future<GitCommandResult> Function(
      List<String> args, {
      required String workingDirectory,
    });

/// The default [GitCommandRunner]: runs real `git` via `Process.run` with the
/// [gitSyncEnvBlacklist] keys stripped (`includeParentEnvironment: false` over a
/// cleaned copy of [Platform.environment]) and stdout/stderr captured. A missing
/// `git` binary is reported as a non-launch, never thrown.
Future<GitCommandResult> processGitCommandRunner(
  List<String> args, {
  required String workingDirectory,
}) async {
  final env = <String, String>{};
  Platform.environment.forEach((key, value) {
    if (!gitSyncEnvBlacklist.contains(key)) env[key] = value;
  });
  try {
    final r = await Process.run(
      'git',
      args,
      workingDirectory: workingDirectory,
      environment: env,
      includeParentEnvironment: false,
      runInShell: false,
      stdoutEncoding: const SystemEncoding(),
      stderrEncoding: const SystemEncoding(),
    );
    return GitCommandResult(
      exitCode: r.exitCode,
      stdout: r.stdout as String,
      stderr: r.stderr as String,
    );
  } on ProcessException catch (e) {
    return GitCommandResult(
      exitCode: -1,
      stdout: '',
      stderr: '$e',
      launched: false,
    );
  }
}

/// Thrown when a `git` act fails (a non-zero exit or a missing binary). Distinct
/// from `FederationException` — a sync failure is NOT a lease-bus/protocol
/// failure; the two channels are separate concerns (ADR-0011 D7).
class GitSyncException implements Exception {
  /// Creates a sync failure carrying the failed [command], its [exitCode], and
  /// the git [output].
  const GitSyncException(this.command, this.exitCode, this.output);

  /// The `git` argument vector that failed (e.g. `['push', 'peer', 'main']`).
  final List<String> command;

  /// The exit code (a negative sentinel when the binary did not launch).
  final int exitCode;

  /// The combined git output (stderr + stdout), for diagnosis.
  final String output;

  @override
  String toString() =>
      'GitSyncException: `git ${command.join(' ')}` exited $exitCode'
      '${output.isEmpty ? '' : '\n$output'}';
}

/// The git-over-LAN code/asset sync capability (ADR-0011 D7) — formalizes the
/// spike's manual bare-repo push. Distributes code/assets to a peer by pushing a
/// refspec to a configured git remote (the peer's bare repo); a SEPARATE concern
/// from the lease bus.
///
/// All methods are acts: they return [Future]s and throw [GitSyncException] on a
/// git failure. Stateless over its injected [GitCommandRunner] — each call names
/// the `workingDirectory` (the source repo) it operates in.
class GitSyncService {
  /// Creates a sync service. [runner] defaults to [processGitCommandRunner]
  /// (real `git`); inject a fake for offline logic tests. [onLog] observes
  /// events (lib is print-free); it defaults to a no-op.
  GitSyncService({GitCommandRunner? runner, void Function(String)? onLog})
    : _run = runner ?? processGitCommandRunner,
      _onLog = onLog ?? _noop;

  final GitCommandRunner _run;
  final void Function(String) _onLog;

  static void _noop(String _) {}

  /// Ensures the repo at [workingDirectory] has a remote named [name] pointing at
  /// [url], creating it (`git remote add`) when absent and updating it
  /// (`git remote set-url`) when it already exists with a different/stale url.
  /// Idempotent. Throws [GitSyncException] if the add/set-url fails. (An act.)
  Future<GitCommandResult> ensureRemote({
    required String workingDirectory,
    required String name,
    required String url,
  }) async {
    final existing = await _run(
      ['remote', 'get-url', name],
      workingDirectory: workingDirectory,
    );
    final List<String> args;
    if (existing.ok) {
      if (existing.stdout.trim() == url) {
        _onLog('remote "$name" already → $url');
        return existing;
      }
      args = ['remote', 'set-url', name, url];
      _onLog('remote "$name" updated → $url');
    } else {
      args = ['remote', 'add', name, url];
      _onLog('remote "$name" added → $url');
    }
    return _runOrThrow(args, workingDirectory: workingDirectory);
  }

  /// Pushes [refspec] from the repo at [workingDirectory] to [remote] (a remote
  /// name or a direct url) — the code/asset distribution to a peer's bare repo.
  /// Pass [force] for a non-fast-forward push. Returns the (successful)
  /// [GitCommandResult]; throws [GitSyncException] on a push failure. (An act.)
  Future<GitCommandResult> push({
    required String workingDirectory,
    required String remote,
    required String refspec,
    bool force = false,
  }) async {
    _onLog('pushing $refspec → $remote${force ? ' (force)' : ''}');
    return _runOrThrow(
      ['push', if (force) '--force', remote, refspec],
      workingDirectory: workingDirectory,
    );
  }

  /// Distributes [refspec] from [workingDirectory] to a peer in one act:
  /// [ensureRemote] ([remoteName] → [remoteUrl]) then [push]. The formalized
  /// "manual bare-repo push" of the spike. Throws [GitSyncException] on failure.
  Future<GitCommandResult> distribute({
    required String workingDirectory,
    required String remoteName,
    required String remoteUrl,
    required String refspec,
    bool force = false,
  }) async {
    await ensureRemote(
      workingDirectory: workingDirectory,
      name: remoteName,
      url: remoteUrl,
    );
    return push(
      workingDirectory: workingDirectory,
      remote: remoteName,
      refspec: refspec,
      force: force,
    );
  }

  Future<GitCommandResult> _runOrThrow(
    List<String> args, {
    required String workingDirectory,
  }) async {
    final result = await _run(args, workingDirectory: workingDirectory);
    if (!result.ok) {
      throw GitSyncException(args, result.exitCode, result.output);
    }
    return result;
  }
}
