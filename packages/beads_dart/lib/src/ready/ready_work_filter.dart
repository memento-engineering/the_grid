import '../models/bead_status.dart';

/// Sort policy for the ready-work predicate (beads `types.SortPolicy`,
/// `internal/types/types.go:1295-1318`).
///
/// The three valid policies plus the empty/default sentinel. Both the SQL
/// `ORDER BY` and the post-merge in-memory comparator implement these
/// identically (port spec §6 / §6.1).
///
/// ⚠ **Defaults disagree by layer** (port spec trap #5): storage maps the empty
/// policy → [hybrid], but the **CLI flag default is `--sort priority`**. The
/// differential harness therefore always passes a policy explicitly so the SQL
/// port and the `bd ready --json` oracle never silently diverge on the default.
enum ReadyWorkSortPolicy {
  /// `ORDER BY created_at ASC, id ASC`.
  oldest('oldest'),

  /// `ORDER BY priority ASC, created_at DESC, id ASC`.
  priority('priority'),

  /// The 48h-recency-banded policy (beads default; port spec §6).
  hybrid('hybrid');

  const ReadyWorkSortPolicy(this.wire);

  /// The `--sort` flag value passed to `bd ready` (the oracle).
  final String wire;
}

/// The subset of beads' `types.WorkFilter`
/// (`internal/types/types.go:1324-1369`) that the ready-work predicate consumes.
///
/// Only the fields that actually influence `buildReadyWorkPredicates`
/// (`ready_work.go:60-208`) + the sort policy are modeled. The port-spec traps
/// #9 (`LabelsAny`) and #10 (`MolType`/`WispType`) are deliberately **absent** —
/// the `bd ready --json` oracle never reads them (`buildReadyWorkPredicates`
/// runs for both the issues and the wisp pass), so modelling them would invite
/// a divergence the oracle does not have.
///
/// Defaults match the `--json` oracle invocation the differential harness uses
/// (`bd ready --json --limit 0 --sort <policy>`):
/// - [status] defaults to [BeadStatus.open] — the `bd ready` CLI hardcodes
///   `Status: "open"` (`cmd/bd/ready.go:123`). Passing `null` selects the
///   storage-API default `status IN ('open', 'in_progress')` instead — see
///   trap #4; the harness never does this.
/// - [limit] defaults to `0` (unlimited); `--limit 0` is what kills the CLI's
///   default 100-row truncation (port spec §10).
class ReadyWorkFilter {
  const ReadyWorkFilter({
    this.status = BeadStatus.open,
    this.includeEphemeral = false,
    this.includeDeferred = false,
    this.priority,
    this.type,
    this.unassigned = false,
    this.assignee,
    this.labels = const [],
    this.excludeLabels = const [],
    this.parentId,
    this.moleculeId,
    this.hasMetadataKey,
    this.metadataFields = const {},
    this.excludeTypes = const [],
    this.sortPolicy = ReadyWorkSortPolicy.priority,
    this.limit = 0,
  });

  /// Exact status to match (`status = ?`). `null` → the storage-API default
  /// `status IN ('open', 'in_progress')` (clause #1; trap #4). The CLI oracle
  /// always pins `'open'`.
  final BeadStatus? status;

  /// When `false` (default), excludes ephemeral beads (clause #4).
  final bool includeEphemeral;

  /// When `false` (default), applies the `defer_until` cutoff (clause #8) plus
  /// the one-hop deferred-parent child exclusion (clause #9).
  final bool includeDeferred;

  /// Exact priority match (clause #5). `null` → no priority filter.
  final int? priority;

  /// Exact `issue_type` match (clause #6a). When set, the §3.1 exclusion list
  /// is **dropped** (trap #6) — `bd ready -t molecule` returns molecules.
  final String? type;

  /// When `true`, `(assignee IS NULL OR assignee = '')` (clause #7a); takes
  /// precedence over [assignee].
  final bool unassigned;

  /// Exact assignee match (clause #7b); ignored when [unassigned] is `true`.
  final String? assignee;

  /// AND-semantics label requirements (clause #10).
  final List<String> labels;

  /// Labels whose presence excludes a bead (clause #11).
  final List<String> excludeLabels;

  /// Recursive-descendant parent scoping (clause #12 / §3.3).
  final String? parentId;

  /// Direct-children molecule scoping (clause #13 / §3.4). Not reachable from
  /// `bd ready` flags; modeled for gc-style callers.
  final String? moleculeId;

  /// Metadata-key existence filter (clause #14).
  final String? hasMetadataKey;

  /// Metadata key=value equality filters (clause #15); keys are sorted
  /// ascending before arg assembly (port spec §3, ⚠ ordering).
  final Map<String, String> metadataFields;

  /// Extra `issue_type`s to exclude, appended to the §3.1 base list in user
  /// order, skipping empties and duplicates (`--exclude-type`). Ignored when
  /// [type] is set (trap #6).
  final List<String> excludeTypes;

  /// The sort policy (§6). Defaults to [ReadyWorkSortPolicy.priority] to match
  /// the `bd ready` CLI default.
  final ReadyWorkSortPolicy sortPolicy;

  /// `LIMIT n`; `0` (default) = unlimited. There is **no OFFSET** in the ready
  /// path (port spec §3).
  final int limit;
}

/// The failure-close vocabulary (beads `types.FailureCloseKeywords`,
/// `internal/types/types.go:907-921`), ported **verbatim and in order**.
///
/// ⚠ **Carried as data only — NOT consulted by the SQL predicate** (port spec
/// §4.3 / trap #1). In bd 1.0.5 `conditional-blocks` behaves identically to
/// `blocks` at the readiness level: the dependent is blocked while the target
/// is open and unblocks on **any** close (success or failure). `IsFailureClose`
/// has zero call sites in bd's ready path, so branching the predicate on
/// `close_reason` would diverge from the `bd ready` oracle. The vocabulary is
/// ported so later reconciler tracks (gc-side conditional semantics) can consume
/// it from a single shared definition.
const List<String> kFailureCloseKeywords = [
  'failed',
  'rejected',
  'wontfix',
  "won't fix",
  'canceled',
  'cancelled',
  'abandoned',
  'blocked',
  'error',
  'timeout',
  'aborted',
];

/// Ports beads `types.IsFailureClose` (`internal/types/types.go:923-937`):
/// case-insensitive **substring** match of any [kFailureCloseKeywords] entry
/// against [closeReason]. An empty reason is never a failure.
///
/// ⚠ Like the vocabulary above, this is **not** used by the ready-work predicate
/// (port spec trap #1); it exists for the reconciler's shared conditional
/// vocabulary. Using it inside the SQL port would diverge from the oracle.
bool isFailureClose(String closeReason) {
  if (closeReason.isEmpty) return false;
  final lower = closeReason.toLowerCase();
  for (final keyword in kFailureCloseKeywords) {
    if (lower.contains(keyword)) return true;
  }
  return false;
}
