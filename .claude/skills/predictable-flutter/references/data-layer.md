# Data Layer Reference

Services and repositories. The longest-lived code in the app. Survives redesigns, feature pivots, framework migrations.

## Services

Stateless gateways to the outside world. One service per external data source. No caching, no state, no coordination — just async I/O that returns data or throws.

**Constructor injection** for configuration. Methods are async, return raw types, throw on failure. Services know nothing about the rest of the app.

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubApiService {
  GitHubApiService({
    required http.Client client,
    this.baseUrl = 'https://api.github.com',
    this.token,
  }) : _client = client;

  final http.Client _client;
  final String baseUrl;
  final String? token;

  Future<List<Map<String, dynamic>>> fetchRepositories(String username) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users/$username/repos'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException(response.statusCode, response.body);
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }
}

class HttpException implements Exception {
  HttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
```

**Anti-pattern — service holding cached state:**

```dart
// WRONG: caching belongs in the repository
class BadService {
  List<Repository>? _cachedRepos; // ← repository's job, not yours
  Future<List<Repository>> getRepos() async {
    _cachedRepos ??= await _fetch();
    return _cachedRepos!;
  }
}
```

## Repositories

Fetch, mutate, and **emit** data via `StateNotifier`. Repositories own the cached state for their data source. They use services for actual I/O, then push results into state.

Provided via `StateNotifierProvider`. Depend on services only — never other repositories, never domain, never view.

### State Shape

Repositories should wrap their data in a snapshot-like type that represents loading/data/error states explicitly — not bare values or boolean flags. Common patterns include `AsyncValue<T>`, custom sealed classes, or `Result<T>` types.

Example using a freezed sealed class (your project may already have its own):

```dart
/// Example — use whatever snapshot wrapper your project defines.
/// The pattern matters more than the specific type name.
@freezed
sealed class AsyncValue<T> with _$AsyncValue<T> {
  const factory AsyncValue.loading() = _Loading;
  const factory AsyncValue.data(T value) = _Data;
  const factory AsyncValue.error(Object error, [StackTrace? stackTrace]) = _Error;
}
```

If your project already has a snapshot type (`AsyncValue`, `DataState`, `Resource`, etc.), use it. Don't introduce a competing one.

### Repository Implementation

```dart
import 'package:state_notifier/state_notifier.dart';

class RepositoryRepository extends StateNotifier<AsyncValue<List<Repository>>> {
  RepositoryRepository({required GitHubApiService gitHubApiService})
      : _gitHubApiService = gitHubApiService,
        super(const AsyncValue.loading());

  final GitHubApiService _gitHubApiService;

  Future<void> fetchRepositories(String username) async {
    state = const AsyncValue.loading();
    try {
      final raw = await _gitHubApiService.fetchRepositories(username);
      final repos = raw.map((json) => Repository.fromJson(json)).toList();
      state = AsyncValue.data(repos);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh(String username) async {
    // Preserve current data while refreshing — don't flash loading state
    try {
      final raw = await _gitHubApiService.fetchRepositories(username);
      final repos = raw.map((json) => Repository.fromJson(json)).toList();
      state = AsyncValue.data(repos);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
```

### Wiring with Provider

```dart
final repositoryRepositoryProvider =
    StateNotifierProvider<RepositoryRepository, AsyncValue<List<Repository>>>(
  (ref) => RepositoryRepository(
    gitHubApiService: ref.watch(gitHubApiServiceProvider),
  ),
);

final gitHubApiServiceProvider = Provider<GitHubApiService>(
  (ref) => GitHubApiService(client: http.Client()),
);
```

**Anti-pattern — repository doing domain coordination:**

```dart
// WRONG: combining data from multiple sources is an interactor's job
class BadRepository extends StateNotifier<SomeCombinedState> {
  BadRepository(this._repoService, this._userService); // two services = smell
  Future<void> fetchDashboard() async {
    final repos = await _repoService.fetch();
    final user = await _userService.fetch();
    state = CombinedState(repos: repos, user: user); // ← interactor territory
  }
}
```

**Anti-pattern — repository depending on another repository:**

```dart
// WRONG: repositories are peers, not a hierarchy
class BadRepository extends StateNotifier<SomeState> {
  BadRepository(this._otherRepo); // ← never depend on another repo
  final OtherRepository _otherRepo;
}
```

## Value Types in the Data Layer

All models are `freezed` classes. Named for what they represent — no suffixes.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'repository.freezed.dart';
part 'repository.g.dart';

@freezed
class Repository with _$Repository {
  const factory Repository({
    required int id,
    required String name,
    required String fullName,
    @JsonKey(name: 'stargazers_count') required int stars,
    String? description,
  }) = _Repository;

  factory Repository.fromJson(Map<String, dynamic> json) =>
      _$RepositoryFromJson(json);
}
```

- `Repository`, not `RepositoryModel` or `RepositoryDTO`
- `@JsonKey` for snake_case ↔ camelCase mapping
- Keep models in `{feature}/models/`
- One model per file, file named after the class: `repository.dart`
- Run `dart run build_runner build` after adding or changing models

## Testing

### Service Tests

Mock the HTTP client. Verify correct URL construction, headers, and error handling.

```dart
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('fetchRepositories sends correct request and parses response', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/users/octocat/repos');
      expect(request.headers['Accept'], 'application/vnd.github.v3+json');
      return http.Response(
        jsonEncode([{'id': 1, 'name': 'hello', 'full_name': 'octocat/hello', 'stargazers_count': 42}]),
        200,
      );
    });

    final service = GitHubApiService(client: client);
    final repos = await service.fetchRepositories('octocat');
    expect(repos, hasLength(1));
    expect(repos.first['name'], 'hello');
  });

  test('fetchRepositories throws on non-200', () async {
    final client = MockClient((_) async => http.Response('not found', 404));
    final service = GitHubApiService(client: client);
    expect(() => service.fetchRepositories('ghost'), throwsA(isA<HttpException>()));
  });
}
```

### Repository Tests

Fake the service. Verify state emission sequence: loading → data (or error).

Use `Fake` from `flutter_test` (or `package:test`) — not mockito. Fakes give you full control over behavior without verification overhead. If you're not calling `verify`, you don't need mocks.

```dart
import 'package:test/test.dart';

class FakeGitHubApiService extends Fake implements GitHubApiService {
  List<Map<String, dynamic>>? result;
  Exception? error;

  @override
  Future<List<Map<String, dynamic>>> fetchRepositories(String username) async {
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  test('fetchRepositories emits loading then data', () async {
    final service = FakeGitHubApiService()
      ..result = [{'id': 1, 'name': 'hello', 'full_name': 'octocat/hello', 'stargazers_count': 42}];

    final repo = RepositoryRepository(gitHubApiService: service);
    final states = <AsyncValue<List<Repository>>>[];
    repo.addListener(states.add);

    await repo.fetchRepositories('octocat');

    expect(states, hasLength(2)); // loading, data
    expect(states.last, isA<AsyncValue<List<Repository>>>());
  });

  test('fetchRepositories emits loading then error on failure', () async {
    final service = FakeGitHubApiService()
      ..error = HttpException(404, 'not found');

    final repo = RepositoryRepository(gitHubApiService: service);
    final states = <AsyncValue<List<Repository>>>[];
    repo.addListener(states.add);

    await repo.fetchRepositories('ghost');

    expect(states, hasLength(2)); // loading, error
  });
}
```
