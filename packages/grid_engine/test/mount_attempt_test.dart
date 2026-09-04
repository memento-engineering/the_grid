import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// Tests for the DURABLE remount-attempt budget (tg-zlfu) — the bound on how
/// many times one work bead may be re-derived by the frontier and remounted.
///
/// The loop this bounds is the storage amplifier behind store growth: a bead
/// whose circuit fails WITHOUT mutating the graph is re-derived and remounted,
/// unbounded, minting a whole session graph every turn.
Bead attemptRecord(
  String id, {
  required String workBead,
  String? count,
  bool closed = false,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  title: 'grid mount-attempt $workBead',
  issueType: GridIssueTypes.mountAttempt,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': 'tranquility',
    MountAttemptKeys.workBead: workBead,
    if (count != null) MountAttemptKeys.count: count,
    ...metadata,
  },
);

void main() {
  group('projectMountAttempt', () {
    test('projects the record and its count', () {
      final record = projectMountAttempt(
        attemptRecord('att1', workBead: 'tg-1', count: '2'),
      );

      expect(record, isNotNull);
      expect(record!.recordId, 'att1');
      expect(record.workBeadId, 'tg-1');
      expect(record.count, 2);
      expect(record.isExhausted, isFalse);
    });

    test('ignores every bead that is not an attempt record', () {
      final session = Bead(
        id: 'sess1',
        issueType: GridIssueTypes.session,
        status: BeadStatus.open,
        metadata: const {MountAttemptKeys.workBead: 'tg-1'},
      );

      expect(projectMountAttempt(session), isNull);
    });

    test('a record with no join key projects to null — nothing to key on', () {
      final orphan = Bead(
        id: 'att1',
        issueType: GridIssueTypes.mountAttempt,
        status: BeadStatus.open,
        metadata: const {MountAttemptKeys.count: '9'},
      );

      expect(projectMountAttempt(orphan), isNull);
    });

    test(
      'an absent or unparseable count reads as zero — a corrupt record '
      'FAILS OPEN rather than locking a bead out of the frontier forever',
      () {
        expect(
          projectMountAttempt(attemptRecord('att1', workBead: 'tg-1'))!.count,
          0,
        );
        expect(
          projectMountAttempt(
            attemptRecord('att2', workBead: 'tg-2', count: 'not-a-number'),
          )!.count,
          0,
        );
        expect(
          projectMountAttempt(
            attemptRecord('att3', workBead: 'tg-3', count: '-4'),
          )!.count,
          0,
        );
      },
    );
  });

  group('the cap', () {
    Bead work(String id) =>
        Bead(id: id, issueType: IssueType.feature, status: BeadStatus.open);

    test('a bead under the cap is eligible', () {
      final clause = mountAttemptClause({
        'tg-1': const MountAttemptRecord(
          recordId: 'att1',
          workBeadId: 'tg-1',
          count: kMaxMountAttempts - 1,
        ),
      });

      expect(clause(work('tg-1')), isA<MountEligible>());
    });

    test('a bead the station has never attempted is eligible — absence means '
        'zero, so no record is written until the first mount', () {
      expect(mountAttemptClause(const {})(work('tg-1')), isA<MountEligible>());
    });

    test('a bead AT the cap stops being remounted', () {
      final clause = mountAttemptClause({
        'tg-1': const MountAttemptRecord(
          recordId: 'att1',
          workBeadId: 'tg-1',
          count: kMaxMountAttempts,
        ),
      });

      final decision = clause(work('tg-1'));
      expect(decision, isA<MountRefused>());
      final clauseText = (decision as MountRefused).clause;
      expect(
        clauseText,
        contains(kMountAttemptCapClause),
        reason:
            'the refusal must NAME itself — it rides '
            'work.mountEligibilityRefused, which is how a capped bead is '
            'visibly awaiting a human rather than silently absent',
      );
      expect(clauseText, contains('att1'), reason: 'name the record to read');
      expect(clauseText, contains('$kMaxMountAttempts'));
    });

    test('another bead at the cap never refuses THIS one', () {
      final clause = mountAttemptClause({
        'tg-OTHER': const MountAttemptRecord(
          recordId: 'att1',
          workBeadId: 'tg-OTHER',
          count: kMaxMountAttempts,
        ),
      });

      expect(clause(work('tg-1')), isA<MountEligible>());
    });
  });

  group('local mount clauses', () {
    Bead work(String id, IssueType type) =>
        Bead(id: id, issueType: type, status: BeadStatus.open);

    test('dispatchable work preserves the non-resident core allow-list', () {
      final clause = dispatchableWorkClause(resident: false);

      expect(clause(work('tg-task', IssueType.task)), isA<MountEligible>());
      expect(clause(work('tg-epic', IssueType.epic)), isA<MountEligible>());
    });

    test('resident work narrows to driveable types and names exclusions', () {
      final clause = dispatchableWorkClause(resident: true);

      expect(clause(work('tg-bug', IssueType.bug)), isA<MountEligible>());
      expect(
        (clause(work('tg-epic', IssueType.epic)) as MountRefused).clause,
        'issue type epic is not dispatchable for this substation',
      );
      expect(
        (clause(work('tg-gate', GridIssueTypes.gate)) as MountRefused).clause,
        'issue type gate is not dispatchable for this substation',
      );
    });

    test('drive list is open when empty or selected and otherwise names the '
        'exclusion', () {
      final bead = work('tg-1', IssueType.task);

      expect(driveListClause(const {})(bead), isA<MountEligible>());
      expect(driveListClause(const {'tg-1'})(bead), isA<MountEligible>());
      expect(
        (driveListClause(const {'tg-2'})(bead) as MountRefused).clause,
        'bead is not selected by the substation drive list',
      );
    });

    test('composition reports the first local refusal', () {
      final bead = work('tg-epic', IssueType.epic);
      final composed = composeMountEligibility([
        dispatchableWorkClause(resident: true),
        driveListClause(const {'tg-other'}),
      ], null);

      expect(
        (composed(bead) as MountRefused).clause,
        'issue type epic is not dispatchable for this substation',
      );
    });
  });

  group('composeMountEligibility', () {
    Bead work(String id) =>
        Bead(id: id, issueType: IssueType.feature, status: BeadStatus.open);

    MountEligibilityPredicate refusing(String clause) =>
        (_) => MountEligibilityDecision.refused(clause: clause);
    MountEligibilityPredicate eligible() =>
        (_) => const MountEligibilityDecision.eligible();

    test('the engine clause applies even when the station composes NO '
        'eligibility assets at all', () {
      final composed = composeMountEligibility([refusing('attempt-cap')], null);

      expect(composed(work('tg-1')), isA<MountRefused>());
    });

    test("the station's own predicate still refuses", () {
      final composed = composeMountEligibility([
        eligible(),
      ], refusing('approval: missing grid.approved label'));

      final decision = composed(work('tg-1'));
      expect(decision, isA<MountRefused>());
      expect((decision as MountRefused).clause, contains('approval'));
    });

    test('the FIRST refusal wins, so the reported clause is deterministic', () {
      final composed = composeMountEligibility([
        refusing('first'),
        refusing('second'),
      ], refusing('asset'));

      expect((composed(work('tg-1')) as MountRefused).clause, 'first');
    });

    test('all clauses passing is eligible', () {
      final composed = composeMountEligibility([eligible()], eligible());

      expect(composed(work('tg-1')), isA<MountEligible>());
    });
  });

  group('DURABILITY — the counter survives a station bounce', () {
    test('the budget is rebuilt from the STORE, so a fresh projection over the '
        'same state carries the same count', () {
      // A bounce is exactly this: the in-memory projection is discarded and
      // rebuilt from the state store. OTP and Gas City keep restart counters
      // in memory so a supervisor restart resets them; that is wrong here
      // because launchd KeepAlive relaunches aggressively, which would give a
      // loop of loops.
      final stored = attemptRecord(
        'att1',
        workBead: 'tg-1',
        count: '$kMaxMountAttempts',
      );

      final beforeBounce = projectMountAttempt(stored);
      final afterBounce = projectMountAttempt(stored);

      expect(beforeBounce!.count, kMaxMountAttempts);
      expect(afterBounce!.count, kMaxMountAttempts);
      expect(afterBounce.isExhausted, isTrue);
      expect(
        mountAttemptClause({'tg-1': afterBounce})(
          Bead(
            id: 'tg-1',
            issueType: IssueType.feature,
            status: BeadStatus.open,
          ),
        ),
        isA<MountRefused>(),
        reason: 'a bounce must not hand the crash loop a fresh budget',
      );
    });

    test('the count is NOT derived from session beads — session count means '
        'ROUNDS, not attempts', () {
      // A bead reworked five times after five healthy mounts carries five-plus
      // sessions and ZERO crash-loop attempts. Deriving the budget from them
      // would count the wrong population entirely.
      final sessions = [
        for (var round = 1; round <= 5; round++)
          Bead(
            id: 'sess$round',
            issueType: GridIssueTypes.session,
            status: BeadStatus.closed,
            metadata: {'work_bead': 'tg-1#r$round'},
          ),
      ];

      final projected = [
        for (final bead in sessions) projectMountAttempt(bead),
      ].whereType<MountAttemptRecord>();

      expect(projected, isEmpty);
    });
  });
}
