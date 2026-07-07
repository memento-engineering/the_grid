import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:genesis_tree/genesis_tree.dart';

part 'scopes.freezed.dart';

/// The grid's home — the root [RawAssetGrid] was authored with.
///
/// The grid's **state store** lives under `<path>/.grid/` (Q5a); the grid has
/// no work store (v3 §3). Provided into the tree by `RawAssetGrid`; a
/// `Station` authored without its own `root` defaults to this (v3 §3).
@freezed
abstract class GridRoot with _$GridRoot {
  /// Wraps the grid's home [path].
  const factory GridRoot({required String path}) = _GridRoot;

  /// The ambient [GridRoot], or null when no `RawAssetGrid` encloses
  /// [context]. Subscribes: a changed root rebuilds the dependent.
  static GridRoot? maybeOf(TreeContext context) =>
      context.dependOnInheritedSeedOfExactType<GridRoot>();

  /// The ambient [GridRoot]. Loud when absent: composition outside a
  /// `RawAssetGrid` is an authoring error, not a default (v3 §0).
  static GridRoot of(TreeContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw StateError(
        'GridRoot.of: no RawAssetGrid encloses this context. A grid tree is '
        'rooted at RawAssetGrid(root: ...) — there is no default root.',
      );
    }
    return scope;
  }
}

/// The enclosing station's identity — the machine (GLOSSARY: Station).
///
/// Provided into the tree by `Station`; its [root] is already resolved
/// (explicit, or defaulted to the ambient [GridRoot] at build).
@freezed
abstract class StationScope with _$StationScope {
  /// A station named [name] rooted at [root].
  const factory StationScope({required String name, required String root}) =
      _StationScope;

  /// The ambient [StationScope], or null when no `Station` encloses
  /// [context].
  static StationScope? maybeOf(TreeContext context) =>
      context.dependOnInheritedSeedOfExactType<StationScope>();

  /// The ambient [StationScope], loud when absent.
  static StationScope of(TreeContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw StateError(
        'StationScope.of: no Station encloses this context.',
      );
    }
    return scope;
  }
}

/// The enclosing substation's identity — a project: a name and ONE root
/// (v3 §0: never sets, never defaults). Its **work store** lives at
/// `<root>/.beads/` — a store lives at a root, uniformly (Q5a).
@freezed
abstract class SubstationScope with _$SubstationScope {
  /// A substation named [name] whose single root is [root].
  const factory SubstationScope({required String name, required String root}) =
      _SubstationScope;

  /// The ambient [SubstationScope], or null when no `Substation` encloses
  /// [context].
  static SubstationScope? maybeOf(TreeContext context) =>
      context.dependOnInheritedSeedOfExactType<SubstationScope>();

  /// The ambient [SubstationScope], loud when absent.
  static SubstationScope of(TreeContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw StateError(
        'SubstationScope.of: no Substation encloses this context.',
      );
    }
    return scope;
  }
}
