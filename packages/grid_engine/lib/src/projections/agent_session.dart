import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_controller/grid_controller.dart';

part 'agent_session.freezed.dart';

/// Lifecycle state of a session, derived from the bead's status.
///
/// gc's session lifecycle is rich (draining, drained, detached…) and lives in
/// `metadata.state`; the_grid's *durable* state notion is the binary the bead
/// status carries: an open bead is a live session, a closed bead is a retired
/// one. The finer-grained gc lifecycle is preserved on
/// [AgentSession.lifecycleState] (from `metadata.state`) without being promoted
/// to a typed enum the_grid does not yet own.
enum SessionState { open, closed }

/// Typed view over the `session.*` metadata namespace.
///
/// Maps the documented keys (agent_name, alias, command, continuation_epoch,
/// close_reason, closed_at, state, …) to typed getters while preserving the
/// **entire** raw metadata map (gc writes ~40 keys per session) — unknown keys
/// are never dropped.
@freezed
abstract class SessionMetadata with _$SessionMetadata {
  const SessionMetadata._();

  const factory SessionMetadata({
    @Default(<String, dynamic>{}) Map<String, dynamic> raw,
  }) = _SessionMetadata;

  /// Wraps a bead's raw metadata blob. Total — never throws.
  factory SessionMetadata.fromMetadata(Map<String, dynamic> metadata) =>
      SessionMetadata(raw: Map<String, dynamic>.unmodifiable(metadata));

  String? _str(String key) {
    final value = raw[key];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// The stable agent name (`metadata.agent_name`) — the durable identity that
  /// survives process restarts.
  String? get agentName => _str('agent_name');

  /// Human alias for the session (`metadata.alias`).
  String? get alias => _str('alias');

  /// The launch command (`metadata.command`).
  String? get command => _str('command');

  /// Continuation epoch counter (`metadata.continuation_epoch`), parsed.
  int? get continuationEpoch => int.tryParse(_str('continuation_epoch') ?? '');

  /// gc's fine-grained lifecycle state (`metadata.state`): drained, detached,
  /// running, … — preserved verbatim, not promoted to a typed enum.
  String? get lifecycleState => _str('state');

  /// Reason recorded when the session closed (`metadata.close_reason`).
  String? get closeReason => _str('close_reason');

  /// Wall-clock close time from metadata (`metadata.closed_at`), parsed.
  DateTime? get closedAt {
    final raw = _str('closed_at');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Template the session was spawned from (`metadata.template`).
  String? get template => _str('template');

  /// Provider backing the session process (`metadata.provider`).
  String? get provider => _str('provider');

  /// True when gc marked this a pool-managed session (`metadata.pool_managed`).
  bool get poolManaged => _str('pool_managed') == 'true';
}

/// An agent session: a disposable process container with a durable identity.
///
/// "Stable name even as the underlying process restarts" (ADR-0002 Decision 2):
/// the [AgentSession] persists in the Beads Store; the OS process does not. Open
/// vs closed comes from the bead status, the rest from the typed
/// [SessionMetadata] codec.
@freezed
abstract class AgentSession with _$AgentSession {
  const AgentSession._();

  const factory AgentSession({
    required String id,
    required String title,
    required SessionState state,
    required SessionMetadata metadata,
    required List<String> labels,
    DateTime? closedAt,
    @Default('') String closeReason,
  }) = _AgentSession;

  /// Projects a `session`-typed [bead] into an [AgentSession], or returns a
  /// typed [ProjectionError] (wrong type only — sessions always decode).
  static ProjectionResult<AgentSession> project(Bead bead) {
    if (bead.issueType != IssueType.session) {
      return ProjectionFailed(
        ProjectionError(
          beadId: bead.id,
          issueType: bead.issueType.wire,
          projection: 'AgentSession',
          reason: 'expected issue_type "session", got "${bead.issueType.wire}"',
        ),
      );
    }
    final metadata = SessionMetadata.fromMetadata(bead.metadata);
    return ProjectionOk(
      AgentSession(
        id: bead.id,
        title: bead.title,
        state: bead.status == BeadStatus.closed
            ? SessionState.closed
            : SessionState.open,
        metadata: metadata,
        labels: List<String>.unmodifiable(bead.labels),
        // Prefer the column; fall back to the metadata mirror.
        closedAt: bead.closedAt ?? metadata.closedAt,
        closeReason: bead.closeReason.isNotEmpty
            ? bead.closeReason
            : (metadata.closeReason ?? ''),
      ),
    );
  }

  /// The durable agent identity (`metadata.agent_name`), falling back to the
  /// bead title (gc sets the title to the agent name for sessions).
  String get agentName => metadata.agentName ?? title;

  bool get isOpen => state == SessionState.open;
  bool get isClosed => state == SessionState.closed;
}
