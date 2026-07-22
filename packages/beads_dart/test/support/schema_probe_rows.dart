import 'package:beads_dart/src/services/dolt_schema_shape.dart';

/// The v53 (bd 1.1.0) column set, verbatim from
/// `SELECT table_name AS t, column_name AS c FROM information_schema.columns`
/// against the live `tg` store on 2026-07-21. Shared by every fake connection
/// so one capture is the single source of truth for "a supported store".
final List<Map<String, Object?>> kV53ProbeRows = [
  for (final column in _beadColumns) ...[
    {'t': 'issues', 'c': column},
    {'t': 'wisps', 'c': column},
  ],
  for (final column in _labelColumns) ...[
    {'t': 'labels', 'c': column},
    {'t': 'wisp_labels', 'c': column},
  ],
  for (final column in _dependencyColumns) ...[
    {'t': 'dependencies', 'c': column},
    {'t': 'wisp_dependencies', 'c': column},
  ],
];

/// The shape those rows parse into, at migration 53.
final DoltSchemaShape kV53Shape = DoltSchemaShape.fromColumnRows(
  kV53ProbeRows,
  migrationVersion: 53,
);

/// `issues` and `wisps` carry the identical 54-column list at v53.
const List<String> _beadColumns = [
  'id',
  'content_hash',
  'title',
  'description',
  'design',
  'acceptance_criteria',
  'notes',
  'status',
  'priority',
  'issue_type',
  'assignee',
  'estimated_minutes',
  'created_at',
  'created_by',
  'owner',
  'updated_at',
  'closed_at',
  'closed_by_session',
  'external_ref',
  'spec_id',
  'compaction_level',
  'compacted_at',
  'compacted_at_commit',
  'original_size',
  'sender',
  'ephemeral',
  'wisp_type',
  'pinned',
  'is_template',
  'mol_type',
  'work_type',
  'source_system',
  'metadata',
  'source_repo',
  'close_reason',
  'event_kind',
  'actor',
  'target',
  'payload',
  'await_type',
  'await_id',
  'timeout_ns',
  'waiters',
  'hook_bead',
  'role_bead',
  'agent_state',
  'last_activity',
  'role_type',
  'rig',
  'due_at',
  'defer_until',
  'no_history',
  'started_at',
  'is_blocked',
];

const List<String> _labelColumns = ['issue_id', 'label'];

const List<String> _dependencyColumns = [
  'id',
  'issue_id',
  'type',
  'created_at',
  'created_by',
  'metadata',
  'thread_id',
  'depends_on_issue_id',
  'depends_on_wisp_id',
  'depends_on_external',
];
