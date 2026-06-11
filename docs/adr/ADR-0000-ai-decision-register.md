# ADR-0000 — AI decision register

**Status:** Living document — never Accepted, never closed.
**Rule (Nico, 2026-06-11):** any decision made by AI lands here as an amendment and **stays here** until Nico promotes it (into its own ADR, or a named amendment of an existing one) or shoots it down. AI must not write its own decisions directly into ADR-0001+; those documents record human-ratified decisions only.

Entry format: `A<n> (date) — title` · Decision · Why · Affects (docs/code that change if promoted) · **Status:** pending | promoted → ⟨where⟩ | rejected.

---

## A1 (2026-06-11) — Fixture capture scheme

**Decision:** Pinned upstream fixtures live at `fixtures/upstream/<date>-bd-<version>/`, captured with `BD_JSON_ENVELOPE=1`. the_grid contributes the empty-workspace cases (`tg-list-all-empty`, `tg-ready-empty`) plus `statuses`/`types` (the 13 custom types); the city HQ contributes per-domain samples extracted from `bd export --include-infra` JSONL (not from `bd list`) and a 25-line raw export sample; one error fixture captures the failure shape.
**Why:** PDR §6.7 and ADR-0001 Decision 7 require version-pinned fixtures; the HQ export is 24MB so wholesale check-in is wrong; per-domain extraction keeps fixtures small and representative.
**Affects:** test layout in `grid_controller`; the porting skill's re-capture procedure.
**Status:** promoted → ADR-0001 Decision 7 (2026-06-11).

## A2 (2026-06-11) — M1 proving domains: sessions + messages + molecules (not agents/sessions/rigs)

**Decision:** Swap M1's proving domains for the projection mechanism to **session, message, molecule/step** — the domains that actually exist as beads in the live city. Flag `agent`/`role`/`rig`/`convoy` projections as *pending an upstream-representation investigation*.
**Why:** Fixture capture (2026-06-11, bd 1.0.5, city HQ) found **zero** agent/rig/role/convoy/gate beads: 34,588 task, 692 session, 390 chore, 1 molecule, 1 step, 1 bug. In current gc, agents/rigs/roles appear to be config/registry-derived (`city.toml`, `~/.gc/cities.toml`), not beads — the_grid's `types.custom` anticipates them, but there is nothing to pin mappings against. ADR-0002's mapping table is unaffected as a target; only the M1 proving set and its fixtures change.
**Affects (if promoted):** ADR-0002 Decision 2 consequences (proving trio); PDR §6 acceptance criterion 8 (`agentsProvider/sessionsProvider/rigsProvider` → `sessionsProvider/inboxProvider/moleculesProvider`); M1-BUILD-ORDER Track E.
**Status:** promoted → ADR-0002 Decision 2 + PDR §6.8 (2026-06-11).

## A3 (2026-06-11) — bd errors are enveloped on STDOUT

**Decision:** `BdException` parsing must treat **stdout** as the primary error channel when exit ≠ 0: observed shape is `{"data": {"error": "<message>"}, "schema_version": 1}` on stdout with **empty stderr**, exit 1 (`bd dep list <unknown-id> --json`, bd 1.0.5, envelope mode). Parse stdout first, fall back to stderr, then raw text.
**Why:** ADR-0001's error-decision assumed stderr JSON (per `cmd/bd/output.go` reading); live behavior under `BD_JSON_ENVELOPE=1` differs. Fixture: `fixtures/upstream/2026-06-11-bd-1.0.5/tg-error-stdout.json`.
**Affects (if promoted):** ADR-0001 Decision 4 wording; `BdCliService` error hierarchy.
**Status:** promoted → ADR-0001 Decision 4 (2026-06-11).

## A4 (2026-06-11) — Pre-ultracode onboarding artifacts: CLAUDE.md + M1-BUILD-ORDER

**Decision:** Two repo artifacts carry context across compaction and into subagents: `CLAUDE.md` (session contract: read-first list, the gate, process rules including this register, conventions, bd rules, environment facts, upstream pins) and `docs/M1-BUILD-ORDER.md` (dependency-ordered work breakdown with parallelizable tracks for orchestration).
**Why:** Post-compact sessions and fanned-out agents must not depend on conversation history; the PDR/ADRs hold decisions but not operating instructions or build sequencing.
**Affects:** repo root; docs/.
**Status:** promoted → ADR-0001 Decision 8 (2026-06-11).

## A5 (2026-06-11) — `bd list` does not surface infra-typed beads

**Decision (observation + handling):** treat `bd list` as unsuitable for infra domains regardless of `--all`; domain sampling and the CLI-fallback snapshot read use `bd export --include-infra` exclusively (already ADR-0001's fallback read; this closes the loophole of ever composing snapshots from `bd list`).
**Why:** `bd list --json --all --type agent/rig/role` returned empty envelopes in HQ while `--type message/session/molecule` returned data; export is the documented carrier of infra records.
**Affects (if promoted):** ADR-0001 Decision 4 amendment wording; `BdCliService.list` documentation.
**Status:** promoted → ADR-0001 Decision 4 (2026-06-11).

## A6 (2026-06-11) — M4 is scoped usage-driven, decomposed M4a–M4f with just-in-time ADRs, adopted via the fs ladder

**Decision:** M4 is scoped by the measured surface of the live city (audited 2026-06-11: 12 gc command families, 13 agent templates, 35 orders, 33 formulas, 2 active rigs — full inventory in `docs/M4-SCOPING.md`), decomposed into M4a config / M4b topology reconciler / M4c orders / M4d sling+hooks / M4e patrol / M4f cutover, each getting its ADR (0005–0010) just-in-time as predecessors land. M4 acceptance = cutover of one real rig, not feature parity. fs adoption is per-milestone: M1 observe, M2 shadow, M3 drive-one-rig (dogfood: the_grid rig), M4f replace.
**Why:** One up-front M4 ADR would speculate against a target M1–M3 (and the upstream RFC) will move; the usage inventory makes the checklist finite and testable.
**Affects (if promoted):** PDR §5 (M4 row → sub-milestones + ladder reference), `docs/M4-SCOPING.md` status.
**Status:** promoted → PDR §5 + docs/M4-SCOPING.md ratified (2026-06-11).

## A7 (2026-06-11) — Coexistence partition rule

**Decision:** While gc and the_grid both run, the_grid owns a bead/rig set **disjoint** from gc's reconciler — partitioned by rig and/or ownership marker; M2 shadow mode is strictly read-only.
**Why:** gc's convergence handler assumes a single writer per bead (ADR-0003 invariant 7); two reconcilers on one convergence bead corrupts state for both.
**Affects (if promoted):** ADR-0003 (operating-mode section), M2/M3 acceptance criteria, M4-SCOPING.
**Status:** promoted → ADR-0003 Decision 6 (2026-06-11).

## A8 (2026-06-11) — Dolt auth spike outcome: `mysql_client` is wire-compatible; credential is operator-provided env

**Decision:** Keep `mysql_client` as the SQL read-path client (ADR-0001 Decision 4, no change). The `DoltQueryService` resolves its credential from the documented env contract — `GC_DOLT_USER` (default `root`) and `GC_DOLT_PASSWORD` — and connects with `secure: false` (the gc-managed server offers no SSL). Live-SQL integration tests **self-skip** when `GC_DOLT_PASSWORD` is absent (the lenny e2e pattern); the bd-CLI read path is the guaranteed fallback, so M1 acceptance never depends on the SQL credential being present in CI.
**Why:** Track 0.2 spike (2026-06-11, `mysql_client 0.0.27` → `127.0.0.1:34947` db `tg`): the client completed Dolt's MySQL handshake through to credential evaluation, and the server returned an application-level **`1045 Access Denied`** ERR packet — proving wire/auth-plugin compatibility. (Contrast: requesting `secure: true` threw a distinct *client* exception, "Server does not support SSL." Two different exception classes confirm the server processed our handshake and answered at the application layer rather than failing the protocol.) The only gap is the credential itself, which is gc-provisioned and surfaced through the same `GC_DOLT_PASSWORD` channel `bd` uses — an operational wiring step, not a Dart-client limitation. Process-env credential extraction was deliberately not attempted (and was blocked by the sandbox classifier as credential exploration); the spike's protocol question is answered without it. PDR Risk #1 ("Dart MySQL client can't complete Dolt's auth handshake") is **retired** at the protocol level.
**Affects (if promoted):** ADR-0001 Decision 4 (credential-resolution sentence + SSL/`secure:false` note); `DoltQueryService` connection config; the live-SQL integration test's skip guard; PDR §8 risk table (Risk #1 → resolved). Spike artifact: `packages/grid_controller/tool/dolt_spike.dart`.
**Status:** pending.

## A9 (2026-06-11) — `BeadStatus` is an extension type over String, not a 7-value enum

**Decision:** Model `BeadStatus` (and uniformly `IssueType`, `DependencyType`) as a zero-cost extension type over the wire string with named constants for the built-ins, rather than a strict closed Dart enum. `category`/`isClosed`/`isBuiltIn` cover the seven built-ins; unknown values decode without throwing (`category → StatusCategory.unspecified`).
**Why:** the PDR plan and ADR-0001 Decision 1 framed status as an "enum, closed set of 7", but upstream beads supports **custom statuses** (`Status.IsValidWithCustom`, `internal/types/types.go`), so a strict enum would throw on a custom value during snapshot decode — a latent crash. Extension-type-over-String matches beads reality, keeps value equality/`hashCode` correct for free (a `BeadStatus` *is* its String at runtime), and is uniform with the already-open `IssueType`/`DependencyType`. The canonical seven remain enumerated as constants.
**Affects (if promoted):** ADR-0001 Decision 1 wording (status "enum" → extension type). Code: `packages/grid_controller/lib/src/models/bead_status.dart`.
**Status:** pending.

## A10 (2026-06-11) — `GraphEvent` gains `BeadDeleted`; dependency edges diff by the (issue,dependsOn,type) triple

**Decision:** Add a `BeadDeleted(Bead)` variant to the ratified `GraphEvent` union, and key dependency add/remove detection by the triple `(issueId, dependsOnId, type)` (`BeadDependency.edgeKey`).
**Why:** (a) ADR-0001 Decision 5 enumerated the event set without a delete variant, but a hard `bd delete` removes a bead from the snapshot — silently dropping it would violate the "diff is authoritative, no missed change class" invariant (PDR Risk row). `BeadDeleted` keeps the diff complete and the union exhaustively switchable. (b) The upstream `dependencies` PK is the *pair* `(issue_id, depends_on_id)`, but keying the diff by the full triple makes a dependency **type change** surface as remove+add (complete) rather than being missed; the known small gap is that a metadata-only edit on an unchanged triple is not surfaced (no `DependencyUpdated` event in M1 — low value, documented).
**Affects (if promoted):** ADR-0001 Decision 5 event list (+`BeadDeleted`). Code: `packages/grid_controller/lib/src/diff/graph_event.dart`, `diff_snapshots.dart`, `models/bead_dependency.dart`.
**Status:** pending.

## A11 (2026-06-11) — Bead labels are canonicalized to sorted order at the model boundary

**Decision:** Sort `Bead.labels` on construction in **both** read paths — the bd-CLI decoder (`Bead.fromJson`, via a `SortedLabelsConverter`) and the SQL `beadFromRow` mapper.
**Why:** labels are a **set** upstream (the `labels` table PK is `(issue_id, label)`), so order carries no meaning, yet `Bead ==` (freezed, order-sensitive on lists) and the SQL-vs-CLI snapshot equivalence canary (ADR-0001 Decision 7) require the two read paths to agree byte-for-byte. Without a canonical order the canary fails on label ordering alone. The structural diff already compares labels order-insensitively (set equality), so this only makes `Bead ==` and the equivalence test reliable; no behavior is lost.
**Affects (if promoted):** ADR-0001 Decision 7 (note the canonicalization). Code: `models/converters.dart` (`SortedLabelsConverter`), `models/bead.dart`, `services/dolt_row_mapper.dart`.
**Status:** pending.

## A12 (2026-06-11) — `BdRunner.run` gains a `stdin` channel for `bd batch`

**Decision:** Extend the `BdRunner` seam with an optional `{String? stdin}` parameter; `ProcessBdRunner` writes it to the child's stdin and closes the stream (EOF). `BdCliService.batch(lines)` pipes its newline-joined script this way.
**Why:** upstream `bd batch` reads its line-oriented script from **stdin** (`cmd/bd/batch.go`), but the first-cut runner interface was argv-only, so `batch()` was a no-op that would commit an empty transaction (caught by the Wave-1 adversarial verifier). A stdin channel keeps batching a single atomic spawn / one `DOLT_COMMIT` (ADR-0001 Decision 4) with no temp-file lifecycle. Minor internal-interface refinement, recorded for completeness.
**Affects (if promoted):** none in the ratified docs (implementation detail of ADR-0001 D4's batch requirement). Code: `services/bd_runner.dart`, `services/bd_cli_service.dart`.
**Status:** pending.

## A13 (2026-06-11) — Domain-projection design (Track E): result boundary, session state, step/needs composition

**Decision:** the M1 projections (ADR-0002 D2 trio) adopt these shapes: (a) every `project()` factory returns a sealed `ProjectionResult<T>` (`ProjectionOk` | `ProjectionFailed(ProjectionError)`) — decode is total, never throws past the projector, never silently drops (a type mismatch is a typed failure); unknown metadata keys are preserved in a `raw` map. (b) `AgentSession.state` is a binary `{open, closed}` derived from bead **status** (durable identity per ADR-0002 D2); gc's finer lifecycle string (`drained`/`detached`/…) is preserved verbatim on `SessionMetadata.lifecycleState` but not promoted to a typed enum the_grid doesn't yet own. (c) `Molecule` resolves child steps from `parent-child` edges and `Step.needs` from blocking edges between sibling steps; `isWisp = bead.ephemeral || metadata.wisp_type present`; `threadProvider` groups by the `thread:<id>` label (not `replies-to` edges).
**Why:** ADR-0002 D2 names the projections and composition rules but leaves the boundary/error shape and several mappings to implementation. **Validated against fixtures:** session (hq-session-sample ga-dvt2), message (hq-message-sample), molecule metadata + `isWisp` (hq-molecule-sample ga-dda). **NOT yet validated:** step/`needs` composition and the `wisp_type` metadata key — the pinned set contains **zero** step beads and zero molecule dependencies, so the edge direction/semantics are tested only synthetically. A follow-up capture of a real molecule+step+needs subgraph should pin these before the M2 reconciler consumes `runnableSteps`.
**Affects (if promoted):** ADR-0002 D2 (projection boundary + composition specifics); a new pinned fixture (molecule+step+needs). Code: `packages/grid_controller/lib/src/projections/`.
**Status:** pending.

## A14 (2026-06-11) — `bd ready` excludes molecule-type beads; PDR §6.1 demo and the ≤500ms target

**Decision:** the two-terminal acceptance demo (PDR §6.1) asserts `ReadySetChanged` against a **task/step** create, not a `molecule` create; and the ≤500ms latency budget is understood as the **pooled-SQL** path's target, with the bd-CLI fallback measured separately (~0.6–0.8s, embedded mode).
**Why:** observed live (bd 1.0.5, hermetic `bd init`): `bd ready` excludes `molecule`-type beads — molecules are containers; only their claimable steps enter the ready set. So `bd create -t molecule` fires `BeadCreated` only, with **no** `ReadySetChanged` (the M1 live demo and the integration test both confirm this). PDR §6.1's literal "molecule → BeadCreated + ReadySetChanged" is therefore inaccurate. Separately, the embedded-mode CLI read path is bd-spawn-dominated (~70–140ms × 2 per refresh + 150ms quiet + watcher latency), consistently ~0.6–0.8s — within the integration suite's generous 2s budget but above §6.1's 500ms, which the SQL path (≈1–5ms reads) targets. Latency is printed per event so the claim stays quantitative either way.
**Affects (if promoted):** PDR §6.1 (reword the demo to a task/step; note the SQL-vs-CLI latency split + retire the molecule→ready assumption). Code: `packages/grid_controller/test/integration/reactive_lifecycle_test.dart` already uses a task for the ready-set assertion.
**Status:** pending.
