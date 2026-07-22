import 'package:beads_dart/src/errors/bd_exception.dart';
import 'package:beads_dart/src/services/dolt_schema_shape.dart';
import 'package:test/test.dart';

import '../support/schema_probe_rows.dart';

void main() {
  group('DoltSchemaShape.fromColumnRows (pure)', () {
    test('the live v53 column set is supported', () {
      expect(kV53Shape.missing, isEmpty);
      expect(kV53Shape.isSupported, isTrue);
      expect(kV53Shape.migrationVersion, 53);
      expect(kV53Shape.assertSupported, returnsNormally);
    });

    test('row keys are matched case-insensitively', () {
      final shape = DoltSchemaShape.fromColumnRows([
        {'T': 'dependencies', 'C': 'depends_on_external'},
      ]);
      expect(shape.hasColumn('dependencies', 'depends_on_external'), isTrue);
    });

    test('a missing required column is named, and only that one', () {
      final rows = [
        for (final row in kV53ProbeRows)
          if (!(row['t'] == 'issues' && row['c'] == 'is_blocked')) row,
      ];
      final shape = DoltSchemaShape.fromColumnRows(rows, migrationVersion: 99);
      expect(shape.missing, ['issues.is_blocked']);
      expect(
        shape.assertSupported,
        throwsA(
          isA<BdSchemaDriftException>()
              .having((e) => e.missing, 'missing', ['issues.is_blocked'])
              .having(
                (e) => e.message,
                'message',
                contains('issues.is_blocked'),
              )
              .having((e) => e.message, 'message', contains('migration 99')),
        ),
      );
    });

    test('the wisp family is optional but must be whole when present', () {
      final noWisps = [
        for (final row in kV53ProbeRows)
          if (!(row['t']! as String).startsWith('wisp')) row,
      ];
      expect(DoltSchemaShape.fromColumnRows(noWisps).missing, isEmpty);

      final brokenWisps = [
        for (final row in kV53ProbeRows)
          if (!(row['t'] == 'wisp_dependencies' && row['c'] == 'thread_id'))
            row,
      ];
      expect(DoltSchemaShape.fromColumnRows(brokenWisps).missing, [
        'wisp_dependencies.thread_id',
      ]);
    });

    test('descriptive text columns are NOT required', () {
      // beadFromRow collapses an absent title/description to '', so requiring
      // them would refuse a store the read path can still serve correctly.
      final rows = [
        for (final row in kV53ProbeRows)
          if (row['c'] != 'title' && row['c'] != 'description') row,
      ];
      expect(DoltSchemaShape.fromColumnRows(rows).missing, isEmpty);
    });

    test('an absent required table is named as the table itself', () {
      final rows = [
        for (final row in kV53ProbeRows)
          if (row['t'] != 'labels') row,
      ];
      expect(DoltSchemaShape.fromColumnRows(rows).missing, ['labels']);
    });
  });

  group('DoltSchemaShape.depTargetExprFor', () {
    test('COALESCEs every present target column, in beads order', () {
      expect(
        kV53Shape.depTargetExprFor('dependencies'),
        'COALESCE(depends_on_issue_id, depends_on_wisp_id, '
        'depends_on_external)',
      );
      expect(
        kV53Shape.depTargetExprFor('wisp_dependencies'),
        'COALESCE(depends_on_issue_id, depends_on_wisp_id, '
        'depends_on_external)',
      );
    });

    test('depends_on_external is always in the expression (ADR-0000 A44 '
        'cross-store edges must survive the read)', () {
      expect(
        kV53Shape.depTargetExprFor('dependencies'),
        contains('depends_on_external'),
      );
      // …and a store WITHOUT it is refused outright rather than read with
      // cross-store edges silently dropped (the `bd doctor --fix` orphan
      // interpretation this client must not inherit).
      final rows = [
        for (final row in kV53ProbeRows)
          if (row['c'] != 'depends_on_external') row,
      ];
      expect(
        DoltSchemaShape.fromColumnRows(rows).missing,
        contains('dependencies.depends_on_external'),
      );
    });

    test('a single present target column needs no COALESCE', () {
      final shape = DoltSchemaShape.fromColumnRows([
        {'t': 'dependencies', 'c': 'depends_on_issue_id'},
      ]);
      expect(shape.depTargetExprFor('dependencies'), 'depends_on_issue_id');
    });

    test('an absent table throws LOUDLY rather than emitting empty SQL', () {
      expect(
        () => kV53Shape.depTargetExprFor('nope'),
        throwsA(isA<StateError>()),
      );
      final shape = DoltSchemaShape.fromColumnRows([
        {'t': 'dependencies', 'c': 'issue_id'},
      ]);
      expect(
        () => shape.depTargetExprFor('dependencies'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DoltSchemaShape.probeSql', () {
    test('names exactly the six tables the read path touches', () {
      for (final table in const [
        'issues',
        'wisps',
        'labels',
        'wisp_labels',
        'dependencies',
        'wisp_dependencies',
      ]) {
        expect(DoltSchemaShape.probeSql, contains("'$table'"));
      }
      // Scoped to the connection's own database, and a read.
      expect(DoltSchemaShape.probeSql, contains('table_schema = DATABASE()'));
      expect(DoltSchemaShape.probeSql, startsWith('SELECT '));
    });
  });
}
