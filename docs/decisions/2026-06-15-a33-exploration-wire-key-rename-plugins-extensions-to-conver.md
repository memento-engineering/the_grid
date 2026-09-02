---
status: accepted
date: 2026-06-15
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a33-exploration-wire-key-rename-plugins-extensions-to-conver
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A33"
---
## A33 (2026-06-15) — exploration wire-key rename `plugins`→`extensions` to converge on leonard's published read contract

**Decision (M3 discovery, drafted as `docs/M3-BUILD-ORDER.md` Track 6):** the_grid's exploration host serialized key `plugins` is renamed to `extensions` (both the handshake and the observation envelope), to match leonard ≥0.1.0's reader, which reads **only** `extensions` with **no fallback** (`leonard_agent/.../vm_service_client.dart`, `observation/models.dart`). The `ext.exploration.*` prefix, the `core.handshake`/`<ns>.<tool>` method names, and protocol version `'1'` are **already aligned** — this is a pure wire **key-name** fix, not a protocol change. the_grid's own `grid_devtools` client and the affected tests move in **lockstep** (else the_grid's own panel breaks). This makes the_grid emit a shape **ADR-0001 Decision 6 (RATIFIED, documents `plugins`/`plugins.grid`) no longer describes** — per the CLAUDE.md process rule ADR-0001 is **not** silently edited; ADR-0001 D6 gets a one-line amendment **upon Nico's ratification**, not before. No leonard change, no `exploration_contract` change, no protocol-version bump.
**Why:** leonard debugs the_grid's **pure-Dart VM directly**; today leonard attaches but sees zero extensions / empty grid state because of the key mismatch. Converging on leonard's already-published `extensions` contract is the minimal fix that makes a stock `leonard_cli --extensions grid` truly attach.
**Affects (if promoted):** ADR-0001 D6 (one-line amendment on ratification); code `grid_exploration` host + `grid_devtools` client (+ recompiled `main.dart.js`) + flipped attach tests; a new pinned cross-repo handshake/observation conformance fixture.
**Status:** **ratified (Nico, 2026-06-15)** — promoted into ADR-0006 (Accepted); the ADR-0001 D6 one-line amendment lands when M3 Track 6 ships the rename (keeps doc+code in sync).

