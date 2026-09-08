import 'dart:async';

import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';

final class FakeTreeWireSource implements TreeWireSource {
  FakeTreeWireSource({this.latest});

  final StreamController<TreeSnapshot> _snapshots =
      StreamController<TreeSnapshot>.broadcast(sync: true);

  @override
  TreeSnapshot? latest;

  int disposeCalls = 0;

  @override
  Stream<TreeSnapshot> get snapshots => _snapshots.stream;

  void add(TreeSnapshot snapshot) {
    latest = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_snapshots.isClosed) await _snapshots.close();
  }
}
