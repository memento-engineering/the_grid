import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_controller/grid_controller.dart';

part 'message.freezed.dart';

/// Typed view over a message bead's `metadata` namespace.
///
/// Messages carry a thin metadata blob (the live city writes just `from`);
/// unknown keys are preserved in [raw].
@freezed
abstract class MessageMetadata with _$MessageMetadata {
  const MessageMetadata._();

  const factory MessageMetadata({
    @Default(<String, dynamic>{}) Map<String, dynamic> raw,
  }) = _MessageMetadata;

  factory MessageMetadata.fromMetadata(Map<String, dynamic> metadata) =>
      MessageMetadata(raw: Map<String, dynamic>.unmodifiable(metadata));

  /// The sender (`metadata.from`).
  String? get from {
    final value = raw['from'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }
}

/// A message: "mail = a bead with `type: message`" (ADR-0002 Decision 2).
///
/// - `assignee` = recipient
/// - `metadata.from` = sender
/// - `labels` carry `thread:<id>`
/// - **closing = archiving**; an *open* + *addressed* message is **unread**.
@freezed
abstract class Message with _$Message {
  const Message._();

  const factory Message({
    required String id,
    required String title,
    required String body,
    required String recipient,
    required MessageMetadata metadata,
    required List<String> labels,
    required bool archived,
    DateTime? createdAt,
  }) = _Message;

  /// Label prefix that carries the conversation thread id.
  static const threadLabelPrefix = 'thread:';

  /// Projects a `message`-typed [bead] into a [Message], or returns a typed
  /// [ProjectionError] on type mismatch.
  static ProjectionResult<Message> project(Bead bead) {
    if (bead.issueType != IssueType.message) {
      return ProjectionFailed(
        ProjectionError(
          beadId: bead.id,
          issueType: bead.issueType.wire,
          projection: 'Message',
          reason: 'expected issue_type "message", got "${bead.issueType.wire}"',
        ),
      );
    }
    return ProjectionOk(
      Message(
        id: bead.id,
        title: bead.title,
        body: bead.description,
        recipient: bead.assignee,
        metadata: MessageMetadata.fromMetadata(bead.metadata),
        labels: List<String>.unmodifiable(bead.labels),
        // closing = archiving.
        archived: bead.status == BeadStatus.closed,
        createdAt: bead.createdAt,
      ),
    );
  }

  /// The sender, from `metadata.from`.
  String? get sender => metadata.from;

  /// The conversation thread id parsed from the first `thread:<id>` label, if
  /// any.
  String? get threadId {
    for (final label in labels) {
      if (label.startsWith(threadLabelPrefix)) {
        return label.substring(threadLabelPrefix.length);
      }
    }
    return null;
  }

  /// "open + addressed = unread": not archived and addressed to a recipient.
  bool get isUnread => !archived && recipient.isNotEmpty;
}
