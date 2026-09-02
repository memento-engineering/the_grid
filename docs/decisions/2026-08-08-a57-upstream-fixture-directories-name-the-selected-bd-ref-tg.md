---
status: accepted
date: 2026-08-08
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a57-upstream-fixture-directories-name-the-selected-bd-ref-tg
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A57"
---
## A57 (2026-08-08) — upstream fixture directories name the selected bd ref (tg-rnd8)

**Decision (AI; pending Nico promotion).** Under ratified D-BD1's two compatibility rails, a complete upstream capture lives at `fixtures/upstream/<date>-bd-<ref>/`, where `<ref>` is `main` for the drift rail or the requested release tag. The capture command requires both the explicit ref and its independently resolved 40-character lowercase hexadecimal commit SHA; its README records both, the executable path, `BD_JSON_ENVELOPE=1`, sources, exact commands, and findings. A capture is assembled wholesale in a staging directory and atomically published only after every command succeeds; prior directories remain and captured fixture bytes are never hand-edited.

**Why.** ADR-0001 Decision 7's historical `<version>` slot predates D-BD1. D-BD1, already ratified and stamped into ADR-0002 Decision 1 on 2026-08-08, establishes `main` and release-tag rails, so the directory must identify the selected ref without rewriting the ratified historical decision.

**Not this.** This entry does not alter envelope decoding, the A2 corpus replay harness, compatibility rail CI, or any ratified ADR. In particular, `docs/adr/ADR-0001-technical-foundations.md` remains byte-for-byte untouched.

**Affects (if promoted).** The grid-porting fixture naming description and future fixture captures; no in-place edit to ADR-0001.

**Status:** Pending — Nico promotes or rejects.

