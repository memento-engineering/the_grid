import 'package:genesis_tree/genesis_tree.dart';

/// Creates a value owned by a [ProviderScope].
typedef ProviderCreate<T extends Object> = T Function();

/// Disposes a value owned by a [ProviderScope].
typedef ProviderDispose<T extends Object> = void Function(T value);

/// Describes an owned or adopted ambient value for a [ProviderScope].
final class Provider<T extends Object> {
  const Provider({
    required ProviderCreate<T> create,
    ProviderDispose<T>? dispose,
  }) : _create = create,
       _dispose = dispose,
       _value = null;

  const Provider.value(T value)
    : _value = value,
      _create = null,
      _dispose = null;

  final ProviderCreate<T>? _create;
  final ProviderDispose<T>? _dispose;
  final T? _value;

  Type get _type => T;

  _ProviderEntry _initialize() {
    final create = _create;
    if (create == null) return _ProviderEntry(_value as T, null);
    final value = create();
    final dispose = _dispose;
    return _ProviderEntry(value, dispose == null ? null : () => dispose(value));
  }

  bool get _isAdopted => _create == null;
}

/// Provides a typed collection of ambient values to one child subtree.
final class ProviderScope extends SingleChildStatefulSeed {
  const ProviderScope({required this.providers, super.child, super.key});

  final List<Provider<Object>> providers;

  @override
  SingleChildState<SingleChildStatefulSeed> createState() =>
      _ProviderScopeState();
}

/// Adds nullable, dependency-registering provider lookup to [TreeContext].
extension ProviderTreeContext on TreeContext {
  T? watch<T extends Object>() {
    final values = dependOnInheritedSeedOfExactType<_ProviderValues>();
    final provided = values?.find<T>();
    if (provided != null) return provided;
    // Compatibility for engine-private tests and staged migrations that still
    // mount a raw genesis inherited value above no ProviderScope at all.
    return dependOnInheritedSeedOfExactType<T>();
  }
}

final class _ProviderScopeState
    extends SingleChildState<SingleChildStatefulSeed> {
  late final Map<Type, _ProviderEntry> _entries;

  ProviderScope get _scope => seed as ProviderScope;

  @override
  void initState() {
    final descriptors = List<Provider<Object>>.of(_scope.providers);
    final entries = <Type, _ProviderEntry>{};
    try {
      for (final descriptor in descriptors) {
        final type = descriptor._type;
        if (entries.containsKey(type)) {
          throw StateError(
            'ProviderScope contains duplicate provider type: $type',
          );
        }
        entries[type] = descriptor._initialize();
      }
    } catch (error, stack) {
      for (final entry in entries.values.toList().reversed) {
        entry.dispose?.call();
      }
      Error.throwWithStackTrace(error, stack);
    }
    _entries = entries;
  }

  @override
  Seed build(TreeContext context) =>
      _build(context, _scope.child ?? const _Empty());

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      _build(context, child);

  Seed _build(TreeContext context, Seed child) {
    for (final descriptor in _scope.providers) {
      if (descriptor._isAdopted) {
        _entries[descriptor._type]?.value = descriptor._value as Object;
      }
    }
    final parent = context.dependOnInheritedSeedOfExactType<_ProviderValues>();
    return InheritedSeed<_ProviderValues>(
      value: _ProviderValues(_entries, parent),
      child: child,
    );
  }

  @override
  void dispose() {
    for (final entry in _entries.values.toList().reversed) {
      entry.dispose?.call();
    }
  }
}

final class _Empty extends Seed {
  const _Empty();

  @override
  Branch createBranch() => _EmptyBranch(this);
}

final class _EmptyBranch extends Branch {
  _EmptyBranch(_Empty super.seed);
}

final class _ProviderEntry {
  _ProviderEntry(this.value, this.dispose);

  Object value;
  final void Function()? dispose;
}

final class _ProviderValues {
  const _ProviderValues(this.entries, this.parent);

  final Map<Type, _ProviderEntry> entries;
  final _ProviderValues? parent;

  T? find<T extends Object>() {
    final local = entries[T];
    return local == null ? parent?.find<T>() : local.value as T;
  }
}
