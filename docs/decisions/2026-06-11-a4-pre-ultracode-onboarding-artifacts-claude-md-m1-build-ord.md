---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a4-pre-ultracode-onboarding-artifacts-claude-md-m1-build-ord
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A4"
---
## A4 (2026-06-11) — Pre-ultracode onboarding artifacts: CLAUDE.md + M1-BUILD-ORDER

**Decision:** Two repo artifacts carry context across compaction and into subagents: `CLAUDE.md` (session contract: read-first list, the gate, process rules including this register, conventions, bd rules, environment facts, upstream pins) and `docs/M1-BUILD-ORDER.md` (dependency-ordered work breakdown with parallelizable tracks for orchestration).
**Why:** Post-compact sessions and fanned-out agents must not depend on conversation history; the PDR/ADRs hold decisions but not operating instructions or build sequencing.
**Affects:** repo root; docs/.
**Status:** promoted → ADR-0001 Decision 8 (2026-06-11).

