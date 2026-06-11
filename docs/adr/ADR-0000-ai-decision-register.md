# ADR-0000 — AI decision register

**Status:** Living document — never Accepted, never closed.
**Rule (Nico, 2026-06-11):** any decision made by AI lands here as an amendment and **stays here** until Nico promotes it (into its own ADR, or a named amendment of an existing one) or shoots it down. AI must not write its own decisions directly into ADR-0001+; those documents record human-ratified decisions only.

Entry format: `A<n> (date) — title` · Decision · Why · Affects (docs/code that change if promoted) · **Status:** pending | promoted → ⟨where⟩ | rejected.

---

## A1 (2026-06-11) — Fixture capture scheme

**Decision:** Pinned upstream fixtures live at `fixtures/upstream/<date>-bd-<version>/`, captured with `BD_JSON_ENVELOPE=1`. the_grid contributes the empty-workspace cases (`tg-list-all-empty`, `tg-ready-empty`) plus `statuses`/`types` (the 13 custom types); the city HQ contributes per-domain samples extracted from `bd export --include-infra` JSONL (not from `bd list`) and a 25-line raw export sample; one error fixture captures the failure shape.
**Why:** PDR §6.7 and ADR-0001 Decision 7 require version-pinned fixtures; the HQ export is 24MB so wholesale check-in is wrong; per-domain extraction keeps fixtures small and representative.
**Affects:** test layout in `grid_controller`; the porting skill's re-capture procedure.
**Status:** pending.

## A2 (2026-06-11) — M1 proving domains: sessions + messages + molecules (not agents/sessions/rigs)

**Decision:** Swap M1's proving domains for the projection mechanism to **session, message, molecule/step** — the domains that actually exist as beads in the live city. Flag `agent`/`role`/`rig`/`convoy` projections as *pending an upstream-representation investigation*.
**Why:** Fixture capture (2026-06-11, bd 1.0.5, city HQ) found **zero** agent/rig/role/convoy/gate beads: 34,588 task, 692 session, 390 chore, 1 molecule, 1 step, 1 bug. In current gc, agents/rigs/roles appear to be config/registry-derived (`city.toml`, `~/.gc/cities.toml`), not beads — the_grid's `types.custom` anticipates them, but there is nothing to pin mappings against. ADR-0002's mapping table is unaffected as a target; only the M1 proving set and its fixtures change.
**Affects (if promoted):** ADR-0002 Decision 2 consequences (proving trio); PDR §6 acceptance criterion 8 (`agentsProvider/sessionsProvider/rigsProvider` → `sessionsProvider/inboxProvider/moleculesProvider`); M1-BUILD-ORDER Track E.
**Status:** pending.

## A3 (2026-06-11) — bd errors are enveloped on STDOUT

**Decision:** `BdException` parsing must treat **stdout** as the primary error channel when exit ≠ 0: observed shape is `{"data": {"error": "<message>"}, "schema_version": 1}` on stdout with **empty stderr**, exit 1 (`bd dep list <unknown-id> --json`, bd 1.0.5, envelope mode). Parse stdout first, fall back to stderr, then raw text.
**Why:** ADR-0001's error-decision assumed stderr JSON (per `cmd/bd/output.go` reading); live behavior under `BD_JSON_ENVELOPE=1` differs. Fixture: `fixtures/upstream/2026-06-11-bd-1.0.5/tg-error-stdout.json`.
**Affects (if promoted):** ADR-0001 Decision 4 wording; `BdCliService` error hierarchy.
**Status:** pending.

## A4 (2026-06-11) — Pre-ultracode onboarding artifacts: CLAUDE.md + M1-BUILD-ORDER

**Decision:** Two repo artifacts carry context across compaction and into subagents: `CLAUDE.md` (session contract: read-first list, the gate, process rules including this register, conventions, bd rules, environment facts, upstream pins) and `docs/M1-BUILD-ORDER.md` (dependency-ordered work breakdown with parallelizable tracks for orchestration).
**Why:** Post-compact sessions and fanned-out agents must not depend on conversation history; the PDR/ADRs hold decisions but not operating instructions or build sequencing.
**Affects:** repo root; docs/.
**Status:** pending.

## A5 (2026-06-11) — `bd list` does not surface infra-typed beads

**Decision (observation + handling):** treat `bd list` as unsuitable for infra domains regardless of `--all`; domain sampling and the CLI-fallback snapshot read use `bd export --include-infra` exclusively (already ADR-0001's fallback read; this closes the loophole of ever composing snapshots from `bd list`).
**Why:** `bd list --json --all --type agent/rig/role` returned empty envelopes in HQ while `--type message/session/molecule` returned data; export is the documented carrier of infra records.
**Affects (if promoted):** ADR-0001 Decision 4 amendment wording; `BdCliService.list` documentation.
**Status:** pending.

## A6 (2026-06-11) — M4 is scoped usage-driven, decomposed M4a–M4f with just-in-time ADRs, adopted via the fs ladder

**Decision:** M4 is scoped by the measured surface of the live city (audited 2026-06-11: 12 gc command families, 13 agent templates, 35 orders, 33 formulas, 2 active rigs — full inventory in `docs/M4-SCOPING.md`), decomposed into M4a config / M4b topology reconciler / M4c orders / M4d sling+hooks / M4e patrol / M4f cutover, each getting its ADR (0005–0010) just-in-time as predecessors land. M4 acceptance = cutover of one real rig, not feature parity. fs adoption is per-milestone: M1 observe, M2 shadow, M3 drive-one-rig (dogfood: the_grid rig), M4f replace.
**Why:** One up-front M4 ADR would speculate against a target M1–M3 (and the upstream RFC) will move; the usage inventory makes the checklist finite and testable.
**Affects (if promoted):** PDR §5 (M4 row → sub-milestones + ladder reference), `docs/M4-SCOPING.md` status.
**Status:** pending.

## A7 (2026-06-11) — Coexistence partition rule

**Decision:** While gc and the_grid both run, the_grid owns a bead/rig set **disjoint** from gc's reconciler — partitioned by rig and/or ownership marker; M2 shadow mode is strictly read-only.
**Why:** gc's convergence handler assumes a single writer per bead (ADR-0003 invariant 7); two reconcilers on one convergence bead corrupts state for both.
**Affects (if promoted):** ADR-0003 (operating-mode section), M2/M3 acceptance criteria, M4-SCOPING.
**Status:** pending.
