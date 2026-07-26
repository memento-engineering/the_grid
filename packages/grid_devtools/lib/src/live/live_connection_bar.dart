import 'package:flutter/material.dart';

import 'live_connection_controller.dart';

/// Shell-level controls for discovering or manually connecting to a station.
final class LiveConnectionBar extends StatefulWidget {
  /// Creates controls bound to [controller].
  const LiveConnectionBar({super.key, required this.controller});

  /// The live connection state owner.
  final LiveConnectionController controller;

  @override
  State<LiveConnectionBar> createState() => _LiveConnectionBarState();
}

class _LiveConnectionBarState extends State<LiveConnectionBar> {
  final _url = TextEditingController();
  final _token = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
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
          LiveDisconnected() => 'Replay • live disconnected',
          LiveDiscovering() => 'Discovering local station…',
          LiveManual(:final message) => message ?? 'Enter station credentials.',
          LiveConnecting() => 'Connecting…',
          LiveConnected() => 'Live station connected',
          LiveFailed(:final message) => message,
        };
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(status, key: const Key('live.status')),
                if (!connected) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: const Key('live.url'),
                          controller: _url,
                          enabled: !busy,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Station URL',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('live.token'),
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
                        key: const Key('live.connect'),
                        onPressed: busy
                            ? null
                            : () => widget.controller.connect(
                                controlUrl: _url.text,
                                token: _token.text,
                              ),
                        child: const Text('Connect'),
                      ),
                    ],
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('live.disconnect'),
                      onPressed: widget.controller.disconnect,
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
