/// Standalone macOS operator cockpit for resident grid stations.
library;

import 'package:grid_station_client/grid_station_client.dart';

export 'package:grid_station_client/grid_station_client.dart'
    show
        LiveConnected,
        LiveConnecting,
        LiveConnectionController,
        LiveConnectionState,
        LiveDisconnected,
        LiveDiscovering,
        LiveDiscoveryUnavailable,
        LiveFailed,
        LiveManual,
        LiveTreeSourceConnector;
export 'src/cockpit_connection_bar.dart' show CockpitConnectionBar;
export 'src/cockpit_dashboard.dart' show CockpitDashboard;
export 'src/current_directory_station_discovery.dart'
    show currentDirectoryStationDiscovery;
export 'src/grid_cockpit_app.dart' show GridCockpitApp;
export 'src/mdns_station_discovery.dart'
    show MdnsStationDiscovery, StationChoice, localNetworkStationDiscovery;

/// Cockpit vocabulary for the shared live-connection state.
typedef CockpitConnectionState = LiveConnectionState;

/// Cockpit vocabulary for the shared disconnected state.
typedef CockpitDisconnected = LiveDisconnected;

/// Cockpit vocabulary for the shared discovery-in-progress state.
typedef CockpitDiscovering = LiveDiscovering;

/// Cockpit vocabulary for unavailable local discovery.
typedef CockpitDiscoveryUnavailable = LiveDiscoveryUnavailable;

/// Cockpit vocabulary for the shared manual-credentials state.
typedef CockpitManual = LiveManual;

/// Cockpit vocabulary for the shared connection-in-progress state.
typedef CockpitConnecting = LiveConnecting;

/// Cockpit vocabulary for the shared connected state.
typedef CockpitConnected = LiveConnected;

/// Cockpit vocabulary for the shared failed state.
typedef CockpitFailed = LiveFailed;

/// Cockpit vocabulary for the shared tree-source construction seam.
typedef CockpitTreeSourceConnector = LiveTreeSourceConnector;

/// Cockpit vocabulary for the shared live-connection owner.
typedef CockpitConnectionController = LiveConnectionController;
