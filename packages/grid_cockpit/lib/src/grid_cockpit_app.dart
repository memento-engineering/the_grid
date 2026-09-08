import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grid_station_client/grid_station_client.dart';

import 'cockpit_connection_bar.dart';
import 'cockpit_dashboard.dart';

/// Watch-only application shell for one resident station.
final class GridCockpitApp extends StatefulWidget {
  /// Creates the app and transfers ownership of [controller].
  ///
  /// Callers must neither reuse nor replace the controller while this widget
  /// is mounted.
  const GridCockpitApp({super.key, required this.controller});

  /// Connection controller owned and disposed by this app.
  final LiveConnectionController controller;

  @override
  State<GridCockpitApp> createState() => _GridCockpitAppState();
}

final class _GridCockpitAppState extends State<GridCockpitApp> {
  late final LiveConnectionController _controller = widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_controller.autoConnect());
    });
  }

  @override
  void didUpdateWidget(covariant GridCockpitApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      throw StateError(
        'GridCockpitApp controller ownership cannot change while mounted',
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Grid Cockpit',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CockpitConnectionBar(controller: _controller),
          Expanded(
            child: ValueListenableBuilder<LiveConnectionState>(
              valueListenable: _controller,
              builder: (context, state, _) => switch (state) {
                LiveConnected(:final source) => CockpitDashboard(
                  source: source,
                ),
                LiveDiscovering() || LiveConnecting() => const Center(
                  child: CircularProgressIndicator(),
                ),
                LiveDisconnected() ||
                LiveDiscoveryUnavailable() ||
                LiveManual() ||
                LiveFailed() => const Center(
                  child: Text('Connect to a station to view live work.'),
                ),
              },
            ),
          ),
        ],
      ),
    ),
  );
}
