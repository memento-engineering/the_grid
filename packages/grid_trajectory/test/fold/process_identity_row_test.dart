import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

void main() {
  test('P6 SQL row decodes every typed field', () {
    final row = ProcessIdentityRow.fromSqlRow(const {
      'attempt_id': 'a-1',
      'session_id': 's-1',
      'round': '2',
      'step_path': 'work/agent',
      'step_round': '3',
      'incarnation': '4',
      'pid': '101',
      'pgid': '100',
      'lease_state': 'held',
      'worktree': '/repo/.grid/worktrees/proj/w-1',
      'branch': 'grid/w-1',
      'base_sha': 'abc',
      'adopted_existing': '1',
      'worktree_state': 'live',
      'predecessor_attempt_id': 'a-0',
      'last_seq': '55',
    });

    expect(row.attemptId, 'a-1');
    expect(row.sessionId, 's-1');
    expect(row.ladder, ('s-1', 2, 'work/agent', 3, 4));
    expect(row.pid, 101);
    expect(row.pgid, 100);
    expect(row.adoptedExisting, isTrue);
    expect(row.worktreeState, 'live');
    expect(row.predecessorAttemptId, 'a-0');
    expect(row.lastSeq, 55);
  });

  test('P6 seed SQL names the typed projection and stable order', () {
    expect(scanProcessIdentityRowsSql, contains('proj_process_identity'));
    expect(
      scanProcessIdentityRowsSql,
      contains('session_id, step_path, round, step_round, incarnation'),
    );
  });
}
