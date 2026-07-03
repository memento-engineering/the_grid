import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('IssueTypeDriveability', () {
    test('driveable types are the DRIVEABLE-WORK boundary (RS-3/D-R4): '
        'task/bug/feature/chore only — every other core type, including the '
        'organizational ones, is not driveable', () {
      expect(IssueType.task.isDriveable, isTrue);
      expect(IssueType.bug.isDriveable, isTrue);
      expect(IssueType.feature.isDriveable, isTrue);
      expect(IssueType.chore.isDriveable, isTrue);
      expect(IssueType.epic.isDriveable, isFalse);
      expect(IssueType.decision.isDriveable, isFalse);
      expect(IssueType.spike.isDriveable, isFalse);
      expect(IssueType.story.isDriveable, isFalse);
      expect(IssueType.milestone.isDriveable, isFalse);
      expect(IssueType.molecule.isDriveable, isFalse);
    });
  });
}
