@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Cross-process exploration-attach conformance via the CREDENTIAL-FREE driver
/// (tg-e28 — the "leonard DEBUGS the_grid" half of the dogfood thesis).
///
/// Unlike [leonard_cli_attach_test], which drives lenny's autonomous LLM loop
/// (`leonard_cli`) and therefore *self-skips* whenever inference credentials
/// are not armed — leonard initializes its model provider BEFORE it attaches,
/// so a credential-less run never reaches the handshake — this test drives
/// `leonard_drive`, lenny's stateless VM-service driver that makes **zero model
/// calls**. Each `leonard_drive` subcommand connects, performs one operation,
/// prints JSON, and disconnects. That makes the attach deterministic and the
/// assertions strong: when lenny is present the test genuinely PASSES (it does
/// not skip), and it would FAIL if the grid exploration host regressed.
///
/// It launches `tool/attach_target.dart` under its own VM service (a real
/// [GridControllerRuntime] + [GridExplorationHost] over a fixed in-memory
/// snapshot: 3 beads, 2 ready — `tg-2`/`tg-3`), then points `leonard_drive` at
/// that ws:// URI and asserts the full read loop:
///
///   * `tools`  — handshake reports the `grid` namespace + its 5 tools;
///   * `observe`— `get_stable_observation` carries the live grid state under
///                `observation.extensions.grid.data` (readyCount 2, the two
///                ready bead ids);
///   * `invoke grid.ready` — returns `{ok:true, value:{count:2, …}}`.
///
/// **Self-skips** only when `leonard_drive` is not discoverable (lenny not
/// checked out / no `$LEONARD_DRIVE`). The offline suite (`dart test -x
/// integration`) never reaches it, keeping the_grid's own test run hermetic.
///
/// Discovery order for `leonard_drive` (mirrors [leonard_cli_attach_test]):
///   1. `$LEONARD_DRIVE` (absolute path to the executable/entrypoint, or a bare
///      command resolvable on `$PATH`);
///   2. a `leonard_drive` executable on `$PATH`;
///   3. the sibling lenny checkout's
///      `packages/leonard_cli/bin/leonard_drive.dart` (run via `dart run`) at
///      `~/development/engineering.memento/lenny`.

/// How to invoke `leonard_drive` once discovered.
typedef _DriveInvocation = ({
  String executable,
  List<String> prefixArgs,
  String? workingDirectory,
});

_DriveInvocation? _discoverLeonardDrive() {
  // 1. Explicit override.
  final override = Platform.environment['LEONARD_DRIVE'];
  if (override != null && override.trim().isNotEmpty) {
    final f = File(override);
    if (f.existsSync()) {
      return override.endsWith('.dart')
          ? (
              executable: _dartExecutable(),
              prefixArgs: <String>['run', override],
              workingDirectory: _packageRootOf(override),
            )
          : (
              executable: override,
              prefixArgs: const <String>[],
              workingDirectory: null,
            );
    }
    // Treat as a bare command name resolvable via PATH.
    return (
      executable: override,
      prefixArgs: const <String>[],
      workingDirectory: null,
    );
  }

  // 2. On PATH.
  final onPath = _which('leonard_drive');
  if (onPath != null) {
    return (
      executable: onPath,
      prefixArgs: const <String>[],
      workingDirectory: null,
    );
  }

  // 3. Sibling lenny checkout entrypoint.
  final home = Platform.environment['HOME'];
  if (home != null) {
    final entry = File(
      '$home/development/engineering.memento/lenny/'
      'packages/leonard_cli/bin/leonard_drive.dart',
    );
    if (entry.existsSync()) {
      return (
        executable: _dartExecutable(),
        prefixArgs: <String>['run', entry.path],
        workingDirectory: _packageRootOf(entry.path),
      );
    }
  }
  return null;
}

String _dartExecutable() => Platform.resolvedExecutable;

/// The package root for a `.dart` entrypoint — the nearest ancestor carrying a
/// resolved `.dart_tool/package_config.json` (lenny's pub-workspace root), so
/// `dart run <entry>` resolves leonard_drive's deps regardless of test cwd.
String? _packageRootOf(String dartFile) {
  var dir = File(dartFile).parent;
  while (true) {
    if (File('${dir.path}/.dart_tool/package_config.json').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

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
  late _DriveInvocation drive;
  late Process target;
  late String wsUri;

  setUpAll(() async {
    final discovered = _discoverLeonardDrive();
    if (discovered == null) return; // handled per-test via skip
    drive = discovered;

    // Launch the the_grid VM-service target (real host over a fixed snapshot).
    target = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        'tool/attach_target.dart',
      ],
      workingDirectory: Directory.current.path, // package root
    );
    wsUri = await _readVmUri(target).timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw StateError('attach_target never printed GRID_VM_URI'),
    );
  });

  tearDownAll(() {
    try {
      target.kill(ProcessSignal.sigterm);
    } on Object {
      // target may not have started (discovery skipped the run).
    }
  });

  /// Run one `leonard_drive` subcommand against [wsUri] and decode the single
  /// JSON object it prints to stdout.
  Future<Map<String, Object?>> driveJson(List<String> subArgs) async {
    final result = await Process.run(
      drive.executable,
      <String>[...drive.prefixArgs, ...subArgs, '--vm-uri', wsUri],
      workingDirectory: drive.workingDirectory,
    ).timeout(const Duration(seconds: 120));

    expect(
      result.exitCode,
      0,
      reason:
          'leonard_drive ${subArgs.join(' ')} exited ${result.exitCode}\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );

    // Machine output is a single JSON object on stdout; `dart run` compile
    // chatter (if any) goes to stderr. Parse the last JSON-object line.
    final lines = (result.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('{'))
        .toList();
    expect(
      lines,
      isNotEmpty,
      reason: 'no JSON object on stdout: ${result.stdout}',
    );
    return jsonDecode(lines.last) as Map<String, Object?>;
  }

  test('stock leonard_drive reads the grid host over ext.exploration.* '
      '(handshake + observe + invoke), credential-free', () async {
    final discovered = _discoverLeonardDrive();
    if (discovered == null) {
      markTestSkipped(
        r'leonard_drive not found (set $LEONARD_DRIVE or check out lenny at '
        '~/development/engineering.memento/lenny) — cross-process attach skipped.',
      );
      return;
    }

    // ---- handshake: the grid namespace + its tools ----
    final tools = await driveJson(<String>['tools']);
    final namespaces = (tools['namespaces'] as List)
        .cast<Map<String, Object?>>();
    final grid = namespaces.firstWhere(
      (n) => n['namespace'] == 'grid',
      orElse: () => throw StateError('handshake had no grid namespace: $tools'),
    );
    expect(
      (grid['tools'] as List).cast<String>(),
      containsAll(<String>['requery', 'snapshot', 'ready', 'events', 'stats']),
      reason: 'grid namespace must surface its 5 read tools',
    );

    // ---- observe: live grid state under extensions.grid ----
    final obs = await driveJson(<String>['observe']);
    final observation = obs['observation'] as Map<String, Object?>;
    final extensions = observation['extensions'] as Map<String, Object?>;
    final gridExt = extensions['grid'] as Map<String, Object?>;
    final data = gridExt['data'] as Map<String, Object?>;
    expect(data['beadCount'], 3);
    expect(data['readyCount'], 2);
    final readyIds = (data['readyBeads'] as List)
        .cast<Map<String, Object?>>()
        .map((b) => b['id'])
        .toSet();
    expect(readyIds, <String>{'tg-2', 'tg-3'});

    // ---- invoke grid.ready: the tool dispatch path ----
    final ready = await driveJson(<String>['invoke', '--tool', 'grid.ready']);
    final resultMap = ready['result'] as Map<String, Object?>;
    expect(resultMap['ok'], isTrue);
    final value = resultMap['value'] as Map<String, Object?>;
    expect(value['count'], 2);
    final invokedIds = (value['beads'] as List)
        .cast<Map<String, Object?>>()
        .map((b) => b['id'])
        .toSet();
    expect(invokedIds, <String>{'tg-2', 'tg-3'});
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
