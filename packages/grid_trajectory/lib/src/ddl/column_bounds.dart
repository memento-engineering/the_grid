/// Column-width bounds derived from the §4 DDL — the rule that a fold value
/// can never fail its own append.
///
/// The trajectory is a LEDGER: a record's identity (session, step, state,
/// failure class, time) is the fact; a free-text `*_reason` is a decoration on
/// it. A decoration that outgrew its column used to take the whole append down
/// with it — dolt answers an oversized VARCHAR with a 1105, and every statement
/// in the append transaction rolls back together, the `trajectory` row
/// included — so the record vanished and the round read as still running
/// (tg-kzvs, lunar epoch 18).
///
/// The cure is to shape the value to the column where the writer derives it.
/// Widths are parsed from [trajectoryTableDdl]'s own statement text, so this
/// file never carries a hand-copied column list.
///
/// SCOPE — deliberately only `*_reason` columns. Identity-bearing text
/// (`idem_key_text`, whose SHA-256 is the `idem_key`; `source`; `receipt`)
/// carries service-derived values of known width, not leg-authored prose, and
/// a bound there would make stored text disagree with the identity derived
/// from it.
library;

import 'trajectory_schema.dart';

/// The append-only log table.
const String kTrajectoryTable = 'trajectory';

/// The P1 session-head projection.
const String kSessionHeadTable = 'proj_session_head';

/// The name suffix that marks a column as leg-authored free text.
const String kReasonColumnSuffix = '_reason';

/// True when [column] is a free-text reason column by name.
bool isReasonColumn(String column) => column.endsWith(kReasonColumnSuffix);

final RegExp _createTablePattern = RegExp(
  r'CREATE TABLE (?:IF NOT EXISTS )?(\w+)',
  caseSensitive: false,
);

final RegExp _createTableEntryPattern = RegExp(
  r'(?:^|,)\s*(\w+)\s+',
  caseSensitive: false,
  multiLine: true,
);

const Set<String> _createTableClauses = {
  'CREATE',
  'PRIMARY',
  'UNIQUE',
  'KEY',
  'CONSTRAINT',
  'FOREIGN',
  'CHECK',
  'AND',
  'OR',
};

String? _createTableName(String statement) =>
    _createTablePattern.firstMatch(statement)?.group(1)?.toLowerCase();

/// Every column declared by one CREATE TABLE [statement].
///
/// The same CREATE TABLE parser that derives [trajectoryColumnWidths] backs
/// this test-facing view, so schema-coverage tests do not carry a second DDL
/// parser.
Set<String> createTableColumnNames(String statement) {
  if (_createTableName(statement) == null) return const <String>{};
  return Set<String>.unmodifiable({
    for (final match in _createTableEntryPattern.allMatches(statement))
      if (!_createTableClauses.contains(match.group(1)!.toUpperCase()))
        match.group(1)!.toLowerCase(),
  });
}

Map<String, Map<String, int>> _parseColumnWidths() {
  final varcharColumn = RegExp(
    r'(\w+)\s+VARCHAR\((\d+)\)',
    caseSensitive: false,
  );
  final parsed = <String, Map<String, int>>{};
  for (final statement in trajectoryTableDdl) {
    final table = _createTableName(statement);
    if (table == null) continue;
    parsed[table] = Map<String, int>.unmodifiable({
      for (final match in varcharColumn.allMatches(statement))
        match.group(1)!.toLowerCase(): int.parse(match.group(2)!),
    });
  }
  return Map<String, Map<String, int>>.unmodifiable(parsed);
}

/// Every `VARCHAR(n)` the §4 DDL declares: table name → column name → n.
final Map<String, Map<String, int>> trajectoryColumnWidths =
    _parseColumnWidths();

/// The [isReasonColumn] subset of [trajectoryColumnWidths] — the columns whose
/// value is leg-authored prose and therefore unbounded at its source. Tables
/// declaring no reason column are absent.
final Map<String, Map<String, int>> trajectoryReasonColumnWidths =
    Map<String, Map<String, int>>.unmodifiable({
      for (final entry in trajectoryColumnWidths.entries)
        if (entry.value.keys.any(isReasonColumn))
          entry.key: Map<String, int>.unmodifiable({
            for (final column in entry.value.entries)
              if (isReasonColumn(column.key)) column.key: column.value,
          }),
    });

/// [value] shaped to fit [limit] CHARACTERS, with a visible marker when it did
/// not fit.
///
/// A bounded value is exactly [limit] code points: the head of [value] followed
/// by ` …[truncated from <original length>]`. The marker states the ORIGINAL
/// length rather than the dropped count, so the kept head never depends on its
/// own width. Truncation is by CODE POINT (never by UTF-16 unit), so an astral
/// character is dropped whole and the result can never carry a lone surrogate.
///
/// A [limit] too small to hold the marker plus one kept character yields the
/// first [limit] code points, unmarked. The function is TOTAL by construction:
/// its caller is an append that must not fail.
String boundText(String value, int limit) {
  if (limit <= 0) return '';
  final runes = value.runes.toList();
  if (runes.length <= limit) return value;
  final marker = ' …[truncated from ${runes.length}]';
  final keep = limit - marker.runes.length;
  if (keep < 1) return String.fromCharCodes(runes.take(limit));
  return '${String.fromCharCodes(runes.take(keep))}$marker';
}

/// [columns] with every declared reason column of [table] shaped to its
/// declared width by [boundText].
///
/// Non-reason columns, non-String values and nulls pass through untouched, and
/// a table the DDL does not declare returns [columns] unchanged — the map is a
/// SQL parameter set, and this function only ever narrows a value that could
/// not have been stored at all.
Map<String, Object?> boundReasonColumns(
  String table,
  Map<String, Object?> columns,
) {
  final widths = trajectoryReasonColumnWidths[table];
  if (widths == null) return columns;
  return {
    for (final entry in columns.entries)
      entry.key: switch ((widths[entry.key], entry.value)) {
        (final int limit, final String text) => boundText(text, limit),
        _ => entry.value,
      },
  };
}
