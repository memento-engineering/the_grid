import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/src/diagnostics/state_store_deadline.dart';
import 'package:test/test.dart';

void main() {
  test('deadline provenance classifies every state-store failure shape', () {
    expect(
      stateStoreDeadlineMetadata(TimeoutException('Future not completed')),
      const {
        'deadlineConstant': 'DoltQueryService.queryTimeout',
        'deadlineMs': '10000',
      },
    );
    expect(
      stateStoreDeadlineMetadata(
        const BdTimeoutException(
          command: ['create', '--graph', 'plan.json'],
          timeout: BdCliService.pourTimeout,
        ),
      ),
      const {
        'deadlineConstant': 'BdCliService.pourTimeout',
        'deadlineMs': '60000',
      },
    );
    expect(
      stateStoreDeadlineMetadata(
        const BdTimeoutException(
          command: ['query', 'id=tg-1'],
          timeout: Duration(seconds: 15),
        ),
      ),
      const {
        'deadlineConstant': 'BdRunner.run(timeout)',
        'deadlineMs': '15000',
      },
    );
    expect(stateStoreDeadlineMetadata(StateError('not a timeout')), isEmpty);
  });
}
