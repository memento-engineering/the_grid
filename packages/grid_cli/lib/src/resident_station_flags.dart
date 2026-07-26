/// Shared configuration and flags for a composed resident station.
library;

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Operator-supplied appended substation identity.
class ResidentSubstationConfig {
  /// Creates an appended substation value.
  const ResidentSubstationConfig({
    required this.name,
    required this.root,
    required this.prefix,
  });

  /// The station-unique name.
  final String name;

  /// The absolute work-store root.
  final String root;

  /// The work store's issue-id prefix.
  final String prefix;
}

/// Parsed values passed to a resident delegate factory.
class ResidentStationConfig {
  /// Creates resident boot configuration.
  const ResidentStationConfig({
    required this.gridHome,
    required this.appended,
    required this.dryRun,
    required this.controlPort,
    required this.runFor,
    required this.harness,
    required this.buildHarness,
    required this.model,
    required this.graderModel,
    required this.maxAgents,
  });

  /// The absolute grid home containing `.grid/`.
  final String gridHome;

  /// The append-only operator roster layer.
  final List<ResidentSubstationConfig> appended;

  /// Whether all effect seams are inert.
  final bool dryRun;

  /// The station-control loopback port; zero requests an ephemeral port.
  final int controlPort;

  /// A bounded resident duration, or null to wait for a signal.
  final Duration? runFor;

  /// The ambient harness name.
  final String harness;

  /// The BUILD-only harness override, when selected.
  final String? buildHarness;

  /// The BUILD model override.
  final String? model;

  /// The GRADE model override.
  final String? graderModel;

  /// The station-wide work concurrency ceiling.
  final int maxAgents;
}

/// Adds the shared resident `up` flags; deliberately adds no `--bead`.
void residentStationFlags(
  ArgParser parser, {
  required List<String> codedNames,
  required Set<String> harnessAllowList,
}) {
  if (harnessAllowList.isEmpty) {
    throw ArgumentError.value(harnessAllowList, 'harnessAllowList');
  }
  final harnesses = harnessAllowList.toList()..sort();
  parser
    ..addMultiOption(
      'substation',
      abbr: 'r',
      help:
          'Append a substation to the coded roster (${codedNames.join(', ')}): '
          '<name>[@<prefix>]=<absolute-root>. Repeatable and append-only.',
    )
    ..addOption(
      'grid-home',
      abbr: 'g',
      help: 'Absolute grid home containing the state store and station lock.',
    )
    ..addOption('state-workspace', help: 'Alias for --grid-home.')
    ..addFlag(
      'dry-run',
      defaultsTo: true,
      help: 'Observe only: no writes, spawns, git, or delivery.',
    )
    ..addOption('for-seconds', help: 'Exit after this many seconds.')
    ..addOption(
      'control-port',
      defaultsTo: '0',
      help: 'Station-control loopback port; 0 chooses an ephemeral port.',
    )
    ..addOption(
      'harness',
      defaultsTo: harnesses.first,
      allowed: harnesses,
      help: 'Ambient agent harness.',
    )
    ..addOption(
      'build-harness',
      allowed: harnesses,
      help: 'BUILD-only harness override.',
    )
    ..addOption('model', help: 'BUILD model override.')
    ..addOption('grader-model', help: 'GRADE model override.')
    ..addOption(
      'max-agents',
      defaultsTo: '4',
      help: 'Station-wide concurrent-work ceiling.',
    );
}

/// Parses and validates the shared resident values.
ResidentStationConfig residentStationConfigFrom(
  ArgResults args, {
  required String stationName,
  required Set<String> codedNames,
}) {
  final gridHome = args.option('grid-home')?.trim();
  final stateWorkspace = args.option('state-workspace')?.trim();
  if (gridHome != null &&
      gridHome.isNotEmpty &&
      stateWorkspace != null &&
      stateWorkspace.isNotEmpty &&
      !p.equals(p.canonicalize(gridHome), p.canonicalize(stateWorkspace))) {
    throw FormatException(
      '--grid-home and --state-workspace must name the same root',
    );
  }
  final rawHome = gridHome?.isNotEmpty == true ? gridHome! : stateWorkspace;
  if (rawHome == null || rawHome.isEmpty) {
    throw FormatException('--grid-home is required');
  }
  if (!p.isAbsolute(rawHome)) {
    throw FormatException('--grid-home must be absolute: $rawHome');
  }

  final appended = <ResidentSubstationConfig>[];
  final seen = <String>{};
  for (final raw in args.multiOption('substation')) {
    if (raw.trim().isEmpty) continue;
    final parsed = _parseSubstation(raw, stationName: stationName);
    if (codedNames.contains(parsed.name)) {
      throw FormatException(
        '--substation "$raw" names coded substation "${parsed.name}"; '
        'flags append only',
      );
    }
    if (!seen.add(parsed.name)) {
      throw FormatException(
        '--substation "$raw" registers "${parsed.name}" more than once',
      );
    }
    appended.add(parsed);
  }

  final controlPort = _positiveInt(
    args.option('control-port')!,
    '--control-port',
    allowZero: true,
  );
  if (controlPort > 65535) {
    throw FormatException('--control-port must be at most 65535');
  }
  final seconds = args.option('for-seconds');
  final runSeconds = seconds == null
      ? null
      : _positiveInt(seconds, '--for-seconds');
  final maxAgents = _positiveInt(args.option('max-agents')!, '--max-agents');
  return ResidentStationConfig(
    gridHome: p.canonicalize(rawHome),
    appended: List.unmodifiable(appended),
    dryRun: args.flag('dry-run'),
    controlPort: controlPort,
    runFor: runSeconds == null ? null : Duration(seconds: runSeconds),
    harness: args.option('harness')!,
    buildHarness: args.option('build-harness'),
    model: args.option('model'),
    graderModel: args.option('grader-model'),
    maxAgents: maxAgents,
  );
}

ResidentSubstationConfig _parseSubstation(
  String raw, {
  required String stationName,
}) {
  final equals = raw.indexOf('=');
  if (equals < 0) {
    throw FormatException(
      '$stationName up: --substation "$raw" must be '
      '<name>[@<prefix>]=<root>',
    );
  }
  var name = raw.substring(0, equals).trim();
  final root = raw.substring(equals + 1).trim();
  var prefix = name;
  final at = name.indexOf('@');
  if (at >= 0) {
    prefix = name.substring(at + 1).trim();
    name = name.substring(0, at).trim();
  }
  if (name.isEmpty || prefix.isEmpty || root.isEmpty) {
    throw FormatException(
      '$stationName up: --substation "$raw" has an empty name, prefix, or root',
    );
  }
  if (name.contains('@') || prefix.contains('@') || !p.isAbsolute(root)) {
    throw FormatException(
      '$stationName up: --substation "$raw" must have one optional prefix '
      'and an absolute root',
    );
  }
  return ResidentSubstationConfig(
    name: name,
    root: p.canonicalize(root),
    prefix: prefix,
  );
}

int _positiveInt(String raw, String flag, {bool allowZero = false}) {
  final value = int.tryParse(raw);
  if (value == null || value < (allowZero ? 0 : 1)) {
    throw FormatException(
      '$flag must be ${allowZero ? 'a non-negative' : 'a positive'} integer',
    );
  }
  return value;
}
