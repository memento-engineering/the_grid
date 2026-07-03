import 'package:freezed_annotation/freezed_annotation.dart';

part 'bead_comment.freezed.dart';
part 'bead_comment.g.dart';

/// A comment attached to a bead. Comments are heavy and only fetched on the
/// `bd export` / `bd show` paths — snapshots used for diffing omit them and
/// rely on [Bead.commentCount] as the change signal.
@freezed
abstract class BeadComment with _$BeadComment {
  const factory BeadComment({
    required String id,
    @JsonKey(name: 'issue_id') @Default('') String issueId,
    @Default('') String author,
    @Default('') String text,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _BeadComment;

  factory BeadComment.fromJson(Map<String, dynamic> json) =>
      _$BeadCommentFromJson(json);
}
