import 'package:flutter/material.dart';

import '../protocol/grid_exploration_client.dart' show GridEventRecord;
import 'events_source.dart';

/// Events timeline panel — lists recent grid [GridEventRecord]s (type + id +
/// arrival order), newest at the top.
///
/// Seeds from the `events` tool and grows live off the
/// `grid.controller.event` postEvent stream, both via [GridEventsSource].
/// Capture ownership stays with the shell so events are collected before this
/// lazily built panel is first visited.
class EventsPanel extends StatelessWidget {
  const EventsPanel({super.key, required this.source});

  /// Started event source owned by the surrounding shell.
  final GridEventsSource source;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GridEventRecord>>(
      valueListenable: source.records,
      builder: (context, records, _) {
        if (records.isEmpty) {
          return const Center(
            child: Text('No grid events yet.', key: Key('events.empty')),
          );
        }
        // Newest first: render in reverse arrival order.
        return ListView.separated(
          key: const Key('events.list'),
          reverse: false,
          itemCount: records.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final record = records[records.length - 1 - index];
            return _EventRow(record: record, ordinal: records.length - index);
          },
        );
      },
    );
  }
}

/// One row in the events timeline: the event type, its bead id (when the
/// event carries one), and an arrival ordinal standing in for time (the
/// wire shape carries no timestamp).
class _EventRow extends StatelessWidget {
  const _EventRow({required this.record, required this.ordinal});

  final GridEventRecord record;
  final int ordinal;

  @override
  Widget build(BuildContext context) {
    final id = record.id;
    return ListTile(
      key: Key('events.row.$ordinal'),
      dense: true,
      leading: Text(
        '#$ordinal',
        key: const Key('events.row.ordinal'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      title: Text(record.type, key: const Key('events.row.type')),
      subtitle: id == null ? null : Text(id, key: const Key('events.row.id')),
    );
  }
}
