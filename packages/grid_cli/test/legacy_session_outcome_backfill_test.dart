import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import '../tool/backfill_legacy_session_outcomes.dart';

Bead _row(
  String id, {
  required IssueType type,
  required BeadStatus status,
  DateTime? createdAt,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  issueType: type,
  status: status,
  createdAt: createdAt,
  metadata: {'rig': 'tgdog', 'untouched': 'yes', ...metadata},
);

final class _LegacyBackfillRunner implements BdRunner {
  _LegacyBackfillRunner(this.rows);

  final List<Bead> rows;
  final List<String> updatedIds = [];

  Bead bead(String id) => rows.singleWhere((row) => row.id == id);

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    switch (args.first) {
      case 'list':
        expect(
          args,
          containsAllInOrder([
            'list',
            '-t',
            GridIssueTypes.session.wire,
            '--status',
            BeadStatus.closed.wire,
            '--json',
          ]),
        );
        return _envelope([
          for (final row in rows)
            if (row.issueType == GridIssueTypes.session && row.isClosed)
              row.toJson(),
        ]);
      case 'update':
        final id = args[1];
        expect(
          args,
          containsAllInOrder([
            'update',
            id,
            '--json',
            '--actor',
            'grid-controller',
            '--set-metadata',
            '${SessionBeadKeys.outcome}=$kSessionOutcomeLegacy',
          ]),
        );
        final index = rows.indexWhere((row) => row.id == id);
        rows[index] = rows[index].copyWith(
          metadata: {
            ...rows[index].metadata,
            SessionBeadKeys.outcome: kSessionOutcomeLegacy,
          },
        );
        updatedIds.add(id);
        return _envelope({'id': id});
      default:
        throw StateError('unexpected bd call: $args');
    }
  }

  BdResult _envelope(Object data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );
}

void main() {
  test(
    'filters the legacy population and the second run writes nothing',
    () async {
      final cutoff = DateTime.utc(2026, 7, 13);
      final runner = _LegacyBackfillRunner([
        _row(
          'tgdog-eligible',
          type: GridIssueTypes.session,
          status: BeadStatus.closed,
          createdAt: cutoff.subtract(const Duration(seconds: 1)),
        ),
        _row(
          'tgdog-open',
          type: GridIssueTypes.session,
          status: BeadStatus.open,
          createdAt: cutoff.subtract(const Duration(days: 1)),
        ),
        _row(
          'tgdog-at-cutoff',
          type: GridIssueTypes.session,
          status: BeadStatus.closed,
          createdAt: cutoff,
        ),
        _row(
          'tgdog-after',
          type: GridIssueTypes.session,
          status: BeadStatus.closed,
          createdAt: cutoff.add(const Duration(seconds: 1)),
        ),
        _row(
          'tgdog-missing-created',
          type: GridIssueTypes.session,
          status: BeadStatus.closed,
        ),
        _row(
          'tgdog-complete',
          type: GridIssueTypes.session,
          status: BeadStatus.closed,
          createdAt: cutoff.subtract(const Duration(days: 1)),
          metadata: const {SessionBeadKeys.outcome: kSessionOutcomeComplete},
        ),
        _row(
          'tg-not-session',
          type: IssueType.task,
          status: BeadStatus.closed,
          createdAt: cutoff.subtract(const Duration(days: 1)),
        ),
      ]);

      final first = await LegacySessionOutcomeBackfill.run(
        bd: BdCliService(runner),
        before: cutoff,
      );
      expect(first, (scanned: 5, stamped: 1, skippedMissingCreatedAt: 1));
      expect(runner.updatedIds, ['tgdog-eligible']);
      expect(
        runner.bead('tgdog-eligible').metadata,
        containsPair(SessionBeadKeys.outcome, kSessionOutcomeLegacy),
      );
      expect(
        runner.bead('tgdog-eligible').metadata,
        containsPair('untouched', 'yes'),
      );
      for (final id in [
        'tgdog-open',
        'tgdog-at-cutoff',
        'tgdog-after',
        'tgdog-missing-created',
      ]) {
        expect(
          runner.bead(id).metadata,
          isNot(contains(SessionBeadKeys.outcome)),
        );
      }
      expect(
        runner.bead('tgdog-complete').metadata[SessionBeadKeys.outcome],
        kSessionOutcomeComplete,
      );

      final second = await LegacySessionOutcomeBackfill.run(
        bd: BdCliService(runner),
        before: cutoff,
      );
      expect(second, (scanned: 5, stamped: 0, skippedMissingCreatedAt: 1));
      expect(runner.updatedIds, ['tgdog-eligible']);
    },
  );
}
