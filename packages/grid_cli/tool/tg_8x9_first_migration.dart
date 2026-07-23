import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';

const gridRoot = '/Users/nico/development/engineering.memento/space_station';
const tgRoot = '/Users/nico/development/engineering.memento/the_grid';

Future<void> main() async {
  final q9k = await Process.run('bd', [
    '-C',
    tgRoot,
    'show',
    'tg-q9k',
    '--json',
  ]);
  if (q9k.exitCode != 0) {
    stderr.write(q9k.stderr);
    exitCode = q9k.exitCode;
    return;
  }
  final q9kJson = jsonDecode(q9k.stdout.toString()) as List<dynamic>;
  final q9kIssue = q9kJson.single as Map<String, dynamic>;
  if (q9kIssue['status'] != 'closed') {
    stderr.writeln('refusing: tg-q9k is not observably closed');
    exitCode = 1;
    return;
  }

  final stateStore = GridStateStore.forGridRoot(gridRoot);
  final bd = BdCliService(
    ProcessBdRunner(workspaceRoot: stateStore.runtimeDir),
  );
  final snapshot = await bd.exportAll();
  final matches = snapshot.beads
      .where(
        (bead) =>
            bead.issueType == IssueType.link &&
            !bead.isClosed &&
            bead.metadata[CrossLinkKeys.from] == 'tg-8x9' &&
            bead.metadata[CrossLinkKeys.to] == 'tg-ama' &&
            bead.metadata[CrossLinkKeys.type] == kCrossLinkBlocks,
      )
      .toList();
  if (matches.length > 1) {
    stderr.writeln('refusing: duplicate inaugural links already exist');
    exitCode = 1;
    return;
  }

  var linkId = matches.isEmpty ? '' : matches.single.id;
  if (linkId.isEmpty) {
    final parser = ArgParser()
      ..addOption('grid-root')
      ..addMultiOption('prefix')
      ..addOption('blocked-by')
      ..addOption('reason')
      ..addOption('actor');
    final output = <String>[];
    final code = await runLink(
      arguments: parser.parse([
        'tg-8x9',
        '--blocked-by',
        'tg-ama',
        '--grid-root',
        gridRoot,
        '--prefix',
        'houston',
        '--prefix',
        'tg',
        '--actor',
        'build',
        '--reason',
        'tg-8x9 verb half waits on landed tg-ama engine half',
      ]),
      stateStorePrefix: 'houston',
      endpoints: const [
        LinkEndpointStore(
          prefix: 'tg',
          store: SubstationWorkStore(root: tgRoot),
        ),
      ],
      out: output.add,
      err: stderr.writeln,
    );
    if (code != 0 || output.length != 1) {
      exitCode = code == 0 ? 1 : code;
      return;
    }
    linkId = output.single;
  }

  final note =
      'First-migration receipt: the requested tg-q9k -> pow-60g '
      'link was not reminted because tg-q9k closed in PR #76 and pow-60g is '
      'not observable from the armed tg roster. Inaugural live Houston link: '
      '$linkId (tg-8x9 blocked by tg-ama).';
  final existingNotes = q9kIssue['notes']?.toString() ?? '';
  if (!existingNotes.contains(note)) {
    final update = await Process.run('bd', [
      '-C',
      tgRoot,
      'update',
      'tg-q9k',
      '--actor',
      'build',
      '--append-notes',
      note,
    ]);
    if (update.exitCode != 0) {
      stderr.write(update.stderr);
      exitCode = update.exitCode;
      return;
    }
  }
  stdout.writeln(jsonEncode({'link_id': linkId, 'note': note}));
}
