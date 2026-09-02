---
status: accepted
date: 2026-06-15
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a35-m3-dogfood-concrete-inputs-ratified-rig-checkout-token-p
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A35"
---
## A35 (2026-06-15) — M3 dogfood concrete inputs ratified (rig, checkout, token, permissions, leonard flag)

**Decision (Nico, 2026-06-15, ratifying ADR-0006):** the concrete dogfood inputs are pinned — rig/allow-set token **`tgdog`**; Layer-1 root checkout **`/Users/nico/development/engineering.memento/lenny-tgdog`** (a real lenny clone, **explicit one-time registration**, default branch probed from `origin/HEAD`, never auto-provisioned); the agent's `CLAUDE_CODE_OAUTH_TOKEN` sourced from an **operator-provided env channel** and forwarded into the child via the **explicit allowlist** (`includeParentEnvironment:false`), never argv, never the full parent env; dogfood agents run **pre-granted permissions**; leonard attaches with explicit **`--extensions grid`**. **Deferred to the first live-arm gate (Nico present):** the **2 specific lenny work beads** the dogfood drives, and the go-ahead for the first real bd writes + agent spawns beside the running gc.
**Why:** these pin ADR-0006's open decisions so the M3 build can proceed autonomously; the build stays **fully offline** (fakes + temp repos + `grid run --dry-run`), and the one human-in-the-loop moment — the first live coexistence run + the lenny PR targets — is deliberately held for Nico.
**Affects:** ADR-0006 (Accepted) ratified-inputs block; `docs/M3-BUILD-ORDER.md` Track 0.2 gate (satisfied for the build; the live arm stays gated on Nico's presence). Code: the ownership allow-set seed (`{tgdog}`), the `SubprocessProvider` env allowlist.
**Status:** **Nico's decision, 2026-06-15** — recorded; the 2 lenny beads + the live-arm go-ahead remain with Nico at the gate.

