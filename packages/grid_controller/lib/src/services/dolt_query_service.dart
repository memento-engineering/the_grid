import 'dart:async';

import 'package:meta/meta.dart';
import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';

import '../errors/bd_exception.dart';
import '../models/bead.dart';
import '../models/bead_dependency.dart';
import 'dolt_endpoint.dart';
import 'dolt_row_mapper.dart';

/// The beads schema migration version this read path is written against
/// (`internal/storage/schema/migrations/0050_dependencies_deterministic_id`).
///
/// The targeted SELECTs assume the post-0041 dependencies layout (typed target
/// columns surfaced via a `COALESCE(...) AS depends_on_id` alias), the
/// `started_at`/`spec_id` issue columns added by 0027/0034, and the wisp tables
/// (`wisps`/`wisp_labels`/`wisp_dependencies`, migrations 0020/0021 plus the
/// ignored-track split of wisp_dependencies' target columns) that bd routes
/// ephemeral/no-history/infra beads into (ephemeral_routing.go, migration
/// 0035). A database **newer** than this (forward drift) may have dropped or
/// renamed a column this code reads, so the connect-time guard rejects it and
/// the caller falls back to the bd CLI (ADR-0001 Decision 4 schema-drift
/// guard). Bump this constant whenever the targeted SELECTs are re-validated
/// against a newer migration.
const int kTargetSchemaVersion = 50;

/// Internal seam for unit-testing the pooled service without a real socket: a
/// minimal subset of `mysql_client`'s [MySQLConnection] surface. The production
/// implementation ([_RealConnection]) wraps the real client; tests pass a fake.
@visibleForTesting
abstract interface class DoltConnection {
  bool get connected;
  Future<List<Map<String, Object?>>> query(String sql);
  Future<void> close();
}

/// Opens a [DoltConnection] for [endpoint]. Swappable in tests.
@visibleForTesting
typedef DoltConnectionFactory =
    Future<DoltConnection> Function(DoltEndpoint endpoint);

/// Pooled, **SELECT-only** MySQL-protocol read service over a gc-managed Dolt
/// sql-server (predictable-flutter Service tier: stateless beyond the pooled
/// sockets, all IO, no domain state).
///
/// Responsibilities (ADR-0001 Decisions 4 & 5):
/// - a tiny pool of ≤2 connections, reconnected transparently when the server
///   reaps an idle socket (30s) or a query hits a closed connection;
/// - [probe] — the `SELECT @@<db>_working` working-set hash, the ~1ms
///   authoritative change signal that doubles as keepalive;
/// - [snapshotParts] — the COMPLETE graph (`issues` ∪ `wisps`, plus both
///   label and dependency tables) composed into [Bead]s and [BeadDependency]s
///   (the ready set is **not** computed here; `bd ready` is authoritative in
///   M1);
/// - a connect-time schema-drift guard that throws [BdSchemaDriftException] on a
///   database newer than [kTargetSchemaVersion] so the caller falls back to the
///   bd CLI.
///
/// Writes are impossible by construction: there is no mutate method, and the
/// single generic entry point ([_runSelect]) rejects any non-SELECT statement.
/// All mutations go through the bd CLI (never SQL) per CLAUDE.md / ADR-0001.
class DoltQueryService {
  DoltQueryService(
    this.endpoint, {
    int poolSize = 2,
    @visibleForTesting DoltConnectionFactory? connectionFactory,
  }) : _poolSize = poolSize.clamp(1, 2),
       _connectionFactory = connectionFactory ?? _defaultConnect;

  final DoltEndpoint endpoint;
  final int _poolSize;
  final DoltConnectionFactory _connectionFactory;

  final List<DoltConnection> _pool = [];
  int _rr = 0;
  bool _closed = false;
  bool _driftChecked = false;

  /// The working-set probe statement for this endpoint's database, e.g.
  /// `SELECT @@tg_working`. Database-scoped: any committed data change flips the
  /// returned hash (ADR-0001 Decision 5). Exposed for callers/tests that want
  /// the exact SQL.
  String get probeSql => 'SELECT @@${endpoint.database}_working';

  /// Opens the pool (lazily filled on demand) and runs the schema-drift guard.
  /// Safe to call more than once.
  Future<void> connect() async {
    _closed = false;
    // Touch one connection so the drift guard runs eagerly and credential /
    // reachability failures surface at connect() rather than first query.
    await _ensureDriftChecked();
  }

  /// Closes every pooled connection. The service can be [connect]ed again after.
  Future<void> close() async {
    _closed = true;
    final conns = List<DoltConnection>.of(_pool);
    _pool.clear();
    _rr = 0;
    for (final conn in conns) {
      try {
        await conn.close();
      } on Object {
        // Best-effort: a socket already torn down by the server is fine.
      }
    }
  }

  /// The working-set hash from `SELECT @@<db>_working`. Cheap (~1ms) and
  /// idempotent when the workspace is idle — two back-to-back probes return the
  /// same value until a write commits.
  Future<String> probe() async {
    final rows = await _runSelect(probeSql);
    if (rows.isEmpty) {
      throw const BdParseException('working-set probe returned no rows');
    }
    final first = rows.first;
    final value = first.values.isNotEmpty ? first.values.first : null;
    if (value == null) {
      throw const BdParseException('working-set probe returned a null hash');
    }
    return value.toString();
  }

  /// Reads the parts that compose a graph snapshot and returns the value-typed
  /// results. The ready set is intentionally excluded — it comes from
  /// `bd ready` in M1 (ADR-0001 Decision 4); the caller assembles a
  /// `GraphSnapshot` from these parts plus that ready set.
  ///
  /// **The snapshot is the COMPLETE graph: `issues` ∪ `wisps`, all statuses,
  /// including infra/template/gate-typed beads.** bd routes ephemeral,
  /// no-history, and infra beads to the separate `wisps`/`wisp_labels`/
  /// `wisp_dependencies` tables (beads internal/storage/dolt/
  /// ephemeral_routing.go; migrations 0020/0021/0035), so a read over `issues`
  /// alone would never see a poured wisp — or, post-0035, any agent/rig/role/
  /// message bead. Filtering is the consumer's job (projections/selectors);
  /// the CLI capture path (`bd export --all`, cmd/bd/export.go) shares these
  /// inclusion semantics so the two paths produce identical snapshots.
  ///
  /// Four SELECTs (issues, wisps, labels∪wisp_labels, dependencies∪
  /// wisp_dependencies); labels are grouped per issue and dependency/dependent
  /// counts are derived from the dependency edges so a single round of queries
  /// yields fully-populated [Bead]s. Issue and wisp rows are merged by column
  /// *name* in Dart rather than positionally UNION'd in SQL: the two tables
  /// share every column this mapper reads, but their ordinal layouts can
  /// diverge across upgrade histories (`is_blocked` arrived via the numbered
  /// track on `issues` (0046) and via the ignored track on `wisps`), which
  /// would silently scramble a positional `SELECT *` UNION.
  Future<({List<Bead> beads, List<BeadDependency> dependencies})>
  snapshotParts() async {
    await _ensureDriftChecked();

    final issueRows = await _runSelect(issuesSelect);
    final wispRows = await _runSelect(wispsSelect);
    final labelRows = await _runSelect(labelsSelect);
    final depRows = await _runSelect(dependenciesSelect);

    // labels grouped per issue.
    final labelsByIssue = <String, List<String>>{};
    for (final row in labelRows) {
      final issueId = row['issue_id']?.toString();
      final label = row['label']?.toString();
      if (issueId == null || label == null) continue;
      (labelsByIssue[issueId] ??= <String>[]).add(label);
    }

    // dependency edges + per-issue out/in degree.
    final dependencies = <BeadDependency>[];
    final dependencyCount = <String, int>{}; // edges this issue owns (out)
    final dependentCount = <String, int>{}; // edges pointing at this issue (in)
    for (final row in depRows) {
      final dep = dependencyFromRow(row);
      dependencies.add(dep);
      dependencyCount[dep.issueId] = (dependencyCount[dep.issueId] ?? 0) + 1;
      dependentCount[dep.dependsOnId] =
          (dependentCount[dep.dependsOnId] ?? 0) + 1;
    }

    // issues ∪ wisps — bd hard-errors when an id exists in both tables
    // (issueops/search.go), so plain concatenation cannot double-count.
    final beadRows = [...issueRows, ...wispRows];
    final beads = <Bead>[
      for (final row in beadRows)
        () {
          final id = row['id']?.toString();
          return beadFromRow(
            row,
            labels: id == null
                ? const <String>[]
                : (labelsByIssue[id] ?? const <String>[]),
            dependencyCount: id == null ? 0 : (dependencyCount[id] ?? 0),
            dependentCount: id == null ? 0 : (dependentCount[id] ?? 0),
          );
        }(),
    ];

    return (beads: beads, dependencies: dependencies);
  }

  // -------------------------------------------------------------------------
  // SELECT statements. Column lists are explicit so a drifted column rename is
  // a loud query error (caught → reconnect/fallback) rather than silent data.
  // -------------------------------------------------------------------------

  /// The issues SELECT. Exposed for tests that fake the connection layer.
  @visibleForTesting
  static const String issuesSelect = 'SELECT * FROM issues';

  /// The wisps SELECT — the ephemeral/no-history/infra half of the bead set
  /// (beads routes those to the `wisps` table; ephemeral_routing.go, migration
  /// 0035). Read separately from [issuesSelect] and merged by column name in
  /// Dart (see [snapshotParts] for why a positional SQL UNION is unsafe).
  /// `ephemeral` is a real column on `wisps` and is mapped as-is — no-history
  /// beads live there with `ephemeral = 0` (GH#3649), so it is NOT assumed
  /// true. Exposed for tests that fake the connection layer.
  @visibleForTesting
  static const String wispsSelect = 'SELECT * FROM wisps';

  /// The labels SELECT: `labels` ∪ `wisp_labels` — wisp labels live in their
  /// own table (migration 0021), identical two-column shape, so a UNION ALL is
  /// positionally safe. Exposed for tests that fake the connection layer.
  @visibleForTesting
  static const String labelsSelect =
      'SELECT issue_id, label FROM labels '
      'UNION ALL '
      'SELECT issue_id, label FROM wisp_labels';

  /// The dependencies SELECT: `dependencies` ∪ `wisp_dependencies` (a wisp's
  /// outgoing edges live in `wisp_dependencies`; beads counts.go). Mirrors
  /// beads' own dependency read (internal/storage/domain/db/dependency.go):
  /// the natural target is
  /// `COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)`
  /// surfaced as a `depends_on_id` alias, robust to whether the legacy generated
  /// `depends_on_id` column is present. Both tables carry the identical
  /// explicit column list (migration 0021 + ignored-track split), so the UNION
  /// ALL is positionally safe. Exposed for tests that fake the connection
  /// layer.
  @visibleForTesting
  static const String dependenciesSelect =
      'SELECT issue_id, '
      'COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) '
      'AS depends_on_id, type, created_at, created_by, metadata, thread_id '
      'FROM dependencies '
      'UNION ALL '
      'SELECT issue_id, '
      'COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) '
      'AS depends_on_id, type, created_at, created_by, metadata, thread_id '
      'FROM wisp_dependencies';

  // -------------------------------------------------------------------------
  // Drift guard.
  // -------------------------------------------------------------------------

  Future<void> _ensureDriftChecked() async {
    if (_driftChecked) return;
    final version = await _readSchemaVersion();
    if (version > kTargetSchemaVersion) {
      throw BdSchemaDriftException(
        found: version,
        expected: kTargetSchemaVersion,
        source: 'schema_migrations',
      );
    }
    _driftChecked = true;
  }

  /// Reads `MAX(version)` from `schema_migrations` — the cursor table beads
  /// records applied migrations in (internal/storage/schema/schema.go). A fresh
  /// or table-less database reports 0.
  Future<int> _readSchemaVersion() async {
    final rows = await _runSelect(
      'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations',
    );
    if (rows.isEmpty) return 0;
    final value = rows.first['v'] ?? rows.first.values.firstOrNull;
    switch (value) {
      case final int v:
        return v;
      case final num v:
        return v.toInt();
      case final String v:
        return int.tryParse(v.trim()) ?? 0;
      default:
        return 0;
    }
  }

  // -------------------------------------------------------------------------
  // Pool + SELECT-only enforcement + reconnect-on-error.
  // -------------------------------------------------------------------------

  /// Rejects any non-SELECT statement, then runs it with one transparent
  /// reconnect retry if the connection was reaped/closed mid-flight.
  Future<List<Map<String, Object?>>> _runSelect(String sql) async {
    assertSelectOnly(sql);
    if (_closed) {
      throw const BdParseException(
        'DoltQueryService is closed; call connect() first',
      );
    }
    try {
      final conn = await _acquire();
      return await conn.query(sql);
    } on Object catch (error) {
      if (_isConnectionClosed(error)) {
        // Server reaped the idle socket (30s) or it dropped mid-query: drop the
        // dead connection and retry once on a fresh one.
        _evictDead();
        final conn = await _acquire(forceFresh: true);
        return await conn.query(sql);
      }
      rethrow;
    }
  }

  /// Round-robins a live connection out of the pool, lazily filling it up to
  /// [_poolSize] and discarding any connection the client reports as not
  /// `connected`.
  Future<DoltConnection> _acquire({bool forceFresh = false}) async {
    if (forceFresh) {
      return _openInto();
    }
    // Reap any dead connections first.
    _pool.removeWhere((c) => !c.connected);
    if (_pool.length < _poolSize) {
      return _openInto();
    }
    _rr = (_rr + 1) % _pool.length;
    final conn = _pool[_rr];
    if (!conn.connected) {
      _pool.removeAt(_rr);
      return _openInto();
    }
    return conn;
  }

  Future<DoltConnection> _openInto() async {
    final conn = await _connectionFactory(endpoint);
    if (_pool.length >= _poolSize) {
      // Never exceed the documented ≤2 ceiling: retire the oldest.
      final evicted = _pool.removeAt(0);
      unawaited(_safeClose(evicted));
    }
    _pool.add(conn);
    return conn;
  }

  void _evictDead() {
    final dead = _pool.where((c) => !c.connected).toList();
    _pool.removeWhere((c) => !c.connected);
    for (final conn in dead) {
      unawaited(_safeClose(conn));
    }
  }

  static Future<void> _safeClose(DoltConnection conn) async {
    try {
      await conn.close();
    } on Object {
      // ignore — best effort.
    }
  }

  bool _isConnectionClosed(Object error) {
    if (error is MySQLClientException) {
      final msg = error.message.toLowerCase();
      return msg.contains('closed') ||
          msg.contains('not connected') ||
          msg.contains('connection');
    }
    // Socket-level teardown.
    return error is StateError &&
            error.message.toLowerCase().contains('closed') ||
        error.toString().toLowerCase().contains('socket');
  }

  /// Guards the generic execution seam: only `SELECT` (optionally preceded by a
  /// leading `WITH` CTE) is permitted. Anything that could mutate — `INSERT`,
  /// `UPDATE`, `DELETE`, `REPLACE`, `CALL`, DDL, multi-statement — is rejected
  /// before it can reach the server (CLAUDE.md: SQL is SELECT-only by
  /// construction; all writes go through the bd CLI).
  @visibleForTesting
  static void assertSelectOnly(String sql) {
    final normalized = _stripLeadingNoise(sql);
    final lowered = normalized.toLowerCase();
    final head = lowered.split(RegExp(r'\s')).first;
    if (head != 'select' && head != 'with') {
      throw ArgumentError.value(
        sql,
        'sql',
        'DoltQueryService is SELECT-only; statement is not a read',
      );
    }
    // Reject statement-batching (";" mid-statement) that could smuggle a write.
    final trimmed = normalized.trim();
    final withoutTrailing = trimmed.endsWith(';')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    if (withoutTrailing.contains(';')) {
      throw ArgumentError.value(
        sql,
        'sql',
        'DoltQueryService rejects multi-statement SQL',
      );
    }
  }

  /// Strips leading line/block comments and whitespace so the leading-keyword
  /// check sees the real first token.
  static String _stripLeadingNoise(String sql) {
    var s = sql.trimLeft();
    var changed = true;
    while (changed) {
      changed = false;
      if (s.startsWith('--')) {
        final nl = s.indexOf('\n');
        s = nl < 0 ? '' : s.substring(nl + 1).trimLeft();
        changed = true;
      } else if (s.startsWith('/*')) {
        final end = s.indexOf('*/');
        s = end < 0 ? '' : s.substring(end + 2).trimLeft();
        changed = true;
      }
    }
    return s;
  }

  // -------------------------------------------------------------------------
  // Default (real socket) connection.
  // -------------------------------------------------------------------------

  static Future<DoltConnection> _defaultConnect(DoltEndpoint endpoint) async {
    final conn = await MySQLConnection.createConnection(
      host: endpoint.host,
      port: endpoint.port,
      userName: endpoint.user,
      password: endpoint.password,
      databaseName: endpoint.database,
      // gc-managed server offers no TLS (DoltEndpoint docs / ADR-0000 A8).
      secure: false,
    );
    await conn.connect();
    return _RealConnection(conn);
  }
}

/// Production [DoltConnection] over `mysql_client`. Reads each row via `assoc()`
/// (raw column strings) — the pure [dolt_row_mapper] normalizes the SQL types,
/// so we deliberately avoid `typedAssoc()`'s type-guessing to keep both read
/// paths byte-identical.
class _RealConnection implements DoltConnection {
  _RealConnection(this._conn);

  final MySQLConnection _conn;

  @override
  bool get connected => _conn.connected;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    final result = await _conn.execute(sql);
    return [for (final row in result.rows) row.assoc()];
  }

  @override
  Future<void> close() => _conn.close();
}
