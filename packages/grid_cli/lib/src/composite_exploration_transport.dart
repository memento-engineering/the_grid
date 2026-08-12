import 'package:grid_engine/grid_engine.dart' show ExplorationTransport;

/// Forwards each flare to every child in declaration order.
final class CompositeExplorationTransport implements ExplorationTransport {
  /// Creates an immutable fan-out over [children].
  CompositeExplorationTransport(Iterable<ExplorationTransport> children)
    : _children = List<ExplorationTransport>.unmodifiable(children);

  final List<ExplorationTransport> _children;

  @override
  void flare(String name, Map<String, String> data) {
    for (final child in _children) {
      try {
        child.flare(name, data);
      } catch (_) {
        // One observability sink never breaks the station or later sinks.
      }
    }
  }
}
