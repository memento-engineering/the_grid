import '../errors/bd_exception.dart';

/// The probed SQL shape of a live beads store: which of the tables and columns
/// the pooled read path needs are actually present.
///
/// beads_dart supports **bd >= 1.0.5** rather than one pinned migration level.
/// The connect-time guard verifies the SHAPE it is about to read instead of
/// comparing a migration number, so any later 1.x store that still carries
/// these columns is usable, and a store that genuinely drifted stands down to
/// the bd CLI naming exactly what it lost. [migrationVersion] is recorded for
/// diagnostics only and is never compared.
class DoltSchemaShape {
  /// Creates a shape from an already-probed column map. Prefer
  /// [DoltSchemaShape.fromColumnRows].
  const DoltSchemaShape({
    required this.columnsByTable,
    this.migrationVersion = 0,
  });

  /// Builds the shape from [rows] — the result of [probeSql], keyed `t`/`c`.
  /// Row keys are matched case-insensitively: MySQL-protocol servers differ on
  /// whether `information_schema` headers come back upper-cased.
  factory DoltSchemaShape.fromColumnRows(
    List<Map<String, Object?>> rows, {
    int migrationVersion = 0,
  }) {
    final byTable = <String, Set<String>>{};
    for (final row in rows) {
      final table = _cell(row, 't')?.toLowerCase();
      final column = _cell(row, 'c')?.toLowerCase();
      if (table == null || column == null) continue;
      (byTable[table] ??= <String>{}).add(column);
    }
    return DoltSchemaShape(
      columnsByTable: byTable,
      migrationVersion: migrationVersion,
    );
  }

  /// The single probe SELECT, run once per pool at connect.
  static const String probeSql =
      'SELECT table_name AS t, column_name AS c '
      'FROM information_schema.columns '
      'WHERE table_schema = DATABASE() AND table_name IN '
      "('issues', 'wisps', 'labels', 'wisp_labels', 'dependencies', "
      "'wisp_dependencies')";

  /// The bead columns the snapshot mapper and the ready-work predicate read for
  /// CORRECTNESS. Descriptive text columns (`title`, `description`, …) are
  /// deliberately absent: they arrive through `SELECT *` and `beadFromRow`
  /// already collapses an absent one to `''`, so requiring them would refuse a
  /// store the read path can still serve correctly.
  static const Set<String> requiredBeadColumns = {
    'id',
    'status',
    'priority',
    'issue_type',
    'assignee',
    'created_at',
    'updated_at',
    'metadata',
    'defer_until',
    'ephemeral',
    'pinned',
    'is_blocked',
  };

  /// The label-table columns the label SELECT names.
  static const Set<String> requiredLabelColumns = {'issue_id', 'label'};

  /// The dependency-table columns the explicit dependency SELECT names.
  ///
  /// `depends_on_external` is REQUIRED, not optional: ADR-0000 A44's cross-store
  /// edges live in it — a foreign bead id recorded as a raw dependency target
  /// that the origin store's own `is_blocked` recompute never reads. A shape
  /// without it cannot express a cross-store dependency, so the SQL path stands
  /// down to the bd CLI rather than silently reading a graph with those edges
  /// dropped — which is exactly the orphan interpretation `bd doctor --fix`
  /// applies to a raw cross-store bead-id dep, and which this client must never
  /// inherit.
  static const Set<String> requiredDependencyColumns = {
    'issue_id',
    'type',
    'created_at',
    'created_by',
    'metadata',
    'thread_id',
    'depends_on_issue_id',
    'depends_on_wisp_id',
    'depends_on_external',
  };

  /// The dependency target columns, in the `COALESCE` order beads' own
  /// `DepTargetExpr` uses (`internal/storage/issueops/dependencies.go:37`).
  static const List<String> targetColumnOrder = [
    'depends_on_issue_id',
    'depends_on_wisp_id',
    'depends_on_external',
  ];

  /// Table name → the column names present on it (both lower-cased).
  final Map<String, Set<String>> columnsByTable;

  /// `MAX(version)` from `schema_migrations` — diagnostic only, never compared.
  final int migrationVersion;

  /// Whether [table] exists on this store.
  bool hasTable(String table) => columnsByTable.containsKey(table);

  /// Whether [table] carries [column].
  bool hasColumn(String table, String column) =>
      columnsByTable[table]?.contains(column) ?? false;

  /// The dependency-target expression for [table]: `COALESCE(...)` over the
  /// target columns actually present, in [targetColumnOrder].
  ///
  /// Throws [StateError] when [table] is absent or carries no target column — a
  /// caller that got here without checking [hasTable] has a bug, and returning
  /// an empty expression would emit invalid SQL instead of failing loudly.
  String depTargetExprFor(String table) {
    final columns = columnsByTable[table];
    if (columns == null) {
      throw StateError(
        'dependency table "$table" is not present on this store',
      );
    }
    final present = [
      for (final column in targetColumnOrder)
        if (columns.contains(column)) column,
    ];
    if (present.isEmpty) {
      throw StateError('table "$table" carries no dependency target column');
    }
    return present.length == 1
        ? present.single
        : 'COALESCE(${present.join(', ')})';
  }

  /// Every required table/column this store does NOT have, as `table` or
  /// `table.column` strings, sorted. Empty ⇒ the SQL read path is usable.
  ///
  /// The wisp family (`wisps`/`wisp_labels`/`wisp_dependencies`) is OPTIONAL —
  /// bd only creates it from migrations 0020/0021/0035 onward — but when a wisp
  /// table IS present it must carry the same columns, because the snapshot and
  /// ready-work reads UNION it in.
  List<String> get missing {
    final gaps = <String>[];
    void require(String table, Set<String> columns, {required bool optional}) {
      final present = columnsByTable[table];
      if (present == null) {
        if (!optional) gaps.add(table);
        return;
      }
      for (final column in columns) {
        if (!present.contains(column)) gaps.add('$table.$column');
      }
    }

    require('issues', requiredBeadColumns, optional: false);
    require('labels', requiredLabelColumns, optional: false);
    require('dependencies', requiredDependencyColumns, optional: false);
    require('wisps', requiredBeadColumns, optional: true);
    require('wisp_labels', requiredLabelColumns, optional: true);
    require('wisp_dependencies', requiredDependencyColumns, optional: true);
    return gaps..sort();
  }

  /// Whether the pooled SQL read path may run against this store.
  bool get isSupported => missing.isEmpty;

  /// Throws [BdSchemaDriftException] when this store cannot serve the SQL read
  /// path, so the caller falls back to the bd CLI (ADR-0001 Decision 4).
  void assertSupported() {
    final gaps = missing;
    if (gaps.isEmpty) return;
    throw BdSchemaDriftException.sqlShape(
      missing: gaps,
      found: migrationVersion,
    );
  }

  static String? _cell(Map<String, Object?> row, String key) {
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == key) return entry.value?.toString();
    }
    return null;
  }
}
