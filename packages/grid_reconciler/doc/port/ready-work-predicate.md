# bd ready-work predicate — port spec for the Track F SQL port

**Status:** port spec (M2 Track F, ADR-0003 D5). Source of truth: **bd 1.0.5 (f9fe4ef2a)**, pinned
on disk at `/Users/nico/development/com.gastownhall/beads`. All `file:line` references below are
relative to that repo unless prefixed. Captured 2026-06-12.

This spec is self-contained: a Dart implementer ports from this document; the Go is the tiebreaker
only when this document is ambiguous. The differential oracle is **`bd ready --json`**
(`cmd/bd/ready.go:226-249` → `GetReadyWorkWithCounts`). Read §2 first: `bd ready` and
`bd ready --json` execute **different** code paths that are *intended* to agree but are assembled
differently — the port must replicate the `--json` path.

---

## 1. Entry-point chain

| Layer | Symbol | Location |
|---|---|---|
| CLI | `readyCmd.Run` | `cmd/bd/ready.go:38-318` |
| CLI → filter | `types.WorkFilter` construction | `cmd/bd/ready.go:122-174` |
| Store (plain) | `DoltStore.GetReadyWork` | `internal/storage/dolt/queries.go:34-42` |
| Store (--json) | `DoltStore.GetReadyWorkWithCounts` | `internal/storage/dolt/queries.go:44-52` |
| Core (plain) | `issueops.GetReadyWorkInTx` | `internal/storage/issueops/ready_work.go:211-261` |
| Core (--json) | `issueops.GetReadyWorkWithCountsInTx` | `internal/storage/issueops/ready_work_counts.go:14-77` |
| Shared predicate | `issueops.buildReadyWorkPredicates` | `internal/storage/issueops/ready_work.go:60-208` |
| Filter input | `types.WorkFilter` | `internal/types/types.go:1324-1369` |

Both store methods run inside **one read transaction** (`withReadTx`), so all sub-queries
(deferred-parent scan, descendant CTE, wisp pages) see a single MVCC snapshot.
⚠ **ordering** — the Dart port must likewise evaluate every sub-query of one ready computation
against a single consistent snapshot (one Dolt transaction on the pooled connection), or
differential runs will flake under concurrent writes.

---

## 2. Two execution paths (both consume the same predicate builder)

| | `GetReadyWorkInTx` (plain `bd ready`) | `GetReadyWorkWithCountsInTx` (`bd ready --json`) |
|---|---|---|
| issues table | `SELECT id FROM issues <where> <order> <limit>` (`ready_work.go:222-227`), then hydrate by IDs preserving page order (`ready_work.go:234-247`) | full row + counts join query via `runSearchQueryInTx` with the same `whereSQL/orderBySQL/limitSQL` (`ready_work_counts.go:21-26`, `search_counts.go:98-180`) |
| wisps table | separate path: `getReadyWispsInTx` builds an `IssueFilter` via `readyWorkWispIssueFilter` + Go-side post-filtering (`ready_work.go:281-337,478-566`) | **same predicate builder** re-run with `WispsFilterTables` (`ready_work_counts.go:40-50`) |
| merge | `mergeReadyWisps`: duplicate-ID error, re-sort, truncate to limit (`ready_work.go:263-279`) | append wisp rows, duplicate-ID error, `sortIssuesWithCountsByPolicy`, truncate to limit (`ready_work_counts.go:56-75`) |

⚠ The **port target is the `--json` shape**: predicate SQL evaluated against `issues`
(tables = `issues`/`labels`/`dependencies`) and again against `wisps`
(tables = `wisps`/`wisp_labels`/`wisp_dependencies`), results concatenated, in-memory re-sort,
truncate. The plain-path wisp machinery (§8.2) is documented for completeness because the two
paths can disagree (see Porting traps #9, #10).

Wisp-side probes before the second pass (`ready_work_counts.go:15-18,30-38`):
`optionalTableExistsInTx(tx, "wisp_dependencies")` = `SELECT 1 FROM wisp_dependencies LIMIT 1`
(exists also when 0 rows; missing only on table-not-exist error — `wisp_routing.go:41-54`), and
`wispsTableEmptyOrMissingInTx` = `SELECT 1 FROM wisps LIMIT 1` (`wisp_routing.go:25-38`). If wisps
are empty/missing or `wisp_dependencies` doesn't exist, the result is the issues pass alone.

---

## 3. The WHERE clause — `buildReadyWorkPredicates`

`ready_work.go:60-208`. Clauses are ANDed in **exactly this order**; positional `?` args are
appended in the same order. Table names below are `tables.Labels` / `tables.Dependencies` from
`FilterTables` (`filters.go:15-25`): `labels`/`dependencies` for the issues pass,
`wisp_labels`/`wisp_dependencies` for the `--json` wisps pass.

| # | Condition for inclusion | Literal SQL appended | Args appended | Source |
|---|---|---|---|---|
| 1 | always | `status = ?` if `filter.Status != ""`, else `status IN ('open', 'in_progress')` | the status string (only in the `= ?` form; appended at `ready_work.go:76-78`, i.e. *first*) | `ready_work.go:61-66` |
| 2 | always | `(pinned = 0 OR pinned IS NULL)` | — | `ready_work.go:69` |
| 3 | always | `is_blocked = 0` | — | `ready_work.go:70` |
| 4 | `!filter.IncludeEphemeral` | `(ephemeral = 0 OR ephemeral IS NULL)` | — | `ready_work.go:72-74` |
| 5 | `filter.Priority != nil` | `priority = ?` | priority int | `ready_work.go:80-83` |
| 6a | `filter.Type != ""` | `issue_type = ?` | type string | `ready_work.go:84-86` |
| 6b | `filter.Type == ""` | `issue_type NOT IN (?,?,...)` | the exclusion list, §3.1 | `ready_work.go:87-95` |
| 7a | `filter.Unassigned` | `(assignee IS NULL OR assignee = '')` | — | `ready_work.go:96-97` |
| 7b | else if `filter.Assignee != nil` | `assignee = ?` | assignee string | `ready_work.go:98-101` |
| 8 | `!filter.IncludeDeferred` | `(defer_until IS NULL OR defer_until <= UTC_TIMESTAMP())` | — | `ready_work.go:104-105` |
| 9 | `!filter.IncludeDeferred` and deferred-parent children exist | one `id NOT IN (?,...)` clause **per batch of 200** child IDs | child IDs, §3.2 | `ready_work.go:107-121` |
| 10 | each `filter.Labels` entry (AND semantics) | `id IN (SELECT issue_id FROM <labels> WHERE label = ?)` — one clause per label | label | `ready_work.go:124-129` |
| 11 | `filter.ExcludeLabels` non-empty | `id NOT IN (SELECT issue_id FROM <labels> WHERE label IN (?, ...))` | labels | `ready_work.go:130-137` |
| 12 | `filter.ParentID != nil` | OR-group, §3.3 | parentID + descendant IDs | `ready_work.go:143-161` |
| 13 | `filter.MoleculeID != ""` | molecule clause, §3.4 | moleculeID ×2 | `ready_work.go:163-166` |
| 14 | `filter.HasMetadataKey != ""` | `JSON_EXTRACT(metadata, ?) IS NOT NULL` | JSON path, §3.5 | `ready_work.go:168-174` |
| 15 | each `filter.MetadataFields` entry, **keys sorted ascending** | `JSON_UNQUOTE(JSON_EXTRACT(metadata, ?)) = ?` per key | JSON path, value | `ready_work.go:176-189` |

Then `whereSQL = "WHERE " + join(clauses, " AND ")` (`ready_work.go:191`); ORDER BY args (§6) are
appended **after** all WHERE args (`ready_work.go:193-194`); `LIMIT <n>` is inlined (not a
placeholder) only when `filter.Limit > 0` (`ready_work.go:196-199`). There is **no OFFSET** —
`WorkFilter.Offset` (`types.go:1368`) is dead in the ready path.

⚠ **ordering** — clause #15 sorts metadata keys with `sort.Strings` before appending
(`ready_work.go:177-181`); replicate or arg positions drift.

⚠ `WorkFilter.LabelsAny`, `LabelPattern`, `LabelRegex`, `MolType`, `WispType`
(`types.go:1331,1333-1334,1345,1348`) are **not consumed by `buildReadyWorkPredicates` at all** —
see Porting traps #9, #10.

### 3.1 Issue-type exclusion list (ADR-0000 A14)

`readyWorkExcludeTypes` (`ready_work.go:412-434`). Base list, in order:

```
'merge-request', 'gate', 'molecule', 'message', 'agent', 'role', 'rig'
```

(`types.TypeGate` = `gate`, `types.TypeMolecule` = `molecule`, `types.TypeMessage` = `message` —
`internal/types/types.go:530-532`; the other four are inline `IssueType` strings.) Extra
`filter.ExcludeTypes` (CLI `--exclude-type`) are appended in user order, skipping empty strings and
duplicates of anything already present (`ready_work.go:422-433`).

**`molecule` is in the base exclusion** — molecules are containers; only claimable steps surface.
This is the observed behavior recorded as the_grid's ADR-0000 **A14**
(`docs/adr/ADR-0000-ai-decision-register.md:101-105`): `bd create -t molecule` never produces a
`ReadySetChanged`.

⚠ When `--type/-t` is given, the exclusion list is **dropped entirely** (clause 6a replaces 6b) —
`bd ready -t molecule` *does* return molecules. `WorkFilter.ExcludeTypes` doc:
"When Type is set, ExcludeTypes is ignored" (`types.go:1359-1362`).

### 3.2 Children of deferred parents

`getChildrenOfDeferredParentsInTx` (`ready_work.go:636-702`). Two stages:

1. **Cheap probe** — for each of `issues`, `wisps` (in that order), stop at the first hit:

```sql
SELECT 1 FROM %s
WHERE defer_until IS NOT NULL
  AND defer_until > UTC_TIMESTAMP()
LIMIT 1
```

(`ready_work.go:641-646`; `sql.ErrNoRows` → continue; `wisps` table-not-exist → continue.) If no
future-deferred row exists anywhere, return no children — clause #9 is skipped.

2. **Child collection** — for every `depTable` ∈ {`dependencies`, `wisp_dependencies`} ×
`issueTable` ∈ {`issues`, `wisps`} (that nesting order), with `targetCol` =
`depends_on_issue_id` when `issueTable` = `issues`, `depends_on_wisp_id` when `wisps`:

```sql
SELECT dep.issue_id
FROM %s dep
JOIN %s parent ON parent.id = dep.%s
WHERE dep.type = 'parent-child'
  AND parent.defer_until IS NOT NULL
  AND parent.defer_until > UTC_TIMESTAMP()
```

(`ready_work.go:670-677`; `wisp_dependencies` not existing breaks out of that depTable, a missing
`wisps` table skips that combination.)

⚠ **One hop only.** Deferral of a parent excludes its *direct* children; grandchildren stay ready
unless their own parent is deferred. Do not "fix" this with a recursive query.

⚠ The collected IDs go into `id NOT IN (...)` clauses batched at `queryBatchSize = 200`
(`batching.go:5`; loop at `ready_work.go:112-121`) — multiple NOT IN clauses ANDed, not one giant
clause. Semantically equivalent either way, but arg counts must match if you replicate SQL text
for diffing.

### 3.3 `--parent` clause (recursive descendants, GH#3396)

`ready_work.go:143-161`. First compute all transitive descendants via `GetDescendantIDsInTx`
(`blocked.go:162-237`), `maxDepth = 0` (unbounded). The CTE (verbatim; `%s` = the edge UNION
below):

```sql
WITH RECURSIVE
parent_edges(issue_id, depends_on_id) AS (
    %s
),
descendants(id, depth, path) AS (
    SELECT issue_id, 1, CONCAT(',', ?, ',', issue_id, ',')
    FROM parent_edges
    WHERE depends_on_id = ?
    UNION ALL
    SELECT e.issue_id, d.depth + 1, CONCAT(d.path, e.issue_id, ',')
    FROM parent_edges e
    JOIN descendants d ON e.depends_on_id = d.id
    WHERE (? <= 0 OR d.depth < ?)
      AND LOCATE(CONCAT(',', e.issue_id, ','), d.path) = 0
)
SELECT id, depth FROM descendants WHERE id <> ?
```

with `parent_edges` =

```sql
SELECT issue_id, COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) FROM dependencies WHERE type = 'parent-child'
UNION ALL
SELECT issue_id, COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) FROM wisp_dependencies WHERE type = 'parent-child'
```

(`blocked.go:168-196`; args = rootID, rootID, maxDepth, maxDepth, rootID; falls back to the
issues-only edge query if `wisp_dependencies` doesn't exist, `blocked.go:223-232`). The
`COALESCE(...)` is the shared constant `DepTargetExpr` (`dependencies.go:37`). Cycle defense is the
`LOCATE` path check; depth cap only when `maxDepth > 0`.

The predicate clause is an OR-group (`ready_work.go:149-160`):

```sql
( (id LIKE CONCAT(?, '.%') AND id NOT IN (SELECT issue_id FROM <deps> WHERE type = 'parent-child'))
  OR id IN (?,...) [OR id IN (?,...) ...] )
```

— the `LIKE` leg (arg = parentID) catches **dotted-ID children that have no parent-child edge yet**
(e.g. `root.1` newly created); descendant IDs are batched at 200 per `IN`. An issue with a dotted
ID *and* an explicit parent-child edge must qualify through the edge, not the prefix.

### 3.4 `MoleculeID` clause

`ready_work.go:163-166` (set by gc-style callers; **not** reachable from `bd ready` flags — the
CLI's `--mol` takes a different code path entirely, §7):

```sql
(id IN (SELECT issue_id FROM <deps> WHERE type = 'parent-child' AND COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) = ?)
 OR (id LIKE CONCAT(?, '.%') AND id NOT IN (SELECT issue_id FROM <deps> WHERE type = 'parent-child')))
```

Args: moleculeID, moleculeID. Direct children only (one hop), unlike `--parent`.

### 3.5 Metadata filters

Key validation: `^[a-zA-Z_][a-zA-Z0-9_.]*$` (`internal/storage/metadata.go:208-220`,
`validMetadataKeyRe`). JSON path construction (`metadata.go:226-231`): keys containing `.` are
quoted — `gc.routed_to` → `$."gc.routed_to"` — otherwise `$.` + key. The path is passed as a bind
**argument**, not inlined.

- existence: `JSON_EXTRACT(metadata, ?) IS NOT NULL`
- equality: `JSON_UNQUOTE(JSON_EXTRACT(metadata, ?)) = ?` — string equality after unquote; AND
  across keys; top-level keys only.

---

## 4. Blocking-dependency logic — the `is_blocked` column

**The predicate does not walk the dependency graph at read time.** Readiness w.r.t.
{`blocks`, `conditional-blocks`, `waits-for`, inherited parent-child blockage} is one column test:
`is_blocked = 0` (clause #3). `is_blocked` is a **denormalized column maintained by bd's write
paths** in the same transaction as each mutation (callers of `RecomputeIsBlockedInTx` /
`MarkIsBlockedInTx`: `create.go`, `update.go`, `close.go`, `delete.go`, `dependencies.go`,
`bulk_ops.go`, `promote.go`, `blocked_merge.go`). Schema: `issues.is_blocked TINYINT(1) NOT NULL
DEFAULT 0` + index `idx_issues_is_blocked (is_blocked, status)` (migration
`0046_add_is_blocked.up.sql`); `wisps.is_blocked` identically (`ignored/0006_add_wisp_is_blocked.up.sql`).

⚠ **The Dart port must treat `is_blocked` as authoritative input and must never recompute or
write it** — bd owns it; the_grid is a reader (CLAUDE.md coexistence rules). The semantics below
are documented so the differential harness can *construct* scenarios and so divergence reports can
*explain* a mismatch.

### 4.1 What makes `is_blocked = 1` (mark template, issues)

`markBlockedTemplateForIssues` (`blocked_state.go:123-165`), verbatim (`%%s` = ID batch
placeholders; the final `%s` = `waitsForGateBlockedSQL`, §4.2):

```sql
UPDATE issues i SET i.is_blocked = 1
WHERE i.id IN (%s)
  AND i.is_blocked = 0
  AND i.status <> 'closed' AND i.status <> 'pinned'
  AND (
    EXISTS (
      SELECT 1 FROM dependencies d
      JOIN issues t ON t.id = d.depends_on_issue_id
      WHERE d.issue_id = i.id
        AND (d.type = 'blocks' OR d.type = 'conditional-blocks')
        AND t.status <> 'closed' AND t.status <> 'pinned'
    )
    OR EXISTS (
      SELECT 1 FROM dependencies d
      JOIN wisps t ON t.id = d.depends_on_wisp_id
      WHERE d.issue_id = i.id
        AND (d.type = 'blocks' OR d.type = 'conditional-blocks')
        AND t.status <> 'closed' AND t.status <> 'pinned'
    )
    OR EXISTS (
      SELECT 1 FROM dependencies d
      JOIN issues p ON p.id = d.depends_on_issue_id
      WHERE d.issue_id = i.id
        AND d.type = 'parent-child'
        AND p.is_blocked = 1
    )
    OR EXISTS (
      SELECT 1 FROM dependencies d
      JOIN wisps p ON p.id = d.depends_on_wisp_id
      WHERE d.issue_id = i.id
        AND d.type = 'parent-child'
        AND p.is_blocked = 1
    )
    OR EXISTS (
      SELECT 1 FROM dependencies d
      WHERE d.issue_id = i.id AND d.type = 'waits-for'
        AND (%s)
    )
  )
```

In words, an open/in-progress bead is blocked iff any of:

1. **`blocks` or `conditional-blocks` edge** whose target (issue *or* wisp, resolved through
   `depends_on_issue_id` / `depends_on_wisp_id` separately) has `status` not in
   {`closed`, `pinned`}. ⚠ `depends_on_external` targets **never block** — no EXISTS leg covers
   them.
2. **Inherited blockage**: a `parent-child` edge to a parent with `is_blocked = 1`
   (transitive via the fixed-point loop, §4.4).
3. **`waits-for` fan-out gate** unsatisfied (§4.2).

The unmark template (`unmarkBlockedTemplateForIssues`, `blocked_state.go:167-211`) is the exact
negation: set `is_blocked = 0` where currently 1 and (`status` ∈ {`closed`,`pinned`} OR none of
the five EXISTS hold). Wisp-row variants are symmetric with `wisps w` / `wisp_dependencies d`
(`blocked_state.go:229-317`).

The dependency-type relevance set matches `types.DependencyType.AffectsReadyWork()`
(`types.go:845-848`): `blocks`, `parent-child`, `conditional-blocks`, `waits-for`
(`types.go:781-784`). All other edge types (`related`, `discovered-from`, `tracks`, …) are inert
here.

### 4.2 `waits-for` gate semantics

`waitsForGateBlockedSQL` (`blocked_state.go:11-47`), verbatim — evaluated per `waits-for` edge `d`:

```sql
(
  EXISTS (
    SELECT 1 FROM dependencies cd JOIN issues child ON child.id = cd.issue_id
    WHERE cd.type = 'parent-child'
      AND ((d.depends_on_issue_id IS NOT NULL AND cd.depends_on_issue_id = d.depends_on_issue_id)
        OR (d.depends_on_wisp_id IS NOT NULL AND cd.depends_on_wisp_id = d.depends_on_wisp_id))
      AND child.status <> 'closed' AND child.status <> 'pinned'
  )
  OR EXISTS (
    SELECT 1 FROM wisp_dependencies cd JOIN wisps child ON child.id = cd.issue_id
    WHERE cd.type = 'parent-child'
      AND ((d.depends_on_issue_id IS NOT NULL AND cd.depends_on_issue_id = d.depends_on_issue_id)
        OR (d.depends_on_wisp_id IS NOT NULL AND cd.depends_on_wisp_id = d.depends_on_wisp_id))
      AND child.status <> 'closed' AND child.status <> 'pinned'
  )
)
AND NOT (
  JSON_UNQUOTE(JSON_EXTRACT(d.metadata, '$.gate')) = 'any-children'
  AND (
    EXISTS (
      SELECT 1 FROM dependencies cd JOIN issues child ON child.id = cd.issue_id
      WHERE cd.type = 'parent-child'
        AND ((d.depends_on_issue_id IS NOT NULL AND cd.depends_on_issue_id = d.depends_on_issue_id)
          OR (d.depends_on_wisp_id IS NOT NULL AND cd.depends_on_wisp_id = d.depends_on_wisp_id))
        AND child.status = 'closed'
    )
    OR EXISTS (
      SELECT 1 FROM wisp_dependencies cd JOIN wisps child ON child.id = cd.issue_id
      WHERE cd.type = 'parent-child'
        AND ((d.depends_on_issue_id IS NOT NULL AND cd.depends_on_issue_id = d.depends_on_issue_id)
          OR (d.depends_on_wisp_id IS NOT NULL AND cd.depends_on_wisp_id = d.depends_on_wisp_id))
        AND child.status = 'closed'
    )
  )
)
```

Semantics: the gate target ("spawner") is `d.depends_on_*`; its **children via `parent-child`
edges** are the gate population. Default gate = `all-children`: blocked while **any** child is not
closed/pinned. If `metadata.gate == 'any-children'` (`WaitsForMeta`, `types.go:858-866`; constants
`'all-children'` / `'any-children'`, `types.go:868-869`; permissive parse defaults to all-children,
`ParseWaitsForGateMetadata` `types.go:876-893`): unblocked as soon as **one** child has
`status = 'closed'` (⚠ `pinned` children count as "not blocking" but do **not** satisfy
any-children — the release leg checks `= 'closed'` exactly). A `waits-for` whose spawner has **zero
children does not block** (the first EXISTS pair fails) — note the asymmetry with `blocks`.

### 4.3 `conditional-blocks` and the failure keywords — read this twice

Two layers exist in bd 1.0.5 and **only one is live**:

1. **Live (what the port implements):** in every SQL template above, `conditional-blocks` is
   matched in the same `(d.type = 'blocks' OR d.type = 'conditional-blocks')` disjunction —
   i.e. at the readiness level it behaves **identically to `blocks`**: the dependent is blocked
   while the target is not closed/pinned, and unblocks on **any** close, success or failure.
   No SQL anywhere inspects the close reason.

2. **Defined-but-dormant (carry as data, do not wire into the predicate):** the failure-close
   vocabulary, `types.FailureCloseKeywords` (`internal/types/types.go:907-921`), verbatim:

   ```go
   var FailureCloseKeywords = []string{
       "failed",
       "rejected",
       "wontfix",
       "won't fix",
       "canceled",
       "cancelled",
       "abandoned",
       "blocked",
       "error",
       "timeout",
       "aborted",
   }
   ```

   and `types.IsFailureClose(closeReason string)` (`types.go:923-937`): **case-insensitive
   substring** match (`strings.Contains(strings.ToLower(closeReason), keyword)`) against the
   **close reason** — the `issues.close_reason` column (`0001_create_issues.up.sql`,
   `TEXT DEFAULT ''`; written by `bd close` via `close.go:47` and `update.go:56`), surfaced as
   `Issue.CloseReason` / JSON `close_reason`. Empty reason → not a failure. Design intent
   (docs/DEPENDENCIES.md:41): "`conditional-blocks` | B runs only if A fails".

   **In bd 1.0.5 `IsFailureClose` has zero call sites outside its own unit test** (verified by
   grep across `cmd/` and `internal/`; gascity's `internal/convergence` doesn't reference it
   either). There is no auto-close/skip cascade for conditional dependents on a successful close.

⚠ Consequence for Track F: the Dart predicate must treat `conditional-blocks` exactly as `blocks`.
Port the keyword list + matcher into the reconciler's shared vocabulary (gc-side conditional
semantics may consume it in later tracks), but if the SQL port branches on `close_reason` it
**will** diverge from the `bd ready` oracle.

### 4.4 Recompute discipline (context for scenario construction)

`RecomputeIsBlockedInTx` (`blocked_state.go:49-72`): loop `{mark pass over issue IDs; mark+unmark
pass over wisp IDs}` until a full iteration changes 0 rows. Per pass
(`runMarkUnmarkBatchedInTx`, `blocked_state.go:320-344`): IDs batched at 200; **mark executes
before unmark** within each batch. The fixed point is what propagates parent-blockage chains
(`parent-child` legs reference `p.is_blocked`, which earlier passes may have just changed).
Affected-ID sets for a mutation are computed by `AffectedByStatusChangeInTx` /
`AffectedByDepChangeInTx` / `AffectedByDeletionInTx` (`blocked_state.go:366-550`): blocking
dependers of the changed bead + waiters whose gate spawner is a parent of it + all transitive
`parent-child` descendants. One-time backfills: migration `0046` (issues-only,
⚠ historical: treated `waits-for` like a plain blocker) and `0047_recompute_mixed_is_blocked.up.sql`
(mixed issues+wisps recursive CTE matching the runtime templates, incl. the any-children carve-out);
wisps via `ignored/0007_recompute_wisp_is_blocked.up.sql`.

---

## 5. `defer_until`, ephemeral, pinned, status — value domains

| Column | Domain | Ready semantics | Source |
|---|---|---|---|
| `status` | `'open'`, `'in_progress'`, `'blocked'`, `'deferred'`, `'closed'`, `'pinned'`, `'hooked'` (`types.go:326-333`) + free-form custom statuses (migration `0024`) | CLI `bd ready` pins `Status: "open"` (`cmd/bd/ready.go:123`) → `status = 'open'`. API default (empty `WorkFilter.Status`) → `status IN ('open', 'in_progress')`. The statuses `'blocked'`, `'deferred'`, `'hooked'` are excluded purely by not being in that set | `ready_work.go:61-66` |
| `pinned` (column) | `TINYINT(1)`, nullable in practice | excluded unless `0`/NULL. ⚠ distinct from the `'pinned'` **status**: the status releases *blockers* (§4.1 checks `t.status <> 'pinned'`); the column hides the bead itself from ready | `ready_work.go:69` |
| `ephemeral` | `TINYINT(1)` | excluded unless `0`/NULL, unless `--include-ephemeral`. Beads in the `wisps` *table* with `ephemeral = 0` ("no-history" durable wisps) **are** ready-eligible by default (`types.go:1353-1357`) | `ready_work.go:72-74` |
| `defer_until` | `DATETIME`, NULL = not deferred | ready iff `NULL` or `<= UTC_TIMESTAMP()` (boundary instant = ready). Plus the one-hop deferred-parent child exclusion (§3.2). `--include-deferred` removes both | `ready_work.go:104-105` |
| `is_blocked` | `TINYINT(1) NOT NULL` | must be `0` (§4) | `ready_work.go:70` |
| `issue_type` | free-form; well-known set in `types.go:524-535` | §3.1 | `ready_work.go:84-95` |

⚠ All time comparisons in SQL use **`UTC_TIMESTAMP()`** (server-side UTC), and the Go-side wisp
filter uses `time.Now().UTC()` (`ready_work.go:516-526`). The Dart port must compare in UTC; using
`NOW()` on a non-UTC session or local `DateTime.now()` is a divergence source.

---

## 6. Sort policies — exact ORDER BY per mode

`buildReadyWorkOrder` (`ready_work.go:40-58`), policy = `types.SortPolicy`
(`types.go:1295-1318`; valid: `hybrid`, `priority`, `oldest`, `""`):

| Policy | Literal ORDER BY | Args |
|---|---|---|
| `oldest` | `ORDER BY created_at ASC, id ASC` | — |
| `priority` | `ORDER BY priority ASC, created_at DESC, id ASC` | — |
| `hybrid` or `""` | `ORDER BY`<br>`CASE WHEN created_at >= ? THEN 0 ELSE 1 END ASC,`<br>`CASE WHEN created_at >= ? THEN priority ELSE 999 END ASC,`<br>`created_at ASC, id ASC` | `recentCutoff` twice |
| anything else | `ORDER BY priority ASC, created_at DESC, id ASC` (silent priority fallback) | — |

`recentCutoff = time.Now().UTC().Add(-48 * time.Hour)` computed **once per query, Go-side**, and
bound as two identical parameters (`ready_work.go:47-53`). Lower `priority` int = more urgent
(P0 first).

⚠ **Defaults disagree by layer**: storage maps `""` → hybrid, but the **CLI flag default is
`--sort priority`** (`cmd/bd/ready.go:737`) — so plain `bd ready` is priority-sorted, and a
differential harness driving the storage API with an empty policy gets hybrid. Always pass the
policy explicitly. Invalid values are rejected by the CLI (`ready.go:176-179`,
`SortPolicy.IsValid` `types.go:1315-1318`) but silently fall back inside storage.

### 6.1 In-memory re-sort after the wisp merge

After merging wisp rows, both paths re-sort the combined slice with `sortReadyIssues`
(`ready_work.go:568-591`; counts variant `sortIssuesWithCountsByPolicy`,
`ready_work_counts.go:77-103`) using `sort.SliceStable`:

- `oldest`: `CreatedAt` ascending; tie → `ID` ascending (`issueCreatedBefore`,
  `ready_work.go:603-608`).
- `priority` (and unknown): `Priority` ascending; tie → `CreatedAt` **descending**; tie → `ID`
  ascending (`issuePriorityBefore`, `ready_work.go:593-601`).
- `hybrid`/`""`: recent (`CreatedAt >= now-48h`, **fresh cutoff recomputed here**,
  `ready_work.go:569`) before non-recent; within recent, `Priority` ascending then
  `issueCreatedBefore`; within non-recent, `issueCreatedBefore` only.

⚠ The SQL ORDER BY and the in-memory comparator implement the same policy; the merged result's
final order comes from the **in-memory comparator** whenever any wisp was merged, and from SQL
order otherwise. Truncation to `filter.Limit` happens **after** the re-sort
(`ready_work.go:275-277`, `ready_work_counts.go:72-75`). Equal-timestamp DATETIME ties (1s
granularity) are broken by `id` lexicographically — keep that in the Dart port or differential
runs will flap on same-second creates.

---

## 7. CLI parameters that alter the predicate

`bd ready` flag inventory (`cmd/bd/ready.go:732-755`) → `WorkFilter` (`ready.go:122-174`):

| Flag (default) | WorkFilter effect | Predicate effect |
|---|---|---|
| — (always) | `Status: "open"` (`ready.go:123`) | `status = 'open'` — `bd ready` **never** shows in_progress; API callers with empty status get `IN ('open','in_progress')` |
| `--limit/-n` (**100**) | `Limit` | `LIMIT n`; `0` = unlimited. ⚠ default truncates at 100 — run the oracle with `--limit 0` |
| `--priority/-p` | `Priority` (only if flag *changed* — `cmd.Flags().Changed`, `ready.go:136-139`, so `-p 0` works) | clause 5 |
| `--assignee/-a` | `Assignee` (ignored if `--unassigned`) | clause 7b |
| `--unassigned/-u` | `Unassigned: true` | clause 7a |
| `--sort/-s` (**`priority`**) | `SortPolicy` | §6 |
| `--label/-l` (repeat/CSV) | `Labels` (AND), via `utils.NormalizeLabels` — trim/dedupe/drop-empty (`utils/strings.go:27-43`) | clause 10 |
| `--label-any` | `LabelsAny` | ⚠ **no effect on the `--json` oracle** (trap #9) |
| `--exclude-label` | `ExcludeLabels` | clause 11 |
| `--type/-t` | `Type`, alias-expanded by `utils.NormalizeIssueType` (`utils/strings.go:18-23`: `mr`→`merge-request`, `feat`→`feature`, `mol`→`molecule`, `enhancement`→`feature`, `dec`/`adr`→`decision`) | clause 6a, drops exclusion list |
| `--exclude-type` (repeat/CSV, split+trim `ready.go:113-121`) | `ExcludeTypes` | appended to base list §3.1 |
| `--parent` | `ParentID` | §3.3 |
| `--mol-type` (`swarm`\|`patrol`\|`work`) | `MolType` | ⚠ **no effect on the `--json` oracle** (trap #10) |
| `--include-deferred` | `IncludeDeferred: true` | removes clauses 8 + 9 |
| `--include-ephemeral` | `IncludeEphemeral: true` | removes clause 4 |
| `--metadata-field k=v` (repeat) | `MetadataFields` | clause 15 |
| `--has-metadata-key k` | `HasMetadataKey` | clause 14 |
| *(no labels given)* | directory-scoped labels auto-fill `LabelsAny` (GH#541, `ready.go:106-110`, `config.GetDirectoryLabels`) | ⚠ same trap #9 — and it makes oracle output cwd-dependent; run the harness from the workspace root or pass an explicit `--label` |

Flags that **bypass** the predicate entirely (different code paths; out of Track F scope):
`--mol` (in-memory molecule subgraph analysis, `ready.go:52-59,608-713`), `--gated` (gate-resume
discovery, `mol_ready_gated.go`), `--explain` (`ready.go:61-69,477-605`).

`--claim` (`ready.go:198-224` → `ClaimReadyIssueInTx`, `issueops/claim.go:114-144`) runs the same
`GetReadyWorkInTx` with forced overrides `Status='open'`, `Unassigned=true`, `Assignee=nil`,
`Limit=0` (`claim.go:119-123`), then CAS-claims the first issue:
`UPDATE ... SET assignee = ?, status = 'in_progress' ... WHERE id = ? AND status = 'open' AND
(assignee = '' OR assignee IS NULL OR assignee = ?)` (`claim.go:50-61`) — skipping
already-claimed/not-claimable and moving on. Write path; the grid's read-only port never executes
it, but the forced-filter overrides matter when diffing `--claim --json` traces.

JSON truncation telemetry: when `len(results) == limit`, the CLI re-runs the whole query with
`Limit: 0` just to print a stderr count (`ready.go:230-241`) — stdout JSON stays truncated.

---

## 8. Wisps — the second population

"Wisps" are rows in the parallel `wisps` table (ephemeral and/or no-history beads;
`0020_create_wisps.up.sql` mirrors the issues schema). Their readiness inputs are the same columns;
their edges live in `wisp_dependencies` / labels in `wisp_labels` (`0021_create_wisp_auxiliary.up.sql`).

### 8.1 `--json` path (the port target)

`buildReadyWorkPredicates(filter, WispsFilterTables)` → identical WHERE text with
`wisp_labels`/`wisp_dependencies` substituted, run against `wisps`
(`ready_work_counts.go:40-50`). Note clause #9's deferred-children list is recomputed by the
shared helper which already scans both table families (§3.2), so the same NOT-IN IDs appear in
both passes.

### 8.2 Plain path (documented for divergence analysis only)

`getReadyWispsInTx` (`ready_work.go:281-337`): probe `wisps` (§2); translate the WorkFilter via
`readyWorkWispIssueFilter` (`ready_work.go:436-476`) into a `types.IssueFilter`:

| WorkFilter | IssueFilter | Resulting SQL (from `BuildIssueFilterClauses`, `filters.go:31-300`) |
|---|---|---|
| `Status != ""` | `Status` | `status = ?` (`filters.go:70-72`) |
| `Status == ""` | `Statuses = [open, in_progress]` | `status IN (?,?)` (`filters.go:73-80`) |
| `Type != ""` | `IssueType` | `issue_type = ?` (`filters.go:91-93`) |
| `Type == ""` | `ExcludeTypes` = §3.1 list | `issue_type NOT IN (?,...)` (`filters.go:94-101`) |
| `Unassigned` | `NoAssignee: true` | `(assignee IS NULL OR assignee = '')` (`filters.go:209-211`) |
| `Assignee` | `Assignee` | `assignee = ?` (`filters.go:103-106`) |
| `Priority` | `Priority` | `priority = ?` (`filters.go:108-111`) |
| `Labels` | `Labels` | label-driven JOINs (below) |
| `LabelsAny` | `LabelsAny` | JOIN + `label IN (...)` — **honored here**, unlike the issues pass |
| `ExcludeLabels` | `ExcludeLabels` | `id NOT IN (SELECT issue_id FROM wisp_labels WHERE label IN (...))` (`filters.go:169-176`) |
| `MolType` / `WispType` | `MolType` / `WispType` | `mol_type = ?` / `wisp_type = ?` (`filters.go:146-153`) — honored only here |
| `MoleculeID` | `ParentID` | parent clause (`filters.go:137-141`) |
| `!IncludeEphemeral` | `Ephemeral: &false` | `(ephemeral = 0 OR ephemeral IS NULL)` (`filters.go:191-197`) |
| always | `Pinned: &false` | `(pinned = 0 OR pinned IS NULL)` (`filters.go:178-184`) |
| `MetadataFields`/`HasMetadataKey` | same | same JSON clauses (`filters.go:272-300`) |

When `Limit > 0` the page query (`queryReadyWispIssueIDPage`, `ready_work.go:339-385`) is

```
SELECT [DISTINCT] id FROM <from> <where> <orderBy> LIMIT <pageSize> OFFSET <offset>
```

with `<from>` from `buildLabelDrivenSearch` (`search.go:272-306`): no labels → `wisps`; otherwise
`wisps JOIN wisp_labels label_filter_N ON label_filter_N.issue_id = wisps.id` per AND-label (+
`label_filter_any` for LabelsAny) and `SELECT DISTINCT`. `excludeDeferred` appends the same
`(defer_until IS NULL OR defer_until <= UTC_TIMESTAMP())` (`ready_work.go:349-351`). Page size:
`max(limit, 100)` (`readyWorkPageSize`, `ready_work.go:29-38`); pages advance by `pageSize` until
`filter.Limit` ready wisps are collected or a short page ends the scan. ⚠ `is_blocked` is **not**
in this WHERE — blocked wisps are dropped Go-side per page, so OFFSET indexes the *unfiltered*
ordering (correct, but easy to get wrong if you "optimize" the filter into SQL while mirroring
this path).

Go-side post-filter `filterReadyWispsInTx` (`ready_work.go:478-566`), exclusion in this order:
(a) `--parent`: keep descendants (recomputed `GetDescendantIDsInTx`) plus *parentless* dotted-ID
prefix matches — parentedness probed via `SELECT issue_id FROM <depTable> WHERE type =
'parent-child' AND issue_id IN (...)` over both dep tables (`getParentedIDSetInTx`,
`ready_work.go:705-743`); (b) deferral: drop `DeferUntil > now` and the §3.2 child IDs; (c)
blocked: `SELECT id FROM wisps WHERE id IN (%s) AND is_blocked = 1` batched at 200
(`ready_work.go:535-537`); (d) `wisp.Pinned` (Go field) dropped last (`ready_work.go:557`).

Merge: any ID present in both populations is a **hard error**
(`"ready work id %q exists in both issues and wisps"`, `ready_work.go:270`,
`ready_work_counts.go:66-68`).

---

## 9. Table/column inventory (cross-checked against `internal/storage/schema/migrations/`)

Everything the predicate (both passes) touches:

| Table.column | Declared | Notes |
|---|---|---|
| `issues.id` | `VARCHAR(255) PRIMARY KEY` (`0001`) | dotted IDs encode implicit hierarchy (`root.1`) |
| `issues.status` | `VARCHAR(32) NOT NULL DEFAULT 'open'` (`0001`) | §5 |
| `issues.priority` | `INT NOT NULL DEFAULT 2` (`0001`) | ascending = more urgent |
| `issues.issue_type` | `VARCHAR(32) NOT NULL DEFAULT 'task'` (`0001`) | §3.1 |
| `issues.assignee` | `VARCHAR(255)` NULL (`0001`) | NULL and `''` both mean unassigned |
| `issues.created_at` | `DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP` (`0001`) | 1s granularity → §6.1 tiebreak |
| `issues.pinned` | `TINYINT(1) DEFAULT 0` (`0001`) | column, not status |
| `issues.ephemeral` | `TINYINT(1) DEFAULT 0` (`0001`) | |
| `issues.defer_until` | `DATETIME` NULL (`0001`) | |
| `issues.metadata` | `JSON DEFAULT (JSON_OBJECT())` (`0001`) | clauses 14/15 |
| `issues.close_reason` | `TEXT DEFAULT ''` (`0001`) | failure-keyword field (§4.3) — **not** read by the predicate |
| `issues.is_blocked` | `TINYINT(1) NOT NULL DEFAULT 0` + `idx_issues_is_blocked(is_blocked, status)` (`0046_add_is_blocked.up.sql`) | §4 |
| `dependencies.issue_id` | `VARCHAR(255) NOT NULL` (`0002`) | the dependent ("from") |
| `dependencies.depends_on_issue_id` / `depends_on_wisp_id` / `depends_on_external` | `VARCHAR(255) NULL` each, `ck_dep_one_target` CHECK exactly-one (`0041_split_dependencies_target.up.sql`) | the legacy `depends_on_id` stored-generated column was **dropped** in `0043_drop_dependencies_generated_column.up.sql` (surrogate `id CHAR(36)` PK + unique keys per target column; deterministic ids in `0050`); runtime always reads the target via `DepTargetExpr` = `COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)` (`dependencies.go:37`) |
| `dependencies.type` | `VARCHAR(32) NOT NULL DEFAULT 'blocks'` (`0002`) | values used here: `'blocks'`, `'conditional-blocks'`, `'waits-for'`, `'parent-child'` |
| `dependencies.metadata` | `JSON DEFAULT (JSON_OBJECT())` (`0002`) | `$.gate` for waits-for (§4.2) |
| `labels.issue_id`, `labels.label` | `VARCHAR(255)` ×2, PK(issue_id,label), `idx_labels_label` (`0003`) | clauses 10/11 |
| `wisps.*` | mirror of `issues` (`0020_create_wisps.up.sql`) | `wisps.is_blocked` via `ignored/0006_add_wisp_is_blocked.up.sql` (+ `idx_wisps_is_blocked(is_blocked, status)`) |
| `wisp_dependencies.*` | split-target from birth (`0021`; backfill for older DBs in `ignored/0003`/`0005` and the prelude of `0047`) | same columns as `dependencies` |
| `wisp_labels.issue_id/label` | (`0021`) | |
| `custom_statuses.name/category` | (`0024_create_custom_status_type_tables.up.sql`) | used by the **view** only, not the predicate |

**The `ready_issues` SQL view is NOT the predicate.** Migrations `0017` → `0025` → `0044` maintain
a `ready_issues` view, but it diverges from `bd ready` in at least five ways: it only considers
`type = 'blocks'` (no `conditional-blocks`, no `waits-for`), it propagates blockage *down*
parent-child transitively via its own CTE rather than reading `is_blocked`, it ignores the
`pinned` column, it has no type exclusions, and it admits custom `'active'` statuses. Do not port
it, do not differential-test against it.

---

## 10. Differential harness notes (ADR-0003 D5)

- Oracle invocation: `BD_JSON_ENVELOPE=1 bd ready --json --limit 0 --sort <policy>` (explicit
  policy per §6's default split; `--limit 0` to kill truncation). Output: enveloped JSON array of
  `IssueWithCounts` (`cmd/bd/ready.go:226-249`); compare on ordered ID sequence first, then on
  `status/priority/issue_type/assignee/defer_until` per row.
- The oracle path is `GetReadyWorkWithCounts` — i.e. §2's right-hand column. A port that mirrors
  the *plain* path will pass most scenarios and then diverge exactly on traps #9/#10 below.
- Scenario axes to cover (each maps to a clause above): status × {open, in_progress, blocked,
  deferred, hooked, pinned-status}; pinned column; ephemeral ± `--include-ephemeral`; each
  excluded type ± `-t` override ± `--exclude-type`; blocks / conditional-blocks (close with
  success reason *and* with each failure keyword — results must be identical) / waits-for
  (all-children, any-children, zero-children, pinned-child) / parent-child inheritance chains ≥ 3
  deep; external-target blocks edge (must NOT block); defer_until past/boundary/future;
  deferred parent → child vs grandchild; dotted-ID child with and without explicit edge;
  `--parent` over ≥ 3-level trees; labels AND/exclude; metadata key/equality incl. dotted keys;
  every sort policy incl. the 48h hybrid boundary and same-second ID tiebreaks; wisp twins of all
  of the above; limit interplay with the post-merge re-sort.

---

## Porting traps

1. **`conditional-blocks` does not check failure keywords.** The keyword machinery
   (`FailureCloseKeywords`/`IsFailureClose`, `types.go:907-937`, matched case-insensitively as
   substrings of `close_reason`) is dead code in bd 1.0.5's ready path. In SQL,
   `conditional-blocks` ≡ `blocks`. Implementing the documented "B runs only if A fails" intent
   diverges from the oracle. Port the keywords as a vocabulary constant; do not consult them in
   the predicate. (§4.3)
2. **`is_blocked` is input, not logic.** Never recompute it in the_grid, never write it — bd
   maintains it transactionally on every mutation. The mark/unmark templates (§4.1) exist in this
   spec to explain divergence, not to be executed by the port.
3. **Two pinned things.** The `pinned` *column* hides a bead from ready (clause 2); the `'pinned'`
   *status* makes a bead a non-blocker (released target in §4.1/§4.2) and is excluded from ready
   only via the status set. Conflating them flips both directions.
4. **CLI vs API status default.** `bd ready` hardcodes `status = 'open'` (`ready.go:123`); the
   storage API default is `status IN ('open', 'in_progress')` (`ready_work.go:65`). A port
   exercised through the API with an empty status will return in_progress beads the CLI never
   shows.
5. **CLI vs API sort default.** CLI default `--sort priority`; storage maps `""` → `hybrid`
   (`ready_work.go:46`). And the hybrid cutoff (`now-48h`) is computed Go-side per query and
   bound twice — recomputed *again*, slightly later, for the in-memory merge sort
   (`ready_work.go:569`). A bead created exactly ~48h ago can straddle the two cutoffs.
6. **`-t <type>` silently drops the exclusion list** — including `molecule` (A14) and
   `merge-request`. `--exclude-type` only *extends* the list and is ignored when `-t` is present
   (`ready_work.go:84-95`).
7. **Deferral is one hop.** Children of a future-deferred parent are excluded; grandchildren are
   not (§3.2). The view's recursive behavior (§9) is the wrong reference.
8. **UTC everywhere.** `UTC_TIMESTAMP()` in SQL, `time.Now().UTC()` in Go; boundary instant
   (`defer_until == now`) is *ready*. `NOW()` under a non-UTC session diverges (the legacy `0017`
   view used `NOW()`; `0025` fixed it — don't copy the old one).
9. **`--label-any` is a no-op on the oracle.** `buildReadyWorkPredicates` never reads
   `LabelsAny` (`ready_work.go:124-137`), and `bd ready --json` uses that builder for *both*
   issues and wisps. Only the plain-path wisp pass honors it (`ready_work.go:441`). Worse, the
   directory-label scoping (GH#541, `ready.go:106-110`) auto-populates `LabelsAny` — making it
   silently inert in JSON mode but live for plain-mode wisps. Replicate the no-op; flag it in the
   harness report rather than "fixing" it.
10. **`--mol-type`/`WispType` likewise only affect the plain-path wisp pass**
    (`ready_work.go:444-445`); the `--json` oracle ignores them for both populations. Same
    treatment as #9.
11. **External dependency targets never block.** Every blocking EXISTS joins through
    `depends_on_issue_id` or `depends_on_wisp_id`; a `blocks` edge whose only target is
    `depends_on_external` leaves the dependent ready (§4.1). The exactly-one-target CHECK
    (`ck_dep_one_target`, `0041`) guarantees the COALESCE/`DepTargetExpr` reading order
    issue → wisp → external is moot for blocking but load-bearing for parent/descendant queries.
12. **`waits-for` with zero spawned children does not block; a pinned child blocks all-children
    gates? No — inverse:** pinned children are treated as done for *blocking* purposes
    (`child.status <> 'closed' AND child.status <> 'pinned'`) but do **not** satisfy an
    `any-children` release (`child.status = 'closed'` exactly) (§4.2). Three distinct literals;
    transcribe each.
13. **Gate metadata parse is permissive.** Only the exact string `any-children` in
    `JSON_UNQUOTE(JSON_EXTRACT(d.metadata, '$.gate'))` activates any-children; absent/empty/
    invalid/unknown → all-children (`types.go:876-893`). In SQL, a NULL `JSON_EXTRACT` makes the
    `= 'any-children'` predicate false — same outcome; keep it that way in Dart SQL.
14. **Order-sensitive arg assembly.** All fragments use positional `?`; WHERE args in clause
    order (status first at `ready_work.go:76-78` even though appended after three later clauses
    were *declared* — declaration vs arg-append order differ!), then ORDER BY args last
    (`ready_work.go:193-194`). Metadata keys sorted; NOT-IN batches of 200 (`batching.go:5`).
    If the port builds one flat SQL string for diff-by-text, byte equality requires all of this.
15. **Duplicate IDs across `issues`/`wisps` are a hard error**, not a dedupe
    (`ready_work.go:268-271`). Surface it as an error in Dart too — silently deduping masks an
    upstream corruption the harness should catch.
16. **Limit interacts with the merge.** SQL `LIMIT` caps each pass independently; the final
    truncation happens after concat + re-sort (§6.1). With `limit = N` you can get a wisp ranked
    above an issue that the issues pass already cut — both implementations must cut identically.
    Differential runs should prefer `--limit 0`.
17. **`bd ready` excludes nothing by `status = 'blocked'` logic** — a bead whose status column
    says `open` but whose `is_blocked` flag is stale (e.g. mid-crash) is what the *predicate*
    reports; there is no re-derivation. Shadow-mode divergence between the port and a freshly
    recomputed graph is a bd consistency finding, not a port bug. Keep `bd ready` as the oracle
    (ADR-0003 D5) precisely because both sides then read the same flag.
