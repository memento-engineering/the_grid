/// The thin, injectable protocol-call layer for grid_devtools.
///
/// `grid_devtools` rides the exploration protocol ONLY (ADR-0002 Decision 3):
/// it never links `grid_controller` for live data. To keep the widgets
/// testable without a live VM service, every call into the protocol goes
/// through [GridExplorationClient]; production wires a `VmService`-backed
/// implementation, tests inject a fake.
///
/// The wire shapes consumed here are defined by the grid exploration host
/// (`packages/grid_exploration/lib/src/grid_exploration_protocol.dart` and
/// `grid_exploration_host.dart`). We do NOT import `grid_exploration` — the
/// contract is the wire JSON, so the minimal shapes we consume are
/// re-declared as plain value types below.
library;

/// Default postEvent stream id the grid host streams `GraphEvent`s on
/// (`developer.postEvent('grid.controller.event', ...)`). Mirrors
/// `GridExplorationHost.eventStreamId`.
const String kGridEventStreamId = 'grid.controller.event';

/// Fully-qualified `ext.exploration.core.handshake` extension method.
const String kHandshakeExtension = 'ext.exploration.core.handshake';

/// Fully-qualified `ext.exploration.grid.events` extension method.
const String kEventsExtension = 'ext.exploration.grid.events';

/// One plugin entry from the handshake `plugins` array:
/// `{namespace, tools}`.
class GridPlugin {
  const GridPlugin({required this.namespace, required this.tools});

  final String namespace;
  final List<String> tools;

  /// Decodes a single plugin entry, tolerating missing/extra keys. Returns
  /// `null` when [raw] is not a well-formed plugin map (no namespace).
  static GridPlugin? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final namespace = raw['namespace'];
    if (namespace is! String) return null;
    final rawTools = raw['tools'];
    final tools = <String>[
      if (rawTools is List)
        for (final tool in rawTools)
          if (tool is String) tool,
    ];
    return GridPlugin(namespace: namespace, tools: tools);
  }
}

/// The handshake response: `{protocolVersion, plugins:[{namespace,tools}]}`.
///
/// Extra advertised keys (`bindingType`, `hostType`, `pluginCount`) are
/// ignored — only the substance the panels render is decoded.
class GridHandshake {
  const GridHandshake({required this.protocolVersion, required this.plugins});

  final String protocolVersion;
  final List<GridPlugin> plugins;

  /// Decodes a handshake response. Throws [FormatException] when
  /// `protocolVersion` is missing or not a string (a malformed host).
  factory GridHandshake.fromWire(Map<String, Object?> json) {
    final version = json['protocolVersion'] ?? json['contractVersion'];
    if (version is! String) {
      throw FormatException(
        'handshake response missing/malformed protocolVersion: $version',
      );
    }
    final rawPlugins = json['plugins'];
    final plugins = <GridPlugin>[
      if (rawPlugins is List)
        for (final entry in rawPlugins)
          if (GridPlugin.fromWire(entry) case final GridPlugin p) p,
    ];
    return GridHandshake(protocolVersion: version, plugins: plugins);
  }
}

/// One graph event as the host serializes it (`graphEventToWire`): always a
/// `type` discriminator, usually an `id`, plus type-specific extra fields
/// which we preserve verbatim in [extra] so the panel can show detail
/// without re-declaring every variant.
class GridEventRecord {
  const GridEventRecord({required this.type, this.id, this.extra = const {}});

  /// The event discriminator, e.g. `beadCreated`, `readySetChanged`.
  final String type;

  /// The affected bead id when the event carries one (`id`, or nested
  /// `bead.id` for create/delete). `null` for set-level events.
  final String? id;

  /// All wire fields other than `type` and the surfaced `id`, preserved so
  /// no data is silently dropped (ADR-0002 Decision 2 — projections never
  /// lose data).
  final Map<String, Object?> extra;

  /// Decodes one event object. A non-map or a map without a string `type`
  /// yields `null` (skipped by callers).
  static GridEventRecord? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String) return null;
    final extra = <String, Object?>{};
    String? id;
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || key == 'type') continue;
      if (key == 'id' && entry.value is String) {
        id = entry.value as String;
        continue;
      }
      extra[key] = entry.value;
    }
    // Create/delete events nest the id under `bead.id` rather than `id`.
    if (id == null) {
      final bead = extra['bead'];
      if (bead is Map) {
        final nested = bead['id'];
        if (nested is String) id = nested;
      }
    }
    return GridEventRecord(type: type, id: id, extra: extra);
  }
}

/// A page of recent events from the `events` tool: `{count, events:[...]}`,
/// itself wrapped by the host in `{ok, value:{...}}`.
class GridEventsPage {
  const GridEventsPage({required this.count, required this.events});

  final int count;
  final List<GridEventRecord> events;

  /// Decodes the `events` tool result. Accepts either the full host
  /// envelope `{ok, value:{count, events}}` or a bare `{count, events}`
  /// payload (so a fake can return whichever is convenient). Throws
  /// [FormatException] when `ok` is present and false, or when the payload
  /// has no `events` list.
  factory GridEventsPage.fromWire(Map<String, Object?> json) {
    Map<Object?, Object?> payload = json;
    if (json.containsKey('ok')) {
      if (json['ok'] != true) {
        throw FormatException('events tool returned not-ok: ${json['error']}');
      }
      final value = json['value'];
      if (value is! Map) {
        throw const FormatException('events tool ok result missing value map');
      }
      payload = value;
    }
    final rawEvents = payload['events'];
    final events = <GridEventRecord>[
      if (rawEvents is List)
        for (final entry in rawEvents)
          if (GridEventRecord.fromWire(entry) case final GridEventRecord e) e,
    ];
    final rawCount = payload['count'];
    final count = rawCount is int ? rawCount : events.length;
    return GridEventsPage(count: count, events: events);
  }
}

/// The protocol seam every grid_devtools panel talks through.
///
/// Implementations own whatever connection they need (production: a borrowed
/// `serviceManager.service` + main isolate id; tests: an in-memory fake).
/// Methods are Futures for acts; [eventStream] is a Stream for observations
/// (house rule: Futures for acts, Streams for observations).
abstract interface class GridExplorationClient {
  /// Runs `ext.exploration.core.handshake` and returns the advertised
  /// protocol version + plugin manifest.
  ///
  /// Throws [GridBindingMissing] when the extension is absent (the target
  /// process has no grid exploration host registered). Any other failure
  /// propagates.
  Future<GridHandshake> handshake();

  /// Calls the `ext.exploration.grid.events` tool, optionally bounding the
  /// number of recent events returned by [limit].
  Future<GridEventsPage> fetchEvents({int? limit});

  /// The live `grid.controller.event` postEvent stream, decoded into
  /// [GridEventRecord]s. Each grid `GraphEvent` arrives here as the host
  /// emits it. May be a broadcast stream shared across listeners.
  Stream<GridEventRecord> get eventStream;
}

/// Thrown by [GridExplorationClient.handshake] when the grid exploration
/// host's extensions are not registered in the attached process (the
/// VM-service "method not found" condition). The shell renders this as a
/// distinct "no grid host detected" state rather than a generic failure.
class GridBindingMissing implements Exception {
  const GridBindingMissing([
    this.message = 'grid exploration host not detected',
  ]);
  final String message;

  @override
  String toString() => 'GridBindingMissing: $message';
}
