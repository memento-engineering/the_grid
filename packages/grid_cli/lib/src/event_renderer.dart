import 'dart:convert';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_exploration/grid_exploration.dart';

/// Renders [GraphEvent]s for `grid watch` — either a human-readable line or a
/// machine-readable NDJSON record, both annotated with the measured reaction
/// latency (PDR §6.1: ≤500ms).
class EventRenderer {
  EventRenderer({required this.json});

  final bool json;

  /// One line per event. [reaction] is the cycle's dirty→emit latency.
  String render(GraphEvent event, {Duration? reaction, required DateTime at}) {
    if (json) {
      return jsonEncode({
        'ts': at.toIso8601String(),
        'reactionMs': reaction?.inMilliseconds,
        'event': graphEventToWire(event),
      });
    }
    final stamp = _hms(at);
    final reactionTag = reaction == null
        ? ''
        : ' (reacted ${reaction.inMilliseconds}ms)';
    return '$stamp  ${_describe(event)}$reactionTag';
  }

  String _describe(GraphEvent event) => switch (event) {
    SnapshotInitialized(:final beadCount, :final readyCount) =>
      'SnapshotInitialized — $beadCount beads, $readyCount ready',
    BeadCreated(:final bead) =>
      'BeadCreated     ${bead.id} "${_clip(bead.title)}" '
          '[${bead.issueType.wire}]',
    BeadUpdated(:final after, :final changedFields) =>
      'BeadUpdated     ${after.id} {${(changedFields.toList()..sort()).join(', ')}}',
    BeadClosed(:final after) => 'BeadClosed      ${after.id}',
    BeadReopened(:final after) => 'BeadReopened    ${after.id}',
    BeadDeleted(:final bead) => 'BeadDeleted     ${bead.id}',
    DependencyAdded(:final dependency) =>
      'DependencyAdded ${dependency.issueId} → ${dependency.dependsOnId} '
          '(${dependency.type.wire})',
    DependencyRemoved(:final dependency) =>
      'DependencyRemoved ${dependency.issueId} → ${dependency.dependsOnId}',
    ReadySetChanged(:final entered, :final exited) =>
      'ReadySetChanged +[${(entered.toList()..sort()).join(', ')}] '
          '-[${(exited.toList()..sort()).join(', ')}]',
  };

  static String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms';
  }

  static String _clip(String s, [int max = 48]) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';
}
