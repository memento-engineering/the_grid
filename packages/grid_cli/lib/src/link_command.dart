import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';

import 'station_stores.dart';
import 'operator_text_file.dart';

/// One observable work store in the composing station's armed roster.
class LinkEndpointStore {
  const LinkEndpointStore({
    required this.name,
    required this.prefix,
    required this.store,
  });

  /// The substation's ROSTER NAME — the `<project>` token an
  /// `external:<project>:<capability>` row carries, and the same token bd
  /// resolves through its own `external_projects` config.
  final String name;

  /// The substation's bead-id prefix — how an endpoint id resolves to a store.
  final String prefix;

  final SubstationWorkStore store;
}

typedef LinkBdFactory = BdCliService Function(BeadsWorkspace workspace);

class LinkCommand extends Command<int> {
  LinkCommand({required Iterable<LinkEndpointStore> endpoints})
    : endpoints = List.unmodifiable(endpoints) {
    argParser
      ..addOption('blocked-by')
      ..addFlag('json', negatable: false);
  }

  final List<LinkEndpointStore> endpoints;

  @override
  final String name = 'link';

  @override
  final String description =
      'Wire a cross-store blocker as a bd external dependency. '
      '$kExternalDepSugarRule';

  @override
  Future<int> run() => runLink(arguments: argResults!, endpoints: endpoints);
}

/// What the `link` verb is, stated where an operator reads it.
const kExternalDepSugarRule =
    'Convenience only: it labels the target `export:<target>` and runs '
    '`bd dep add <from> external:<project>:<target>`. It performs nothing '
    '`bd dep` does not, and mints no bead. The edge lifts when the target '
    'ships — `bd ship <target>` on a CLOSED target.';

class UnlinkCommand extends Command<int> {
  UnlinkCommand({
    required this.stateStorePrefix,
    required Iterable<LinkEndpointStore> endpoints,
    Stream<List<int>>? input,
  }) : endpoints = List.unmodifiable(endpoints),
       _input = input {
    argParser
      ..addOption('grid-root')
      ..addMultiOption(
        'prefix',
        help:
            'Repeatable; must include the state prefix and, for <from> <to>, '
            'every endpoint prefix.',
      )
      ..addOption('reason')
      ..addOption('reason-file')
      ..addOption('actor');
  }

  final String stateStorePrefix;
  final List<LinkEndpointStore> endpoints;
  final Stream<List<int>>? _input;

  @override
  final String name = 'unlink';

  @override
  final String description = 'Close a cross-repository link.';

  @override
  Future<int> run() => runUnlink(
    arguments: argResults!,
    stateStorePrefix: stateStorePrefix,
    endpoints: endpoints,
    input: _input,
  );
}

/// `grid link <from> --blocked-by <to>` — SUGAR over `bd dep add` (tg-xh5d,
/// `the_grid#the-grid-is-a-beads-controller`).
///
/// Three bd writes and nothing else: the target is labelled
/// `export:<target>` if it is not already, and the consumer gains the
/// dependency row `external:<project>:<target>`, where `<project>` is the
/// target substation's ROSTER NAME. No bead is minted; the station's own
/// state store is never touched.
///
/// `grid link ls` lists the external rows the roster's stores carry.
Future<int> runLink({
  required ArgResults arguments,
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
  final isList = arguments.rest.length == 1 && arguments.rest.single == 'ls';
  final json = arguments.flag('json');
  if (json && !isList) {
    writeErr('grid link: --json is accepted only by link ls.');
    return 64;
  }
  final roster = _roster(endpoints, writeErr, 'link');
  if (roster == null) return 64;
  final factory = bdFactory ?? _processBd;

  if (isList) {
    if (_hasValue(arguments, 'blocked-by')) {
      writeErr('grid link ls: only --json is accepted.');
      return 64;
    }
    try {
      final probes = _StoreProbes(factory, dirExists);
      final rows = <Map<String, String>>[];
      for (final endpoint in roster.values) {
        rows.addAll(await _externalRowsOf(endpoint, roster, probes));
      }
      rows.sort((a, b) {
        final byFrom = a['from']!.compareTo(b['from']!);
        return byFrom != 0 ? byFrom : a['to']!.compareTo(b['to']!);
      });
      if (json) {
        write(jsonEncode(rows));
      } else {
        for (final row in rows) {
          write(
            '${row['from']} [${row['fromStatus']}] --blocked-by '
            '${row['to']} — ${row['edgeState']}',
          );
        }
      }
      return 0;
    } on StoreRefusal catch (e) {
      writeErr('grid link ls: ${e.message}');
      return 1;
    } on BdException catch (e) {
      writeErr('grid link ls: ${e.message}');
      return 1;
    }
  }

  if (arguments.rest.length != 1) {
    writeErr('grid link: exactly one <from-bead> is required.');
    return 64;
  }
  final from = arguments.rest.single;
  final to = arguments.option('blocked-by')?.trim() ?? '';
  if (to.isEmpty) {
    writeErr('grid link: --blocked-by is required.');
    return 64;
  }
  final consumer = _endpointOf(from, roster, writeErr, 'link');
  final provider = _endpointOf(to, roster, writeErr, 'link');
  if (consumer == null || provider == null) return 64;
  if (identical(consumer, provider)) {
    // A same-store blocker needs nothing this verb adds: bd's own dependency
    // row already blocks it, and a self-referential `external:` row is one no
    // store can resolve. The grid adds only what bd lacks.
    writeErr(
      'grid link: "$from" and "$to" are both in substation '
      '"${consumer.name}" — a same-store blocker is a plain '
      '`bd dep add $from $to`, not a cross-project capability.',
    );
    return 64;
  }

  try {
    final providerBd = factory(
      openWorkStore(
        provider.store,
        substationName: provider.name,
        dirExists: dirExists,
      ),
    );
    final providerProbe = await _probeReader(providerBd);
    final target = await providerProbe.reader.beadById(
      to,
      types: providerProbe.types,
    );
    if (target == null) {
      writeErr(
        'grid link: "$to" is not observable in substation '
        '"${provider.name}" — nothing to export.',
      );
      return 1;
    }
    final label = exportLabel(to);
    if (!target.labels.contains(label)) {
      await providerBd.addLabels(to, [label]);
    }

    final consumerBd = factory(
      openWorkStore(
        consumer.store,
        substationName: consumer.name,
        dirExists: dirExists,
      ),
    );
    final ref = ExternalDepRef(project: provider.name, capability: to);
    await consumerBd.depAdd(from, ref.wire);

    final configRefusal = externalProjectConfigRefusal(
      project: provider.name,
      configured: await consumerBd.externalProjects(),
      store: consumer.store.root,
    );
    if (configRefusal != null) writeErr(configRefusal);

    write('$from --blocked-by ${ref.wire}');
    return 0;
  } on StoreRefusal catch (e) {
    writeErr('grid link: ${e.message}');
    return 1;
  } on BdException catch (e) {
    writeErr('grid link: ${e.message}');
    return 1;
  }
}

/// One opened bd service + type set per endpoint, for the whole `link ls`
/// pass.
///
/// Every store's `bd types` discovery is a process spawn, and the listing
/// consults a target store once per ROW; without this, a roster with a fan-in
/// re-probes the same store N times for one listing.
class _StoreProbes {
  _StoreProbes(this._factory, this._dirExists);

  final LinkBdFactory _factory;
  final DirectoryProbe? _dirExists;
  final Map<String, _StoreProbe> _opened = {};

  Future<_StoreProbe> of(LinkEndpointStore endpoint) async {
    final cached = _opened[endpoint.name];
    if (cached != null) return cached;
    final bd = _factory(
      openWorkStore(
        endpoint.store,
        substationName: endpoint.name,
        dirExists: _dirExists,
      ),
    );
    final probe = await _probeReader(bd);
    return _opened[endpoint.name] = (
      bd: bd,
      reader: probe.reader,
      types: probe.types,
    );
  }
}

typedef _StoreProbe = ({
  BdCliService bd,
  CliBeadProbeReader reader,
  Set<IssueType> types,
});

/// Every `external:` dependency row [endpoint]'s store carries on an OPEN
/// bead, with the edge's current state.
///
/// Open-scoped by construction: a consumer still waiting on a capability is
/// open, so a closed bead's historical row is not an edge anyone is held by.
Future<List<Map<String, String>>> _externalRowsOf(
  LinkEndpointStore endpoint,
  Map<String, LinkEndpointStore> roster,
  _StoreProbes probes,
) async {
  final probe = await probes.of(endpoint);
  final open = await probe.reader.openBeads(types: probe.types);
  if (open.isEmpty) return const [];
  final statusOf = {for (final bead in open) bead.id: bead.status.wire};
  final deps = await probe.bd.depList([for (final bead in open) bead.id]);
  final rows = <Map<String, String>>[];
  for (final dep in deps) {
    if (!dep.type.affectsBlocking) continue;
    final ref = ExternalDepRef.parse(dep.dependsOnId);
    if (ref == null) continue;
    final target = roster.values
        .where((candidate) => candidate.name == ref.project)
        .firstOrNull;
    rows.add({
      'from': dep.issueId,
      'fromStatus': statusOf[dep.issueId] ?? 'unobserved',
      'to': ref.wire,
      'project': ref.project,
      'edgeState': target == null
          ? 'UNARMED (no "${ref.project}" substation)'
          : await _capabilityState(target, ref.capability, probes),
    });
  }
  return rows;
}

/// Whether [capability] is SHIPPED in [endpoint]'s store — the FRONTIER's
/// reading, so the verb and the engine never disagree about one edge.
///
/// Shipped means what [capabilityShipped] means: the store holds a CLOSED bead
/// carrying `provides:<capability>`. That is a LABEL scan, not an id lookup,
/// so a NAMED (fan-in) capability — a container bead whose own id is not the
/// capability — reads SHIPPED exactly when the frontier admits its consumers.
///
/// Only when the capability is unshipped is its id-shaped convention consulted,
/// and then only to say WHY: by convention the capability IS the exporting
/// bead's id, so naming that bead's status is the useful answer; a named
/// capability resolves to no bead and says so.
Future<String> _capabilityState(
  LinkEndpointStore endpoint,
  String capability,
  _StoreProbes probes,
) async {
  final probe = await probes.of(endpoint);
  final providers = await probe.bd.query(
    'label=${providesLabel(capability)}',
    includeClosed: true,
  );
  if (capabilityShipped(capability, providers)) return 'SHIPPED (inert)';
  final exporter = await probe.reader.beadById(capability, types: probe.types);
  return exporter == null
      ? 'PENDING (unshipped)'
      : 'PENDING (${exporter.status.wire})';
}

/// The endpoint owning [id], or `null` after reporting why none does.
LinkEndpointStore? _endpointOf(
  String id,
  Map<String, LinkEndpointStore> roster,
  void Function(String) err,
  String verb,
) {
  final prefix = BeadOwnershipPredicate.ownedPrefixOf(id, roster.keys);
  if (prefix == null) {
    err(
      'grid $verb: endpoint "$id" has no prefix in the configured endpoint '
      'roster (${roster.keys.join(', ')}).',
    );
    return null;
  }
  return roster[prefix];
}

Future<int> runUnlink({
  required ArgResults arguments,
  required String stateStorePrefix,
  required Iterable<LinkEndpointStore> endpoints,
  void Function(String)? out,
  void Function(String)? err,
  DirectoryProbe? dirExists,
  LinkBdFactory? bdFactory,
  Stream<List<int>>? input,
}) async {
  final void Function(String) write =
      out ?? (message) => stdout.writeln(message);
  final void Function(String) writeErr =
      err ?? (message) => stderr.writeln(message);
  final roster = _roster(endpoints, writeErr, 'unlink');
  if (roster == null) return 64;
  final String? reason;
  final reasonFile = arguments.options.contains('reason-file')
      ? arguments.option('reason-file')
      : null;
  try {
    reason = await selectOperatorText(
      inlineFlag: '--reason',
      fileFlag: '--reason-file',
      inlineValue: arguments.option('reason'),
      filePath: reasonFile,
      input: input,
    );
  } on OperatorTextUsage catch (error) {
    writeErr('grid unlink: ${error.message}.');
    return 64;
  } on FileSystemException catch (error) {
    writeErr(
      'grid unlink: cannot read --reason-file $reasonFile: ${error.message}',
    );
    return 64;
  } on FormatException catch (error) {
    writeErr(
      'grid unlink: --reason-file $reasonFile is not valid UTF-8: ${error.message}',
    );
    return 64;
  }
  final actor = arguments.option('actor')?.trim() ?? '';
  final stateStore = _stateStore(arguments, writeErr, 'unlink');
  final armed = arguments.multiOption('prefix').toSet();
  if ((arguments.rest.length != 1 && arguments.rest.length != 2) ||
      reason == null ||
      reason.trim().isEmpty ||
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
    final probe = await _probeReader(bd);
    final matches = arguments.rest.length == 1
        ? [
            await probe.reader.beadById(
              arguments.rest.single,
              types: probe.types,
            ),
          ].whereType<Bead>().toList()
        : await _openLinkBeads(
            probe,
            metadataAll: {
              CrossLinkKeys.from: arguments.rest[0],
              CrossLinkKeys.to: arguments.rest[1],
            },
          );
    if (matches.length != 1) {
      writeErr(
        'grid unlink: expected exactly one matching open link; found '
        '${matches.length}.',
      );
      return 1;
    }
    final link = matches.single;
    if (link.issueType != GridIssueTypes.link || link.isClosed) {
      writeErr('grid unlink: ${link.id} is not an open type=link bead.');
      return 1;
    }
    if (BeadOwnershipPredicate.ownedPrefixOf(link.id, {stateStorePrefix}) !=
        stateStorePrefix) {
      writeErr(
        'grid unlink: ${link.id} is not owned by state prefix '
        '"$stateStorePrefix".',
      );
      return 1;
    }
    final writer = StationBeadWriter(
      bd: bd,
      reader: probe.reader,
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
  } on BdException catch (e) {
    writeErr('grid unlink: ${e.message}');
    return 1;
  }
}

BdCliService _processBd(BeadsWorkspace workspace) =>
    BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));

Future<({CliBeadProbeReader reader, Set<IssueType> types})> _probeReader(
  BdCliService bd,
) async {
  final data = await bd.types();
  final names = configuredBdTypeNames(
    data,
    fields: const <String>['core_types', 'custom_types'],
  );
  if (names.isEmpty) {
    throw const BdParseException('bd type discovery was empty');
  }
  final types = {for (final name in names) IssueType(name)};
  return (reader: CliBeadProbeReader(bd, lifecycleTypes: types), types: types);
}

Future<List<Bead>> _openLinkBeads(
  ({CliBeadProbeReader reader, Set<IssueType> types}) probe, {
  Map<String, String> metadataAll = const {},
}) async {
  // A scoped read REFUSES an unregistered type (bd: invalid issue type
  // 'link'), where a whole-store export simply finds nothing. A store without
  // the `link` custom type cannot hold link beads, so that is an empty result,
  // not an error.
  if (!probe.types.contains(GridIssueTypes.link)) return <Bead>[];
  final links = await probe.reader.openBeads(
    types: {GridIssueTypes.link},
    metadataAll: metadataAll,
  );
  links.sort((a, b) => a.id.compareTo(b.id));
  return links;
}

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
    final prefix = BeadOwnershipPredicate.ownedPrefixOf(id, {
      ...roster.keys,
      ...armed,
    });
    if (prefix == null) {
      err(
        'grid $verb: endpoint "$id" has no prefix matching the configured '
        'endpoint roster or any supplied --prefix.',
      );
      return false;
    }
    if (!roster.containsKey(prefix)) {
      err(
        'grid $verb: endpoint "$id" uses supplied --prefix "$prefix", but '
        '"$prefix" is not in the configured endpoint roster.',
      );
      return false;
    }
    if (!armed.contains(prefix)) {
      err(
        'grid $verb: endpoint "$id" uses configured prefix "$prefix"; '
        'pass another --prefix $prefix.',
      );
      return false;
    }
  }
  return true;
}

bool _hasValue(ArgResults arguments, String name) =>
    arguments.options.contains(name) &&
    (arguments.option(name)?.trim() ?? '').isNotEmpty;
