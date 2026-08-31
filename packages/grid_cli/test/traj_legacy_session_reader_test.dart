/// grid_cli's ledger half of the §9 shadow seam: the session-bead → view
/// projection (markers from `projectSession`, round from the `#rN` key
/// shape), the reader over the injected fetch, and the factory's graceful
/// degrade on a home with no ledger.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead, BeadStatus, IssueType;
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_trajectory/grid_trajectory.dart'
    show AttemptLifecycleShadow, ShadowCompare, SubjectRecords;
import 'package:test/test.dart';

Bead sessionBead({
  String id = 'tranquility-1',
  String workBead = 'tg-9abc',
  BeadStatus status = BeadStatus.open,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  issueType: const IssueType('session'),
  status: status,
  metadata: {'work_bead': workBead, ...metadata},
);

void main() {
  group('legacySessionViewOf', () {
    test('a live bare-key session: open, no round, no markers', () {
      final view = legacySessionViewOf(sessionBead());
      expect(view.sessionId, 'tranquility-1');
      expect(view.workBeadId, 'tg-9abc');
      expect(view.closed, isFalse);
      expect(view.completed, isFalse);
      expect(view.held, isFalse);
      expect(view.voided, isFalse);
      expect(view.round, isNull);
    });

    test('a completed close carries the grid.outcome marker', () {
      final view = legacySessionViewOf(
        sessionBead(
          status: BeadStatus.closed,
          metadata: const {'grid.outcome': 'complete'},
        ),
      );
      expect(view.closed, isTrue);
      expect(view.completed, isTrue);
    });

    test('the #rN retired key strips to the base id and names the round', () {
      final view = legacySessionViewOf(sessionBead(workBead: 'tg-9abc#r2'));
      expect(view.workBeadId, 'tg-9abc');
      expect(view.round, 2);
      expect(view.voided, isFalse);
    });

    test('the #void- dead key strips and flags voided, never a round', () {
      final view = legacySessionViewOf(
        sessionBead(workBead: 'tg-9abc#void-tranquility-0'),
      );
      expect(view.workBeadId, 'tg-9abc');
      expect(view.voided, isTrue);
      expect(view.round, isNull);
    });

    test('human markers project held + the diagnostic reason', () {
      final escalated = legacySessionViewOf(
        sessionBead(
          status: BeadStatus.closed,
          metadata: const {
            'grid.escalation': 'true',
            'grid.escalation_reason': 'breaker exhausted',
          },
        ),
      );
      expect(escalated.held, isTrue);
      expect(escalated.heldReason, 'breaker exhausted');

      final declined = legacySessionViewOf(
        sessionBead(
          status: BeadStatus.closed,
          metadata: const {
            'grid.rework_declined': 'true',
            'grid.rework_declined_reason': 'orphaned at a gate',
          },
        ),
      );
      expect(declined.held, isTrue);
      expect(declined.heldReason, 'orphaned at a gate');
    });
  });

  group('BdLegacySessionReader', () {
    test('returns the view for a matching bead, null otherwise', () async {
      final reader = BdLegacySessionReader(
        (ids) async => [sessionBead(id: ids.single)],
      );
      final view = await reader.sessionView('tranquility-1');
      expect(view!.workBeadId, 'tg-9abc');

      final empty = BdLegacySessionReader((ids) async => const []);
      expect(await empty.sessionView('tranquility-2'), isNull);
    });
  });

  group('legacyShadowCompareFor', () {
    test(
      'a home with no ledger degrades: nothing comparable, with a reason',
      () async {
        final home = Directory.systemTemp.createTempSync('traj_legacy_');
        addTearDown(() => home.deleteSync(recursive: true));
        final ShadowCompare shadow = await legacyShadowCompareFor(home.path);
        expect(shadow, isA<LegacyStoreUnavailableShadow>());
        expect(shadow.comparableFields, isEmpty);
        expect(shadow.unavailableReason, contains('no grid state store'));
        final result = await shadow.compare(
          sessionId: 's',
          records: const SubjectRecords(records: []),
        );
        expect(result.mismatches, isEmpty);
        // A degrade is not an incomplete READ — it is "no oracle here at all",
        // which the verb reports through unavailableReason instead.
        expect(result.isIncomplete, isFalse);
      },
    );

    test(
      'a seeded state-store layout arms the real Family-1 comparator',
      () async {
        final home = Directory.systemTemp.createTempSync('traj_legacy_');
        addTearDown(() => home.deleteSync(recursive: true));
        // The exact-root layout the resident verbs open: <home>/.grid/.beads,
        // with the store metadata that makes it a well-formed workspace.
        Directory('${home.path}/.grid/.beads').createSync(recursive: true);
        File(
          '${home.path}/.grid/.beads/metadata.json',
        ).writeAsStringSync('{"dolt_mode": "direct"}');
        final shadow = await legacyShadowCompareFor(home.path);
        expect(shadow, isA<AttemptLifecycleShadow>());
      },
    );
  });
}
