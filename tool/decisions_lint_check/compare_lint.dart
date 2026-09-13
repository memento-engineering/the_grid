// tg-vmtd AC-5 evidence: a reproducible before/after `decisions lint`
// comparison over `docs/decisions`, using the same `DecisionLintService` the
// station composes behind `lunar decisions lint`.
//
// The claim under test: retiring the orphaned ADR originals directory (and
// the handful of citation-only edits to files under `docs/decisions/` that
// pointed at it) changes NO lint diagnostic — no entry's `register:` front
// matter or body text was touched, so the register should lint identically
// before and after.
//
// Usage:
//   dart run compare_lint.dart <beforeRepoRoot> <afterRepoRoot>
//
// Exits 0 and prints "identical (<n> diagnostics)" when the two diagnostic
// sets match by (ruleId, entry filename, message) — the repo-root prefix on
// `file` differs between the two checkouts by construction, so it is
// stripped before comparing. Exits 1 and prints the set difference
// otherwise.
import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;

/// One diagnostic normalized for cross-checkout comparison.
typedef _Key = (String ruleId, String fileName, String message);

_Key _key(DecisionLintDiagnostic diagnostic) => (
  diagnostic.ruleId,
  p.basename(diagnostic.file),
  diagnostic.message,
);

String _describe(DecisionLintDiagnostic diagnostic) =>
    '${p.basename(diagnostic.file)}: [${diagnostic.ruleId}] ${diagnostic.message}';

DecisionLintResult _lint(String repoRoot) {
  final registerPath = p.join(repoRoot, 'docs', 'decisions');
  if (!Directory(registerPath).existsSync()) {
    stderr.writeln('no register at $registerPath');
    exit(2);
  }
  return const DecisionLintService().lint(
    registerPath: registerPath,
    repoRoot: repoRoot,
  );
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run compare_lint.dart <beforeRepoRoot> <afterRepoRoot>',
    );
    exitCode = 2;
    return;
  }

  final before = _lint(p.normalize(p.absolute(arguments[0])));
  final after = _lint(p.normalize(p.absolute(arguments[1])));

  final beforeByKey = {for (final d in before.diagnostics) _key(d): d};
  final afterByKey = {for (final d in after.diagnostics) _key(d): d};

  final onlyBefore = beforeByKey.keys.toSet().difference(afterByKey.keys.toSet());
  final onlyAfter = afterByKey.keys.toSet().difference(beforeByKey.keys.toSet());

  if (onlyBefore.isEmpty && onlyAfter.isEmpty) {
    stdout.writeln(
      'identical (${before.diagnostics.length} diagnostics, both before and after):',
    );
    for (final diagnostic in before.diagnostics) {
      stdout.writeln('  ${_describe(diagnostic)}');
    }
    return;
  }

  stderr.writeln('DIAGNOSTIC SETS DIFFER');
  stderr.writeln('before: ${before.diagnostics.length} diagnostic(s)');
  stderr.writeln('after:  ${after.diagnostics.length} diagnostic(s)');
  for (final key in onlyBefore) {
    stderr.writeln('- only before: ${_describe(beforeByKey[key]!)}');
  }
  for (final key in onlyAfter) {
    stderr.writeln('+ only after:  ${_describe(afterByKey[key]!)}');
  }
  exitCode = 1;
}
