import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  test('delivers every flare to children in order and isolates failures', () {
    final first = _RecordingTransport();
    final second = _RecordingTransport();
    final composite = CompositeExplorationTransport([
      first,
      _ThrowingTransport(),
      second,
    ]);

    for (var index = 1; index <= 3; index++) {
      composite.flare('event.$index', {'index': '$index'});
    }

    expect(first.flares.map((flare) => flare.name), [
      'event.1',
      'event.2',
      'event.3',
    ]);
    expect(second.flares.map((flare) => flare.name), [
      'event.1',
      'event.2',
      'event.3',
    ]);
    expect(first.flares.map((flare) => flare.data['index']), ['1', '2', '3']);
    expect(second.flares.map((flare) => flare.data['index']), ['1', '2', '3']);
  });

  test('empty composite is a no-op', () {
    expect(
      () => CompositeExplorationTransport(const []).flare('event', const {}),
      returnsNormally,
    );
  });
}

final class _RecordingTransport implements ExplorationTransport {
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map<String, String>.of(data)));
  }
}

final class _ThrowingTransport implements ExplorationTransport {
  @override
  void flare(String name, Map<String, String> data) => throw StateError('sink');
}
