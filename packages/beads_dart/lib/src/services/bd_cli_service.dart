import 'dart:convert';
import 'dart:io';

import '../codecs/envelope.dart';
import '../errors/bd_exception.dart';
import '../models/bead.dart';
import '../models/bead_dependency.dart';
import '../models/bead_status.dart';
import '../models/dependency_type.dart';
import '../models/graph_apply_plan.dart';
import '../models/issue_type.dart';
import 'bd_runner.dart';

/// The bd-CLI service tier (predictable-flutter Services: stateless I/O).
///
/// Wraps a [BdRunner] and turns each `bd` subcommand into a typed Future.
/// **Futures for acts** (every method here is one-shot); observations are the
/// repository's job. Reads decode through [BdEnvelope.parse] (asserting
/// `schema_version == 1`); a non-zero exit is always raised as
/// [BdCommandFailed], which reads the error envelope off stdout first
/// (ADR-0001 Decision 4).
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

  final BdRunner _runner;

  // ---------------------------------------------------------------------------
  // READS
  // ---------------------------------------------------------------------------

  /// `bd ready --json` — the authoritative ready-work set (ADR-0001 D4: ready
  /// is never reimplemented in M1). Decodes the list envelope into [Bead]s.
  Future<List<Bead>> ready() async {
    final env = await _runEnvelope(readyArgs());
    return _beadsFromList(env.dataList);
  }

  /// `bd export --all` — the full-graph JSONL snapshot in a single spawn, and
  /// the CLI-fallback snapshot read (ADR-0001 D4). Output is **raw JSONL**
  /// (one JSON object per line, `_type == "issue"`), NOT an envelope — parsed
  /// line-by-line.
  ///
  /// **The snapshot is the COMPLETE graph: issues ∪ wisps, all statuses,
  /// including infra/template/gate-typed beads** — identical inclusion
  /// semantics to the SQL capture path (`DoltQueryService.snapshotParts`,
  /// which reads `issues` ∪ `wisps`). Filtering is the consumer's job
  /// (projections/selectors). `--all` subsumes `--include-infra` and lifts the
  /// default template + ephemeral exclusions (beads cmd/bd/export.go:96-126;
  /// ephemeral beads live in the separate `wisps` tables per
  /// internal/storage/dolt/ephemeral_routing.go and would otherwise never
  /// appear in a snapshot). `--all` also emits persistent memories, but those
  /// arrive as `_type == "memory"` config-KV records — not graph nodes — and
  /// are skipped by the JSONL parse on this path, exactly as the SQL path
  /// never reads the config table.
  ///
  /// Each issue record may carry an inline `dependencies` array (the upstream
  /// `Issue.Dependencies` field); those edges are gathered alongside the beads
  /// (bd's bulk loaders route wisp ids to `wisp_dependencies`/`wisp_labels`,
  /// so wisp edges and labels arrive inline too).
  Future<({List<Bead> beads, List<BeadDependency> dependencies})>
  exportAll() async {
    final result = await _run(exportArgs());
    _throwIfFailed(exportArgs(), result);
    return _parseExportJsonl(result.stdout);
  }

  /// `bd query "<expr>" --json` — a filtered read returning matching [Bead]s.
  Future<List<Bead>> query(String expr) async {
    final env = await _runEnvelope(queryArgs(expr));
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
  /// watcher→refresh feedback loop. Use [exportAll] (or pooled SQL) for
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

  /// `bd create --title … [--type …] [--priority …] [--description …]` —
  /// creates one bead and returns the created [Bead]'s id from the envelope.
  Future<String> create({
    required String title,
    IssueType type = IssueType.task,
    int priority = 2,
    String? description,
  }) async {
    final env = await _runEnvelope(
      createArgs(
        title: title,
        type: type,
        priority: priority,
        description: description,
      ),
    );
    return _idFromEnvelope(env);
  }

  /// `bd update` with any of `--title`, `--status`, `--priority`,
  /// `--description`, `--type`, `--assignee`, `--metadata '{…}'`.
  /// Only the provided fields are sent.
  ///
  /// **[metadata] is the convergence-transition write channel (ADR-0000
  /// A16).** It is emitted as `--metadata '<json>'` (a single JSON object),
  /// which bd **MERGES** into the bead's existing metadata — keys carried
  /// here overwrite, keys absent are preserved (beads `cmd/bd/update.go`
  /// `mergeMetadata`, spike-pinned `tool/wisp_pour_spike.sh`) — so a write
  /// sequence carries ONLY its named keys and never clobbers the agent-owned
  /// `convergence.agent_verdict*` channel. The update **succeeds on a CLOSED
  /// bead**, which the terminal `last_processed_wisp` write (written AFTER
  /// the close) requires (ADR-0000 A19). An empty [metadata] map is omitted.
  ///
  /// [type] and [assignee] are the speculative-wisp **activation** channel
  /// (`ActivateWisp`, convergence_store.go:204-246): a deferred node is
  /// promoted by restoring its real `gc.deferred_type`/`gc.deferred_assignee`
  /// via `-t`/`--assignee` (with the `gc.routed_to`/`gc.execution_routed_to`
  /// values riding [metadata]).
  ///
  /// [appendNotes] is a straight `--append-notes <text>` passthrough (bd
  /// concatenates it onto the bead's existing notes with a newline separator,
  /// `cmd/bd/update.go`); mutually exclusive with `--notes` upstream, but this
  /// service never sends `--notes`, so no conflict arises here.
  Future<void> update(
    String id, {
    String? title,
    BeadStatus? status,
    int? priority,
    String? description,
    IssueType? type,
    String? assignee,
    Map<String, String>? metadata,
    String? appendNotes,
  }) async {
    // Decode asserts the schema version (drift guard) on the mutation path too;
    // a non-zero exit was already raised inside _runEnvelope.
    await _runEnvelope(
      updateArgs(
        id,
        title: title,
        status: status,
        priority: priority,
        description: description,
        type: type,
        assignee: assignee,
        metadata: metadata,
        appendNotes: appendNotes,
      ),
    );
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

  /// `bd delete <id> --force` — the **burn** primitive (ADR-0000 A16): a
  /// subtree delete that removes the bead (and its descendants) entirely.
  ///
  /// Convergence **burns a speculative wisp by deleting it, NEVER closing**:
  /// a closed speculative wisp keeps its `converge:…:iter:N` key prefix +
  /// closed status and permanently inflates `deriveIterationCount`
  /// (ADR-0003 invariant 4; handler-9step trap 2). The actuator calls this
  /// in **post-order** over `Wisp.subtreeIds` (children before parents).
  /// `--force` skips the interactive confirmation (non-interactive spawn).
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

  List<String> readyArgs() => const ['ready', '--json'];

  List<String> exportArgs() => const ['export', '--all'];

  List<String> queryArgs(String expr) => ['query', expr, '--json'];

  List<String> depListArgs(List<String> ids) => [
    'dep',
    'list',
    ...ids,
    '--json',
  ];

  List<String> statusesArgs() => const ['statuses', '--json'];

  List<String> typesArgs() => const ['types', '--json'];

  List<String> showArgs(List<String> ids) => ['show', ...ids, '--json'];

  List<String> createArgs({
    required String title,
    required IssueType type,
    required int priority,
    String? description,
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
  ];

  List<String> updateArgs(
    String id, {
    String? title,
    BeadStatus? status,
    int? priority,
    String? description,
    IssueType? type,
    String? assignee,
    Map<String, String>? metadata,
    String? appendNotes,
  }) => [
    'update',
    id,
    '--json',
    ..._actorArgs,
    if (title != null) ...['--title', title],
    if (status != null) ...['--status', status.wire],
    if (priority != null) ...['--priority', '$priority'],
    if (description != null) ...['--description', description],
    if (type != null) ...['--type', type.wire],
    if (assignee != null) ...['--assignee', assignee],
    // `--metadata '<json>'` MERGES (named keys overwrite, absent preserved)
    // and works on a closed bead (ADR-0000 A16/A19). Empty map ⇒ omitted.
    if (metadata != null && metadata.isNotEmpty) ...[
      '--metadata',
      jsonEncode(metadata),
    ],
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

  /// `bd delete <id> --force --json` — the burn primitive (subtree delete).
  List<String> deleteArgs(String id) => [
    'delete',
    id,
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
    // [stdin] feeds `bd batch`'s line-oriented script to the child process
    // (ADR-0001 D4: one spawn, one Dolt transaction).
    return _runner.run(args, stdin: stdin);
  }

  Future<BdEnvelope> _runEnvelope(List<String> args, {String? stdin}) async {
    final result = await _run(args, stdin: stdin);
    _throwIfFailed(args, result);
    return BdEnvelope.parse(result.stdout);
  }

  void _throwIfFailed(List<String> args, BdResult result) {
    if (result.exitCode != 0) {
      throw BdCommandFailed.fromOutput(
        command: ['bd', ...args],
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    }
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

  ({List<Bead> beads, List<BeadDependency> dependencies}) _parseExportJsonl(
    String jsonl,
  ) {
    final beads = <Bead>[];
    final edges = <String, BeadDependency>{};
    for (final line in const LineSplitter().convert(jsonl)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException catch (e) {
        throw BdParseException(
          'invalid JSONL line from bd export: ${e.message}',
          trimmed,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw BdParseException('export line was not a JSON object', trimmed);
      }
      // Export interleaves record types (issue / memory / …); only issues are
      // beads. Records without `_type` are treated as issues for forward-compat.
      final recordType = decoded['_type'];
      if (recordType is String && recordType != 'issue') continue;

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
    return (beads: beads, dependencies: edges.values.toList(growable: false));
  }

  static Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}
