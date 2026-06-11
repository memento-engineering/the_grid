import 'package:flutter/material.dart';

import '../protocol/grid_exploration_client.dart';
import 'events_source.dart';

/// Events timeline panel — lists recent grid [GridEventRecord]s (type + id +
/// arrival order), newest at the top.
///
/// Seeds from the `events` tool and grows live off the
/// `grid.controller.event` postEvent stream, both via [GridEventsSource].
/// The panel constructs and owns its source from the injected
/// [GridExplorationClient]; the client is the only seam, so a fake drives
/// the whole widget in tests with no VM service.
class EventsPanel extends StatefulWidget {
  const EventsPanel({super.key, required this.client, this.seedLimit = 64});

  final GridExplorationClient client;

  /// How many recent events to seed from the ring buffer on attach.
  final int seedLimit;

  @override
  State<EventsPanel> createState() => _EventsPanelState();
}

class _EventsPanelState extends State<EventsPanel> {
  late GridEventsSource _source;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _source = GridEventsSource(widget.client);
    // ignore: unawaited_futures
    _source.start(seedLimit: widget.seedLimit);
  }

  @override
  void didUpdateWidget(covariant EventsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      // ignore: unawaited_futures
      _source.close();
      _start();
    }
  }

  @override
  void dispose() {
    // ignore: unawaited_futures
    _source.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GridEventRecord>>(
      valueListenable: _source.records,
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
