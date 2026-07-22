import '../models/bead_status.dart';
import '../services/dolt_query_service.dart';
import 'ready_work_filter.dart';

/// The table family a single predicate pass runs against (beads `FilterTables`,
/// `internal/storage/issueops/filters.go:15-25`). The `--json` oracle runs the
/// **same** predicate builder once against the `issues` family and once against
/// the `wisps` family, then concatenates (port spec §2 / §8.1).
class _FilterTables {
  const _FilterTables({
    required this.issues,
    required this.labels,
    required this.dependencies,
  });

  final String issues;
  final String labels;
  final String dependencies;

  static const issuesFamily = _FilterTables(
    issues: 'issues',
    labels: 'labels',
    dependencies: 'dependencies',
  );
  static const wispsFamily = _FilterTables(
    issues: 'wisps',
    labels: 'wisp_labels',
    dependencies: 'wisp_dependencies',
  );
}

/// One row of a ready-work result: the bead id plus the columns the sort policy
/// and the differential per-row comparison need. The ordered list of these
/// **is** the differential primitive (port spec §10: compare on ordered id
/// sequence first, then on the per-row fields).
class ReadyWorkRow {
  const ReadyWorkRow({
    required this.id,
    required this.priority,
    required this.createdAt,
    required this.status,
    required this.issueType,
    required this.assignee,
    required this.deferUntil,
  });

  final String id;
  final int priority;
  final DateTime createdAt;
  final String status;
  final String issueType;
  final String assignee;
  final DateTime? deferUntil;
}

/// The ready-work predicate ported from beads
/// `internal/storage/issueops/ready_work.go` (ported from bd 1.0.5, f9fe4ef2a;
/// re-verified against bd 1.1.0 / schema v53 on 2026-07-21 — the predicate is
/// unchanged, and the dependency-target expression is now built from the
/// store's probed [DoltSchemaShape] rather than assumed), evaluated
/// over a [DoltQueryService]'s pooled, **SELECT-only** connection inside one
/// read transaction.
///
/// This ports the **`--json` execution path** (`GetReadyWorkWithCountsInTx`),
/// which is the differential oracle `bd ready --json` runs (port spec §2): the
/// shared predicate builder is evaluated against the `issues` family and again
/// against the `wisps` family, the two id lists are concatenated, re-sorted by
/// the policy's in-memory comparator (§6.1), and truncated to the limit. It does
/// **not** reproduce the plain-path wisp machinery (`getReadyWispsInTx`), whose
/// `LabelsAny`/`MolType` honoring is exactly the divergence the oracle avoids
/// (traps #9/#10).
///
/// SELECT-only by construction: every statement is a `SELECT`; the work runs
/// through [DoltQueryService.runReadTransaction], which forbids writes. The port
/// **never** writes `is_blocked` or any column — `is_blocked` is bd-maintained
/// input read as `is_blocked = 0` (port spec §4 / trap #2).
class ReadyWorkQuery {
  ReadyWorkQuery(this._dolt);

  final DoltQueryService _dolt;

  /// Computes the ordered ready set for [filter], returning rows in final
  /// ready order. Pass [now] to pin the time basis (hybrid cutoff + the
  /// in-memory comparator's recency band) for deterministic offline replay;
  /// production callers leave it null (server-side `UTC_TIMESTAMP()` governs the
  /// SQL cutoffs, `DateTime.now().toUtc()` the Dart re-sort — both UTC, port
  /// spec trap #8).
  Future<List<ReadyWorkRow>> readyRows(
    ReadyWorkFilter filter, {
    DateTime? now,
  }) {
    return _dolt.runReadTransaction((select) => _compute(select, filter, now));
  }

  /// Convenience: just the ordered ids (the differential primitive).
  Future<List<String>> readyIds(ReadyWorkFilter filter, {DateTime? now}) async {
    final rows = await readyRows(filter, now: now);
    return [for (final r in rows) r.id];
  }

  Future<List<ReadyWorkRow>> _compute(
    SelectRunner select,
    ReadyWorkFilter filter,
    DateTime? now,
  ) async {
    // The hybrid 48h cutoff is computed once per query and bound twice in SQL
    // (port spec §6); UTC_TIMESTAMP() handled server-side for the WHERE cutoffs.
    final basis = (now ?? DateTime.now()).toUtc();
    final recentCutoff = basis.subtract(const Duration(hours: 48));

    // Clause #9 deferred-parent children — computed once, shared by both passes
    // (port spec §3.2 / §8.1: the same NOT-IN ids appear in both).
    final deferredChildIds = filter.includeDeferred
        ? const <String>[]
        : await _childrenOfDeferredParents(select);

    final issueRows = await _passRows(
      select,
      filter,
      _FilterTables.issuesFamily,
      deferredChildIds,
      recentCutoff,
    );

    // The wisp pass only runs when the wisps table family is present and
    // non-empty (port spec §2: optionalTableExists + wispsTableEmptyOrMissing).
    var allRows = issueRows;
    if (await _wispPassApplies(select)) {
      final wispRows = await _passRows(
        select,
        filter,
        _FilterTables.wispsFamily,
        deferredChildIds,
        recentCutoff,
      );
      // Duplicate id across issues ∪ wisps is a hard error (port spec trap #15;
      // ready_work_counts.go:66-68) — bd's single-writer invariant; surface it.
      final issueIds = {for (final r in issueRows) r.id};
      for (final w in wispRows) {
        if (issueIds.contains(w.id)) {
          throw StateError(
            'ready work id "${w.id}" exists in both issues and wisps',
          );
        }
      }
      allRows = [...issueRows, ...wispRows];
    }

    _sortByPolicy(allRows, filter.sortPolicy, recentCutoff);
    if (filter.limit > 0 && allRows.length > filter.limit) {
      allRows = allRows.sublist(0, filter.limit);
    }
    return allRows;
  }

  /// Runs one predicate pass (issues *or* wisps) and returns its ordered rows.
  Future<List<ReadyWorkRow>> _passRows(
    SelectRunner select,
    ReadyWorkFilter filter,
    _FilterTables tables,
    List<String> deferredChildIds,
    DateTime recentCutoff,
  ) async {
    final whereSql = await _buildWhere(
      select,
      filter,
      tables,
      deferredChildIds,
    );
    final orderBySql = _buildOrderBy(filter.sortPolicy, recentCutoff);
    final limitSql = filter.limit > 0 ? 'LIMIT ${filter.limit}' : '';

    final sql =
        'SELECT id, priority, created_at, status, issue_type, assignee, '
        'defer_until FROM ${tables.issues} $whereSql $orderBySql $limitSql';
    final rows = await select(sql);
    return [for (final row in rows) _rowFrom(row)];
  }

  // -------------------------------------------------------------------------
  // WHERE — ports buildReadyWorkPredicates (ready_work.go:60-208). Clause order
  // is preserved so a SQL-text diff against the Go output stays comparable
  // (port spec §3, ⚠ ordering / trap #14). Literals are inlined (the
  // DoltConnection seam takes a single SQL string) and quoted via _q/_qInt.
  // -------------------------------------------------------------------------

  Future<String> _buildWhere(
    SelectRunner select,
    ReadyWorkFilter filter,
    _FilterTables tables,
    List<String> deferredChildIds,
  ) async {
    final clauses = <String>[];

    // #1 status.
    final status = filter.status;
    clauses.add(
      status != null
          ? 'status = ${_q(status.wire)}'
          : "status IN ('open', 'in_progress')",
    );

    // #2 pinned column, #3 is_blocked.
    clauses.add('(pinned = 0 OR pinned IS NULL)');
    clauses.add('is_blocked = 0');

    // #4 ephemeral.
    if (!filter.includeEphemeral) {
      clauses.add('(ephemeral = 0 OR ephemeral IS NULL)');
    }

    // #5 priority.
    if (filter.priority != null) {
      clauses.add('priority = ${_qInt(filter.priority!)}');
    }

    // #6 issue_type (6a exact / 6b exclusion list).
    final type = filter.type;
    if (type != null && type.isNotEmpty) {
      clauses.add('issue_type = ${_q(type)}');
    } else {
      final exclude = _readyWorkExcludeTypes(filter.excludeTypes);
      final list = exclude.map(_q).join(',');
      clauses.add('issue_type NOT IN ($list)');
    }

    // #7 assignee (7a unassigned / 7b exact).
    if (filter.unassigned) {
      clauses.add("(assignee IS NULL OR assignee = '')");
    } else if (filter.assignee != null) {
      clauses.add('assignee = ${_q(filter.assignee!)}');
    }

    // #8 defer_until cutoff + #9 deferred-parent children.
    if (!filter.includeDeferred) {
      clauses.add('(defer_until IS NULL OR defer_until <= UTC_TIMESTAMP())');
      for (final batch in _batches(deferredChildIds, 200)) {
        final list = batch.map(_q).join(',');
        clauses.add('id NOT IN ($list)');
      }
    }

    // #10 required labels (AND).
    for (final label in filter.labels) {
      clauses.add(
        'id IN (SELECT issue_id FROM ${tables.labels} '
        'WHERE label = ${_q(label)})',
      );
    }

    // #11 excluded labels.
    if (filter.excludeLabels.isNotEmpty) {
      final list = filter.excludeLabels.map(_q).join(', ');
      clauses.add(
        'id NOT IN (SELECT issue_id FROM ${tables.labels} '
        'WHERE label IN ($list))',
      );
    }

    // #12 --parent recursive descendants (§3.3).
    if (filter.parentId != null) {
      final parentId = filter.parentId!;
      final descendantIds = await _descendantIds(select, parentId);
      final parentClauses = <String>[
        '(id LIKE CONCAT(${_q(parentId)}, \'.%\') AND id NOT IN '
            '(SELECT issue_id FROM ${tables.dependencies} '
            "WHERE type = 'parent-child'))",
      ];
      for (final batch in _batches(descendantIds, 200)) {
        final list = batch.map(_q).join(',');
        parentClauses.add('id IN ($list)');
      }
      clauses.add('(${parentClauses.join(' OR ')})');
    }

    // #13 MoleculeID direct-children (§3.4).
    if (filter.moleculeId != null && filter.moleculeId!.isNotEmpty) {
      final mol = filter.moleculeId!;
      final depTarget = _dolt.shape.depTargetExprFor(tables.dependencies);
      clauses.add(
        '(id IN (SELECT issue_id FROM ${tables.dependencies} '
        "WHERE type = 'parent-child' AND $depTarget = ${_q(mol)}) "
        'OR (id LIKE CONCAT(${_q(mol)}, \'.%\') AND id NOT IN '
        '(SELECT issue_id FROM ${tables.dependencies} '
        "WHERE type = 'parent-child')))",
      );
    }

    // #14 has-metadata-key.
    final hasKey = filter.hasMetadataKey;
    if (hasKey != null && hasKey.isNotEmpty) {
      _validateMetadataKey(hasKey);
      clauses.add(
        'JSON_EXTRACT(metadata, ${_q(_jsonMetadataPath(hasKey))}) '
        'IS NOT NULL',
      );
    }

    // #15 metadata equality fields — keys sorted ascending (§3, ⚠ ordering).
    if (filter.metadataFields.isNotEmpty) {
      final keys = filter.metadataFields.keys.toList()..sort();
      for (final k in keys) {
        _validateMetadataKey(k);
        final path = _jsonMetadataPath(k);
        final value = filter.metadataFields[k]!;
        clauses.add(
          'JSON_UNQUOTE(JSON_EXTRACT(metadata, ${_q(path)})) = ${_q(value)}',
        );
      }
    }

    return 'WHERE ${clauses.join(' AND ')}';
  }

  // -------------------------------------------------------------------------
  // ORDER BY — buildReadyWorkOrder (ready_work.go:40-58). The hybrid cutoff is
  // inlined as a literal here (rather than bound) because the seam takes a
  // string; it is the same value the Dart re-sort uses (§6.1).
  // -------------------------------------------------------------------------

  String _buildOrderBy(ReadyWorkSortPolicy policy, DateTime recentCutoff) {
    switch (policy) {
      case ReadyWorkSortPolicy.oldest:
        return 'ORDER BY created_at ASC, id ASC';
      case ReadyWorkSortPolicy.priority:
        return 'ORDER BY priority ASC, created_at DESC, id ASC';
      case ReadyWorkSortPolicy.hybrid:
        final cut = _q(_sqlDateTime(recentCutoff));
        return 'ORDER BY '
            'CASE WHEN created_at >= $cut THEN 0 ELSE 1 END ASC, '
            'CASE WHEN created_at >= $cut THEN priority ELSE 999 END ASC, '
            'created_at ASC, id ASC';
    }
  }

  // -------------------------------------------------------------------------
  // In-memory re-sort after the wisp merge — sortReadyIssues / the counts
  // variant (ready_work.go:568-608 / ready_work_counts.go:77-103). Stable sort;
  // the comparator mirrors the SQL ORDER BY for the same policy.
  // -------------------------------------------------------------------------

  void _sortByPolicy(
    List<ReadyWorkRow> rows,
    ReadyWorkSortPolicy policy,
    DateTime recentCutoff,
  ) {
    int byCreated(ReadyWorkRow a, ReadyWorkRow b) {
      if (!a.createdAt.isAtSameMomentAs(b.createdAt)) {
        return a.createdAt.compareTo(b.createdAt);
      }
      return a.id.compareTo(b.id);
    }

    int byPriority(ReadyWorkRow a, ReadyWorkRow b) {
      if (a.priority != b.priority) return a.priority.compareTo(b.priority);
      if (!a.createdAt.isAtSameMomentAs(b.createdAt)) {
        // priority policy breaks priority ties by created_at DESC.
        return b.createdAt.compareTo(a.createdAt);
      }
      return a.id.compareTo(b.id);
    }

    int comparator(ReadyWorkRow a, ReadyWorkRow b) {
      switch (policy) {
        case ReadyWorkSortPolicy.oldest:
          return byCreated(a, b);
        case ReadyWorkSortPolicy.priority:
          return byPriority(a, b);
        case ReadyWorkSortPolicy.hybrid:
          final aRecent = !a.createdAt.isBefore(recentCutoff);
          final bRecent = !b.createdAt.isBefore(recentCutoff);
          if (aRecent != bRecent) return aRecent ? -1 : 1;
          if (aRecent && a.priority != b.priority) {
            return a.priority.compareTo(b.priority);
          }
          return byCreated(a, b);
      }
    }

    _stableSort(rows, comparator);
  }

  // -------------------------------------------------------------------------
  // Sub-queries: deferred-parent children, descendant ids, wisp-pass probe.
  // -------------------------------------------------------------------------

  /// getChildrenOfDeferredParentsInTx (ready_work.go:636-702): one-hop children
  /// of any future-deferred parent across both table families. Probe first,
  /// then collect (port spec §3.2).
  Future<List<String>> _childrenOfDeferredParents(SelectRunner select) async {
    var hasDeferredParent = false;
    for (final issueTable in const ['issues', 'wisps']) {
      final rows = await _selectMaybeMissing(
        select,
        'SELECT 1 AS one FROM $issueTable '
        'WHERE defer_until IS NOT NULL AND defer_until > UTC_TIMESTAMP() '
        'LIMIT 1',
      );
      if (rows != null && rows.isNotEmpty) {
        hasDeferredParent = true;
        break;
      }
    }
    if (!hasDeferredParent) return const [];

    final childIds = <String>[];
    for (final depTable in const ['dependencies', 'wisp_dependencies']) {
      var depMissing = false;
      for (final issueTable in const ['issues', 'wisps']) {
        final targetCol = issueTable == 'wisps'
            ? 'depends_on_wisp_id'
            : 'depends_on_issue_id';
        final rows = await _selectMaybeMissing(
          select,
          'SELECT dep.issue_id AS issue_id FROM $depTable dep '
          'JOIN $issueTable parent ON parent.id = dep.$targetCol '
          "WHERE dep.type = 'parent-child' "
          'AND parent.defer_until IS NOT NULL '
          'AND parent.defer_until > UTC_TIMESTAMP()',
        );
        if (rows == null) {
          // Missing table: a missing dep table breaks out of the dep loop; a
          // missing issue table just skips that combination (ready_work.go).
          if (depTable == 'wisp_dependencies') {
            depMissing = true;
            break;
          }
          continue;
        }
        for (final row in rows) {
          final id = row['issue_id']?.toString();
          if (id != null) childIds.add(id);
        }
      }
      if (depMissing) break;
    }
    return childIds;
  }

  /// GetDescendantIDsInTx (blocked.go:162-237) — all transitive parent-child
  /// descendants of [parentId], unbounded depth, cycle-defended via the LOCATE
  /// path check (port spec §3.3). Falls back to the issues-only edge query when
  /// `wisp_dependencies` is absent.
  Future<List<String>> _descendantIds(
    SelectRunner select,
    String parentId,
  ) async {
    final root = _q(parentId);
    final issuesEdge =
        'SELECT issue_id, ${_dolt.shape.depTargetExprFor('dependencies')} '
        "FROM dependencies WHERE type = 'parent-child'";
    final wispEdge = _dolt.shape.hasTable('wisp_dependencies')
        ? 'SELECT issue_id, '
              '${_dolt.shape.depTargetExprFor('wisp_dependencies')} '
              "FROM wisp_dependencies WHERE type = 'parent-child'"
        : null;

    String cte(String parentEdges) =>
        'WITH RECURSIVE parent_edges(issue_id, depends_on_id) AS ($parentEdges), '
        'descendants(id, depth, path) AS ('
        "SELECT issue_id, 1, CONCAT(',', $root, ',', issue_id, ',') "
        'FROM parent_edges WHERE depends_on_id = $root '
        'UNION ALL '
        "SELECT e.issue_id, d.depth + 1, CONCAT(d.path, e.issue_id, ',') "
        'FROM parent_edges e JOIN descendants d ON e.depends_on_id = d.id '
        'WHERE (0 <= 0 OR d.depth < 0) '
        "AND LOCATE(CONCAT(',', e.issue_id, ','), d.path) = 0) "
        'SELECT id, depth FROM descendants WHERE id <> $root';

    // maxDepth = 0 (unbounded): the depth cap legs are inert (0<=0 is true).
    final rows = wispEdge == null
        ? null
        : await _selectMaybeMissing(
            select,
            cte('$issuesEdge UNION ALL $wispEdge'),
          );
    final source = rows ?? await select(cte(issuesEdge));
    return [
      for (final row in source)
        if (row['id'] != null) row['id'].toString(),
    ];
  }

  /// Whether the wisp predicate pass should run: `wisp_dependencies` exists and
  /// the `wisps` table is non-empty (port spec §2).
  Future<bool> _wispPassApplies(SelectRunner select) async {
    final depExists = await _selectMaybeMissing(
      select,
      'SELECT 1 AS one FROM wisp_dependencies LIMIT 1',
    );
    if (depExists == null) return false; // table-not-exist
    final wispRow = await _selectMaybeMissing(
      select,
      'SELECT 1 AS one FROM wisps LIMIT 1',
    );
    if (wispRow == null) return false; // wisps table missing
    return wispRow.isNotEmpty; // empty wisps → issues pass alone
  }

  /// Runs a SELECT, returning `null` when the statement fails because a table
  /// does not exist (the wisp tables are optional on older DBs). Any other
  /// error propagates.
  Future<List<Map<String, Object?>>?> _selectMaybeMissing(
    SelectRunner select,
    String sql,
  ) async {
    try {
      return await select(sql);
    } on Object catch (error) {
      if (_isTableNotExist(error)) return null;
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Exclusion-type list — readyWorkExcludeTypes (ready_work.go:412-434).
  // -------------------------------------------------------------------------

  static List<String> _readyWorkExcludeTypes(List<String> extra) {
    final base = <String>[
      'merge-request',
      'gate',
      'molecule',
      'message',
      'agent',
      'role',
      'rig',
    ];
    final seen = {...base};
    for (final t in extra) {
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      base.add(t);
    }
    return base;
  }

  // -------------------------------------------------------------------------
  // Row mapping + small helpers.
  // -------------------------------------------------------------------------

  ReadyWorkRow _rowFrom(Map<String, Object?> row) {
    return ReadyWorkRow(
      id: row['id']?.toString() ?? '',
      priority: _int(row['priority']) ?? 0,
      createdAt: _dateTime(row['created_at']) ?? DateTime.utc(1970),
      status: row['status']?.toString() ?? BeadStatus.open.wire,
      issueType: row['issue_type']?.toString() ?? '',
      assignee: row['assignee']?.toString() ?? '',
      deferUntil: _dateTime(row['defer_until']),
    );
  }

  static bool _isTableNotExist(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains("doesn't exist") ||
        msg.contains('does not exist') ||
        msg.contains('table not found') ||
        msg.contains('unknown table') ||
        (msg.contains('table') && msg.contains('not exist'));
  }

  static Iterable<List<T>> _batches<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }

  static void _stableSort(
    List<ReadyWorkRow> rows,
    int Function(ReadyWorkRow, ReadyWorkRow) compare,
  ) {
    // Decorate-sort-undecorate to make Dart's List.sort stable on equal keys.
    final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
    indexed.sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    for (var i = 0; i < rows.length; i++) {
      rows[i] = indexed[i].$2;
    }
  }

  /// Validates a metadata key against beads' `validMetadataKeyRe`
  /// (`^[a-zA-Z_][a-zA-Z0-9_.]*$`, metadata.go:208-220).
  static void _validateMetadataKey(String key) {
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.]*$').hasMatch(key)) {
      throw ArgumentError.value(
        key,
        'metadataKey',
        'invalid metadata key: must match [a-zA-Z_][a-zA-Z0-9_.]*',
      );
    }
  }

  /// JSONMetadataPath (metadata.go:226-231): dotted keys are quoted.
  static String _jsonMetadataPath(String key) =>
      key.contains('.') ? '\$."$key"' : '\$.$key';

  /// SQL string literal: single-quote-wrapped, mirroring mysql_client's
  /// `_escapeString` (backslash + single-quote doubling) so inlined literals
  /// match the bound-parameter encoding byte-for-byte.
  static String _q(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", "''");
    return "'$escaped'";
  }

  static String _qInt(int value) => value.toString();

  /// MySQL DATETIME literal (`yyyy-MM-dd HH:mm:ss`, UTC) for the inlined hybrid
  /// cutoff.
  static String _sqlDateTime(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)} '
        '${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  static int? _int(Object? value) {
    switch (value) {
      case final int v:
        return v;
      case final num v:
        return v.toInt();
      case final String v:
        return int.tryParse(v.trim());
      default:
        return null;
    }
  }

  static DateTime? _dateTime(Object? value) {
    switch (value) {
      case final DateTime v:
        return v;
      case final String v when v.trim().isNotEmpty:
        // MySQL datetimes are UTC on this server; parse as UTC.
        return DateTime.tryParse(v.trim().replaceFirst(' ', 'T'))?.toUtc();
      default:
        return null;
    }
  }
}
