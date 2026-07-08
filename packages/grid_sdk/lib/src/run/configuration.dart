import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:genesis_tree/genesis_tree.dart';

part 'configuration.freezed.dart';

/// The grid's configuration — a **thin, plain value** (Q6): plausibly nothing
/// more than the result of TOML loading, provided *into* the tree like any
/// other value. There is **no domain/aspect machinery** (no `of<T>()`, no
/// `addDomain`) until a real consumer earns the first typed domain — the §2
/// pseudo's `GridConfiguration.of<ButaneGridConfiguration>` is aspirational,
/// deliberately deferred (v3 §1/§6, "earn it").
///
/// It is the observed state of the [GridDelegate]
/// (`StateNotifier<GridConfiguration>`): `runGrid` re-provides the currently
/// observed value ambiently as `InheritedSeed<GridConfiguration>`, so a station
/// author reads it with [of]/[maybeOf] and a re-emitted configuration
/// **re-composes** the dependent subtree (v3 §1: "a watched value re-composes").
///
/// [settings] is the opaque payload (e.g. the parsed TOML). It is compared by
/// value (a deep map equality) so re-emitting an equal configuration does not
/// churn the tree — genesis's identity check declines to notify.
///
/// See `GridDelegate` for the delegate that carries it and `docs/`
/// `SCRATCH-station-config-model.md` §4 for the ratified model.
@freezed
abstract class GridConfiguration with _$GridConfiguration {
  /// A configuration carrying an opaque [settings] payload — plausibly the
  /// TOML-load result. Empty by default; typed access is deferred (Q6).
  const factory GridConfiguration({
    @Default(<String, Object?>{}) Map<String, Object?> settings,
  }) = _GridConfiguration;

  const GridConfiguration._();

  /// The ambient [GridConfiguration] provided by `runGrid`, or null outside a
  /// running grid. **Subscribes**: a re-emitted configuration rebuilds the
  /// reader (use this in a `build`, never in `State.initState`).
  static GridConfiguration? maybeOf(TreeContext context) =>
      context.dependOnInheritedSeedOfExactType<GridConfiguration>();

  /// The ambient [GridConfiguration], **loud when absent** — reading
  /// configuration outside a running grid is an authoring error, not a default
  /// (v3 §0; the guard principle). Read it below `runGrid`, inside the tree.
  static GridConfiguration of(TreeContext context) {
    final config = maybeOf(context);
    if (config == null) {
      throw StateError(
        'GridConfiguration.of: no configuration in scope. The ambient '
        'GridConfiguration is provided by runGrid — read it inside the grid '
        'tree, below runGrid(delegate).',
      );
    }
    return config;
  }
}
