@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

/// Cross-process exploration-attach conformance (M3 Track 6 DoD): a STOCK
/// `leonard_cli --extensions grid` attaches to the_grid's pure-Dart VM and
/// reads live grid state over `ext.exploration.*`.
///
/// This is the real-leonard analog of `attach_conformance_test.dart` (which
/// uses an in-process leonard-shaped reader). It launches `tool/attach_target.dart`
/// under its own VM service, then points `leonard_cli` at that ws:// URI.
///
/// **Self-skips** when `leonard_cli` is not discoverable, OR when it is present
/// but cannot run a live session because its inference credentials are not armed
/// (leonard initializes its model provider BEFORE it attaches — `run.dart:101`
/// returns `config_error` on a missing key, so a credential-less run never
/// reaches the handshake the rename fixes). It is a sibling-repo, fully-armed
/// integration check, not a hard dependency of the_grid's offline suite; the
/// offline run (`dart test -x integration`) never reaches it, and the spec is
/// explicit not to execute anything live unarmed.
///
/// Discovery order for `leonard_cli`:
///   1. `$LEONARD_CLI` (an explicit absolute path or an on-PATH executable);
///   2. a `leonard_cli` executable on `$PATH`;
///   3. the sibling lenny checkout's `packages/leonard_cli/bin/leonard_cli.dart`
///      (run via `dart run`) at the conventional
///      `~/development/engineering.memento/lenny` location.

/// How to invoke leonard_cli once discovered: either a direct executable or a
/// `dart run <entrypoint>` pair.
typedef _LeonardInvocation = ({String executable, List<String> prefixArgs});

_LeonardInvocation? _discoverLeonardCli() {
  // 1. Explicit override.
  final override = Platform.environment['LEONARD_CLI'];
  if (override != null && override.trim().isNotEmpty) {
    final f = File(override);
    if (f.existsSync()) {
      return override.endsWith('.dart')
          ? (executable: _dartExecutable(), prefixArgs: <String>['run', override])
          : (executable: override, prefixArgs: const <String>[]);
    }
    // Treat as a bare command name resolvable via PATH.
    return (executable: override, prefixArgs: const <String>[]);
  }

  // 2. On PATH.
  final onPath = _which('leonard_cli');
  if (onPath != null) {
    return (executable: onPath, prefixArgs: const <String>[]);
  }

  // 3. Sibling lenny checkout entrypoint.
  final home = Platform.environment['HOME'];
  if (home != null) {
    final entry = File(
      '$home/development/engineering.memento/lenny/'
      'packages/leonard_cli/bin/leonard_cli.dart',
    );
    if (entry.existsSync()) {
      return (
        executable: _dartExecutable(),
        prefixArgs: <String>['run', entry.path],
      );
    }
  }
  return null;
}

String _dartExecutable() => Platform.resolvedExecutable;

String? _which(String name) {
  final pathEnv = Platform.environment['PATH'];
  if (pathEnv == null) return null;
  for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    final candidate = File('$dir${Platform.pathSeparator}$name');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

void main() {
  test('stock leonard_cli --extensions grid attaches to the_grid VM', () async {
    final leonard = _discoverLeonardCli();
    if (leonard == null) {
      markTestSkipped(
        r'leonard_cli not found (set $LEONARD_CLI or check out lenny at '
        '~/development/engineering.memento/lenny) — cross-process attach skipped.',
      );
      return;
    }

    // Launch the the_grid VM-service target.
    final target = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        'tool/attach_target.dart',
      ],
      // Test cwd is the package root.
      workingDirectory: Directory.current.path,
    );
    addTearDown(() => target.kill(ProcessSignal.sigterm));

    final wsUri = await _readVmUri(target).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw StateError('attach_target never printed GRID_VM_URI'),
    );

    // Point stock leonard at it. `--goal` keeps the run bounded; we only
    // assert the attach + handshake + observation succeed, which leonard does
    // before/while pursuing the goal. `--output` keeps leonard's trajectory in
    // a temp dir so an armed run never pollutes the package tree.
    final outDir = await Directory.systemTemp.createTemp('grid_leonard_attach_');
    addTearDown(() async {
      if (outDir.existsSync()) await outDir.delete(recursive: true);
    });
    final result = await Process.run(
      leonard.executable,
      <String>[
        ...leonard.prefixArgs,
        '--vm-uri', wsUri,
        '--extensions', 'grid',
        '--goal', 'read the grid ready set and stop',
        '--output', '${outDir.path}/trajectory.jsonl',
      ],
    ).timeout(const Duration(minutes: 3));

    final combined = '${result.stdout}\n${result.stderr}';

    // leonard inits its model provider BEFORE attaching: a missing inference
    // key surfaces as `config_error` / `missing required environment variable`
    // and the run returns 1 WITHOUT ever connecting. That is an un-armed
    // environment, not a Track-6 failure — skip rather than fail.
    final lower = combined.toLowerCase();
    final unarmed =
        lower.contains('missing required environment variable') ||
        lower.contains('config_error') ||
        lower.contains('api_key');
    final attached =
        lower.contains('handshake') ||
        lower.contains('extension') ||
        lower.contains('grid');
    if (unarmed && !attached) {
      markTestSkipped(
        'leonard_cli is present but its inference credentials are not armed '
        '(it bailed before attaching) — cross-process live attach skipped.',
      );
      return;
    }

    // Armed path: leonard reached the VM. The handshake found the grid
    // exploration host iff the host emits the `extensions` wire key (the
    // plugins->extensions rename, ADR-0000 A33). A `BindingNotInitialized`
    // would mean the handshake saw no extensions.
    expect(
      combined,
      isNot(contains('BindingNotInitialized')),
      reason: 'leonard must find the grid exploration host (extensions key)',
    );
    expect(
      lower,
      contains('grid'),
      reason: 'leonard should report the grid extension/namespace',
    );
  });
}

/// Read the `GRID_VM_URI=<ws://…>` sentinel line from the target's stdout.
Future<String> _readVmUri(Process target) {
  final completer = Completer<String>();
  late StreamSubscription<List<int>> sub;
  final buffer = StringBuffer();
  sub = target.stdout.listen((chunk) {
    buffer.write(String.fromCharCodes(chunk));
    final text = buffer.toString();
    final idx = text.indexOf('GRID_VM_URI=');
    if (idx >= 0) {
      final rest = text.substring(idx + 'GRID_VM_URI='.length);
      final end = rest.indexOf('\n');
      final uri = (end >= 0 ? rest.substring(0, end) : rest).trim();
      if (uri.isNotEmpty && !completer.isCompleted) {
        completer.complete(uri);
        unawaited(sub.cancel());
      }
    }
  });
  return completer.future;
}
