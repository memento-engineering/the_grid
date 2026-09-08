import 'dart:async';

import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

final class FakeMdnsBrowser implements MdnsBrowser {
  FakeMdnsBrowser({this.ads = const Stream<StationAd>.empty()});

  final Stream<StationAd> ads;

  int browseCalls = 0;
  Duration? lastTimeout;

  @override
  Stream<StationAd> browse({Duration timeout = const Duration(seconds: 5)}) {
    browseCalls++;
    lastTimeout = timeout;
    return ads;
  }
}

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
