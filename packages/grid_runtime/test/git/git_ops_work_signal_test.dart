// The work signal's residue filter. `git status --porcelain` output is CANNED
// through a Fake GitRunner (Fakes, not mocks) so every porcelain shape the filter
// must survive is pinned: git's collapsed untracked dir, a nested file, a quoted
// path, a rename that escapes the exclusion, an unparsable line.
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// A `git` that always returns [output] with [exitCode] — the porcelain the
/// filter must read.
class _CannedGit implements GitRunner {
  const _CannedGit(this.output, {this.exitCode = 0});
  final String output;
  final int exitCode;

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => GitRunResult(exitCode: exitCode, output: output);
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
}
