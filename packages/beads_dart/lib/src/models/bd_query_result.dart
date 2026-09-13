import 'package:freezed_annotation/freezed_annotation.dart';

import 'bead.dart';

part 'bd_query_result.freezed.dart';

/// Evidence-bearing outcome of a query whose empty result must prove absence.
///
/// The result deliberately has no JSON codec: it is an in-process correctness
/// contract over bd calls, not a persisted or wire-level value.
@freezed
sealed class BdQueryResult with _$BdQueryResult {
  /// The target query returned one or more [rows].
  const factory BdQueryResult.rows({required List<Bead> rows}) = BdQueryRows;

  /// The target was empty while an independent positive control returned rows.
  const factory BdQueryResult.verifiedEmpty({
    required List<String> targetCall,
    required List<String> positiveControlCall,
  }) = BdQueryVerifiedEmpty;

  /// The two calls could not prove either rows or verified absence.
  const factory BdQueryResult.unavailable({
    required List<String> targetCall,
    required List<String> positiveControlCall,
    required String reason,
    required String remedy,
  }) = BdQueryUnavailable;
}
