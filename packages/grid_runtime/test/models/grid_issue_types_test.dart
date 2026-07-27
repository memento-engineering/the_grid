import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('owns the grid custom vocabulary and infrastructure partition', () {
    expect(
      GridIssueTypes.customTypes.map((type) => type.wire).toSet(),
      equals({
        'agent',
        'convergence',
        'convoy',
        'event',
        'gate',
        'merge-request',
        'message',
        'molecule',
        'rig',
        'role',
        'session',
        'spec',
        'step',
      }),
    );
    expect(GridIssueTypes.link, const IssueType('link'));
    expect(GridIssueTypes.agent.isGridInfrastructure, isTrue);
    expect(GridIssueTypes.rig.isGridInfrastructure, isTrue);
    expect(GridIssueTypes.role.isGridInfrastructure, isTrue);
    expect(GridIssueTypes.session.isGridInfrastructure, isFalse);
    expect(GridIssueTypes.link.isGridInfrastructure, isFalse);
    expect(const IssueType('unknown').isGridInfrastructure, isFalse);
  });
}
