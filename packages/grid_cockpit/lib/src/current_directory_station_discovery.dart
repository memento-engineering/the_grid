import 'dart:io';

import 'package:grid_station_client/grid_station_client.dart';

/// Creates on-box lock discovery rooted at the process working directory.
StationLockDiscovery currentDirectoryStationDiscovery() => StationLockDiscovery(
  workspaceRoots: () async => <Uri>[Directory.current.uri],
  readFile: (uri) => File.fromUri(uri).readAsString(),
);
