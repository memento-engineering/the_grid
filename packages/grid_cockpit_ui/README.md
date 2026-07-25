# grid_cockpit_ui

Transport-neutral Flutter projections and primitives for grid diagnostics.

## Status

Early development (0.1.x). Part of [the_grid](https://github.com/memento-engineering/the_grid) — the memento.engineering grid station monorepo. APIs move fast; pin exact versions.

## Fixture example

Run the bundled, transport-free recording:

```sh
cd packages/grid_cockpit_ui/example
flutter run -d chrome
```

The composition path is TreeSource -> view-models -> views:

```dart
final TreeSource source = ReplayTreeSource(cockpitRecording);
final overview = OverviewViewModel(source);
final work = WorkListViewModel(source);

Column(
  children: [
    StationOverviewView(viewModel: overview),
    WorkListView(viewModel: work),
  ],
);
```

The example intentionally has no door, HTTP, WebSocket, or live transport dependency. It demonstrates deterministic fixture replay only.
