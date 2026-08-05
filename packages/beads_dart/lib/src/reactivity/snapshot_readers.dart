import '../errors/bd_exception.dart';
import '../models/bead.dart';
import '../models/bead_dependency.dart';
import '../models/bead_status.dart';
import '../models/issue_type.dart';
import '../models/graph_snapshot.dart';
import '../services/bd_cli_service.dart';
import '../services/dolt_query_service.dart';
import 'snapshot_reader.dart';

/// Composes a CLI snapshot from every registered type/status scope.
class CliSnapshotReader implements SnapshotReader {
  CliSnapshotReader(this._bd, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final BdCliService _bd;
  final DateTime Function() _clock;

  @override
  Future<GraphSnapshot> read() async {
    final typeData = await _bd.types();
    final statusData = await _bd.statuses();
    final types = _names(typeData, const [
      'core_types',
      'custom_types',
    ]).map(IssueType.new).toSet();
    final statuses = _names(
      statusData,
      statusData.keys.where((key) => key.contains('status')).toList(),
    ).map(BeadStatus.new).toSet();
    if (types.isEmpty || statuses.isEmpty) {
      throw const BdParseException('bd type/status discovery was empty');
    }
    final beads = <String, Bead>{};
    final dependencies = <String, BeadDependency>{};
    for (final type in types) {
      for (final status in statuses) {
        final scope = await _bd.listScope(type: type, status: status);
        for (final bead in scope.beads) {
          beads[bead.id] = bead;
        }
        for (final edge in scope.dependencies) {
          dependencies[edge.edgeKey] = edge;
        }
      }
    }
    final ready = await _bd.ready();
    return GraphSnapshot.fromParts(
      beads: beads.values,
      dependencies: dependencies.values,
      readyIds: ready.map((bead) => bead.id),
      capturedAt: _clock(),
    );
  }

  static Set<String> _names(Map<String, dynamic> data, Iterable<String> keys) {
    final result = <String>{};
    for (final key in keys) {
      final values = data[key];
      if (values == null) continue;
      if (values is! List) {
        throw BdParseException('bd discovery field "$key" was not a list');
      }
      for (final value in values) {
        final name = value is String
            ? value
            : value is Map<String, dynamic>
            ? value['name']
            : null;
        if (name is! String || name.isEmpty) {
          throw BdParseException('bd discovery field "$key" had no name');
        }
        result.add(name);
      }
    }
    return result;
  }
}

/// Composes a snapshot from pooled Dolt SQL (issues ∪ wisps, plus both label
/// and dependency tables — see [SnapshotReader] for the unified inclusion
/// semantics) plus `bd ready` for the ready set (authoritative in M1; M2 ports
/// ready-work to SQL, differential-tested). The heavy read stays on pooled SQL.
///
/// SQL failures propagate: assembly chooses the source once and reads stay loud.
class SqlSnapshotReader implements SnapshotReader {
  SqlSnapshotReader({
    required DoltQueryService dolt,
    required BdCliService bd,
    DateTime Function()? clock,
  }) : _dolt = dolt,
       _bd = bd,
       _clock = clock ?? DateTime.now;

  final DoltQueryService _dolt;
  final BdCliService _bd;
  final DateTime Function() _clock;

  @override
  Future<GraphSnapshot> read() async {
    final parts = await _dolt.snapshotParts();
    final ready = await _bd.ready();
    return GraphSnapshot.fromParts(
      beads: parts.beads,
      dependencies: parts.dependencies,
      readyIds: ready.map((bead) => bead.id),
      capturedAt: _clock(),
    );
  }
}

/// Adapts [DoltQueryService.probe] to the [ChangeProbe] seam consumed by the
/// working-set dirty-signal source.
class DoltChangeProbe implements ChangeProbe {
  DoltChangeProbe(this._dolt);
  final DoltQueryService _dolt;

  @override
  Future<String> probe() => _dolt.probe();
}
