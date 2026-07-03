import 'package:beads_dart/beads_dart.dart';

/// VM-service extension prefix for the_grid's exploration host.
///
/// ADR-0001 Decision 6 ratifies `ext.exploration.` (not the framework-reserved
/// `ext.flutter.exploration.` lenny historically used): registration is via
/// `dart:developer.registerExtension`, so the `flutter` segment was never
/// framework-imposed, and a pure-Dart host advertising it would mislead
/// Flutter-detection tooling. Lenny renames repo-wide in lockstep (lenny M0,
/// bead lenny-wisp-41rdl); until that lands, interop with lenny's consumers
/// requires matching prefixes — kept as a single constant to switch trivially.
const String kExplorationPrefix = 'ext.exploration';

/// Exploration protocol version this host speaks.
const String kProtocolVersion = '1';

/// The grid plugin's namespace; tools are exposed at
/// `ext.exploration.grid.<tool>`.
const String kGridNamespace = 'grid';

/// Serialized map key carrying the per-namespace extension entries/fragments
/// in both the handshake (`extensions: [{namespace, tools}]`) and the stable
/// observation (`extensions: {<ns>: <fragment>}`).
///
/// Renamed from `plugins` to converge on leonard ≥0.1.0's published read
/// contract, which reads **only** `extensions` with no fallback
/// (`leonard_agent/.../vm_service_client.dart`, `observation/models.dart`).
/// ADR-0000 A33 (ratified) records the rename; the `ext.exploration.*` prefix,
/// the method names, and protocol version `'1'` are unchanged. Centralized
/// (mirroring [kExplorationPrefix]) so the host emits one key.
const String kExtensionsKey = 'extensions';

/// Fully-qualified extension method name for a core method.
String coreExtension(String suffix) => '$kExplorationPrefix.core.$suffix';

/// Fully-qualified extension method name for a grid tool.
String gridExtension(String tool) =>
    '$kExplorationPrefix.$kGridNamespace.$tool';

/// A compact, bounded JSON summary of a bead (events/observations carry these
/// rather than full beads to stay within observation budgets).
Map<String, Object?> beadSummary(Bead bead) => {
  'id': bead.id,
  'title': bead.title,
  'status': bead.status.wire,
  'issueType': bead.issueType.wire,
  'priority': bead.priority,
};

/// Serializes a [GraphEvent] to a compact wire object. Exhaustive over the
/// sealed union (compiler-checked), so a new event variant forces an update.
Map<String, Object?> graphEventToWire(GraphEvent event) => switch (event) {
  SnapshotInitialized(:final beadCount, :final readyCount) => {
    'type': 'snapshotInitialized',
    'beadCount': beadCount,
    'readyCount': readyCount,
  },
  BeadCreated(:final bead) => {
    'type': 'beadCreated',
    'bead': beadSummary(bead),
  },
  BeadUpdated(:final after, :final changedFields) => {
    'type': 'beadUpdated',
    'id': after.id,
    'changedFields': changedFields.toList()..sort(),
  },
  BeadClosed(:final after) => {
    'type': 'beadClosed',
    'id': after.id,
    'status': after.status.wire,
  },
  BeadReopened(:final after) => {
    'type': 'beadReopened',
    'id': after.id,
    'status': after.status.wire,
  },
  BeadDeleted(:final bead) => {'type': 'beadDeleted', 'id': bead.id},
  DependencyAdded(:final dependency) => {
    'type': 'dependencyAdded',
    'issueId': dependency.issueId,
    'dependsOnId': dependency.dependsOnId,
    'depType': dependency.type.wire,
  },
  DependencyRemoved(:final dependency) => {
    'type': 'dependencyRemoved',
    'issueId': dependency.issueId,
    'dependsOnId': dependency.dependsOnId,
    'depType': dependency.type.wire,
  },
  ReadySetChanged(:final entered, :final exited) => {
    'type': 'readySetChanged',
    'entered': entered.toList()..sort(),
    'exited': exited.toList()..sort(),
  },
};

/// Serializes sync-loop stats for the `stats` tool / observation stability.
Map<String, Object?> statsToWire(GraphSyncStats stats) => stats.toJson();
