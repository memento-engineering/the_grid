// The work signal's residue filter. `git status --porcelain` output is CANNED
// through a Fake GitRunner (Fakes, not mocks) so every porcelain shape the filter
// must survive is pinned: git's collapsed untracked dir, a nested file, a quoted
// path, a rename that escapes the exclusion, an unparsable line.
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// A `git` that always returns [output] with [exitCode] (and optionally [stderr])
/// — the porcelain the filter must read. Mirrors the real runner: `output` is
/// stdout and stderr COMBINED (gc's `CombinedOutput`), `stderr` is the error
/// stream alone.
class _CannedGit implements GitRunner {
  const _CannedGit(this.output, {this.exitCode = 0, this.stderr = ''});
  final String output;
  final int exitCode;
  final String stderr;

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async =>
      GitRunResult(exitCode: exitCode, output: output, stderr: stderr);
}

Future<GateOutcome> probe(
  String porcelain, {
  Set<String> excluding = const <String>{},
}) => GitOps(_CannedGit(porcelain)).hasUncommittedWork('/w', excluding: excluding);

void main() {
  group('ADR-0006 D3 Gate 1 is UNCHANGED with no exclusion (reap)', () {
    test('grid residue with NO exclusion is still WORK (a reap must refuse)',
        () async {
      expect(await probe('?? .grid/\n'), GateOutcome.present);
    });

    test('an empty status is clear', () async {
      expect(await probe('\n'), GateOutcome.clear);
    });

    test('a failed probe is probeError, exclusion or not', () async {
      expect(
        await GitOps(const _CannedGit('fatal: not a repo', exitCode: 128))
            .hasUncommittedWork('/w', excluding: const {'.grid'}),
        GateOutcome.probeError,
      );
    });
  });

  group('the completion fence excludes the grid runtime dir', () {
    test("git's COLLAPSED untracked dir (`?? .grid/`) is not work", () async {
      expect(
        await probe('?? .grid/\n', excluding: const {'.grid'}),
        GateOutcome.clear,
      );
    });

    test('nested grid artifacts (critique / spec / telemetry / pinned diff) are '
        'not work', () async {
      const porcelain =
          '?? .grid/critique/pinned.diff\n'
          '?? .grid/critique/correctness.json\n'
          '?? .grid/spec/respec.json\n'
          '?? .grid/telemetry/tg-1_agent.usage.json\n';
      expect(
        await probe(porcelain, excluding: const {'.grid'}),
        GateOutcome.clear,
      );
    });

    test('a QUOTED grid path is not work', () async {
      expect(
        await probe('?? ".grid/critique/a b.json"\n', excluding: const {'.grid'}),
        GateOutcome.clear,
      );
    });

    test('REAL uncommitted code IS work', () async {
      expect(
        await probe(' M lib/src/foo.dart\n', excluding: const {'.grid'}),
        GateOutcome.present,
      );
    });

    test('residue NEVER MASKS real work (both present ⇒ present)', () async {
      expect(
        await probe(
          '?? .grid/critique/pinned.diff\n M lib/src/foo.dart\n',
          excluding: const {'.grid'},
        ),
        GateOutcome.present,
      );
    });

    test('a rename OUT of the grid dir is work (one path escapes)', () async {
      expect(
        await probe('R  .grid/x -> lib/x.dart\n', excluding: const {'.grid'}),
        GateOutcome.present,
      );
    });

    test('a rename WITHIN the grid dir is not work', () async {
      expect(
        await probe(
          'R  .grid/critique/a.json -> .grid/critique/b.json\n',
          excluding: const {'.grid'},
        ),
        GateOutcome.clear,
      );
    });

    test('FAIL CLOSED: an unparsable line counts as work', () async {
      expect(await probe('??\n', excluding: const {'.grid'}), GateOutcome.present);
    });

    test('a path merely PREFIXED by the excluded name is work (`.gridlock/x`)',
        () async {
      expect(
        await probe('?? .gridlock/x\n', excluding: const {'.grid'}),
        GateOutcome.present,
      );
    });
  });

  group('a WARNING on stderr is never parsed as a change', () {
    // `git status --porcelain` can exit 0 while warning on stderr (an unreadable
    // dir in the worktree). `GitRunResult.output` is COMBINED (gc fidelity), so a
    // naive line-split would read `warning: could not open directory …` as a
    // porcelain entry and INVENT an uncommitted change — failing a coding agent
    // that committed correctly, forever, on every respawn. A degraded scan is
    // "couldn't tell", not a fabricated answer.
    const warning =
        "warning: could not open directory 'vendor/': Permission denied\n";

    test('exit 0 + a stderr warning over a CLEAN tree is probeError, NOT a '
        'phantom change', () async {
      expect(
        await GitOps(const _CannedGit(warning, stderr: warning))
            .hasUncommittedWork('/w', excluding: const {'.grid'}),
        GateOutcome.probeError,
      );
    });

    test('exit 0 + a stderr warning ALONGSIDE real porcelain is still probeError '
        '(the scan was incomplete — we cannot trust what it did NOT see)',
        () async {
      expect(
        await GitOps(
          const _CannedGit(' M lib/x.dart\n$warning', stderr: warning),
        ).hasUncommittedWork('/w', excluding: const {'.grid'}),
        GateOutcome.probeError,
      );
    });

    test('the reap gate ALSO refuses on a degraded scan (probeError blocks, '
        'exactly as `present` did)', () async {
      final outcome = await GitOps(const _CannedGit(warning, stderr: warning))
          .hasUncommittedWork('/w');
      expect(outcome, GateOutcome.probeError);
      expect(
        gateBlocks(outcome),
        isTrue,
        reason: 'ADR-0006 D3: a reap must still refuse — the decision is '
            'unchanged, only the (honest) reason differs',
      );
    });

    test('a CLEAN probe with EMPTY stderr is unaffected', () async {
      expect(
        await GitOps(const _CannedGit('?? .grid/\n'))
            .hasUncommittedWork('/w', excluding: const {'.grid'}),
        GateOutcome.clear,
      );
    });
  });
}
