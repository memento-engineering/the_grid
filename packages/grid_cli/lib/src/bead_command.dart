import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show
        BeadRoundAbsent,
        BeadRoundFound,
        BoardBeadRow,
        BoardRow,
        BoardStoreUnreadableRow,
        RoundContext;
import 'package:grid_trajectory/grid_trajectory.dart'
    show
        BeadRoundVerdicts,
        TrajectoryNotBootstrapped,
        TrajectoryOpened,
        TrajectoryOpener,
        TrajectoryUnavailable,
        foldBeadRound,
        openTrajectoryReader;

import 'operator_text_file.dart';
import 'station_command_client.dart';

/// Operator bead commands serviced by the resident station.
final class BeadCommand extends Command<int> {
  /// Creates the group. Every seam default-constructs, so a station runner
  /// composes all three verbs with one `..addCommand(BeadCommand())` line.
  BeadCommand({
    StationCommandClient? client,
    Stream<List<int>>? input,
    TrajectoryOpener? open,
  }) {
    addSubcommand(BeadSetCommand(client: client, input: input));
    addSubcommand(BeadBoardCommand(client: client));
    addSubcommand(BeadRoundCommand(client: client, open: open));
  }

  @override
  String get name => 'bead';

  @override
  String get description => 'Operate on resident-owned beads.';
}

void _addGridRootOption(ArgParser parser) {
  parser.addOption(
    'grid-root',
    help:
        'The grid HOME containing .grid/station.lock — and, for `round`, the '
        '.grid/.beads dolt sql-server hosting the trajectory log. Required.',
  );
}

String? _gridRoot(
  ArgResults args,
  void Function(String) writeErr,
  String verb,
) {
  final value = args.option('grid-root');
  if (value == null || value.trim().isEmpty) {
    writeErr('grid bead $verb: --grid-root is required.');
    return null;
  }
  if (!value.startsWith('/')) {
    writeErr('grid bead $verb: --grid-root must be an absolute path.');
    return null;
  }
  return value;
}

/// Writes bead prose exclusively from a file or stdin.
final class BeadSetCommand extends Command<int> {
  BeadSetCommand({StationCommandClient? client, Stream<List<int>>? input})
    : _client = client ?? StationCommandClient(),
      _input = input {
    argParser
      ..addOption('bead', mandatory: true)
      ..addOption(
        'field',
        mandatory: true,
        allowed: const ['description', 'design', 'acceptance', 'notes'],
      )
      ..addOption('file', mandatory: true)
      ..addFlag('append', negatable: false)
      ..addOption('grid-root', mandatory: true);
  }

  final StationCommandClient _client;
  final Stream<List<int>>? _input;

  @override
  String get name => 'set';

  @override
  String get description => 'Write bead prose from a UTF-8 file or stdin.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final root = args.option('grid-root')!;
    final field = args.option('field')!;
    final append = args.flag('append');
    if (!root.startsWith('/')) {
      stderr.writeln('grid bead set: --grid-root must be an absolute path.');
      return 64;
    }
    if (append && field != 'notes') {
      stderr.writeln('grid bead set: --append is valid only for notes.');
      return 64;
    }
    String content;
    try {
      content = (await selectOperatorText(
        inlineFlag: '--text',
        fileFlag: '--file',
        inlineValue: null,
        filePath: args.option('file'),
        input: _input,
      ))!;
    } on FileSystemException catch (error) {
      stderr.writeln(
        'grid bead set: cannot read --file ${args.option('file')}: ${error.message}',
      );
      return 64;
    } on FormatException catch (error) {
      stderr.writeln(
        'grid bead set: --file ${args.option('file')} is not valid UTF-8: ${error.message}',
      );
      return 64;
    }
    final result = await _client.send(
      gridRoot: root,
      method: 'grid/bead/set',
      params: {
        'beadId': args.option('bead')!,
        'field': field,
        'content': content,
        'append': append,
      },
    );
    switch (result) {
      case StationCommandCompleted():
        return 0;
      case StationCommandRefused(:final message):
        stderr.writeln('grid bead set: $message');
        return 1;
      case StationCommandUnavailable(:final message):
        stderr.writeln(
          'grid bead set: $message No direct fallback was attempted. '
          'Without the resident, description/design may use bd update '
          '--body-file, --design-file, or --stdin; acceptance/notes require the resident.',
        );
        return 69;
    }
  }
}

/// `grid bead board` — open work across every resident work store.
final class BeadBoardCommand extends Command<int> {
  /// Creates the board verb.
  BeadBoardCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    _addGridRootOption(argParser);
    argParser
      ..addMultiOption('store', help: 'Narrow to these substation stores.')
      ..addMultiOption('status', help: 'Narrow to these bead statuses.')
      ..addFlag(
        'blocked',
        negatable: false,
        help: 'Only beads carrying an open blocking edge.',
      )
      ..addFlag(
        'approved',
        negatable: false,
        help: 'Only approval-stamped beads.',
      )
      ..addFlag(
        'unapproved',
        negatable: false,
        help: 'Only beads without the approval stamp.',
      )
      ..addFlag('json', negatable: false, help: 'Emit the rows as JSON.');
  }

  final StationCommandClient _client;

  @override
  String get name => 'board';

  @override
  String get description =>
      'Show open work across every resident work store (read-only).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final root = _gridRoot(args, stderr.writeln, 'board');
    if (root == null) return 64;
    if (args.flag('approved') && args.flag('unapproved')) {
      stderr.writeln(
        'grid bead board: --approved and --unapproved are exclusive.',
      );
      return 64;
    }
    return runBeadBoard(
      gridRoot: root,
      client: _client,
      stores: args.multiOption('store'),
      statuses: args.multiOption('status'),
      blockedOnly: args.flag('blocked'),
      approved: args.flag('approved')
          ? true
          : (args.flag('unapproved') ? false : null),
      json: args.flag('json'),
    );
  }
}

/// `grid bead round <bead-id>` — this bead's current round and its lanes.
final class BeadRoundCommand extends Command<int> {
  /// Creates the round verb.
  BeadRoundCommand({StationCommandClient? client, TrajectoryOpener? open})
    : _client = client ?? StationCommandClient(),
      _open = open ?? openTrajectoryReader {
    _addGridRootOption(argParser);
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit the round as one JSON object.',
    );
  }

  final StationCommandClient _client;
  final TrajectoryOpener _open;

  @override
  String get name => 'round';

  @override
  String get description =>
      "Show one bead's current round: lane grades, rationales, the gating "
      'lane(s) and its validation_plan (read-only).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      stderr.writeln(
        rest.isEmpty
            ? 'grid bead round: a <bead-id> is required.'
            : 'grid bead round: round accepts exactly one bead id.',
      );
      return 64;
    }
    final root = _gridRoot(argResults!, stderr.writeln, 'round');
    if (root == null) return 64;
    return runBeadRound(
      gridRoot: root,
      beadId: rest.single,
      client: _client,
      open: _open,
      json: argResults!.flag('json'),
    );
  }
}

/// Reads the board through [client] and renders it.
Future<int> runBeadBoard({
  required String gridRoot,
  required StationCommandClient client,
  List<String> stores = const [],
  List<String> statuses = const [],
  bool blockedOnly = false,
  bool? approved,
  bool json = false,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final void Function(String) write = out ?? stdout.writeln;
  final void Function(String) writeErr = err ?? stderr.writeln;
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/bead/board',
    params: {
      'stores': stores,
      'statuses': statuses,
      'blocked': blockedOnly,
      'approved': approved,
    },
  );
  switch (result) {
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid bead board: $message');
      return 64;
    case StationCommandCompleted(:final value):
      final raw = value['rows'];
      final rows = <BoardRow>[
        if (raw is List)
          for (final row in raw.whereType<Map<Object?, Object?>>())
            BoardRow.fromJson(row.cast<String, dynamic>()),
      ];
      if (json) {
        write(jsonEncode([for (final row in rows) row.toJson()]));
        return 0;
      }
      renderBoard(rows, write);
      return 0;
  }
}

/// Renders [rows] as an aligned table; unreadable stores lead, LOUD.
void renderBoard(List<BoardRow> rows, void Function(String) write) {
  final beads = <BoardBeadRow>[];
  for (final row in rows) {
    switch (row) {
      case BoardBeadRow row:
        beads.add(row);
      case BoardStoreUnreadableRow row:
        write('!! ${row.store} (${row.root}) — ${row.reason}');
    }
  }
  if (beads.isEmpty) {
    write('grid bead board — no open beads.');
    return;
  }
  final cells = <List<String>>[
    const ['ID', 'STORE', 'TYPE', 'STATUS', 'APPROVED', 'BLOCKED-BY', 'TITLE'],
    for (final row in beads)
      [
        row.id,
        row.store,
        row.type,
        row.ready ? '${row.status}*' : row.status,
        row.approvedAt ?? '-',
        row.blockedBy.isEmpty ? '-' : row.blockedBy.join(','),
        row.title,
      ],
  ];
  final widths = <int>[
    for (var column = 0; column < cells.first.length; column++)
      cells
          .map((row) => row[column].length)
          .reduce((left, right) => left > right ? left : right),
  ];
  for (final row in cells) {
    final line = StringBuffer();
    for (var column = 0; column < row.length; column++) {
      line.write(
        column == row.length - 1
            ? row[column]
            : '${row[column].padRight(widths[column])}  ',
      );
    }
    write(line.toString());
  }
}

/// Reads one bead's round: the resident door for the bead facts, the
/// trajectory reader for the lane verdicts. No third path.
Future<int> runBeadRound({
  required String gridRoot,
  required String beadId,
  required StationCommandClient client,
  required TrajectoryOpener open,
  bool json = false,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final void Function(String) write = out ?? stdout.writeln;
  final void Function(String) writeErr = err ?? stderr.writeln;
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/bead/round',
    params: {'beadId': beadId},
  );
  final RoundContext context;
  switch (result) {
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid bead round: $message');
      return 64;
    case StationCommandCompleted(:final value):
      final raw = value['context'];
      if (raw is! Map) {
        writeErr('grid bead round: the resident returned no round context.');
        return 64;
      }
      context = RoundContext.fromJson(raw.cast<String, dynamic>());
  }
  BeadRoundVerdicts? verdicts;
  String? unavailable;
  if (context is BeadRoundFound) {
    final opened = await open(gridRoot);
    switch (opened) {
      case TrajectoryNotBootstrapped(:final message):
        unavailable = message;
      case TrajectoryUnavailable(:final message):
        writeErr('grid bead round: $message');
        return 1;
      case TrajectoryOpened(:final reader):
        try {
          verdicts = foldBeadRound(
            await reader.rowsForSubject(context.sessionId),
          );
        } finally {
          await reader.close();
        }
    }
  }
  if (json) {
    write(
      jsonEncode(
        beadRoundJson(
          context: context,
          verdicts: verdicts,
          unavailableReason: unavailable,
        ),
      ),
    );
    return 0;
  }
  renderBeadRound(
    context: context,
    verdicts: verdicts,
    unavailableReason: unavailable,
    write: write,
  );
  return 0;
}

/// The `--json` object: the resident's context plus the folded verdicts.
Map<String, Object?> beadRoundJson({
  required RoundContext context,
  BeadRoundVerdicts? verdicts,
  String? unavailableReason,
}) {
  final Map<String, Object?> source;
  if (verdicts != null) {
    source = verdicts.toJson();
  } else {
    source = switch (context) {
      BeadRoundAbsent(:final reason) => {
        'source': 'no_round',
        'reason': reason,
      },
      BeadRoundFound() => {
        'source': 'unavailable',
        'reason':
            unavailableReason ??
            'no trajectory database is bootstrapped on this grid home',
      },
    };
  }
  return {...context.toJson(), 'verdicts': source};
}

/// Renders one round for a terminal.
void renderBeadRound({
  required RoundContext context,
  required BeadRoundVerdicts? verdicts,
  required String? unavailableReason,
  required void Function(String) write,
}) {
  switch (context) {
    case BeadRoundAbsent(
      :final beadId,
      :final title,
      :final status,
      :final reason,
      :final validationPlan,
    ):
      write('$beadId  [$status]  $title');
      write('  round: none — $reason');
      write('  validation_plan: ${validationPlan ?? '<unset>'}');
    case BeadRoundFound(
      :final beadId,
      :final title,
      :final status,
      :final sessionId,
      :final round,
      :final validationPlan,
    ):
      write('$beadId  [$status]  $title');
      write('  round $round  ·  session $sessionId');
      write('  validation_plan: ${validationPlan ?? '<unset>'}');
      if (verdicts == null) {
        write(
          '  verdicts: unavailable — '
          '${unavailableReason ?? 'no trajectory database on this grid home'}',
        );
        return;
      }
      final route = verdicts.route;
      write(
        '  route: '
        '${route == null ? 'not ruled' : '${route.verdict} (${route.rule})'}',
      );
      if (verdicts.lanes.isEmpty) {
        write('  lanes: none recorded for this round.');
        return;
      }
      final gating = verdicts.gatingLanes.toSet();
      for (final lane in verdicts.lanes) {
        write(
          '  ${gating.contains(lane.lane) ? '>' : ' '} ${lane.grade}  '
          '${lane.lane}  (${lane.transport})',
        );
        write('      ${lane.rationale}');
      }
  }
}
