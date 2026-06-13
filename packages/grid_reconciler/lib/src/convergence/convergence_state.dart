import 'package:freezed_annotation/freezed_annotation.dart';

part 'convergence_state.freezed.dart';

/// The closed five-state set of gc's convergence loop.
///
/// Wire strings are byte-identical to the upstream constants in
/// `gascity/internal/convergence/metadata.go:50-56`:
///
/// * `creating`        — metadata.go:51 ("set immediately after bead creation;
///   reconciler terminates partial creations")
/// * `active`          — metadata.go:52
/// * `waiting_manual`  — metadata.go:53
/// * `waiting_trigger` — metadata.go:54
/// * `terminated`      — metadata.go:55
///
/// Modeled as an **enum** (closed set), not an extension type: unlike bead
/// statuses/types (open sets with custom values, ADR-0000 A9), gc *validates*
/// this set and errors on anything else (`reconcile.go:101-106` — "unknown
/// convergence state %q"), so an unseen value is upstream drift that must
/// surface loudly, not pass through. The "no state yet" condition (gc's `""`,
/// i.e. an absent `convergence.state` key) is **not** a sixth state — it is the
/// 'not yet adopted' reading, represented by [ConvergenceStateReading.notAdopted].
enum ConvergenceState {
  /// metadata.go:51 — `StateCreating = "creating"`.
  creating('creating'),

  /// metadata.go:52 — `StateActive = "active"`.
  active('active'),

  /// metadata.go:53 — `StateWaitingManual = "waiting_manual"`.
  waitingManual('waiting_manual'),

  /// metadata.go:54 — `StateWaitingTrigger = "waiting_trigger"`.
  waitingTrigger('waiting_trigger'),

  /// metadata.go:55 — `StateTerminated = "terminated"`.
  terminated('terminated');

  const ConvergenceState(this.wire);

  /// The exact string gc writes to `convergence.state`.
  final String wire;

  /// Resolves a wire string to its state, or null when unrecognized.
  /// Callers needing the absent/unrecognized distinction use
  /// [ConvergenceStateReading.decode].
  static ConvergenceState? fromWire(String wire) {
    for (final state in values) {
      if (state.wire == wire) return state;
    }
    return null;
  }

  /// True only for [terminated] — the irreversible terminal state
  /// (ADR-0003 invariant 6).
  bool get isTerminal => this == terminated;
}

/// The result of reading `convergence.state` from a metadata map — total,
/// never throws, never coerces.
///
/// Three mutually exclusive readings:
///
/// * [ConvergenceStateReading.known] — one of the five ratified states.
/// * [ConvergenceStateReading.notAdopted] — the key is absent or the empty
///   string. Go map access cannot distinguish the two (`meta[FieldState]`
///   yields `""` for both), and gc's recovery treats `""` as "the bead was
///   created but the convergence loop never started" (`reconcile.go:73-76`,
///   the adopt/pour-wisp-1 path). Semantically: *not yet adopted* — distinct
///   from every real state and deliberately not modeled as a sixth enum value.
/// * [ConvergenceStateReading.unrecognized] — a non-empty value outside the
///   ratified set (or a non-String value). gc errors on this
///   (`reconcile.go:101-106`); shadow mode must surface it as a typed decode
///   failure, never crash or silently coerce.
@freezed
sealed class ConvergenceStateReading with _$ConvergenceStateReading {
  const ConvergenceStateReading._();

  const factory ConvergenceStateReading.known(ConvergenceState state) =
      KnownConvergenceState;

  const factory ConvergenceStateReading.notAdopted() = ConvergenceNotAdopted;

  const factory ConvergenceStateReading.unrecognized(Object? rawValue) =
      UnrecognizedConvergenceState;

  /// Decodes the raw metadata value for `convergence.state`.
  ///
  /// [present] distinguishes "key absent" from "key present"; both an absent
  /// key and a present-but-empty string decode to [notAdopted] (gc-equivalent,
  /// see class doc).
  static ConvergenceStateReading decode(
    Object? rawValue, {
    required bool present,
  }) {
    if (!present) return const ConvergenceStateReading.notAdopted();
    if (rawValue is! String) {
      return ConvergenceStateReading.unrecognized(rawValue);
    }
    if (rawValue.isEmpty) return const ConvergenceStateReading.notAdopted();
    final state = ConvergenceState.fromWire(rawValue);
    if (state == null) return ConvergenceStateReading.unrecognized(rawValue);
    return ConvergenceStateReading.known(state);
  }

  /// The known state, or null for [notAdopted]/[unrecognized].
  ConvergenceState? get stateOrNull => switch (this) {
    KnownConvergenceState(:final state) => state,
    ConvergenceNotAdopted() => null,
    UnrecognizedConvergenceState() => null,
  };
}
