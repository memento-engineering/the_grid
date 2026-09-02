import 'dart:io';

import 'package:meta/meta.dart';

import '../codecs/envelope.dart';
import '../errors/bd_exception.dart';
import '../models/bead.dart';
import '../models/bead_dependency.dart';
import '../models/bead_status.dart';
import '../models/dependency_type.dart';
import '../models/graph_apply_plan.dart';
import '../models/issue_type.dart';
import '../ready/ready_work_filter.dart';
import '../ready/ready_work_sort.dart';
import 'bd_runner.dart';

enum _GuardedWriteSupport { supported, unsupported, indeterminate }

/// The bd-CLI service tier (predictable-flutter Services: stateless I/O).
///
/// Wraps a [BdRunner] and turns each `bd` subcommand into a typed Future.
/// **Futures for acts** (every method here is one-shot); observations are the
/// repository's job. Reads decode through [BdEnvelope.parse] (asserting
/// `schema_version == 1`); non-zero results route through
/// [BdException.fromOutput], which classifies known contracts and reads error
/// envelopes off stdout first (ADR-0001 Decision 4).
///
/// **Mutations go through `bd` only — never SQL** (ADR-0001 D4). Every
/// mutation carries `--actor grid-controller`. This service holds no Dolt
/// dependency by construction: it cannot issue a SQL string.
class BdCliService {
  BdCliService(this._runner);

  /// The actor stamped on every mutation's audit trail (CLAUDE.md / ADR-0001).
  static const String actor = 'grid-controller';

  /// How many ids to pack into one multi-id spawn (`dep list`, `show`). Bounded
  /// so a huge id set degrades into a handful of spawns, never one-per-id
  /// (ADR-0001 D4: "never spawn bd per issue in a loop").
  static const int idChunkSize = 50;

  static Future<_GuardedWriteSupport>? _guardedWriteSupport;
  static bool _guardedWriteReceiptEmitted = false;

  static const _guardedWriteDegradedData = <String, String>{
    'missingCapability': '--if-assignee,--if-status',
    'safetyDropped': 'compare-and-swap defence in depth',
    'primarySafety': 'StationBeadWriter single-writer chokepoint preserved',
  };

  /// Clears the process-wide guarded-write negotiation state for isolated tests.
  @visibleForTesting
  static void resetGuardedWriteCapabilityForTesting() {
    _guardedWriteSupport = null;
    _guardedWriteReceiptEmitted = false;
  }

  final BdRunner _runner;

  // ---------------------------------------------------------------------------
  // READS
  // ---------------------------------------------------------------------------

  /// `bd ready --json --limit 0` — the authoritative complete ready-work set,
  /// normalized to the CLI default priority order after the unlimited fetch.
  Future<List<Bead>> ready() async {
    final env = await _runEnvelope(readyArgs());
    final beads = _beadsFromList(env.dataList);
    sortReadyWork(
      beads,
      ReadyWorkSortPolicy.priority,
      idOf: (bead) => bead.id,
      priorityOf: (bead) => bead.priority,
      createdAtOf: (bead) => bead.createdAt,
    );
    return beads;
  }

  /// Reads one scope — an explicit [type], an [externalRef], or both —
  /// optionally narrowed to [status] and to the conjunctive metadata equality
  /// filters in [metadataFields], or widened past bd's open-only default by
  /// [includeClosed].
  Future<({List<Bead> beads, List<BeadDependency> dependencies})> listScope({
    IssueType? type,
    BeadStatus? status,
    Map<String, String> metadataFields = const {},
    String? externalRef,
    bool includeClosed = false,
  }) async {
    final env = await _runEnvelope(
      listScopeArgs(
        type: type,
        status: status,
        metadataFields: metadataFields,
        externalRef: externalRef,
        includeClosed: includeClosed,
      ),
    );
    return _parseIssueList(env.dataList);
  }

  /// `bd query "<expr>" --json` — a filtered read returning matching [Bead]s.
  Future<List<Bead>> query(String expr, {bool includeClosed = false}) async {
    final env = await _runEnvelope(
      queryArgs(expr, includeClosed: includeClosed),
    );
    return _beadsFromList(env.dataList);
  }

  /// `bd dep list id1 id2 … --json` — dependency edges for the given issues,
  /// chunked at [idChunkSize] ids per spawn (multi-id form, never per-issue).
  /// Returns the flattened, de-duplicated edge list across all chunks.
  Future<List<BeadDependency>> depList(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final edges = <String, BeadDependency>{};
    for (final chunk in _chunk(ids, idChunkSize)) {
      final env = await _runEnvelope(depListArgs(chunk));
      for (final dep in _depsFromList(env.dataList)) {
        edges[dep.edgeKey] = dep;
      }
    }
    return edges.values.toList(growable: false);
  }

  /// `bd statuses --json` — the workspace's status definitions (object
  /// envelope: `built_in_statuses`, …).
  Future<Map<String, dynamic>> statuses() async {
    final env = await _runEnvelope(statusesArgs());
    return env.dataMap;
  }

  /// `bd types --json` — the workspace's type definitions (object envelope:
  /// `core_types`, `custom_types`).
  Future<Map<String, dynamic>> types() async {
    final env = await _runEnvelope(typesArgs());
    return env.dataMap;
  }

  /// `bd show id1 id2 … --json` — full bead records for the given ids,
  /// chunked at [idChunkSize] per spawn.
  ///
  /// WARNING: `bd show` writes `.beads/last-touched`, which self-triggers the
  /// `.beads/` file watcher. **NEVER call this from the re-query / controller
  /// hot path** (ADR-0001 Decision 5) — doing so creates a refresh→show→
  /// watcher→refresh feedback loop. Use scoped lists (or pooled SQL) for
  /// snapshot composition; reserve [show] for explicit, user-driven lookups.
  Future<List<Bead>> show(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final beads = <Bead>[];
    for (final chunk in _chunk(ids, idChunkSize)) {
      final env = await _runEnvelope(showArgs(chunk));
      beads.addAll(_beadsFromList(env.dataList));
    }
    return beads;
  }

  // ---------------------------------------------------------------------------
  // MUTATIONS — bd CLI only, never SQL; every one carries --actor grid-controller.
  // ---------------------------------------------------------------------------

  /// `bd create --title … [--type …] [--priority …] [--description …]
  /// [--defer …] [--external-ref …]` — creates one bead and returns the
  /// created [Bead]'s id from the envelope.
  ///
  /// [defer] hides the bead from `bd ready` until that calendar date.
  /// [externalRef] stamps the foreign identity (`gh-9`, a Linear URL) that
  /// [listScope]'s `externalRef` filter later reads back.
  ///
  /// [setMetadata] is written by an **unconditional follow-up [update]** —
  /// one `bd create`, then one `bd update <id> --set-metadata k=v …` — never
  /// by `bd create --metadata <json>`, whose whole-object semantics replace
  /// keys other writers own on the same bead. There is no capability probe
  /// and no second code path: the sequence is identical on every bd from the
  /// 1.0.5 floor up, at the cost of one extra spawn per metadata-bearing
  /// create (`the_grid#bd-create-metadata-rides-a-follow-up-update`). An
  /// empty map writes nothing and spawns nothing.
  ///
  /// If the follow-up fails, the created bead survives WITHOUT its metadata
  /// and the id is not returned — but the foreign identity rides the create
  /// argv, so a caller's [externalRef] dedupe read still finds it instead of
  /// double-filing.
  Future<String> create({
    required String title,
    IssueType type = IssueType.task,
    int priority = 2,
    String? description,
    DateTime? defer,
    String? externalRef,
    Map<String, String> setMetadata = const {},
  }) async {
    final env = await _runEnvelope(
      createArgs(
        title: title,
        type: type,
        priority: priority,
        description: description,
        defer: defer,
        externalRef: externalRef,
      ),
    );
    final id = _idFromEnvelope(env);
    if (setMetadata.isNotEmpty) {
      await update(id, mergeMetadata: setMetadata);
    }
    return id;
  }

  /// `bd update` with any of `--title`, `--status`, `--priority`,
  /// `--description`, `--type`, `--assignee`, and metadata operations.
  /// Only the provided fields are sent.
  ///
  /// **[mergeMetadata] is the convergence-transition write channel (ADR-0000
  /// A16).** Each entry is emitted as `--set-metadata key=value`, whose
  /// server-side `MergeMetadata` semantics overwrite named keys while
  /// preserving absent keys. The operations run in the row-locked transaction,
  /// so a write
  /// sequence carries ONLY its named keys and never clobbers the agent-owned
  /// `convergence.agent_verdict*` channel. The update **succeeds on a CLOSED
  /// bead**, which the terminal `last_processed_wisp` write (written AFTER
  /// the close) requires (ADR-0000 A19). An empty [mergeMetadata] map is omitted.
  ///
  /// [type] and [assignee] are the speculative-wisp **activation** channel
  /// (`ActivateWisp`, convergence_store.go:204-246): a deferred node is
  /// promoted by restoring its real `gc.deferred_type`/`gc.deferred_assignee`
  /// via `-t`/`--assignee` (with the `gc.routed_to`/`gc.execution_routed_to`
  /// values riding [mergeMetadata]).
  ///
  /// [appendNotes] is a straight `--append-notes <text>` passthrough (bd
  /// concatenates it onto the bead's existing notes with a newline separator,
  /// `cmd/bd/update.go`); mutually exclusive with `--notes` upstream, but this
  /// service never sends `--notes`, so no conflict arises here.
  Future<void> update(
    String id, {

    /// Expected current assignee for bd's conditional-update guard.
    String? ifAssignee,

    /// Expected current status for bd's conditional-update guard.
    BeadStatus? ifStatus,

    /// Receives the once-per-process receipt when requested guards are unsupported.
    void Function(String name, Map<String, String> data)? onGuardDegraded,
    String? title,
    BeadStatus? status,
    int? priority,
    String? description,
    String? design,
    String? acceptanceCriteria,
    IssueType? type,
    String? assignee,
    Map<String, String> mergeMetadata = const {},
    Iterable<String> unsetMetadata = const [],
    String? notes,
    String? appendNotes,

    /// Whether to re-read and verify argv-transported text after mutation.
    ///
    /// When false, acceptance criteria and appended notes remain guarded before
    /// process execution, but the successful write is unverified.
    bool verifyTextRoundTrip = true,
  }) async {
    if (notes != null && appendNotes != null && appendNotes.isNotEmpty) {
      throw ArgumentError('notes and appendNotes are mutually exclusive');
    }
    if (notes != null) _refuseUnsafeArgvText('notes', notes);
    if (acceptanceCriteria != null) {
      _refuseUnsafeArgvText('acceptanceCriteria', acceptanceCriteria);
    }
    if (appendNotes != null && appendNotes.isNotEmpty) {
      _refuseUnsafeArgvText('appendNotes', appendNotes);
    }
    for (final entry in mergeMetadata.entries) {
      _refuseUnsafeArgvText('metadata.${entry.key}', entry.value);
    }

    var expectedNotes = '';
    if (verifyTextRoundTrip && appendNotes != null && appendNotes.isNotEmpty) {
      final before = (await show([id])).single;
      expectedNotes = before.notes.isEmpty
          ? appendNotes
          : '${before.notes}\n$appendNotes';
    }

    Directory? tempDir;
    String? stdinText;
    String? bodyFile;
    String? designFile;
    // Decode asserts the schema version (drift guard) on the mutation path too;
    // a non-zero exit was already raised inside _runEnvelope.
    try {
      if (description != null) {
        bodyFile = '-';
        stdinText = description;
      }
      if (design != null && description == null) {
        designFile = '-';
        stdinText = design;
      } else if (design != null) {
        tempDir = await Directory.systemTemp.createTemp('beads-dart-update-');
        final file = File('${tempDir.path}/design.txt');
        await file.writeAsString(design);
        designFile = file.path;
      }
      final requestedGuard = ifAssignee != null || ifStatus != null;
      final capability = requestedGuard
          ? await _guardedWriteCapability()
          : _GuardedWriteSupport.supported;
      final guarded =
          requestedGuard && capability != _GuardedWriteSupport.unsupported;
      if (requestedGuard && !guarded) {
        _emitGuardedWriteDegraded(onGuardDegraded);
      }

      Future<void> runUpdate({required bool guarded}) async {
        await _runEnvelope(
          updateArgs(
            id,
            ifAssignee: guarded ? ifAssignee : null,
            ifStatus: guarded ? ifStatus : null,
            title: title,
            status: status,
            priority: priority,
            bodyFile: bodyFile,
            designFile: designFile,
            acceptanceCriteria: acceptanceCriteria,
            type: type,
            assignee: assignee,
            mergeMetadata: mergeMetadata,
            unsetMetadata: unsetMetadata,
            notes: notes,
            appendNotes: appendNotes,
          ),
          stdin: stdinText,
        );
      }

      try {
        await runUpdate(guarded: guarded);
      } on BdCommandFailed catch (error) {
        if (!guarded || !_isUnknownGuardFlag(error)) rethrow;
        _guardedWriteSupport = Future<_GuardedWriteSupport>.value(
          _GuardedWriteSupport.unsupported,
        );
        _emitGuardedWriteDegraded(onGuardDegraded);
        await runUpdate(guarded: false);
      }
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } on Object {
          // Best-effort cleanup; never mask the mutation result/error.
        }
      }
    }

    if (!verifyTextRoundTrip) return;

    final expected = <String, String>{
      if (acceptanceCriteria != null) 'acceptanceCriteria': acceptanceCriteria,
      if (notes != null) 'notes': notes,
      if (appendNotes != null && appendNotes.isNotEmpty)
        'appendNotes': expectedNotes,
    };
    if (expected.isEmpty) return;

    final storedBead = (await show([id])).single;
    final stored = <String, String>{
      if (acceptanceCriteria != null)
        'acceptanceCriteria': storedBead.acceptanceCriteria,
      if (notes != null) 'notes': storedBead.notes,
      if (appendNotes != null && appendNotes.isNotEmpty)
        'appendNotes': storedBead.notes,
    };
    for (final entry in expected.entries) {
      _verifyRoundTrip(entry.key, entry.value, stored[entry.key]!);
    }
  }

  Future<_GuardedWriteSupport> _guardedWriteCapability() async {
    final cached = _guardedWriteSupport;
    if (cached != null) return await cached;
    final probe = _probeGuardedWrites();
    _guardedWriteSupport = probe;
    return await probe;
  }

  Future<_GuardedWriteSupport> _probeGuardedWrites() async {
    try {
      final result = await _runner.run(const ['update', '--help']);
      if (!result.ok) return _GuardedWriteSupport.indeterminate;
      return _parseGuardedWriteHelp('${result.stdout}\n${result.stderr}');
    } on Object {
      return _GuardedWriteSupport.indeterminate;
    }
  }

  _GuardedWriteSupport _parseGuardedWriteHelp(String text) {
    final lines = text.split('\n');
    if (!lines.any((line) => line.trim() == 'Flags:')) {
      return _GuardedWriteSupport.indeterminate;
    }
    final longFlag = RegExp(r'^(?:-\w,\s*)?--[a-z0-9][a-z0-9-]*(?:\s|$)');
    final flagRows = lines
        .map((line) => line.trimLeft())
        .where(longFlag.hasMatch)
        .toList(growable: false);
    if (flagRows.isEmpty) return _GuardedWriteSupport.indeterminate;
    final assignee = RegExp(r'^(?:-\w,\s*)?--if-assignee(?:\s|$)');
    final status = RegExp(r'^(?:-\w,\s*)?--if-status(?:\s|$)');
    return flagRows.any(assignee.hasMatch) && flagRows.any(status.hasMatch)
        ? _GuardedWriteSupport.supported
        : _GuardedWriteSupport.unsupported;
  }

  void _emitGuardedWriteDegraded(
    void Function(String, Map<String, String>)? emit,
  ) {
    if (_guardedWriteReceiptEmitted || emit == null) return;
    _guardedWriteReceiptEmitted = true;
    emit('bd.guardedWriteDegraded', _guardedWriteDegradedData);
  }

  bool _isUnknownGuardFlag(BdCommandFailed error) {
    final message = error.message;
    return message.contains('unknown flag') &&
        (message.contains('--if-assignee') || message.contains('--if-status'));
  }

  /// `bd close <id> [--reason …]`.
  Future<void> close(String id, {String? reason}) async {
    await _runEnvelope(closeArgs(id, reason: reason));
  }

  /// `bd dep add <issueId> <dependsOnId> [--type …]`.
  Future<void> depAdd(
    String issueId,
    String dependsOnId, {
    DependencyType type = DependencyType.blocks,
  }) async {
    await _runEnvelope(depAddArgs(issueId, dependsOnId, type));
  }

  /// `bd batch` — runs a line-oriented mutation [script] as one dolt
  /// transaction / one `DOLT_COMMIT` (ADR-0001 D4: grouped mutations go through
  /// batch, never per-issue loops).
  ///
  /// Upstream `bd batch` reads the script from **stdin**; [BdRunner.run] pipes
  /// [lines] (joined by newlines) to the child's stdin and closes it. Each line
  /// follows the batch grammar (`close`/`update`/`create`/`dep add`/
  /// `dep remove`). An empty [lines] is a no-op.
  Future<void> batch(List<String> lines) async {
    if (lines.isEmpty) return;
    final script = lines.join('\n');
    await _runEnvelope(batchArgs(), stdin: script);
  }

  /// `bd cook <formula> --mode=runtime [--var k=v …] --json` — **resolves**
  /// a formula's step DAG with variables substituted (ADR-0000 A15 step 1).
  ///
  /// This is a **READ, not a mutation** — it does not persist a proto (no
  /// `--persist`), so it carries no `--actor` (nothing is written to audit).
  /// Returns the resolved envelope's `data` map verbatim (the
  /// `proto_id`/`formula`/`steps` shape, cook.go:309); the caller (the M2
  /// actuator) reads `data['steps']` to build a [GraphApplyPlan].
  ///
  /// [formula] is a formula file path or a registered formula name (cook
  /// resolves both). [mode] defaults to `runtime` (substitute vars). [vars]
  /// become repeated `--var k=v` flags.
  Future<Map<String, dynamic>> cook(
    String formula, {
    String mode = 'runtime',
    Map<String, String> vars = const {},
  }) async {
    final env = await _runEnvelope(cookArgs(formula, mode: mode, vars: vars));
    return env.dataMap;
  }

  /// `bd delete <id> --cascade --force` — the **burn** primitive (ADR-0000
  /// A16): a subtree delete that removes the bead (and its descendants)
  /// entirely.
  ///
  /// Convergence **burns a speculative wisp by deleting it, NEVER closing**:
  /// a closed speculative wisp keeps its `converge:…:iter:N` key prefix +
  /// closed status and permanently inflates `deriveIterationCount`
  /// (ADR-0003 invariant 4; handler-9step trap 2). The actuator calls this
  /// in **post-order** over `Wisp.subtreeIds` (children before parents).
  /// `--force` skips the interactive confirmation (non-interactive spawn);
  /// `--cascade` keeps the subtree semantics bd 1.3 stopped defaulting to, so
  /// a post-order walk and a single root burn agree (tg-1liv).
  Future<void> delete(String id) async {
    await _runEnvelope(deleteArgs(id));
  }

  /// `bd create --graph <plan-file> [--ephemeral] --json` — the atomic
  /// graph-apply pour (ADR-0000 A15 step 2): one transaction / one
  /// `DOLT_COMMIT`. Returns the `key → bead-id` map (the envelope's
  /// `data.ids`, graph_apply.go:48-51).
  ///
  /// **DEFAULT [ephemeral] = false (PERSISTENT).** A convergence pour MUST
  /// drop `--ephemeral`: gc's convergence iterations are committed `issues`
  /// rows (`molecule.Cook → store.Create` sets no `Ephemeral`), and the
  /// crash-safety/replay invariants depend on every iteration being a
  /// git-synced row (ADR-0000 A15 correction). The flag exists only for the
  /// rare genuinely-vapor pour; the M2 actuator never sets it.
  ///
  /// bd reads the plan from a **file path** (graph_apply.go:262
  /// `os.ReadFile`), so the plan is written to a temp file under the system
  /// temp dir, passed by path, and deleted afterwards (best-effort).
  Future<Map<String, String>> applyGraph(
    GraphApplyPlan plan, {
    bool ephemeral = false,
  }) async {
    final dir = await Directory.systemTemp.createTemp('grid-graph-apply');
    final planFile = File('${dir.path}/plan.json');
    try {
      await planFile.writeAsString(plan.toJsonString());
      final env = await _runEnvelope(
        applyGraphArgs(planFile.path, ephemeral: ephemeral),
      );
      return _idMapFromEnvelope(env);
    } finally {
      // Best-effort cleanup; never mask the call's result/error.
      try {
        await dir.delete(recursive: true);
      } on Object {
        // ignore
      }
    }
  }

  // ---------------------------------------------------------------------------
  // argv builders — small + pure so tests can assert exact flags.
  // ---------------------------------------------------------------------------

  static const List<String> _actorArgs = ['--actor', actor];

  List<String> readyArgs() => const ['ready', '--json', '--limit', '0'];

  /// `bd list [-t <type>] [--status <status>] [--all] [--external-ref <ref>]
  /// [--metadata-field k=v …] --json --limit 0`.
  ///
  /// Refuses LOUDLY rather than emitting a surprising read:
  /// - neither [type] nor [externalRef]: an unscoped `--limit 0` list returns
  ///   the whole store, and the caller would diff that against a scoped set;
  /// - [status] together with [includeClosed]: one narrows to a single status
  ///   while the other lifts the status filter, so the pair has no single
  ///   meaning (the [update] `notes`/`appendNotes` exclusion precedent).
  List<String> listScopeArgs({
    IssueType? type,
    BeadStatus? status,
    Map<String, String> metadataFields = const {},
    String? externalRef,
    bool includeClosed = false,
  }) {
    if (type == null && externalRef == null) {
      throw ArgumentError('listScope needs a type or an externalRef scope');
    }
    if (status != null && includeClosed) {
      throw ArgumentError('status and includeClosed are mutually exclusive');
    }
    return [
      'list',
      if (type != null) ...['-t', type.wire],
      if (status != null) ...['--status', status.wire],
      if (includeClosed) '--all',
      if (externalRef != null) ...['--external-ref', externalRef],
      ...metadataFieldArgs(metadataFields),
      '--json',
      '--limit',
      '0',
    ];
  }

  List<String> queryArgs(String expr, {bool includeClosed = false}) => [
    'query',
    expr,
    if (includeClosed) '--all',
    '--json',
    '--limit',
    '0',
  ];

  List<String> depListArgs(List<String> ids) => [
    'dep',
    'list',
    ...ids,
    '--json',
  ];

  List<String> statusesArgs() => const ['statuses', '--json'];

  List<String> typesArgs() => const ['types', '--json'];

  List<String> showArgs(List<String> ids) => ['show', ...ids, '--json'];

  /// `bd create --json --actor … --title … --type … --priority …`, plus the
  /// optional `--description`, `--defer` and `--external-ref` flags.
  ///
  /// **No metadata flag rides this argv.** bd's `create` carries only the
  /// whole-object `--metadata <json>` form, which REPLACES the bead's map;
  /// metadata is written by [create]'s follow-up per-key [update] instead
  /// (`the_grid#bd-create-metadata-rides-a-follow-up-update`).
  List<String> createArgs({
    required String title,
    required IssueType type,
    required int priority,
    String? description,
    DateTime? defer,
    String? externalRef,
  }) => [
    'create',
    '--json',
    ..._actorArgs,
    '--title',
    title,
    '--type',
    type.wire,
    '--priority',
    '$priority',
    if (description != null && description.isNotEmpty) ...[
      '--description',
      description,
    ],
    if (defer != null) ...['--defer', _isoDate(defer)],
    if (externalRef != null && externalRef.isNotEmpty) ...[
      '--external-ref',
      externalRef,
    ],
  ];

  List<String> updateArgs(
    String id, {
    String? ifAssignee,
    BeadStatus? ifStatus,
    String? title,
    BeadStatus? status,
    int? priority,
    String? bodyFile,
    String? designFile,
    String? acceptanceCriteria,
    IssueType? type,
    String? assignee,
    Map<String, String> mergeMetadata = const {},
    Iterable<String> unsetMetadata = const [],
    String? notes,
    String? appendNotes,
  }) => [
    'update',
    id,
    '--json',
    ..._actorArgs,
    if (ifAssignee != null) ...['--if-assignee', ifAssignee],
    if (ifStatus != null) ...['--if-status', ifStatus.wire],
    if (title != null) ...['--title', title],
    if (status != null) ...['--status', status.wire],
    if (priority != null) ...['--priority', '$priority'],
    if (bodyFile != null) ...['--body-file', bodyFile],
    if (designFile != null) ...['--design-file', designFile],
    if (acceptanceCriteria != null) ...['--acceptance', acceptanceCriteria],
    if (type != null) ...['--type', type.wire],
    if (assignee != null) ...['--assignee', assignee],
    // Server-side MergeMetadata overwrites named keys, preserves absent keys,
    // and runs in the row-locked transaction. Empty map ⇒ omitted.
    for (final entry in mergeMetadata.entries) ...[
      '--set-metadata',
      '${entry.key}=${entry.value}',
    ],
    for (final key in unsetMetadata) ...['--unset-metadata', key],
    if (notes != null) ...['--notes', notes],
    if (appendNotes != null && appendNotes.isNotEmpty) ...[
      '--append-notes',
      appendNotes,
    ],
  ];

  List<String> closeArgs(String id, {String? reason}) => [
    'close',
    id,
    '--json',
    ..._actorArgs,
    if (reason != null && reason.isNotEmpty) ...['--reason', reason],
  ];

  List<String> depAddArgs(
    String issueId,
    String dependsOnId,
    DependencyType type,
  ) => [
    'dep',
    'add',
    issueId,
    dependsOnId,
    '--type',
    type.wire,
    '--json',
    ..._actorArgs,
  ];

  List<String> batchArgs() => ['batch', '--json', ..._actorArgs];

  /// `bd cook <formula> --mode=<mode> [--var k=v …] --json`. A resolve, not a
  /// mutation — no `--actor` (nothing is persisted without `--persist`).
  List<String> cookArgs(
    String formula, {
    required String mode,
    required Map<String, String> vars,
  }) => [
    'cook',
    formula,
    '--mode=$mode',
    for (final entry in vars.entries) ...[
      '--var',
      '${entry.key}=${entry.value}',
    ],
    '--json',
  ];

  /// `bd delete <id> --cascade --force --json` — the burn primitive (subtree
  /// delete).
  ///
  /// `--cascade` is PINNED on the argv: bd 1.3 stopped cascading by default,
  /// so `--force` alone ORPHANS dependents, and orphaning is never what a burn
  /// means. bd 1.0.5 and the fleet binary already accept the flag, so one argv
  /// serves every supported bd. This EXTENDS ADR-0003 Decision 8 (A26)'s
  /// `bd delete <id> --force`; the verb, the actor and the post-order caller
  /// contract are unchanged (`the_grid#burn-primitive-argv-pins-cascade`).
  List<String> deleteArgs(String id) => [
    'delete',
    id,
    '--cascade',
    '--force',
    '--json',
    ..._actorArgs,
  ];

  /// `bd create --graph <plan-file> [--ephemeral] --json`. The pour drops
  /// `--ephemeral` (persistent) by default (ADR-0000 A15).
  List<String> applyGraphArgs(String planFile, {required bool ephemeral}) => [
    'create',
    '--graph',
    planFile,
    if (ephemeral) '--ephemeral',
    '--json',
    ..._actorArgs,
  ];

  // ---------------------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------------------

  Future<BdResult> _run(List<String> args, {String? stdin}) {
    // [stdin] feeds text through bd's native stdin transports.
    return _runner.run(args, stdin: stdin);
  }

  void _refuseUnsafeArgvText(String field, String value) {
    for (var offset = 0; offset < value.length; offset++) {
      final unit = value.codeUnitAt(offset);
      if (unit <= 0x1f && unit != 0x09 && unit != 0x0a && unit != 0x0d) {
        throw BeadTextRefused(
          field: field,
          offset: offset,
          context: _contextAt(value, offset),
        );
      }
    }
  }

  /// bd's calendar-date form for `--defer`/`--due` (`2026-01-05`).
  ///
  /// [value]'s own calendar fields are rendered verbatim — never normalized
  /// through UTC, which would shift the date by a day either side of midnight
  /// and defer a bead onto the wrong calendar day.
  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _contextAt(String value, int offset) {
    final start = (offset - 30).clamp(0, value.length);
    final end = (start + 60).clamp(0, value.length);
    return value.substring(start, end);
  }

  void _verifyRoundTrip(String field, String sent, String stored) {
    if (sent == stored) return;
    final sharedLength = sent.length < stored.length
        ? sent.length
        : stored.length;
    var offset = 0;
    while (offset < sharedLength &&
        sent.codeUnitAt(offset) == stored.codeUnitAt(offset)) {
      offset++;
    }
    throw BeadTextRoundTripFailure(
      field: field,
      sentLength: sent.length,
      storedLength: stored.length,
      offset: offset,
      sentContext: _contextAt(sent, offset),
      storedContext: _contextAt(stored, offset),
    );
  }

  Future<BdEnvelope> _runEnvelope(List<String> args, {String? stdin}) async {
    final result = await _run(args, stdin: stdin);
    _throwIfFailed(args, result);
    return BdEnvelope.parse(result.stdout);
  }

  void _throwIfFailed(List<String> args, BdResult result) {
    if (result.exitCode == 0) return;
    throw BdException.fromOutput(
      command: ['bd', ...args],
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  List<Bead> _beadsFromList(List<Map<String, dynamic>> rows) => [
    for (final row in rows) Bead.fromJson(row),
  ];

  List<BeadDependency> _depsFromList(List<Map<String, dynamic>> rows) => [
    for (final row in rows) BeadDependency.fromJson(row),
  ];

  /// Pulls a created/affected id out of a mutation envelope. bd reports the id
  /// under `id` (object envelope) or as the first row's `id` (list envelope).
  String _idFromEnvelope(BdEnvelope env) {
    final data = env.data;
    if (data is Map<String, dynamic>) {
      final id = data['id'];
      if (id is String && id.isNotEmpty) return id;
    }
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) {
        final id = first['id'];
        if (id is String && id.isNotEmpty) return id;
      }
    }
    throw BdParseException('bd create envelope carried no id', '$data');
  }

  /// Pulls the `key → id` map out of a `bd create --graph` envelope: the
  /// `data.ids` object (graph_apply.go:48-51 `GraphApplyResult.IDs`).
  Map<String, String> _idMapFromEnvelope(BdEnvelope env) {
    final data = env.data;
    if (data is Map<String, dynamic>) {
      final ids = data['ids'];
      if (ids is Map<String, dynamic>) {
        return {for (final entry in ids.entries) entry.key: '${entry.value}'};
      }
    }
    throw BdParseException(
      'bd create --graph envelope carried no ids map',
      '$data',
    );
  }

  ({List<Bead> beads, List<BeadDependency> dependencies}) _parseIssueList(
    List<dynamic> records,
  ) {
    final beads = <Bead>[];
    final edges = <String, BeadDependency>{};
    for (final record in records) {
      if (record is! Map<String, dynamic>) {
        throw BdParseException('list row was not a JSON object', '$record');
      }
      _collectIssueRecord(record, beads, edges);
    }
    return (beads: beads, dependencies: edges.values.toList(growable: false));
  }

  void _collectIssueRecord(
    Map<String, dynamic> decoded,
    List<Bead> beads,
    Map<String, BeadDependency> edges,
  ) {
    final recordType = decoded['_type'];
    if (recordType is String && recordType != 'issue') return;

    beads.add(Bead.fromJson(decoded));

    final deps = decoded['dependencies'];
    if (deps is List) {
      for (final raw in deps) {
        if (raw is Map<String, dynamic>) {
          final edge = BeadDependency.fromJson(raw);
          edges[edge.edgeKey] = edge;
        }
      }
    }
  }

  static Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}
