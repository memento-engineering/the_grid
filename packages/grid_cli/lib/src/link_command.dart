import 'dart:convert';
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
      ..addFlag('json', negatable: false)
      ..addOption(
        'grid-root',
        help:
            'link migrate only: the grid home whose state store holds the '
            'retired link beads.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'link migrate only: print the plan and write nothing.',
      );
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
  final isMigrate =
      arguments.rest.length == 1 && arguments.rest.single == 'migrate';
  final json = arguments.flag('json');
  if (json && !isList) {
    writeErr('grid link: --json is accepted only by link ls.');
    return 64;
  }
  final roster = _roster(endpoints, writeErr, 'link');
  if (roster == null) return 64;
  final factory = bdFactory ?? _processBd;

  if (isMigrate) {
    return _migrate(
      arguments: arguments,
      roster: roster,
      factory: factory,
      dirExists: dirExists,
      write: write,
      writeErr: writeErr,
    );
  }

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
  final Map<String, Set<String>> _blockingRows = {};

  /// Every blocking dependency row [endpoint]'s store already carries over
  /// [consumerIds], as `<issue>\u0000<target>` keys — read ONCE per store and
  /// then maintained in memory by [markRowWritten].
  ///
  /// BOTH bd surfaces feed it, because neither alone carries both row kinds:
  /// an `external:` target has no issue in this store for bd's RESOLVING read
  /// to answer with, and a plain local row is what that read exists for. One
  /// read pair per STORE rather than per ROW: the migration walks a hundred
  /// links over a handful of stores, and a bd spawn per link per surface is
  /// the CLI-spawn-loop shape this repo refuses.
  Future<Set<String>> blockingRowsOf(
    LinkEndpointStore endpoint,
    Set<String> consumerIds,
  ) async {
    final cached = _blockingRows[endpoint.name];
    if (cached != null) return cached;
    final probe = await of(endpoint);
    final rows = <String>{
      for (final dep in await probe.bd.externalDepRows())
        if (dep.type.affectsBlocking) _rowKey(dep.issueId, dep.dependsOnId),
      for (final dep in await probe.bd.depList(consumerIds.toList()))
        if (dep.type.affectsBlocking) _rowKey(dep.issueId, dep.dependsOnId),
    };
    return _blockingRows[endpoint.name] = rows;
  }

  /// Records a row this pass just wrote, so the in-memory set stays true
  /// without re-reading the store.
  void markRowWritten(LinkEndpointStore endpoint, String from, String wire) =>
      _blockingRows[endpoint.name]?.add(_rowKey(from, wire));

  static String _rowKey(String issueId, String dependsOnId) =>
      '$issueId\u0000$dependsOnId';

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
/// The rows come from [BdCliService.externalDepRows] — the SAME read the
/// FRONTIER takes them from on the CLI path, so the listing and the engine
/// cannot disagree about which edges exist. bd's resolving dependency reads
/// (`bd dep list`, `bd show`) answer with the issue record a row points at and
/// therefore return NO external row at all; listing off one of those would
/// have printed an empty roster over a store full of edges.
///
/// Open-scoped: a consumer still waiting on a capability is open, so a closed
/// bead's historical row is not an edge anyone is held by, and a row whose
/// consumer this store does not observe as open is skipped.
Future<List<Map<String, String>>> _externalRowsOf(
  LinkEndpointStore endpoint,
  Map<String, LinkEndpointStore> roster,
  _StoreProbes probes,
) async {
  final probe = await probes.of(endpoint);
  final open = await probe.reader.openBeads(types: probe.types);
  if (open.isEmpty) return const [];
  final statusOf = {for (final bead in open) bead.id: bead.status.wire};
  final rows = <Map<String, String>>[];
  for (final dep in await probe.bd.externalDepRows()) {
    if (!dep.type.affectsBlocking) continue;
    final status = statusOf[dep.issueId];
    if (status == null) continue;
    final ref = ExternalDepRef.parse(dep.dependsOnId);
    if (ref == null) continue;
    final target = roster.values
        .where((candidate) => candidate.name == ref.project)
        .firstOrNull;
    rows.add({
      'from': dep.issueId,
      'fromStatus': status,
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

/// Every OPEN `type=link` bead in the state store, id-sorted — the legacy
/// receipts `link migrate` retires (tg-6t0h).
///
/// A scoped read REFUSES an unregistered type (bd: invalid issue type
/// 'link'), where a whole-store export simply finds nothing. A store without
/// the `link` custom type cannot hold link beads, so that is an empty result,
/// not an error.
Future<List<Bead>> _openLinkBeads(
  ({CliBeadProbeReader reader, Set<IssueType> types}) probe,
) async {
  if (!probe.types.contains(GridIssueTypes.link)) return <Bead>[];
  final links = await probe.reader.openBeads(types: {GridIssueTypes.link});
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

bool _hasValue(ArgResults arguments, String name) =>
    arguments.options.contains(name) &&
    (arguments.option(name)?.trim() ?? '').isNotEmpty;

/// The metadata keys a RETIRED state-store link bead carries.
///
/// Spelled here, in the ONE verb that still reads them, rather than in a
/// shared engine library: after tg-6t0h nothing enforces a link bead, so the
/// schema is not a contract between the engine and anything — it is the
/// on-disk shape of the receipts this one-shot pass converts and closes.
abstract final class _LegacyLinkKeys {
  static const from = 'grid.link.from';
  static const to = 'grid.link.to';
  static const type = 'grid.link.type';

  /// The one edge kind the retired enforcement ever implemented.
  static const blocks = 'blocks';
}

/// `grid link migrate --grid-root <home> [--dry-run]` — the ONE-PASS, no
/// coexistence window retirement of authored link beads (tg-6t0h,
/// `the_grid#capability-edges-are-bd-native-and-link-is-sugar`).
///
/// For every OPEN `type=link` bead in the state store, in id order:
///
/// 1. the target gains `export:<to>` in its own store, unless it carries it;
/// 2. the consumer gains the dependency row `external:<project>:<to>`, unless
///    it carries it — `<project>` is the target substation's ROSTER NAME;
/// 3. a target that is already CLOSED is SHIPPED (`bd ship <to>`), so the
///    consumer unblocks exactly as the retired link bead would have let it;
/// 4. the link bead is CLOSED with a reason naming the row it became.
///
/// A SAME-STORE link — one bd can express itself — becomes a plain
/// `bd dep add <from> <to>` row with no capability at all; `external:` is for
/// what bd cannot resolve locally, and a self-referential capability is a row
/// no store could satisfy.
///
/// Write order is label → row → ship → close, so an interrupted pass leaves
/// the link bead OPEN and re-running finishes it: every step is idempotent
/// (bd's label add is a set union, the row is written only when absent, and
/// `bd ship` re-adds a label the target may already carry).
///
/// FAIL-CLOSED, never a silent drop: a link this pass cannot faithfully
/// convert — malformed metadata, an unknown edge kind, an endpoint outside the
/// roster, an unobservable target — is reported LOUDLY and left OPEN, and the
/// verb exits non-zero. Closing such a receipt would erase the only remaining
/// record of an edge nothing enforces any more.
///
/// `--dry-run` prints the same plan and writes NOTHING.
Future<int> _migrate({
  required ArgResults arguments,
  required Map<String, LinkEndpointStore> roster,
  required LinkBdFactory factory,
  required DirectoryProbe? dirExists,
  required void Function(String) write,
  required void Function(String) writeErr,
}) async {
  if (_hasValue(arguments, 'blocked-by')) {
    writeErr('grid link migrate: only --grid-root and --dry-run are accepted.');
    return 64;
  }
  final stateStore = _stateStore(arguments, writeErr, 'link migrate');
  if (stateStore == null) {
    writeErr('grid link migrate: --grid-root is required.');
    return 64;
  }
  final dryRun = arguments.flag('dry-run');

  try {
    final probes = _StoreProbes(factory, dirExists);
    final stateBd = factory(openStateStore(stateStore, dirExists: dirExists));
    final links = await _openLinkBeads(await _probeReader(stateBd));
    if (links.isEmpty) {
      write('grid link migrate: 0 open link beads — nothing to migrate.');
      return 0;
    }

    // PLAN the whole pass first, so each consumer store's existing rows are
    // read ONCE, scoped to exactly the consumer ids this pass touches, rather
    // than re-read per link.
    final planned = [
      for (final link in links) (link: link, outcome: _planOf(link, roster)),
    ];
    final consumerIds = <String, Set<String>>{};
    for (final entry in planned) {
      if (entry.outcome case final _LinkPlan plan) {
        (consumerIds[plan.consumer.name] ??= <String>{}).add(plan.from);
      }
    }

    var migrated = 0;
    var refused = 0;
    for (final entry in planned) {
      final link = entry.link;
      switch (entry.outcome) {
        case _LinkRefused(:final message):
          writeErr('grid link migrate: $message');
          refused++;
          continue;
        case _LinkPlan(
          :final from,
          :final to,
          :final consumer,
          :final provider,
          :final ref,
        ):
          final providerProbe = provider == null
              ? null
              : await probes.of(provider);
          final target = providerProbe == null
              ? null
              : await providerProbe.reader.beadById(
                  to,
                  types: providerProbe.types,
                );
          if (providerProbe != null && target == null) {
            writeErr(
              'grid link migrate: ${link.id} targets "$to", which is not '
              'observable in substation "${provider!.name}" — leaving the '
              'link bead OPEN rather than closing a receipt whose edge this '
              'pass cannot author.',
            );
            refused++;
            continue;
          }
          final consumerProbe = await probes.of(consumer);
          final steps = <String>[];

          final label = ref == null ? null : exportLabel(to);
          final needsLabel = label != null && !target!.labels.contains(label);
          if (needsLabel) steps.add('label $to $label');

          final wire = ref?.wire ?? to;
          final hasRow = (await probes.blockingRowsOf(
            consumer,
            consumerIds[consumer.name]!,
          )).contains(_StoreProbes._rowKey(from, wire));
          if (!hasRow) steps.add('dep add $from $wire');

          final needsShip = ref != null && target!.isClosed;
          if (needsShip) steps.add('ship $to (target CLOSED)');
          steps.add('close ${link.id}');

          write('${link.id}: $from --blocked-by $wire');
          for (final step in steps) {
            write('  ${dryRun ? '-' : '+'} $step');
          }
          migrated++;
          if (dryRun) continue;

          if (needsLabel) await providerProbe!.bd.addLabels(to, [label]);
          if (!hasRow) {
            await consumerProbe.bd.depAdd(from, wire);
            probes.markRowWritten(consumer, from, wire);
          }
          if (needsShip) await providerProbe!.bd.ship(to);
          await stateBd.close(
            link.id,
            reason: _migrationReason(from: from, wire: wire),
          );
      }
    }

    write(
      dryRun
          ? 'grid link migrate: DRY RUN — $migrated link bead(s) planned, '
                'nothing written.'
          : 'grid link migrate: $migrated link bead(s) migrated.',
    );
    if (refused > 0) {
      writeErr(
        'grid link migrate: $refused link bead(s) left OPEN — see the '
        'refusals above.',
      );
      return 1;
    }
    return 0;
  } on StoreRefusal catch (e) {
    writeErr('grid link migrate: ${e.message}');
    return 1;
  } on BdException catch (e) {
    writeErr('grid link migrate: ${e.message}');
    return 1;
  }
}

/// The close reason on a retired link bead: the row it became, in full.
String _migrationReason({required String from, required String wire}) =>
    'grid link migrate (tg-6t0h): this edge is now the bd dependency row '
    '"$from" -> "$wire". The receipt is retired; nothing reads link beads.';

/// What one link bead converts to, or why it cannot.
sealed class _LinkOutcome {
  const _LinkOutcome();
}

/// A convertible edge. [provider] and [ref] are null for a SAME-STORE link,
/// whose row is a plain local `bd dep add` with no capability.
class _LinkPlan extends _LinkOutcome {
  const _LinkPlan({
    required this.from,
    required this.to,
    required this.consumer,
    required this.provider,
    required this.ref,
  });

  final String from;
  final String to;

  /// The store that gains the dependency row.
  final LinkEndpointStore consumer;

  /// The store that gains the `export:` label, or null for a SAME-STORE link.
  final LinkEndpointStore? provider;

  /// The capability row, or null for a SAME-STORE link.
  final ExternalDepRef? ref;
}

/// An edge this pass refuses to author, with the LOUD operator line.
class _LinkRefused extends _LinkOutcome {
  const _LinkRefused(this.message);

  final String message;
}

/// Reads [link]'s legacy metadata into the row it becomes.
_LinkOutcome _planOf(Bead link, Map<String, LinkEndpointStore> roster) {
  final from = _metadataText(link, _LegacyLinkKeys.from);
  final to = _metadataText(link, _LegacyLinkKeys.to);
  final kind = _metadataText(link, _LegacyLinkKeys.type);
  if (from == null || to == null) {
    return _LinkRefused(
      '${link.id} names no "${_LegacyLinkKeys.from}"/"${_LegacyLinkKeys.to}" '
      'pair — it enforces nothing and describes no row. Close it by hand.',
    );
  }
  if (kind != _LegacyLinkKeys.blocks) {
    return _LinkRefused(
      '${link.id} carries "${_LegacyLinkKeys.type}"="${kind ?? ''}", which no '
      'engine ever enforced (the only known kind is '
      '"${_LegacyLinkKeys.blocks}") — leaving it OPEN rather than guessing '
      'what row it means.',
    );
  }
  final consumer =
      roster[BeadOwnershipPredicate.ownedPrefixOf(from, roster.keys)];
  final provider =
      roster[BeadOwnershipPredicate.ownedPrefixOf(to, roster.keys)];
  if (consumer == null || provider == null) {
    final unknown = consumer == null ? from : to;
    return _LinkRefused(
      '${link.id} names endpoint "$unknown", which has no prefix in the '
      'configured endpoint roster (${roster.keys.join(', ')}) — arm that '
      'substation and re-run.',
    );
  }
  if (identical(consumer, provider)) {
    return _LinkPlan(
      from: from,
      to: to,
      consumer: consumer,
      provider: null,
      ref: null,
    );
  }
  return _LinkPlan(
    from: from,
    to: to,
    consumer: consumer,
    provider: provider,
    ref: ExternalDepRef(project: provider.name, capability: to),
  );
}

/// A link bead's metadata value as a non-empty `String`, or `null` —
/// `Bead.metadata` is `Map<String, dynamic>` and a hand-edited store can carry
/// anything.
String? _metadataText(Bead bead, String key) {
  final value = bead.metadata[key];
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}
