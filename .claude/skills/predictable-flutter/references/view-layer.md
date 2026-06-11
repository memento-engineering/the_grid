# View Layer Reference

ViewModels, Views, and State Design for the predictable-flutter architecture.

## ViewModels

A ViewModel is a `StateNotifier<T>` subclass where `T` is a freezed state class. Provided via `StateNotifierProvider`. One VM instance per view lifecycle — a simple view may reuse a VM class, but each mounted view gets its own provider instance.

Define an abstract interface for testability and swappability:

```dart
abstract class IssueListViewModel extends StateNotifier<IssueListState> {
  IssueListViewModel(super.state);
  Future<void> onRefresh();
  void onIssueSelected(String id);
  void onFilterChanged(IssueFilter filter);
}
```

Concrete implementation receives dependencies via constructor injection:

```dart
class IssueListViewModelImpl extends IssueListViewModel {
  IssueListViewModelImpl({
    required IssueListInteractor interactor,
    required IssueRepository issueRepository,
  })  : _interactor = interactor,
        _issueRepository = issueRepository,
        super(const IssueListState.loading()) {
    _init();
  }

  final IssueListInteractor _interactor;
  final IssueRepository _issueRepository;

  Future<void> _init() async {
    try {
      final issues = await _interactor.getFilteredIssues();
      state = IssueListState.loaded(issues: issues);
    } catch (e, st) {
      state = IssueListState.error(message: e.toString());
    }
  }

  @override
  Future<void> onRefresh() async {
    state = const IssueListState.loading();
    try {
      final issues = await _interactor.getFilteredIssues();
      state = IssueListState.loaded(issues: issues);
    } catch (e, st) {
      state = IssueListState.error(message: e.toString());
    }
  }

  @override
  void onIssueSelected(String id) {
    // Navigation or selection state — delegate to interactor if coordination needed
    _interactor.selectIssue(id);
  }

  @override
  void onFilterChanged(IssueFilter filter) {
    _interactor.applyFilter(filter);
    onRefresh();
  }
}
```

Provider wiring:

```dart
final issueListViewModelProvider =
    StateNotifierProvider.autoDispose<IssueListViewModel, IssueListState>(
  (ref) => IssueListViewModelImpl(
    interactor: ref.watch(issueListInteractorProvider),
    issueRepository: ref.watch(issueRepositoryProvider),
  ),
);
```

**Classifier:** Always suffix with `ViewModel` — `IssueListViewModel`, `SettingsViewModel`, `BoardDetailViewModel`.

**Allowed dependencies:** Interactors (for coordinated domain logic), repositories (for simple reads/mutations). Never services — if you need raw service access, the repo or interactor layer is incomplete.

### Anti-patterns

- **VM calling HTTP/API directly.** A VM that does `http.get('/issues')` is bypassing the data layer. Route through a repository.
- **Business logic in the VM.** If the VM computes priority scores, validates business rules, or coordinates multiple repos, extract an interactor. The VM selects and maps state — it doesn't own the rules.

## Views

Views are widgets that bind to VM state and forward user actions. No business logic. No data fetching. No conditional logic beyond simple null/empty guards.

Screens live in `{feature}/screens/`, reusable components in `{feature}/widgets/`.

Use `ConsumerWidget` (or `Consumer` for scoped rebuilds within a larger widget):

```dart
class IssueListScreen extends ConsumerWidget {
  const IssueListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(issueListViewModelProvider);
    final vm = ref.read(issueListViewModelProvider.notifier);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      loaded: (issues) => RefreshIndicator(
        onRefresh: vm.onRefresh,
        child: ListView.builder(
          itemCount: issues.length,
          itemBuilder: (context, index) => IssueCard(
            issue: issues[index],
            onTap: () => vm.onIssueSelected(issues[index].id),
          ),
        ),
      ),
      error: (message) => ErrorDisplay(
        message: message,
        onRetry: vm.onRefresh,
      ),
    );
  }
}
```

For scoped rebuilds inside a stateful or larger widget, use `Consumer`:

```dart
Consumer(
  builder: (context, ref, child) {
    final state = ref.watch(issueListViewModelProvider);
    return state.when(/* ... */);
  },
)
```

### Anti-patterns

- **Views watching repositories directly.** Views depend on their VM only. If a view needs repo data, the VM should expose it as part of its state.
- **Conditional logic in views.** Beyond `if (items.isEmpty)` or null checks, move logic to the VM state. If the view decides *what* to show based on business rules, those rules belong in the VM or interactor.

## State Design

VM state is a single freezed class representing the complete render state. The view should call `.when()` / `.map()` on it — not inspect boolean flags.

Prefer sealed union types over flat classes with nullable fields:

```dart
@freezed
class IssueListState with _$IssueListState {
  const factory IssueListState.loading() = _Loading;
  const factory IssueListState.loaded({
    required List<Issue> issues,
    @Default(IssueFilter.all) IssueFilter activeFilter,
    @Default(false) bool isRefreshing,
  }) = _Loaded;
  const factory IssueListState.error({
    required String message,
  }) = _Error;
}
```

Rules:
- **Include everything the view needs.** If the view displays a formatted date, the state holds the formatted string — not a raw `DateTime` for the view to format.
- **Explicit states over boolean flags.** `IssueListState.loading()` is clearer than `IssueListState(isLoading: true, issues: null, error: null)`. Each union case guarantees which fields are available.
- **Derived display values belong in the VM or state.** The view never computes `"${issues.length} items"` — the state provides `itemCountLabel`.
- **Avoid deeply nested state.** If a sub-component has complex state, give it its own VM rather than nesting state objects.

## Testing

### ViewModel Tests

Fake interactors/repos, drive actions, verify state transitions. Use `Fake` from `flutter_test` — not mockito. Fakes give explicit control over behavior without verification overhead.

```dart
class FakeIssueListInteractor extends Fake implements IssueListInteractor {
  List<Issue> issues;
  FakeIssueListInteractor(this.issues);

  @override
  Future<List<Issue>> getFilteredIssues() async => issues;
}

void main() {
  test('onRefresh emits loading then loaded', () async {
    final fakeInteractor = FakeIssueListInteractor([testIssue]);
    final vm = IssueListViewModelImpl(
      interactor: fakeInteractor,
      issueRepository: FakeIssueRepository(),
    );

    await Future.delayed(Duration.zero);
    expect(vm.state, isA<_Loaded>());

    fakeInteractor.issues = [testIssue, anotherIssue];
    await vm.onRefresh();
    expect(vm.state, equals(IssueListState.loaded(issues: [testIssue, anotherIssue])));
  });
}
```

### Widget Tests

Provide a fake VM via provider override, verify rendering per state:

```dart
void main() {
  testWidgets('shows loading indicator for loading state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          issueListViewModelProvider.overrideWith(
            (_) => FakeIssueListViewModel(const IssueListState.loading()),
          ),
        ],
        child: const MaterialApp(home: IssueListScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders issues for loaded state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          issueListViewModelProvider.overrideWith(
            (_) => FakeIssueListViewModel(
              IssueListState.loaded(issues: [testIssue]),
            ),
          ),
        ],
        child: const MaterialApp(home: IssueListScreen()),
      ),
    );

    expect(find.byType(IssueCard), findsOneWidget);
  });
}
```

Don't test that `ListView` scrolls or `CircularProgressIndicator` animates — test that your state-to-widget mapping is correct.
