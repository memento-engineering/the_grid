import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'station_command_client.dart';

/// Lists and resolves gates through the resident StationControl door.
///
/// For raw upstream inspection use `bd -C .grid list -t gate`; generic
/// `bd list --json` currently omits gate beads.
class GateCommand extends Command<int> {
  /// Creates the gate command with an optional injected resident client.
  GateCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    addSubcommand(GateLsCommand(client: _client));
    addSubcommand(GateResolveCommand(client: _client));
  }

  final StationCommandClient _client;

  @override
  final String name = 'gate';

  @override
  final String description =
      'List and resolve resident committee gates. For raw inspection use '
      '`bd -C .grid list -t gate`; generic `bd list --json` omits gates.';

  @override
  Future<int> run() async {
    printUsage();
    return 64;
  }
}

void _addGridRootOption(ArgParser parser) {
  parser.addOption(
    'grid-root',
    help: 'The grid HOME containing .grid/station.lock. Required.',
  );
}

String? _gridRoot(
  ArgResults args,
  void Function(String) writeErr,
  String verb,
) {
  final value = args.option('grid-root');
  if (value == null || value.trim().isEmpty) {
    writeErr('grid gate $verb: --grid-root is required.');
    return null;
  }
  if (!value.startsWith('/')) {
    writeErr('grid gate $verb: --grid-root must be an absolute path.');
    return null;
  }
  return value;
}

/// `grid gate ls` reads open gates from the resident snapshot.
class GateLsCommand extends Command<int> {
  /// Creates the list verb.
  GateLsCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    _addGridRootOption(argParser);
  }

  final StationCommandClient _client;

  @override
  final String name = 'ls';

  @override
  final String description =
      'List OPEN resident gates. Raw inspection: '
      '`bd -C .grid list -t gate` (`bd list --json` omits gates).';

  @override
  Future<int> run() async {
    final root = _gridRoot(argResults!, stderr.writeln, 'ls');
    if (root == null) return 64;
    return runGateLs(gridRoot: root, client: _client);
  }
}

/// `grid gate resolve <gate-id>` resolves one gate in the resident loop.
class GateResolveCommand extends Command<int> {
  /// Creates the resolve verb.
  GateResolveCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    _addGridRootOption(argParser);
    argParser
      ..addMultiOption('grade', help: 'A repeated <lane>=<A-F> ruling.')
      ..addOption('rationale', help: 'Required rationale for grade rulings.');
  }

  final StationCommandClient _client;

  @override
  final String name = 'resolve';

  @override
  final String description =
      'Resolve one OPEN gate through the resident StationControl door.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      stderr.writeln(
        rest.isEmpty
            ? 'grid gate resolve: a <gate-id> is required.'
            : 'grid gate resolve: resolve accepts exactly one gate id.',
      );
      return 64;
    }
    final root = _gridRoot(argResults!, stderr.writeln, 'resolve');
    if (root == null) return 64;
    return runGateResolve(
      gridRoot: root,
      gateId: rest.single,
      grades: argResults!.multiOption('grade'),
      rationale: argResults!.option('rationale'),
      client: _client,
    );
  }
}

/// Lists open gates through [client].
Future<int> runGateLs({
  required String gridRoot,
  required StationCommandClient client,
  void Function(String)? out,
  void Function(String)? err,
  DateTime? now,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/gate/ls',
    params: const {},
  );
  switch (result) {
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid gate ls: $message');
      return 64;
    case StationCommandCompleted(:final value):
      final raw = value['gates'];
      final gates = raw is List
          ? raw
                .whereType<Map<Object?, Object?>>()
                .map((row) => row.cast<String, Object?>())
                .toList()
          : <Map<String, Object?>>[];
      gates.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
      if (gates.isEmpty) {
        write('grid gate ls — no open gates.');
        return 0;
      }
      write(
        'grid gate ls — ${gates.length} open gate'
        '${gates.length == 1 ? '' : 's'}:',
      );
      final clock = now ?? DateTime.now();
      for (final gate in gates) {
        final id = gate['id'];
        final blocks = gate['blocks'] ?? '<no session>';
        final node = gate['node'] ?? '<no node>';
        final reason = '${gate['reason'] ?? ''}';
        final createdAt = DateTime.tryParse('${gate['createdAt'] ?? ''}');
        final regatedAt = DateTime.tryParse('${gate['regatedAt'] ?? ''}');
        final count = gate['regateCount'] is int
            ? gate['regateCount']! as int
            : int.tryParse('${gate['regateCount'] ?? ''}') ?? 0;
        final mark = count > 0 ? '  re-gated ${count}x' : '';
        write(
          '  $id  blocks $blocks  node $node  '
          'age ${_humanAge(regatedAt ?? createdAt, clock)}$mark'
          '${reason.isEmpty ? '' : '\n    reason: $reason'}',
        );
      }
      return 0;
  }
}

/// Resolves [gateId] through [client] after validating raw grade rulings.
Future<int> runGateResolve({
  required String gridRoot,
  required String gateId,
  required StationCommandClient client,
  List<String> grades = const [],
  String? rationale,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  final parsedGrades = <String, String>{};
  for (final raw in grades) {
    final eq = raw.indexOf('=');
    if (eq <= 0 || eq == raw.length - 1) {
      writeErr('grid gate resolve: --grade must be <lane>=<A-F> (got "$raw").');
      return 64;
    }
    final lane = raw.substring(0, eq).trim();
    final letter = raw.substring(eq + 1).trim().toUpperCase();
    if (lane.isEmpty || !_isGrade(letter)) {
      writeErr(
        'grid gate resolve: --grade "$raw" must name a lane and grade A–F.',
      );
      return 64;
    }
    if (parsedGrades.containsKey(lane)) {
      writeErr(
        'grid gate resolve: duplicate --grade lane "$lane" — refused; '
        'each authorization lane must be ruled exactly once.',
      );
      return 64;
    }
    parsedGrades[lane] = letter;
  }
  if (parsedGrades.isNotEmpty &&
      (rationale == null || rationale.trim().isEmpty)) {
    writeErr('grid gate resolve: --grade requires --rationale.');
    return 64;
  }
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/gate/resolve',
    params: {'gateId': gateId, 'grades': parsedGrades, 'rationale': rationale},
  );
  switch (result) {
    case StationCommandCompleted():
      write('grid gate resolve — closed gate $gateId.');
      return 0;
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid gate resolve: $message');
      return 64;
  }
}

bool _isGrade(String value) =>
    value.length == 1 &&
    value.codeUnitAt(0) >= 0x41 &&
    value.codeUnitAt(0) <= 0x46;

String _humanAge(DateTime? createdAt, DateTime now) {
  if (createdAt == null) return '?';
  var duration = now.difference(createdAt);
  if (duration.isNegative) duration = Duration.zero;
  if (duration.inDays > 0) {
    return '${duration.inDays}d${duration.inHours % 24}h';
  }
  if (duration.inHours > 0) {
    return '${duration.inHours}h${duration.inMinutes % 60}m';
  }
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return '${duration.inSeconds}s';
}
