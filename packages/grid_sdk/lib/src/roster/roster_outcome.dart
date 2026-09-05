import 'package:freezed_annotation/freezed_annotation.dart';

part 'roster_outcome.freezed.dart';

/// The typed outcome of one live-roster mutation.
@freezed
sealed class RosterOutcome with _$RosterOutcome {
  /// [name] attached at [root], minting ids under [prefix].
  const factory RosterOutcome.attached({
    required String name,
    required String prefix,
    required String root,
  }) = RosterAttached;

  /// [name] detached and [reapedWorktrees] worktrees were removed.
  const factory RosterOutcome.detached({
    required String name,
    required int reapedWorktrees,
  }) = RosterDetached;

  /// [name] is draining its [inFlight] work beads before detach.
  const factory RosterOutcome.draining({
    required String name,
    required Set<String> inFlight,
  }) = RosterDraining;

  /// The mutation was refused with zero effect.
  const factory RosterOutcome.refused({
    required String code,
    required String message,
  }) = RosterRefused;
}
