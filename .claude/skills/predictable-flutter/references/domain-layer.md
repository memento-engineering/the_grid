# Domain Layer Reference

## Why This Layer Exists

The domain layer is the most commonly missing layer in Flutter apps. Without it, repositories absorb domain coordination logic — combining data from multiple sources, managing selection state, applying business rules across entities. Repositories should do one thing: own a data source and expose its state.

Symptoms that you're missing this layer:

- A repository that reads from two other repositories to build a combined view
- A repository holding "current selection" or "active filter" state that isn't persisted
- A viewmodel that orchestrates multiple repositories, merging their outputs
- Business rules scattered across repositories and viewmodels with no clear owner

The domain layer sits between data and view. It reads repository state, coordinates across repositories, and exposes composed state for viewmodels to consume. Repositories stay focused on data access. ViewModels stay focused on view-specific state. Domain handles everything in between.

The dependency direction: `view → domain → data`. Domain reads repo state (the emitted `StateNotifier` value) and calls repo methods for mutations. It never reaches up into the view layer.

If you're about to add a second repository dependency to a repository, stop. You need an interactor.

## Interactors

The general-purpose domain coordinator. Interactors read state from one or more repositories, expose a combined or transformed view of that state, and delegate mutations back to the appropriate repository.

**Building an Interactor:**

Use `StateNotifier` when the interactor manages derived state that updates reactively. Use a plain `Provider` when it only exposes methods with no observable state of its own.

**What interactors can depend on:**

- Repository state (read the emitted value)
- Repository methods (call for mutations)
- Services (for domain-specific concerns like validation, date math)
- Other domain models and types (value objects, enums)

**What interactors cannot depend on:**

- Other domain observables. No interactor reads another interactor's state. This prevents circular subscription chains and keeps the dependency graph a clean DAG. If two interactors seem to need each other's state, they share a repository or you're missing an abstraction.

**Concrete example** — an interactor that coordinates a project repository and an issue repository to expose issues for the currently selected project:

```dart
class ProjectIssuesInteractor extends StateNotifier<ProjectIssuesState> {
  ProjectIssuesInteractor({
    required ProjectRepository projectRepo,
    required IssueRepository issueRepo,
  })  : _projectRepo = projectRepo,
        _issueRepo = issueRepo,
        super(const ProjectIssuesState()) {
    _projectRepo.addListener(_recompute);
    _issueRepo.addListener(_recompute);
    _recompute(_projectRepo.state); // seed initial state
  }

  final ProjectRepository _projectRepo;
  final IssueRepository _issueRepo;

  void _recompute([dynamic _]) {
    final selectedProject = _projectRepo.state.selectedProject;
    if (selectedProject == null) {
      state = const ProjectIssuesState();
      return;
    }
    final issues = _issueRepo.state.issues
        .where((i) => i.projectId == selectedProject.id)
        .toList();
    state = ProjectIssuesState(
      project: selectedProject,
      issues: issues,
      totalCount: issues.length,
    );
  }

  Future<void> createIssue(String title, String body) async {
    final projectId = _projectRepo.state.selectedProject?.id;
    if (projectId == null) return;
    await _issueRepo.createIssue(
      projectId: projectId,
      title: title,
      body: body,
    );
  }

  @override
  void dispose() {
    _projectRepo.removeListener(_recompute);
    _issueRepo.removeListener(_recompute);
    super.dispose();
  }
}
```

Key observations:
- Reads state from both repos, writes to neither directly — mutations go through repo methods
- Owns the coordination logic (filtering issues by selected project)
- Exposes a single combined state object
- Subscribes to repo changes and recomputes on updates

**Classifier:** always suffix with `Interactor`. Examples: `BoardInteractor`, `ProjectSelectionInteractor`, `TimeTrackingInteractor`.

## Selectors

A specialization of Interactor for deriving or reducing state. Use a Selector when the interactor's primary job is computing a derived view from repository outputs — filtering, aggregating, combining, sorting.

Think `reduce`. The Selector watches one or more repo states and emits a reduced subset or aggregate.

```dart
class FilteredIssuesSelector extends StateNotifier<List<Issue>> {
  FilteredIssuesSelector({
    required IssueRepository issueRepo,
    required FilterRepository filterRepo,
  })  : _issueRepo = issueRepo,
        _filterRepo = filterRepo,
        super(const []) {
    _issueRepo.addListener(_recompute);
    _filterRepo.addListener(_recompute);
    _recompute();
  }

  final IssueRepository _issueRepo;
  final FilterRepository _filterRepo;

  void _recompute([dynamic _]) {
    final filter = _filterRepo.state;
    var issues = _issueRepo.state.issues;
    if (filter.label != null) {
      issues = issues.where((i) => i.labels.contains(filter.label)).toList();
    }
    if (filter.sortBy == SortField.created) {
      issues = [...issues]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    state = issues;
  }

  @override
  void dispose() {
    _issueRepo.removeListener(_recompute);
    _filterRepo.removeListener(_recompute);
    super.dispose();
  }
}
```

**Classifier:** suffix with `Selector`. Examples: `FilteredIssuesSelector`, `ActiveSprintSelector`, `UnreadCountSelector`.

## Transformers

A specialization of Interactor for reshaping data streams. Use a Transformer when the primary job is mapping one data shape to another — converting raw API types to domain types, enriching events, denormalizing nested structures.

Think `map`. Input shape goes in, output shape comes out.

Built with `StreamTransformer`, `Stream.map`, or similar stream-based primitives. Transformers work well when the data source is a stream (WebSocket, SSE, platform channels) rather than a `StateNotifier`.

```dart
class ActivityEventTransformer {
  const ActivityEventTransformer();

  Stream<DomainEvent> transform(Stream<RawApiEvent> source) {
    return source.transform(
      StreamTransformer<RawApiEvent, DomainEvent>.fromHandlers(
        handleData: (raw, sink) {
          final event = switch (raw.type) {
            'issue.created' => IssueCreatedEvent(
              issueId: raw.payload['id'] as String,
              title: raw.payload['title'] as String,
              createdAt: DateTime.parse(raw.payload['created_at'] as String),
            ),
            'issue.closed' => IssueClosedEvent(
              issueId: raw.payload['id'] as String,
              closedAt: DateTime.parse(raw.payload['closed_at'] as String),
            ),
            _ => null,
          };
          if (event != null) sink.add(event);
        },
      ),
    );
  }
}
```

**Classifier:** suffix with `Transformer`. Examples: `ActivityEventTransformer`, `DateRangeTransformer`, `NotificationTransformer`.

## When to Use What

**Default to `Interactor`.** It's the general-purpose coordinator and always a safe choice. If you're unsure, use Interactor.

**Promote to `Selector`** when the interactor's entire job is computing a derived view — filtering a list, aggregating counts, combining two states into a summary. The interactor has no mutation methods, just reactive state derivation.

**Promote to `Transformer`** when the interactor's entire job is reshaping a stream — converting raw events to domain events, enriching payloads, mapping between type systems. The work is stateless `map`, not stateful `reduce`.

Don't overthink classification. The architecture doesn't break if you call a selector an interactor. The specializations exist for readability — when another agent (or you, next week) sees `FilteredIssuesSelector`, the suffix immediately communicates "this derives state." But `FilteredIssuesInteractor` works identically. Promote when the intent is clear; default to Interactor when it's not.

## Testing

Fake repositories to control both emitted state and method calls. Use `Fake` from `flutter_test` — not mockito. Fakes give explicit control over return values and let you inspect calls directly. If you're not calling `verify`, you don't need mocks.

**Interactor test pattern** — verify coordination logic:

```dart
class FakeProjectRepository extends Fake implements ProjectRepository {
  ProjectState _state;
  FakeProjectRepository(this._state);

  @override
  ProjectState get state => _state;
}

class FakeIssueRepository extends Fake implements IssueRepository {
  IssueState _state;
  final List<Map<String, String>> createdIssues = [];

  FakeIssueRepository(this._state);

  @override
  IssueState get state => _state;

  @override
  Future<void> createIssue({
    required String projectId,
    required String title,
    required String body,
  }) async {
    createdIssues.add({'projectId': projectId, 'title': title, 'body': body});
  }
}

void main() {
  late FakeProjectRepository fakeProjectRepo;
  late FakeIssueRepository fakeIssueRepo;
  late ProjectIssuesInteractor interactor;

  setUp(() {
    fakeProjectRepo = FakeProjectRepository(
      ProjectState(selectedProject: Project(id: 'p1', name: 'Alpha')),
    );
    fakeIssueRepo = FakeIssueRepository(
      IssueState(issues: [
        Issue(id: 'i1', projectId: 'p1', title: 'Bug A'),
        Issue(id: 'i2', projectId: 'p2', title: 'Bug B'),
      ]),
    );

    interactor = ProjectIssuesInteractor(
      projectRepo: fakeProjectRepo,
      issueRepo: fakeIssueRepo,
    );
  });

  test('filters issues to selected project', () {
    expect(interactor.state.issues, hasLength(1));
    expect(interactor.state.issues.first.id, 'i1');
  });

  test('delegates createIssue to issue repo', () async {
    await interactor.createIssue('New bug', 'Description');
    expect(fakeIssueRepo.createdIssues, hasLength(1));
    expect(fakeIssueRepo.createdIssues.first['title'], 'New bug');
  });
}
```

**Selector tests** — verify derived state across input combinations:

```dart
test('applies label filter', () {
  final fakeFilterRepo = FakeFilterRepository(Filter(label: 'urgent'));
  final fakeIssueRepo = FakeIssueRepository(IssueState(issues: testIssues));

  final selector = FilteredIssuesSelector(
    issueRepo: fakeIssueRepo,
    filterRepo: fakeFilterRepo,
  );

  expect(selector.state.every((i) => i.labels.contains('urgent')), isTrue);
});
```

**Transformer tests** — verify input→output mapping:

```dart
test('maps raw issue.created to IssueCreatedEvent', () async {
  final transformer = ActivityEventTransformer();
  final output = await transformer.transform(
    Stream.value(RawApiEvent(type: 'issue.created', payload: {
      'id': 'i1',
      'title': 'Bug',
      'created_at': '2025-01-01T00:00:00Z',
    })),
  ).first;

  expect(output, isA<IssueCreatedEvent>());
  expect((output as IssueCreatedEvent).issueId, 'i1');
});
```
