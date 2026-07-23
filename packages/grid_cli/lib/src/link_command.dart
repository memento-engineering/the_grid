import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';

import 'station_stores.dart';

/// One observable work store in the composing station's armed roster.
class LinkEndpointStore {
  const LinkEndpointStore({required this.prefix, required this.store});

  final String prefix;
  final SubstationWorkStore store;
}

typedef LinkBdFactory = BdCliService Function(BeadsWorkspace workspace);

class LinkCommand extends Command<int> {
  LinkCommand({
    required this.stateStorePrefix,
    required Iterable<LinkEndpointStore> endpoints,
  }) : endpoints = List.unmodifiable(endpoints) {
    argParser
      ..addOption('grid-root')
      ..addMultiOption('prefix')
      ..addOption('blocked-by')
      ..addOption('reason')
      ..addOption('actor');
  }

  final String stateStorePrefix;
  final List<LinkEndpointStore> endpoints;

  @override
  final String name = 'link';

  @override
  final String description = 'Mint or list cross-repository links.';

  @override
  Future<int> run() => runLink(
    arguments: argResults!,
    stateStorePrefix: stateStorePrefix,
    endpoints: endpoints,
  );
}

class UnlinkCommand extends Command<int> {
  UnlinkCommand({
    required this.stateStorePrefix,
    required Iterable<LinkEndpointStore> endpoints,
  }) : endpoints = List.unmodifiable(endpoints) {
    argParser
      ..addOption('grid-root')
      ..addMultiOption('prefix')
      ..addOption('reason')
      ..addOption('actor');
  }

  final String stateStorePrefix;
  final List<LinkEndpointStore> endpoints;

  @override
  final String name = 'unlink';

  @override
  final String description = 'Close a cross-repository link.';

  @override
  Future<int> run() => runUnlink(
    arguments: argResults!,
    stateStorePrefix: stateStorePrefix,
    endpoints: endpoints,
  );
}

Future<int> runLink({
  required ArgResults arguments,
  required String stateStorePrefix,
  required Iterable<LinkEndpointStore> endpoints,
  void Function(String)? out,
  void Function(String)? err,
  DirectoryProbe? dirExists,
  LinkBdFactory? bdFactory,
}) async {
  final void Function(String) write =
      out ?? (message) => stdout.writeln(message);
  final void Function(String) writeErr =
      err ?? (message) => stderr.writeln(message);
  final roster = _roster(endpoints, writeErr, 'link');
  if (roster == null) return 64;

  if (arguments.rest.length == 1 && arguments.rest.single == 'ls') {
    if (_hasValue(arguments, 'blocked-by') ||
        _hasValue(arguments, 'reason') ||
        _hasValue(arguments, 'actor') ||
        arguments.multiOption('prefix').isNotEmpty) {
      writeErr('grid link ls: only --grid-root is accepted.');
      return 64;
    }
    final stateStore = _stateStore(arguments, writeErr, 'link ls');
    if (stateStore == null) return 64;
    try {
      final factory = bdFactory ?? _processBd;
      final stateWorkspace = openStateStore(stateStore, dirExists: dirExists);
      final state = await factory(stateWorkspace).exportAll();
      final statuses = <String, String>{};
      for (final endpoint in roster.values) {
        final workspace = openWorkStore(
          endpoint.store,
          substationName: endpoint.prefix,
          dirExists: dirExists,
        );
        final snapshot = await factory(workspace).exportAll();
        for (final bead in snapshot.beads) {
          statuses[bead.id] = bead.status.wire;
        }
      }
      final links =
          state.beads
              .where(
                (bead) => bead.issueType == IssueType.link && !bead.isClosed,
              )
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      for (final bead in links) {
        final from = _metadata(bead, CrossLinkKeys.from);
        final to = _metadata(bead, CrossLinkKeys.to);
        write(
          '${bead.id} $from [${statuses[from] ?? 'unobserved'}] '
          '--blocked-by $to [${statuses[to] ?? 'unobserved'}]',
        );
      }
      return 0;
    } on StoreRefusal catch (e) {
      writeErr('grid link ls: ${e.message}');
      return 1;
    }
  }

  if (arguments.rest.length != 1 || arguments.rest.single == 'ls') {
    writeErr('grid link: exactly one <from-bead> is required.');
    return 64;
  }
  final from = arguments.rest.single;
  final to = arguments.option('blocked-by')?.trim() ?? '';
  final reason = arguments.option('reason')?.trim() ?? '';
  final actor = arguments.option('actor')?.trim() ?? '';
  final stateStore = _stateStore(arguments, writeErr, 'link');
  if (to.isEmpty || reason.isEmpty || actor.isEmpty || stateStore == null) {
    writeErr(
      'grid link: --blocked-by, --reason, --actor, and --grid-root are required.',
    );
    return 64;
  }
  final armed = arguments.multiOption('prefix').toSet();
  if (armed.isEmpty) {
    writeErr('grid link: at least one --prefix is required.');
    return 64;
  }
  if (!_endpointsArmed(from, to, roster, armed, writeErr, 'link')) return 64;

  try {
    final workspace = openStateStore(stateStore, dirExists: dirExists);
    final bd = (bdFactory ?? _processBd)(workspace);
    final refusal = crossLinkTypeRefusal(
      await bd.types(),
      store: stateStore.beadsDir,
    );
    if (refusal != null) {
      writeErr(refusal);
      return 1;
    }
    final writer = StationBeadWriter(
      bd: bd,
      ownership: BeadOwnershipPredicate({...armed, stateStorePrefix}),
    );
    final id = await writer.createLink(
      substation: stateStorePrefix,
      from: from,
      to: to,
      reason: reason,
      actor: actor,
    );
    write(id);
    return 0;
  } on StoreRefusal catch (e) {
    writeErr('grid link: ${e.message}');
    return 1;
  } on OwnershipRefused catch (e) {
    writeErr('grid link: $e');
    return 1;
  }
}

Future<int> runUnlink({
  required ArgResults arguments,
  required String stateStorePrefix,
  required Iterable<LinkEndpointStore> endpoints,
  void Function(String)? out,
  void Function(String)? err,
  DirectoryProbe? dirExists,
  LinkBdFactory? bdFactory,
}) async {
  final void Function(String) write =
      out ?? (message) => stdout.writeln(message);
  final void Function(String) writeErr =
      err ?? (message) => stderr.writeln(message);
  final roster = _roster(endpoints, writeErr, 'unlink');
  if (roster == null) return 64;
  final reason = arguments.option('reason')?.trim() ?? '';
  final actor = arguments.option('actor')?.trim() ?? '';
  final stateStore = _stateStore(arguments, writeErr, 'unlink');
  final armed = arguments.multiOption('prefix').toSet();
  if ((arguments.rest.length != 1 && arguments.rest.length != 2) ||
      reason.isEmpty ||
      actor.isEmpty ||
      stateStore == null ||
      armed.isEmpty) {
    writeErr(
      'grid unlink: one <link-id> or <from> <to>, plus --grid-root, '
      '--prefix, --reason, and --actor are required.',
    );
    return 64;
  }
  if (!armed.contains(stateStorePrefix)) {
    writeErr(
      'grid unlink: state prefix "$stateStorePrefix" is not armed by --prefix.',
    );
    return 64;
  }
  if (arguments.rest.length == 2 &&
      !_endpointsArmed(
        arguments.rest[0],
        arguments.rest[1],
        roster,
        armed,
        writeErr,
        'unlink',
      )) {
    return 64;
  }

  try {
    final workspace = openStateStore(stateStore, dirExists: dirExists);
    final bd = (bdFactory ?? _processBd)(workspace);
    final export = await bd.exportAll();
    final matches = arguments.rest.length == 1
        ? export.beads
              .where((bead) => bead.id == arguments.rest.single)
              .toList()
        : export.beads
              .where(
                (bead) =>
                    bead.issueType == IssueType.link &&
                    !bead.isClosed &&
                    _metadata(bead, CrossLinkKeys.from) == arguments.rest[0] &&
                    _metadata(bead, CrossLinkKeys.to) == arguments.rest[1],
              )
              .toList();
    if (matches.length != 1) {
      writeErr(
        'grid unlink: expected exactly one matching open link; found '
        '${matches.length}.',
      );
      return 1;
    }
    final link = matches.single;
    if (link.issueType != IssueType.link || link.isClosed) {
      writeErr('grid unlink: ${link.id} is not an open type=link bead.');
      return 1;
    }
    if (BeadOwnershipPredicate.prefixOf(link.id) != stateStorePrefix) {
      writeErr(
        'grid unlink: ${link.id} is not owned by state prefix '
        '"$stateStorePrefix".',
      );
      return 1;
    }
    final writer = StationBeadWriter(
      bd: bd,
      ownership: BeadOwnershipPredicate({...armed, stateStorePrefix}),
    );
    await writer.close(link.id, reason: '$reason (unlink actor: $actor)');
    write(link.id);
    return 0;
  } on StoreRefusal catch (e) {
    writeErr('grid unlink: ${e.message}');
    return 1;
  } on OwnershipRefused catch (e) {
    writeErr('grid unlink: $e');
    return 1;
  }
}

BdCliService _processBd(BeadsWorkspace workspace) =>
    BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));

Map<String, LinkEndpointStore>? _roster(
  Iterable<LinkEndpointStore> endpoints,
  void Function(String) err,
  String verb,
) {
  final result = <String, LinkEndpointStore>{};
  for (final endpoint in endpoints) {
    if (endpoint.prefix.trim().isEmpty || result.containsKey(endpoint.prefix)) {
      err('grid $verb: duplicate or empty configured endpoint prefix.');
      return null;
    }
    result[endpoint.prefix] = endpoint;
  }
  return result;
}

GridStateStore? _stateStore(
  ArgResults arguments,
  void Function(String) err,
  String verb,
) {
  final root = arguments.option('grid-root')?.trim() ?? '';
  if (root.isEmpty) return null;
  try {
    return GridStateStore.forGridRoot(root);
  } on ArgumentError catch (e) {
    err('grid $verb: --grid-root ${e.message}');
    return null;
  }
}

bool _endpointsArmed(
  String from,
  String to,
  Map<String, LinkEndpointStore> roster,
  Set<String> armed,
  void Function(String) err,
  String verb,
) {
  for (final id in [from, to]) {
    final prefix = BeadOwnershipPredicate.prefixOf(id);
    if (prefix == null ||
        !roster.containsKey(prefix) ||
        !armed.contains(prefix)) {
      err(
        'grid $verb: endpoint "$id" has an absent, unrostered, or unarmed '
        'prefix; refusing before opening the state store.',
      );
      return false;
    }
  }
  return true;
}

bool _hasValue(ArgResults arguments, String name) =>
    (arguments.option(name)?.trim() ?? '').isNotEmpty;

String _metadata(Bead bead, String key) {
  final value = bead.metadata[key];
  return value is String ? value : '';
}
