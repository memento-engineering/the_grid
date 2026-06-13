# Convergence fixture — real gc-produced `convergence.*` metadata

**Captured 2026-06-13** for M2 Track I (ADR-0000 A29). Validates Track A's 31-key
`convergence.*` metadata codec + the `Convergence`/`Wisp` projections against
**real gascity output**, not synthetic data — the codec-fidelity oracle.

## Provenance (captured, never authored)
- **bd** 1.0.5 (`f9fe4ef2a`) — the current pin.
- **gascity** source `4e1e6f66d` (the version Track A was ported from) built as **gc 1.1.1**.
- **Method:** gc's *real* convergence writer (`internal/convergence` `CreateHandler` /
  `HandleWispClosed` / gate eval) driven across states through `cmd/gc`'s own test
  harness (`setupConvergenceRuntime` → `handleConvergenceRequest` + `convergenceTick`),
  serializing each state's root `metadata` map + the wisp subgraph. No supervisor, no
  agents, no live city — `MemStore` + a fake provider, exactly as gc's integration
  tests run. (`gc start` is machine-wide and was deliberately NOT used; it would
  entangle the live factory.) The throwaway harness was removed from gascity after capture.

## Files
Each `0N-*.json`: `{scenario, convergence_root, root_metadata, subgraph}`. The
`01→02→03` trio is **one** convergence advancing (shared ids) — a tick sequence usable
by the shadow replay harness; `04`/`05` are separate single-loop final states.

| file | state | keys | notable |
|---|---|---|---|
| `01-active-manual` | `active` | 15 | post-create; wisp `gc-2` poured, `idempotency_key=converge:gc-1:iter:1` |
| `02-waiting-manual` | `waiting_manual` | 17 | after `bd close` of the active wisp + tick |
| `03-terminated-approved` | `terminated` | 20 | operator approve → `terminal_reason=approved`, `terminal_actor=controller` |
| `04-gate-pass-terminated` | `terminated` | 28 | condition gate `exit 0` → `gate_outcome=pass`, `gate_exit_code=0`, `gate_duration_ms=143` |
| `05-no-convergence-at-max` | `terminated` | 28 | condition gate `exit 1` ×2 at `max_iterations=2` → `terminal_reason=no_convergence` |
| `06-waiting-trigger` | `waiting_trigger` | 14 | `--trigger event` create |
| `bd-export-roundtrip.jsonl` | — | — | `04`'s metadata written via `bd update --metadata` then `bd export --all` |

## Fidelity findings (real bytes confirm Track A decisions)
- **bd preserves every `convergence.*` value as a STRING** on export — no type coercion
  (`gate_exit_code:"0"`, `gate_duration_ms:"143"` stay strings). The codec's
  string-parsing path (`goAtoi`/`GoDuration`/`FieldReading`) is correct; `coerceWireValue`
  is for edge cases, not the convergence happy path. (`bd-export-roundtrip.jsonl`.)
- **`gate_truncated` is `""` for false**, never `"false"` (A17/A-decision D4 ✓).
- The wisp is a persistent **`molecule`** bead (not ephemeral) carrying
  `idempotency_key=converge:<root>:iter:N` ([[A15]] persistent-pour ✓).
- Empty strings for unset keys (`gate_stdout`, `pending_next_wisp`, `rig`, `trigger`…) —
  the codec's absent-vs-empty handling must treat `""` as set-to-empty.

## Re-capture
Re-run the throwaway harness in `gascity/cmd/gc` (see ADR-0000 A29 for the recipe;
needs `CGO_*FLAGS` → `$(brew --prefix icu4c@78)` to compile gascity's dolt CGO dep),
then re-pin here. Never hand-edit.
