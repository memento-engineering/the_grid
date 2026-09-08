import 'package:freezed_annotation/freezed_annotation.dart';

part 'trajectory_append_result.freezed.dart';

/// The completed disposition of a decision-bearing trajectory append.
///
/// Unlike the recorder's fire-and-forget observations, callers consume this
/// sealed result exhaustively because losing the record can change whether the
/// station may safely admit more work.
@freezed
sealed class TrajectoryAppendResult with _$TrajectoryAppendResult {
  /// The record committed, deduplicated, or was benignly refused testimony.
  const factory TrajectoryAppendResult.acked() = Acked;

  /// The append request was lost before it could earn an acknowledgement.
  const factory TrajectoryAppendResult.dropped() = Dropped;

  /// Harness posture prevented the request from earning an acknowledgement.
  const factory TrajectoryAppendResult.suppressed() = Suppressed;
}
