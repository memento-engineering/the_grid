import 'ready_work_filter.dart';

/// Sorts [items] in bd ready-work order.
///
/// [now] pins the hybrid 48-hour cutoff for differential replay. A missing
/// created-at value is the Unix epoch, matching ReadyWorkQuery row mapping.
void sortReadyWork<T>(
  List<T> items,
  ReadyWorkSortPolicy policy, {
  required String Function(T item) idOf,
  required int Function(T item) priorityOf,
  required DateTime? Function(T item) createdAtOf,
  DateTime? now,
}) {
  final recentCutoff = (now ?? DateTime.now()).toUtc().subtract(
    const Duration(hours: 48),
  );
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];

  DateTime createdAt(T item) =>
      (createdAtOf(item) ?? DateTime.utc(1970)).toUtc();

  int byCreated(T a, T b) {
    final created = createdAt(a).compareTo(createdAt(b));
    return created != 0 ? created : idOf(a).compareTo(idOf(b));
  }

  int byPriority(T a, T b) {
    final priority = priorityOf(a).compareTo(priorityOf(b));
    if (priority != 0) return priority;
    final created = createdAt(b).compareTo(createdAt(a));
    return created != 0 ? created : idOf(a).compareTo(idOf(b));
  }

  int compare(T a, T b) {
    switch (policy) {
      case ReadyWorkSortPolicy.oldest:
        return byCreated(a, b);
      case ReadyWorkSortPolicy.priority:
        return byPriority(a, b);
      case ReadyWorkSortPolicy.hybrid:
        final aRecent = !createdAt(a).isBefore(recentCutoff);
        final bRecent = !createdAt(b).isBefore(recentCutoff);
        if (aRecent != bRecent) return aRecent ? -1 : 1;
        if (aRecent) {
          final priority = priorityOf(a).compareTo(priorityOf(b));
          if (priority != 0) return priority;
        }
        return byCreated(a, b);
    }
  }

  indexed.sort((a, b) {
    final order = compare(a.$2, b.$2);
    return order != 0 ? order : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < items.length; i++) {
    items[i] = indexed[i].$2;
  }
}
