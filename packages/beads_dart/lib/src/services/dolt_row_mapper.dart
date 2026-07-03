/// Pure mappers from raw Dolt SQL rows into the Track A value types.
///
/// These never touch IO: a "row" is a `Map<String, Object?>` keyed by the
/// snake_case SQL column name, with values arriving as either MySQL-protocol
/// strings (the `assoc()` shape from `mysql_client`), already-typed Dart values
/// (the `typedAssoc()` shape — `DateTime`, `int`, `bool`), or `null`. Both
/// shapes are accepted so the mapper is robust to the read strategy
/// `DoltQueryService` picks.
///
/// The field semantics deliberately mirror `Bead.fromJson` / the json codecs so
/// the SQL read path and the bd-CLI read path produce **identical** [Bead]s —
/// the snapshot diff and the SQL-vs-CLI equivalence canary (ADR-0001 Decision 7)
/// depend on byte-for-byte agreement, most subtly on [Bead.labels] ordering,
/// which is why labels are sorted here.
library;

import 'dart:convert';

import '../models/bead.dart';
import '../models/bead_dependency.dart';
import '../models/bead_status.dart';
import '../models/dependency_type.dart';
import '../models/issue_type.dart';

/// Maps a `SELECT * FROM issues` row into a [Bead].
///
/// [labels], [dependencyCount], [dependentCount] and [commentCount] are supplied
/// by the caller from the sibling label/dependency/comment queries — they are
/// not columns on `issues`. [labels] is sorted defensively so the result matches
/// the CLI path regardless of SQL row order.
///
/// Column normalizations (matching the json codec):
/// - null text columns (`title`, `description`, …) collapse to `''`;
/// - `ephemeral` (MySQL `TINYINT(1)`) arrives as `0`/`1`, `'0'`/`'1'`, or `bool`
///   and becomes a `bool`;
/// - `metadata` (MySQL `JSON`) arrives as a JSON `String` (decoded here) or an
///   already-decoded `Map`, and becomes a `Map<String, dynamic>`;
/// - timestamps arrive as `DateTime` or as a MySQL datetime `String`
///   (`yyyy-MM-dd HH:mm:ss`, which `DateTime.parse` accepts).
Bead beadFromRow(
  Map<String, Object?> row, {
  List<String> labels = const [],
  int dependencyCount = 0,
  int dependentCount = 0,
  int commentCount = 0,
}) {
  final sortedLabels = [...labels]..sort();
  return Bead(
    id: _requireString(row, 'id'),
    title: _str(row['title']),
    description: _str(row['description']),
    design: _str(row['design']),
    acceptanceCriteria: _str(row['acceptance_criteria']),
    notes: _str(row['notes']),
    specId: _str(row['spec_id']),
    status: BeadStatus(_strOr(row['status'], BeadStatus.open.wire)),
    priority: _int(row['priority']) ?? 0,
    issueType: IssueType(_strOr(row['issue_type'], IssueType.task.wire)),
    assignee: _str(row['assignee']),
    owner: _str(row['owner']),
    estimatedMinutes: _int(row['estimated_minutes']),
    createdAt: _dateTime(row['created_at']),
    createdBy: _str(row['created_by']),
    updatedAt: _dateTime(row['updated_at']),
    startedAt: _dateTime(row['started_at']),
    closedAt: _dateTime(row['closed_at']),
    closeReason: _str(row['close_reason']),
    closedBySession: _str(row['closed_by_session']),
    dueAt: _dateTime(row['due_at']),
    deferUntil: _dateTime(row['defer_until']),
    externalRef: _strOrNull(row['external_ref']),
    sourceSystem: _str(row['source_system']),
    metadata: _metadata(row['metadata']),
    labels: sortedLabels,
    ephemeral: _bool(row['ephemeral']),
    dependencyCount: dependencyCount,
    dependentCount: dependentCount,
    commentCount: commentCount,
  );
}

/// Maps a dependencies row into a [BeadDependency].
///
/// The dependencies table split its target column into three typed columns
/// (`depends_on_issue_id`/`depends_on_wisp_id`/`depends_on_external`, migrations
/// 0041–0050). The [DoltQueryService] query re-exposes the natural target as a
/// `depends_on_id` alias (`COALESCE(...)`, mirroring beads' own read path), so
/// this mapper reads that single alias and is agnostic to which typed column the
/// edge actually lives in.
BeadDependency dependencyFromRow(Map<String, Object?> row) {
  return BeadDependency(
    issueId: _requireString(row, 'issue_id'),
    dependsOnId: _requireString(row, 'depends_on_id'),
    type: DependencyType(_strOr(row['type'], DependencyType.blocks.wire)),
    createdAt: _dateTime(row['created_at']),
    createdBy: _str(row['created_by']),
    // BeadDependency keeps metadata as the raw JSON string (Track A choice).
    metadata: _metadataString(row['metadata']),
    threadId: _str(row['thread_id']),
  );
}

// ---------------------------------------------------------------------------
// Scalar normalizers. All accept the union of `assoc()`/`typedAssoc()`/null.
// ---------------------------------------------------------------------------

/// A required, non-null string column. Throws [ArgumentError] if absent/null —
/// `id`, `issue_id`, `depends_on_id` are NOT NULL / part of a primary key, so a
/// null here is a real schema violation, not a normalizable absence.
String _requireString(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value == null) {
    throw ArgumentError.value(
      row,
      'row',
      'missing required non-null column "$column"',
    );
  }
  return value.toString();
}

/// A nullable text column, collapsed to `''` when null/absent (mirrors the
/// `as String? ?? ''` json codec default).
String _str(Object? value) => value == null ? '' : value.toString();

/// A nullable text column with a non-empty fallback (used for enum-ish
/// wire-string columns whose json default is a constant, not `''`).
String _strOr(Object? value, String fallback) {
  if (value == null) return fallback;
  final s = value.toString();
  return s.isEmpty ? fallback : s;
}

/// A genuinely nullable text column (`external_ref`): null stays null.
String? _strOrNull(Object? value) => value?.toString();

/// An integer column: accepts `int`, `num`, or a numeric `String`; null/absent
/// or unparseable → null (callers apply their own `?? 0` where appropriate).
int? _int(Object? value) {
  switch (value) {
    case null:
      return null;
    case final int v:
      return v;
    case final num v:
      return v.toInt();
    case final String v:
      final trimmed = v.trim();
      if (trimmed.isEmpty) return null;
      return int.tryParse(trimmed) ?? num.tryParse(trimmed)?.toInt();
    default:
      return null;
  }
}

/// A `TINYINT(1)` boolean: `bool` passes through; `0`/`1` (or `'0'`/`'1'`, or
/// any non-zero number) become `false`/`true`; null/absent → `false`.
bool _bool(Object? value) {
  switch (value) {
    case null:
      return false;
    case final bool v:
      return v;
    case final num v:
      return v != 0;
    case final String v:
      final trimmed = v.trim().toLowerCase();
      if (trimmed.isEmpty || trimmed == '0' || trimmed == 'false') return false;
      return true;
    default:
      return false;
  }
}

/// A `DATETIME` column: `DateTime` passes through; a MySQL datetime `String`
/// (`yyyy-MM-dd HH:mm:ss[.fff]`) is parsed; null/absent/unparseable → null.
///
/// MySQL `DATETIME` is timezone-naive wall-clock, and bd stores UTC (the bd
/// JSON read path emits it with a trailing `Z`). `DateTime.parse` would read a
/// zoneless string as **local** time, so a zoneless value is normalized to UTC
/// — otherwise the SQL and CLI read paths would disagree by the host's offset
/// and break the equivalence canary (ADR-0001 Decision 7).
DateTime? _dateTime(Object? value) {
  switch (value) {
    case null:
      return null;
    case final DateTime v:
      return v;
    case final String v:
      final trimmed = v.trim();
      if (trimmed.isEmpty) return null;
      final hasZone =
          trimmed.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(trimmed);
      final normalized = hasZone
          ? trimmed
          : '${trimmed.replaceFirst(' ', 'T')}Z';
      return DateTime.tryParse(normalized);
    default:
      return null;
  }
}

/// A `JSON` column for [Bead.metadata]: a decoded `Map` passes through; a JSON
/// `String` is decoded; anything else (or a decode failure) → empty map. The
/// result is always a fresh `Map<String, dynamic>`.
Map<String, dynamic> _metadata(Object? value) {
  switch (value) {
    case null:
      return <String, dynamic>{};
    case final Map<String, dynamic> v:
      return Map<String, dynamic>.from(v);
    case final Map<Object?, Object?> v:
      return <String, dynamic>{
        for (final entry in v.entries) entry.key.toString(): entry.value,
      };
    case final String v:
      final trimmed = v.trim();
      if (trimmed.isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return <String, dynamic>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          };
        }
        return <String, dynamic>{};
      } on FormatException {
        return <String, dynamic>{};
      }
    default:
      return <String, dynamic>{};
  }
}

/// A `JSON` column for [BeadDependency.metadata], which Track A keeps as the
/// raw wire string: a `String` passes through; a decoded `Map` is re-encoded so
/// both read paths agree; null/absent → `''`.
String _metadataString(Object? value) {
  switch (value) {
    case null:
      return '';
    case final String v:
      return v;
    case final Map<Object?, Object?> v:
      return jsonEncode(v);
    default:
      return value.toString();
  }
}
