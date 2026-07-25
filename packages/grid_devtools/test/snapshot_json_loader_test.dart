import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

TreeSnapshot _snapshot(String id) => TreeSnapshot(
  contractVersion: 1,
  projectedAt: DateTime.utc(2026, 7, 25),
  root: TreeNode(
    seedType: 'Grid',
    id: id,
    properties: const [],
    children: const [],
  ),
);

void main() {
  test('decodes one snapshot object', () {
    final decoded = decodeSnapshotRecording(jsonEncode(_snapshot('one')));
    expect(decoded.single.root.id, 'one');
  });

  test('decodes an array of snapshots', () {
    final decoded = decodeSnapshotRecording(
      jsonEncode([_snapshot('one'), _snapshot('two')]),
    );
    expect(decoded.map((value) => value.root.id), ['one', 'two']);
  });

  test('rejects an empty recording', () {
    expect(() => decodeSnapshotRecording('[]'), throwsFormatException);
  });

  test('rejects a scalar', () {
    expect(() => decodeSnapshotRecording('42'), throwsFormatException);
  });

  test('rejects malformed JSON', () {
    expect(() => decodeSnapshotRecording('{'), throwsFormatException);
  });

  test('rejects missing contract fields', () {
    expect(
      () => decodeSnapshotRecording('{"contractVersion":1}'),
      throwsA(anything),
    );
  });
}
