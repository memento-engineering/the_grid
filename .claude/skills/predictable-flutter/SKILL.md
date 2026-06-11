---
name: predictable-flutter
description: >
  Prescriptive Flutter/Dart architecture skill organizing code by longevity (Data → Domain → View).
  Use when building or modifying Flutter apps or packages: creating services, repositories, interactors,
  viewmodels, screens, or widgets. Enforces dependency rules, feature-first folder structure, naming
  conventions, and a StateNotifier + freezed state management stack. Not for: pure Dart CLI tools,
  backend services, or projects that explicitly use a different architecture (BLoC, MVC, etc.).
---

# Predictable Flutter

Architecture organized by longevity. Code that changes rarely (data access) stays far from code that changes often (UI). Feature-first folder structure, opinionated state management stack (StateNotifier + freezed), strict dependency rules between layers. This is prescriptive — follow it as written, fork it if you disagree.

## The Longevity Model

Code is organized into three layers by how often it changes:

```
┌─────────────────────────────────────────┐
│  VIEW          (shortest lived)         │
│  ViewModels, Screens, Widgets           │
├─────────────────────────────────────────┤
│  DOMAIN        (mid longevity)          │
│  Interactors, Selectors, Transformers   │
├─────────────────────────────────────────┤
│  DATA          (longest lived)          │
│  Services, Repositories                 │
└─────────────────────────────────────────┘
         ▲ dependencies point DOWN
         │ (view → domain → data)
```

**Why longevity matters:** It determines dependency direction. Long-lived code must never depend on short-lived code, because short-lived code changes frequently and would drag stable layers into churn. Dependencies always point downward — from volatile to stable.

- **Data layer** — survives redesigns, feature pivots, even framework migrations. An HTTP service or local DB repo outlives any screen.
- **Domain layer** — business logic that coordinates data. Survives UI rewrites but changes when product rules change.
- **View layer** — dies and rebirths constantly. New designs, new flows, new platforms. Cheapest to replace.

## Dependency Rules

Hard constraints. No exceptions.

| Component      | Can depend on                                                   | Cannot depend on                          |
|----------------|-----------------------------------------------------------------|-------------------------------------------|
| **Service**    | External packages, platform APIs                                | Anything internal (repos, interactors, VMs) |
| **Repository** | Services it wraps                                               | Other repositories, domain, view          |
| **Interactor** | Repo state (read), repo methods (mutate), services, domain models/types | Other domain observables (no cross-interactor state reads) |
| **ViewModel**  | Interactors, repositories                                       | Services directly                         |
| **View**       | Its ViewModel                                                   | Everything else                           |

Key clarifications:
- **Interactors read repo state** — the value emitted by the repo's `StateNotifier`. They do not hold a reference to the notifier itself or subscribe at the interactor level; the provider framework handles subscriptions.
- **Interactors call repo methods** — for writes/mutations. The repo owns the mutation and state emission.
- **Interactors never observe other interactors' state.** If two interactors need coordinated state, they share a repository or you're missing an abstraction.
- **ViewModels never touch services.** If a VM needs raw service access, the interactor or repository layer is incomplete.
- **Views are dumb.** They bind to VM state and call VM methods. No logic, no conditional data fetching, no direct repo access.

## State Management Stack

- **`StateNotifier` + `StateNotifierProvider`** for all observable state. Works identically with `provider` or `riverpod` — this skill is agnostic between them. Concepts are 1:1.
- **`freezed`** for all value types (models, state classes). No hand-written `==`, `hashCode`, `copyWith`, or `toString`. Every model gets a freezed union or data class.
- **`StreamController` / `StreamTransformer`** in the domain layer when interactors need to compose, debounce, or transform streams of repo state. Keep stream logic in domain — never in views.

Default pattern: repositories expose state via `StateNotifier`, interactors compose that state, viewmodels select/combine what the view needs, views rebuild on VM state changes.

## Feature-First Folders

```
lib/
├── {package_name}.dart        ← barrel export (public API)
└── src/
    ├── core/
    │   ├── extensions/
    │   └── base/
    └── {feature}/
        ├── models/
        ├── services/
        ├── repositories/
        ├── interactors/
        ├── viewmodels/
        ├── screens/
        └── widgets/
```

Rules:
- All implementation code lives under `lib/src/` — private by default (Dart package convention).
- Public API exposed through barrel exports in `lib/` or explicit entry points.
- Works for both packages and apps. Apps just have more features.
- Not every feature needs every subdirectory. Create `services/` only when the feature has services. Don't scaffold empties.
- `core/` holds shared primitives: extensions, base classes, common types. Not a dumping ground — if it's feature-specific, it belongs in the feature.
- App-level wiring (router, theme, DI setup) lives outside feature directories. That's application concern, not architecture.

## Naming Conventions

Two categories, two rules:

**Reference types** (things that *do work*) get classifiers that communicate architectural role:
- `AuthRepository`, `GitHubApiService`, `BoardViewModel`, `LoginInteractor`, `ProjectSelector`, `DateRangeTransformer`
- The classifier tells you where it lives in the architecture and what it does.

**Value types** (things that *are data*) are named what they are:
- `Dog`, `AuthSession`, `Issue`, `Board`, `TimeEntry`
- Never `DogModel`, `IssueData`, `BoardEntity`, `TimeEntryDTO`
- The domain name IS the name. Suffixes like `Model` or `Data` add noise and zero information.

File names follow `snake_case` and match the primary class: `auth_repository.dart`, `dog.dart`, `board_view_model.dart`.

## Reference Loading Triggers

Load reference files based on the work being done:

- **Read `references/data-layer.md`** when creating or modifying services, repositories, or data models. Covers: service patterns, repository state management, error handling, caching strategies.
- **Read `references/domain-layer.md`** when creating interactors, selectors, or transformers. Also read it when a repository appears to be doing domain coordination (composing multiple data sources, applying business rules) — that logic belongs in an interactor.
- **Read `references/view-layer.md`** when creating or modifying viewmodels, screens, or widgets. Covers: VM lifecycle, state selection, view binding patterns.

If unsure which layer something belongs to, re-read the dependency rules above before proceeding. The dependency table is the source of truth for placement.

Do not load all references preemptively. Load only what the current task requires.
