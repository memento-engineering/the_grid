import 'package:flutter/material.dart';

import 'events/events_panel.dart';
import 'handshake_state.dart';
import 'protocol/grid_exploration_client.dart';

/// The visible content of the grid DevTools extension: a handshake header
/// (advertised plugins + tools) over an [EventsPanel].
///
/// Split out from the `DevToolsExtension`-wrapping entrypoint (`main.dart`)
/// so widget tests can pump it with a fake [GridExplorationClient] and never
/// touch the browser-only `serviceManager` globals. The shell is
/// `serviceManager`-free by construction: it talks only through [client].
///
/// On mount it runs `ext.exploration.core.handshake` and publishes a
/// [HandshakeState]; [retrigger], when supplied, re-runs the probe on every
/// fire (production wires reconnect listenables).
class GridDevToolsShell extends StatefulWidget {
  const GridDevToolsShell({super.key, required this.client, this.retrigger});

  /// The exploration-protocol seam — the shell's only dependency.
  final GridExplorationClient client;

  /// Optional listenable that re-runs the handshake probe when it fires
  /// (e.g. `serviceManager.connectedState` on reconnect). Tests can leave
  /// it null and call the probe via a remount.
  final Listenable? retrigger;

  @override
  State<GridDevToolsShell> createState() => _GridDevToolsShellState();
}

class _GridDevToolsShellState extends State<GridDevToolsShell> {
  final ValueNotifier<HandshakeState> _handshake =
      ValueNotifier<HandshakeState>(const HandshakeLoading());

  /// Drops stale probe results — only the latest probe may publish.
  int _probeGen = 0;

  @override
  void initState() {
    super.initState();
    widget.retrigger?.addListener(_onRetrigger);
    // ignore: unawaited_futures
    _probe();
  }

  @override
  void didUpdateWidget(covariant GridDevToolsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retrigger != widget.retrigger) {
      oldWidget.retrigger?.removeListener(_onRetrigger);
      widget.retrigger?.addListener(_onRetrigger);
    }
    if (oldWidget.client != widget.client) {
      // ignore: unawaited_futures
      _probe();
    }
  }

  @override
  void dispose() {
    widget.retrigger?.removeListener(_onRetrigger);
    _handshake.dispose();
    super.dispose();
  }

  void _onRetrigger() {
    // ignore: unawaited_futures
    _probe();
  }

  Future<void> _probe() async {
    final gen = ++_probeGen;
    _handshake.value = const HandshakeLoading();
    try {
      final result = await widget.client.handshake();
      if (gen != _probeGen || !mounted) return;
      _handshake.value = HandshakeLoaded(result);
    } on GridBindingMissing {
      if (gen != _probeGen || !mounted) return;
      _handshake.value = const HandshakeBindingMissing();
    } on Object catch (e) {
      if (gen != _probeGen || !mounted) return;
      _handshake.value = HandshakeFailed(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<HandshakeState>(
            valueListenable: _handshake,
            builder: (context, state, _) => _HandshakeHeader(state: state),
          ),
          const Divider(height: 1),
          Expanded(child: EventsPanel(client: widget.client)),
        ],
      ),
    );
  }
}

/// Renders the handshake result: a spinner while probing, the advertised
/// plugins + tools when loaded, or a banner when the host is missing/failed.
class _HandshakeHeader extends StatelessWidget {
  const _HandshakeHeader({required this.state});

  final HandshakeState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      HandshakeLoading() => const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          key: Key('handshake.loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Probing grid exploration host…'),
          ],
        ),
      ),
      HandshakeBindingMissing() => const _Banner(
        key: Key('handshake.bindingMissing'),
        icon: Icons.link_off,
        message:
            'No grid exploration host detected. Attach to a process '
            'running GridExplorationHost.register() under '
            '--enable-vm-service.',
      ),
      HandshakeFailed(:final message) => _Banner(
        key: const Key('handshake.failed'),
        icon: Icons.error_outline,
        message: 'Handshake failed: $message',
      ),
      HandshakeLoaded(:final handshake) => _LoadedHeader(handshake: handshake),
    };
  }
}

class _LoadedHeader extends StatelessWidget {
  const _LoadedHeader({required this.handshake});

  final GridHandshake handshake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('handshake.loaded'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Grid host • protocol v${handshake.protocolVersion}',
            key: const Key('handshake.protocolVersion'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (handshake.plugins.isEmpty)
            const Text(
              'Host advertised no plugins.',
              key: Key('handshake.noPlugins'),
            )
          else
            ...handshake.plugins.map(
              (plugin) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  key: Key('handshake.plugin.${plugin.namespace}'),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(plugin.namespace, style: theme.textTheme.labelLarge),
                    for (final tool in plugin.tools)
                      Chip(
                        key: Key('handshake.tool.${plugin.namespace}.$tool'),
                        label: Text(tool),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
