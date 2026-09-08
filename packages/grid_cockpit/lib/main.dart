import 'package:flutter/material.dart';

import 'grid_cockpit.dart';

void main() => runApp(
  GridCockpitApp(
    controller: CockpitConnectionController(
      discovery: currentDirectoryStationDiscovery(),
    ),
  ),
);
