import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grid_station_client/grid_station_client.dart';

/// Discovery and manual-connection controls for the standalone cockpit.
final class CockpitConnectionBar extends StatefulWidget {
  /// Creates controls bound to [controller].
  const CockpitConnectionBar({super.key, required this.controller});

  /// The shared live-connection owner.
  final LiveConnectionController controller;

  @override
  State<CockpitConnectionBar> createState() => _CockpitConnectionBarState();
}

final class _CockpitConnectionBarState extends State<CockpitConnectionBar> {
  final _host = TextEditingController();
  final _token = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiveConnectionState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final busy = state is LiveDiscovering || state is LiveConnecting;
        final connected = state is LiveConnected;
        final status = switch (state) {
          LiveDisconnected() => 'Station disconnected',
          LiveDiscovering() => 'Finding local station…',
          LiveManual(:final message) => message ?? 'Enter station credentials.',
          LiveConnecting() => 'Connecting…',
          LiveConnected() => 'Station connected',
          LiveFailed(:final message) => message,
        };
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(status, key: const Key('cockpit.status')),
                if (!connected) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: const Key('cockpit.host'),
                          controller: _host,
                          enabled: !busy,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Station host:port',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('cockpit.token'),
                          controller: _token,
                          enabled: !busy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Token',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('cockpit.connect'),
                        onPressed: busy
                            ? null
                            : () {
                                unawaited(
                                  widget.controller.connect(
                                    controlUrl: _host.text,
                                    token: _token.text,
                                  ),
                                );
                              },
                        child: const Text('Connect'),
                      ),
                    ],
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('cockpit.disconnect'),
                      onPressed: () {
                        unawaited(widget.controller.disconnect());
                      },
                      child: const Text('Disconnect'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
