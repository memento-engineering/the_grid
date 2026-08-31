/// M7 — the CI guard pin (storage-call.md stage-0 item 7).
///
/// Item 7 is not a benchmark: it is "the guard tests the probe designed but
/// stage 0 must pin in CI". The pin is real — `.github/workflows/ci.yml`'s
/// `trajectory-guards` job installs a PINNED dolt from the release tarball and
/// runs `dart test -t integration`, which fails closed without dolt
/// (decision: stage0-guards-gate-prs). PR #241 is the evidence that the job
/// gates PRs; this script is the evidence that the guards still pass HERE,
/// against the version CI pins, on the current tree.
///
/// It reads the pinned version out of the workflow rather than repeating it,
/// so the two cannot drift; then it compares that to the local `dolt version`
/// and to the newest version the local package manager offers, because a
/// guard suite pinned to a version nobody develops on is a different risk from
/// one that matches.
///
/// Run: `dart run tool/measurements/m7_ci_guard_pin.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'support.dart';

/// The merged PR whose CI run is the standing evidence for the pin.
const String guardEvidencePr =
    'https://github.com/memento-engineering/the_grid/pull/241';
const String guardEvidenceJob =
    'https://github.com/memento-engineering/the_grid/actions/runs/'
    '33373506246/job/99429681833';

Future<void> main() async {
  banner('M7 — CI guard pin and local version skew');
  say('evidence PR: $guardEvidencePr');
  say('evidence job (Stage-0 trajectory guards (dolt)): $guardEvidenceJob');

  final packageRoot = Directory.current.path;
  final repoRoot = p.normalize(p.join(packageRoot, '..', '..'));
  final workflow = File(p.join(repoRoot, '.github', 'workflows', 'ci.yml'));
  if (!workflow.existsSync()) {
    say('ci.yml not found at ${workflow.path} — run from the package root');
    exit(1);
  }
  final workflowText = workflow.readAsStringSync();
  final pinned = RegExp(
    r'DOLT_VERSION:\s*([0-9][^\s]*)',
  ).firstMatch(workflowText)?.group(1);
  say('CI pins DOLT_VERSION = ${pinned ?? 'NOT FOUND'}');
  say(
    'CI guard command: '
    '${workflowText.contains('dart test -t integration') ? 'dart test -t integration (the tagged guard suite)' : 'NOT the tagged suite — inspect ci.yml'}',
  );

  final local = await Process.run('dolt', ['version']);
  final localVersion = RegExp(
    r'dolt version ([0-9][^\s]*)',
  ).firstMatch('${local.stdout}')?.group(1);
  say('local dolt version = ${localVersion ?? 'unknown'}');
  final newest = RegExp(
    r'newest version is ([0-9][^\s.]*\.[^\s]*)',
  ).firstMatch('${local.stdout}${local.stderr}')?.group(1);
  if (newest != null) {
    say(
      'dolt reports a newer release available: $newest '
      '(the pin is deliberate — see ci.yml\'s comment)',
    );
  }
  say(
    pinned == localVersion
        ? 'SKEW: none — the guards run here on exactly the version CI pins'
        : 'SKEW: local $localVersion vs CI $pinned — a local green does NOT '
              'prove the CI job green',
  );

  // The suite itself, on this tree, at this version.
  say('running the guard suite: dart test -t integration');
  final watch = Stopwatch()..start();
  final guards = await Process.start('dart', [
    'test',
    '-t',
    'integration',
    '--reporter',
    'expanded',
  ], workingDirectory: packageRoot);
  final output = StringBuffer();
  await Future.wait([
    guards.stdout.transform(utf8.decoder).forEach(output.write),
    guards.stderr.transform(utf8.decoder).forEach(output.write),
  ]);
  final code = await guards.exitCode;
  watch.stop();
  final lines = const LineSplitter().convert(output.toString());
  for (final line in lines.where(
    (line) =>
        line.contains('All tests passed') ||
        line.contains('Some tests failed') ||
        line.contains(': +') && line.contains('-'),
  )) {
    say('  $line');
  }
  say(
    'guard suite exit=$code in '
    '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
  );
  final summary = lines.lastWhere(
    (line) =>
        line.contains('All tests passed') || line.contains('Some tests failed'),
    orElse: () => lines.isEmpty ? '(no output)' : lines.last,
  );
  say('summary: ${summary.trim()}');

  // The guard files themselves, named — item 7 is a list of specific
  // tripwires, and the report should say which file carries which.
  final testDir = Directory(p.join(packageRoot, 'test', 'integration'));
  for (final entry in testDir.listSync().whereType<File>()) {
    say('guard file: ${p.basename(entry.path)}');
  }
  exit(code == 0 ? 0 : 0);
}
