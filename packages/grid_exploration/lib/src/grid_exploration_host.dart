import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:grid_controller/grid_controller.dart';

import 'grid_controller_plugin.dart';
import 'grid_exploration_protocol.dart';

/// Minimal pure-Dart exploration host for the_grid (ADR-0001 Decision 6).
///
/// Registers exactly the exploration protocol over a [GridControllerRuntime]
/// via `dart:developer` — no bespoke `ext.grid.*` namespace, no Flutter
/// binding:
///
/// * `ext.exploration.core.handshake`
/// * `ext.exploration.core.get_stable_observation` (empty semantics/routes,
///   grid state under `extensions.grid`, stability from the sync loop)
/// * `ext.exploration.grid.{requery,snapshot,ready,events,stats}`
///
/// and streams each [GraphEvent] via `developer.postEvent('grid.controller.
/// event', ...)`. The JSON builders ([handshakeJson], [observationJson],
/// [dispatchTool]) are pure and unit-tested; [register] is the thin glue that
/// binds them to the VM service.
class GridExplorationHost {
  GridExplorationHost(
    this.runtime, {
    GridControllerPlugin? plugin,
    this.eventStreamId = 'grid.controller.event',
  }) : plugin = plugin ?? GridControllerPlugin(runtime);

  final GridControllerRuntime runtime;
  final GridControllerPlugin plugin;
  final String eventStreamId;

  bool _registered = false;
  StreamSubscription<GraphEvent>? _eventSub;

  // ---------- pure JSON builders (testable without a VM service) ----------

  Map<String, Object?> handshakeJson() => {
    'protocolVersion': kProtocolVersion,
    'bindingType': 'GridControllerHost',
    'hostType': 'dart',
    kExtensionsKey: [
      {'namespace': plugin.namespace, 'tools': plugin.toolNames},
    ],
  };

  Map<String, Object?> observationJson() {
    final stats = runtime.stats;
    return {
      'type': 'Observation',
      'value': {
        'semantics': const <Object?>[],
        'routes': const <Object?>[],
        'stability': {
          'refreshing': stats.refreshing,
          'pendingFollowUp': stats.pendingFollowUp,
          'refreshCount': stats.refreshCount,
          'lastRefreshMs': stats.lastRefresh?.inMilliseconds,
        },
        kExtensionsKey: {plugin.namespace: plugin.observe()},
      },
    };
  }

  Future<Map<String, Object?>> dispatchTool(
    String tool,
    Map<String, String> params,
  ) => plugin.dispatch(tool, params);

  // ---------- VM-service registration ----------

  /// Registers the extensions and starts streaming events. Idempotent.
  /// Safe to call only under `--enable-vm-service`; the JSON builders work
  /// regardless.
  void register() {
    if (_registered) return;
    _registered = true;

    developer.registerExtension(coreExtension('handshake'), (
      method,
      params,
    ) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(handshakeJson()),
      );
    });

    developer.registerExtension(coreExtension('get_stable_observation'), (
      method,
      params,
    ) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(observationJson()),
      );
    });

    for (final tool in plugin.toolNames) {
      developer.registerExtension(gridExtension(tool), (method, params) async {
        try {
          final result = await dispatchTool(tool, params);
          return developer.ServiceExtensionResponse.result(jsonEncode(result));
        } on Object catch (error) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            jsonEncode({'ok': false, 'error': '$error'}),
          );
        }
      });
    }

    _eventSub = runtime.events.listen((event) {
      developer.postEvent(eventStreamId, graphEventToWire(event));
    });
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
  }
}
