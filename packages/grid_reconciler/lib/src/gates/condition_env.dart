import 'dart:io';

import 'package:path/path.dart' as p;

/// The fallback PATH for gate-script execution — byte-identical to gc's
/// `SafePATH` (condition.go:20).
const String safePath = '/usr/local/bin:/usr/bin:/bin';

/// The tool names whose containing dirs are prepended to the gate `PATH`, in
/// gc's lookup order (condition.go:44): gate scripts use the running city's
/// `bd`/`gc`/`dolt`/`jq`, not stale copies in `/usr/local/bin`.
const List<String> conditionPathTools = <String>['bd', 'gc', 'dolt', 'jq'];

/// Ambient Dolt/Beads connection vars passed through to the child, **only when
/// set**, in exactly gc's order (condition.go:132-147). Load-bearing for any
/// gate that shells out to `bd` under Dolt server mode.
const List<String> doltPassthroughKeys = <String>[
  'BEADS_DOLT_AUTO_START',
  'BEADS_DOLT_SERVER_HOST',
  'BEADS_DOLT_SERVER_PORT',
  'BEADS_DOLT_SERVER_USER',
  'BEADS_DOLT_PASSWORD',
  'GC_DOLT',
  'GC_DOLT_HOST',
  'GC_DOLT_PORT',
  'GC_DOLT_USER',
  'GC_DOLT_PASSWORD',
];

/// Resolves an executable name to its directory via the ambient `PATH`, the
/// `conditionPATH` seam standing in for Go `exec.LookPath` (condition.go:45).
/// Returns null when the tool isn't found.
///
/// Injectable so [ConditionEnv.environ] is testable without mutating the real
/// process `PATH` (the Dart port can't `setenv`; conformance-gate-tests trap
/// #1). The default [systemLookPathDir] walks the real `PATH`.
typedef LookPathDir = String? Function(String name);

/// Default [LookPathDir]: walks [pathValue]'s `:`-separated entries and returns
/// the directory of the first entry containing an executable [name]. Mirrors
/// `exec.LookPath` enough for `conditionPATH` (we only need the *dir*, and gc
/// dedups dirs anyway).
String? systemLookPathDir(String name, {String? pathValue}) {
  final raw = pathValue ?? Platform.environment['PATH'] ?? '';
  for (final dir in raw.split(':')) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, name);
    final stat = FileStat.statSync(candidate);
    if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
      return dir;
    }
  }
  return null;
}

/// Port of `conditionPATH()` (condition.go:31-53): an ordered, **deduplicated**
/// `:`-join of the dirs containing [conditionPathTools] (in order, missing
/// tools skipped) followed by the [safePath] components.
///
/// [lookPathDir] is the [LookPathDir] seam — tests inject a map-backed resolver;
/// production passes [systemLookPathDir].
String conditionPath(LookPathDir lookPathDir) {
  final dirs = <String>[];
  final seen = <String>{};
  void addDir(String? dir) {
    if (dir == null || dir.isEmpty) return;
    if (!seen.add(dir)) return;
    dirs.add(dir);
  }

  for (final name in conditionPathTools) {
    addDir(lookPathDir(name));
  }
  for (final dir in safePath.split(':')) {
    addDir(dir);
  }
  return dirs.join(':');
}

/// Port of gc's `ConditionEnv` (condition.go:55-73): the inputs the gate runner
/// assembles into the child-process env whitelist. A plain immutable value type
/// (no freezed — Track A's generated types are reused where they exist; this is
/// a Track-D-internal assembler, not a wire type).
///
/// All bead-derived values reach the script as **env vars**, never interpolated
/// into a command line (condition.go:55-56). [environ] builds the whitelist.
class ConditionEnv {
  const ConditionEnv({
    this.beadId = '',
    this.iteration = 0,
    this.cityPath = '',
    this.storePath = '',
    this.workDir = '',
    this.wispId = '',
    this.docPath = '',
    this.moleculeDir = '',
    this.artifactDir = '',
    this.iterationDurationMs = 0,
    this.cumulativeDurationMs = 0,
    this.maxIterations = 0,
    this.agentVerdict = '',
    this.agentProvider = '',
    this.agentModel = '',
  });

  final String beadId;
  final int iteration;
  final String cityPath;
  final String storePath;
  final String workDir;
  final String wispId;

  /// `var.doc_path`, may be empty → `GC_DOC_PATH` omitted (condition.go:64).
  final String docPath;

  /// `molecule.Dir(...)`, may be empty for non-molecule beads (condition.go:65).
  final String moleculeDir;

  /// Per-step artifact dir; `GC_ARTIFACT_DIR` omitted when empty (the
  /// sling-time contract, condition.go:66).
  final String artifactDir;

  final int iterationDurationMs;
  final int cumulativeDurationMs;
  final int maxIterations;

  /// Normalized verdict, may be empty → `GC_AGENT_VERDICT` omitted
  /// (condition.go:70). Hybrid mode is the only path that populates it.
  final String agentVerdict;
  final String agentProvider;
  final String agentModel;

  /// A copy with [agentVerdict] replaced — the single place hybrid mode injects
  /// the verdict into the child env (`env.AgentVerdict = verdict`, hybrid.go:14).
  ConditionEnv withAgentVerdict(String verdict) => ConditionEnv(
    beadId: beadId,
    iteration: iteration,
    cityPath: cityPath,
    storePath: storePath,
    workDir: workDir,
    wispId: wispId,
    docPath: docPath,
    moleculeDir: moleculeDir,
    artifactDir: artifactDir,
    iterationDurationMs: iterationDurationMs,
    cumulativeDurationMs: cumulativeDurationMs,
    maxIterations: maxIterations,
    agentVerdict: verdict,
    agentProvider: agentProvider,
    agentModel: agentModel,
  );

  /// The working directory for the gate process, precedence **WorkDir >
  /// StorePath > CityPath** (condition.go:320-326). Sequential overrides —
  /// easy to invert (gates-exec.md trap #12).
  String get workingDirectory {
    var dir = cityPath;
    if (storePath.isNotEmpty) dir = storePath;
    if (workDir.isNotEmpty) dir = workDir;
    return dir;
  }

  /// Port of `ConditionEnv.Environ()` (condition.go:79-150): the child-process
  /// env as a **whitelist built from scratch** — the parent env is NOT
  /// inherited; only the listed ambient vars are read through [ambient].
  /// `GC_CONTROLLER_TOKEN` is therefore never present (the security sandbox,
  /// gates-exec.md trap #10).
  ///
  /// [ambient] stands in for `os.Getenv` (the Dolt/Beads passthrough +
  /// `GC_INTEGRATION_REAL_BD`); [lookPathDir] feeds [conditionPath]; [tempDir]
  /// stands in for `os.TempDir()`. All three are seams so the contract is
  /// asserted without touching the real process env (conformance-gate-tests
  /// trap #1).
  ///
  /// Returns an **ordered** `Map<String,String>` (insertion order preserved) so
  /// the de-facto append-order contract (gates-exec.md §1, trap "ordering") is
  /// observable for fixtures.
  Map<String, String> environ({
    required Map<String, String> ambient,
    required LookPathDir lookPathDir,
    required String tempDir,
  }) {
    // HOME sandboxes scripts away from the controller's ~ (which may hold
    // .ssh/.gnupg); empty cityPath → temp dir (condition.go:80-85).
    final home = cityPath.isNotEmpty ? cityPath : tempDir;
    // BEADS_DIR uses StorePath when set, else CityPath (condition.go:86-89).
    final beadsBase = storePath.isNotEmpty ? storePath : cityPath;

    final env = <String, String>{
      'PATH': conditionPath(lookPathDir),
      'HOME': home,
      'TMPDIR': tempDir,
      'BEADS_DIR': p.join(beadsBase, '.beads'),
      'GC_BEAD_ID': beadId,
      'GC_ITERATION': '$iteration',
      'GC_WISP_ID': wispId,
      'GC_ITERATION_DURATION_MS': '$iterationDurationMs',
      'GC_CUMULATIVE_DURATION_MS': '$cumulativeDurationMs',
      'GC_MAX_ITERATIONS': '$maxIterations',
      // citylayout.CityRuntimeEnvForRuntimeDir (runtime.go:121-132) emits all
      // FOUR vars in this append order (gates-exec.md §1a rows 11-14). The
      // GC_CITY_RUNTIME_DIR default is the canonical <cityPath>/.gc/runtime;
      // the ambient trusted-override path (runtime.go:194-205) is dropped (no
      // ambient anchor on the canonical reconciler path → TrustedAmbient
      // returns "" → the canonical dir is used).
      'GC_CITY': cityPath,
      'GC_CITY_PATH': cityPath,
      'GC_CITY_RUNTIME_DIR': p.join(cityPath, '.gc', 'runtime'),
      // GC_CONTROL_DISPATCHER_TRACE_DEFAULT companion (runtime.go:130). On the
      // canonical path runtimeDir == <cityPath>/.gc/runtime, which is within
      // <cityPath>/.gc, so normalizeRuntimeDir (runtime.go:207-214) leaves it
      // unchanged → <cityPath>/.gc/runtime/control-dispatcher-trace.log
      // (runtime.go:38-41). Emitted right after GC_CITY_RUNTIME_DIR to
      // preserve gc's slice order (the de-facto fixture contract,
      // gates-exec.md §1e ⚠ordering).
      'GC_CONTROL_DISPATCHER_TRACE_DEFAULT': p.join(
        cityPath,
        '.gc',
        'runtime',
        'control-dispatcher-trace.log',
      ),
    };

    // Optional fields: included only when non-empty (absent ≠ empty — a real
    // gate script using `${VAR+set}`/`-z` distinguishes; trap #2). Order
    // matches condition.go:104-128.
    void putIf(String key, String value) {
      if (value.isNotEmpty) env[key] = value;
    }

    putIf('GC_DOC_PATH', docPath);
    putIf('GC_AGENT_VERDICT', agentVerdict);
    putIf('GC_AGENT_PROVIDER', agentProvider);
    putIf('GC_AGENT_MODEL', agentModel);
    putIf('GC_WORK_DIR', workDir);
    putIf('GC_STORE_PATH', storePath);
    putIf('GC_ARTIFACT_DIR', artifactDir);
    putIf('GC_MOLECULE_DIR', moleculeDir);

    // Integration bd-shim passthrough, then the Dolt/Beads set — each only
    // when set in the ambient env (condition.go:129-147).
    final realBd = ambient['GC_INTEGRATION_REAL_BD'];
    if (realBd != null && realBd.isNotEmpty) {
      env['GC_INTEGRATION_REAL_BD'] = realBd;
    }
    for (final key in doltPassthroughKeys) {
      final value = ambient[key];
      if (value != null && value.isNotEmpty) env[key] = value;
    }

    return env;
  }
}
