import '../errors/bd_exception.dart';
import '../models/bead.dart';
import '../models/bead_status.dart';
import '../models/dependency_type.dart';
import '../models/issue_type.dart';
import 'bd_cli_service.dart';
import 'dolt_query_service.dart';
import 'dolt_row_mapper.dart';

/// Purpose-shaped, read-only lifecycle probes.
abstract interface class BeadProbeReader {
  Future<Bead?> beadById(String id, {required Set<IssueType> types});

  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  });

  Future<List<Bead>> openSuperseding(Set<String> priorIds);
}

final class SqlBeadProbeReader implements BeadProbeReader {
  SqlBeadProbeReader(this._dolt);
  final DoltQueryService _dolt;

  static String _metadataEquals(MapEntry<String, String> entry) {
    final member = entry.key.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final path = DoltQueryService.sqlString('\$."$member"');
    return 'JSON_UNQUOTE(JSON_EXTRACT(CAST(metadata AS CHAR), $path)) = '
        '${DoltQueryService.sqlString(entry.value)}';
  }

  String _typeSql(Set<IssueType> types) =>
      types.map((type) => DoltQueryService.sqlString(type.wire)).join(', ');

  Iterable<String> get _beadTables sync* {
    yield 'issues';
    if (_dolt.shape.hasTable('wisps')) yield 'wisps';
  }

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    if (types.isEmpty) return null;
    final rows = await _dolt.runReadTransaction((select) async {
      final result = <Map<String, Object?>>[];
      for (final table in _beadTables) {
        result.addAll(
          await select(
            'SELECT *, CAST(metadata AS CHAR) AS metadata_text FROM $table '
            'WHERE id = ${DoltQueryService.sqlString(id)} '
            'AND issue_type IN (${_typeSql(types)})',
          ),
        );
      }
      return result;
    });
    if (rows.length > 1) {
      throw BdParseException('duplicate bead id "$id" across lifecycle tables');
    }
    return rows.isEmpty ? null : beadFromRow(rows.single);
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (types.isEmpty) return Future.value(const []);
    final allClause = metadataAll.entries.map(_metadataEquals).join(' AND ');
    final anyClause = metadataAny.entries.map(_metadataEquals).join(' OR ');
    return _dolt.runReadTransaction((select) async {
      final rows = <Map<String, Object?>>[];
      for (final table in _beadTables) {
        rows.addAll(
          await select(
            'SELECT *, CAST(metadata AS CHAR) AS metadata_text FROM $table '
            'WHERE status != ${DoltQueryService.sqlString(BeadStatus.closed.wire)} '
            'AND issue_type IN (${_typeSql(types)}) '
            '${allClause.isEmpty ? '' : 'AND ($allClause) '}'
            '${anyClause.isEmpty ? '' : 'AND ($anyClause)'}',
          ),
        );
      }
      return rows.map(beadFromRow).toList(growable: false);
    });
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async {
    if (priorIds.isEmpty) return const [];
    final idsSql = priorIds.map(DoltQueryService.sqlString).join(', ');
    return _dolt.runReadTransaction((select) async {
      String leg(String table) =>
          'SELECT issue_id FROM $table WHERE type = '
          '${DoltQueryService.sqlString(DependencyType.supersedes.wire)} AND '
          '${_dolt.shape.depTargetExprFor(table)} IN ($idsSql)';
      final edgeSql = _dolt.shape.hasTable('wisp_dependencies')
          ? '${leg('dependencies')} UNION ${leg('wisp_dependencies')}'
          : leg('dependencies');
      final edgeRows = await select(edgeSql);
      final successorIds = {
        for (final row in edgeRows)
          if (row['issue_id'] != null) row['issue_id'].toString(),
      };
      if (successorIds.isEmpty) return const <Bead>[];
      final successorSql = successorIds
          .map(DoltQueryService.sqlString)
          .join(', ');
      final rows = <Map<String, Object?>>[];
      for (final table in _beadTables) {
        rows.addAll(
          await select(
            'SELECT *, CAST(metadata AS CHAR) AS metadata_text FROM $table '
            'WHERE status != ${DoltQueryService.sqlString(BeadStatus.closed.wire)} '
            'AND id IN ($successorSql)',
          ),
        );
      }
      return rows.map(beadFromRow).toList(growable: false);
    });
  }
}

final class CliBeadProbeReader implements BeadProbeReader {
  CliBeadProbeReader(this._bd, {required Set<IssueType> lifecycleTypes})
    : _lifecycleTypes = Set.unmodifiable(lifecycleTypes);

  final BdCliService _bd;
  final Set<IssueType> _lifecycleTypes;

  Future<List<Bead>> _open(
    Set<IssueType> types, {
    Map<String, String> metadataFields = const {},
  }) async {
    final beads = <String, Bead>{};
    for (final type in types) {
      final scope = await _bd.listScope(
        type: type,
        status: BeadStatus.open,
        metadataFields: metadataFields,
      );
      for (final bead in scope.beads) {
        beads[bead.id] = bead;
      }
    }
    return beads.values.toList(growable: false);
  }

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    if (types.isEmpty) return null;
    final matches = (await _bd.query('id=$id'))
        .where((bead) => bead.id == id && types.contains(bead.issueType))
        .toList(growable: false);
    if (matches.length > 1) {
      throw BdParseException('duplicate bead id "$id" in query result');
    }
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async {
    final beads = await _open(types, metadataFields: metadataAll);
    return beads
        .where((bead) {
          final all = metadataAll.entries.every(
            (entry) => bead.metadata[entry.key] == entry.value,
          );
          final any =
              metadataAny.isEmpty ||
              metadataAny.entries.any(
                (entry) => bead.metadata[entry.key] == entry.value,
              );
          return all && any;
        })
        .toList(growable: false);
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async {
    if (priorIds.isEmpty) return const [];
    final found = <String, Bead>{};
    for (final type in _lifecycleTypes) {
      final scope = await _bd.listScope(type: type, status: BeadStatus.open);
      for (final edge in scope.dependencies) {
        if (edge.type == DependencyType.supersedes &&
            priorIds.contains(edge.dependsOnId)) {
          for (final bead in scope.beads) {
            if (bead.id == edge.issueId) found[bead.id] = bead;
          }
        }
      }
    }
    return found.values.toList(growable: false);
  }
}
