import 'git_runner.dart';

/// A reference to an opened pull request — what the land step records on the
/// lifecycle bead (ADR-0006 Decision 3). Plain value type (predictable-flutter).
class PullRequestRef {
  const PullRequestRef({required this.url, this.number});

  /// The PR URL (e.g. `https://github.com/<org>/lenny/pull/123`) — `gh pr
  /// create` prints this on stdout.
  final String url;

  /// The PR number, when parseable from the URL. Recorded alongside the URL.
  final int? number;

  @override
  String toString() => 'PullRequestRef(${number ?? '?'}: $url)';
}

/// Why a PR open did not produce a [PullRequestRef]. Modelled as a sealed-ish
/// value so the land step can record the failure on the lifecycle bead rather
/// than throwing.
class PrOpenFailure {
  const PrOpenFailure(this.reason);
  final String reason;

  @override
  String toString() => 'PrOpenFailure($reason)';
}

/// The PR-opener SEAM — the single point where the land step opens a pull
/// request. INJECTABLE so the whole land path (commit → push → open PR) runs
/// offline against a fake that records the branch it was asked to open (Fakes,
/// not mocks). A reference type (the `Opener` role name; predictable-flutter).
///
/// The land step is a DIVERGENCE from gc (gc has no PR-open prior art); this
/// seam is the boundary that keeps the offline build from ever touching real
/// GitHub. [GhPrOpener] is the real impl (shells `gh pr create`); the dogfood
/// arming wires it, but it is NEVER constructed in the offline tests.
abstract interface class PrOpener {
  /// Opens a PR for [branch] (already pushed with `-u`) against [baseBranch],
  /// run from [workDir]. Returns the [PullRequestRef] on success, or a
  /// [PrOpenFailure] (never throws — the land step records either on the bead).
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body,
  });
}

/// The result of [PrOpener.open]: either the ref or a failure. A tiny sealed
/// union via a record-style holder (kept simple; no freezed needed for two
/// branches consumed at one call site).
class PullRequestResult {
  const PullRequestResult._(this.ref, this.failure);

  /// Success: the PR was opened.
  factory PullRequestResult.opened(PullRequestRef ref) =>
      PullRequestResult._(ref, null);

  /// Failure: the PR could not be opened (recorded, not thrown).
  factory PullRequestResult.failed(PrOpenFailure failure) =>
      PullRequestResult._(null, failure);

  final PullRequestRef? ref;
  final PrOpenFailure? failure;

  bool get isOpened => ref != null;
}

/// The real PR opener: shells `gh pr create`. Constructed ONLY by the live
/// dogfood arming — the offline test suite always injects a fake. Kept tiny and
/// over the [GitRunner]-style shell so it inherits no real-GitHub dependency in
/// the type graph the tests exercise.
///
/// NOTE: this uses [GitRunner] only as a generic command runner shape for `gh`;
/// it execs `gh`, not `git`. The land step constructs it lazily so an offline
/// run never instantiates a real `gh` exec.
class GhPrOpener implements PrOpener {
  const GhPrOpener(this._gh);

  /// A runner that execs the `gh` CLI (not `git`). The blacklist-stripping
  /// [SystemGitRunner] is not reused for `gh`; the dogfood wiring supplies a
  /// `gh`-specific runner. Left abstract here so this file stays free of a real
  /// `gh` dependency for the offline graph.
  final Future<GitRunResult> Function(
    String workDir,
    List<String> args,
  )
  _gh;

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    final result = await _gh(workDir, <String>[
      'pr',
      'create',
      '--head',
      branch,
      '--base',
      baseBranch,
      '--title',
      title,
      '--body',
      body,
    ]);
    if (!result.ok) {
      return PullRequestResult.failed(
        PrOpenFailure('gh pr create failed: ${result.output.trim()}'),
      );
    }
    final url = result.output.trim().split('\n').last.trim();
    return PullRequestResult.opened(
      PullRequestRef(url: url, number: _parsePrNumber(url)),
    );
  }

  static int? _parsePrNumber(String url) {
    final match = RegExp(r'/pull/(\d+)').firstMatch(url);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
