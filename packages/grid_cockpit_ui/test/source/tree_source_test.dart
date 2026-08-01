import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

import '../fixtures.dart';

final class FakeTreeWireSource implements TreeWireSource {
  FakeTreeWireSource() {
    stream = controller.stream;
  }

  TreeSnapshot? current;
  final controller = StreamController<TreeSnapshot>.broadcast();
  late final Stream<TreeSnapshot> stream;
  int disposeCalls = 0;

  @override
  TreeSnapshot? get latest => current;

  @override
  Stream<TreeSnapshot> get snapshots => stream;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await controller.close();
  }
}

void main() {
  test('live source delegates latest and preserves stream identity', () async {
    final wire = FakeTreeWireSource();
    final source = LiveTreeSource(wire);
    expect(source.latest, isNull);
    expect(identical(source.snapshots, wire.snapshots), isTrue);

    wire.current = snapshot(version: 1);
    expect(identical(source.latest, wire.current), isTrue);
    await source.dispose();
    expect(wire.disposeCalls, 1);
    expect(source.snapshots, emitsDone);
  });

  test('replay refuses an empty recording', () {
    expect(() => ReplayTreeSource(const []), throwsArgumentError);
  });

  test('replay seeks and advances in order and validates ranges', () async {
    final first = snapshot(version: 1);
    final second = snapshot(version: 2);
    final third = snapshot(version: 3);
    final source = ReplayTreeSource([first, second, third]);
    final emitted = <TreeSnapshot>[];
    source.snapshots.listen(emitted.add);

    expect(source.latest, same(first));
    expect(source.index, 0);
    expect(source.advance(), isTrue);
    source.seek(2);
    expect(emitted, [same(second), same(third)]);
    expect(source.canAdvance, isFalse);
    expect(source.advance(), isFalse);
    expect(() => source.seek(3), throwsRangeError);

    await source.dispose();
    expect(source.snapshots, emitsDone);
  });
}
