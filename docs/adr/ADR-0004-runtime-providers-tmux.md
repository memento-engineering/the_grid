# ADR-0004 — M3 runtime providers: tmux first, tiered

**Status:** Proposed
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** M3 gives the_grid hands — spawning and supervising coding-agent sessions for ready work. Source assessed 2026-06-11: gc's tmux provider (`gascity/internal/runtime/tmux/`, ~5.9k LOC production + ~8.1k tests; PDR §7a) and the `runtime.Provider` contract (`gascity/internal/runtime/runtime.go`). gc's provider is pure subprocess invocation of the `tmux` binary — no library, no control mode — so the port is `Process.run` plus the reliability heuristics.

---

## Decision 1 — Provider contract: a ported subset, capability-flagged

`grid_runtime` defines a Dart `RuntimeProvider` interface ported from gc's, trimmed to what M3 consumes, with a `capabilities` record (mirroring gc's optional-extension pattern) so providers degrade explicitly rather than silently:

```dart
abstract interface class RuntimeProvider {
  Future<void> start(String name, RuntimeConfig config);
  Future<void> stop(String name);                          // full process-tree kill
  Future<void> interrupt(String name);
  Future<bool> isRunning(String name);
  Future<bool> processAlive(String name, List<String> processNames);
  Future<void> nudge(String name, List<ContentBlock> content);
  Future<String> peek(String name, int lines);
  Future<List<String>> listRunning(String prefix);
  Future<DateTime?> lastActivity(String name);
  Future<void> attach(String name);                        // capability-gated
  RuntimeCapabilities get capabilities;
}
```

Two providers in M3: **`TmuxProvider`** (primary — attachable, survives the orchestrator, gc-compatible) and **`SubprocessProvider`** (plain `Process` supervision — CI/headless, no attach). Session lifecycle is tracked as session beads either way; provider state is observable via the exploration protocol (`plugins.grid` payload + tools), per ADR-0001 Decision 6.

## Decision 2 — Tmux via `Process.run`, per-grid socket isolation

All tmux interaction is argv subprocess calls (`tmux -u -L <socket> …`), exactly as gc does. the_grid gets its **own tmux server socket** (`-L grid-<workspace-hash>`), isolating it from gc's sockets and the user's tmux during coexistence. Targets use `session:^.0` pane addressing (robust to `base-index` configs); session names validated `^[a-zA-Z0-9_-]+$`.

## Decision 3 — Tiered implementation; tiers are the M3 work plan

**Tier 1 — MVP (≈1.5–2k LOC):** new-session (detached, `-c` workdir, `-e` env), kill-session, has-session, list-sessions, capture-pane (`peek`), display-message attribute queries (pane PID/command/attached/activity), send-keys with literal mode + the "not in a mode" retry loop (exponential backoff 500ms→2s cap). Exit: dispatch an agent CLI into a session, feed it a prompt, observe output, detect death, kill cleanly.

**Tier 2 — Reliability (≈1.2k LOC):** copy-mode probe + cancel before *every* send (user scrollback must never swallow a nudge); per-session nudge serialization (mutex + 30s timed lock); paste-buffer path for payloads >8KB (load-buffer → paste-buffer → delete-buffer); paste→Enter debounce; poke-activity discounting (subtract our own keystroke echoes from activity signals); `WakePane` resize dance (SIGWINCH) for detached panes; find-agent-pane via `list-panes` enumeration + process-tree match; respawn-pane recovery.

**Tier 3 — Process hygiene:** full kill sequence — pane PID → recursive child walk (`pgrep -P`) → collect reparented descendants → SIGTERM → 2s grace → SIGKILL → kill-session; server-liveness probe before new-session (2s `has-session` probe; refuse on degraded server to avoid socket clobber).

**Deferred (explicitly out of M3):** approval-prompt detection/response, startup-dialog dismissal, Gemini turn-rewind / Codex abort markers, state caching, tmux hooks, themes.

## Decision 4 — Agent quirks are data, not code

gc encodes per-agent timing/keying differences in code (Escape-before-Enter skip list for claude/codex/gemini/grok/kimi; 500ms default vs 1.5s Kimi paste debounce). `grid_runtime` ports these as a declarative **quirk table** (freezed value type keyed by agent family) seeded verbatim from gc's values, so new agents are a data change and the table is inspectable at runtime via the exploration tools.

## Decision 5 — Conformance and the test strategy

gc's 8.1k LOC tmux test suite is the porting spec; M3's conformance suite transliterates its highest-value scenarios: startup races ("not in a mode"), copy-mode interference, zombie/corpse detection, activity discounting, and the kill-sequence edge cases (reparented orphans). Unit tier fakes the tmux binary (scripted argv→stdout/exit transcripts); a tagged integration tier drives a real tmux server on an isolated socket. macOS first; Linux in CI; Windows out of scope (gc isolates it behind process-group files; we inherit the boundary, not the port).

---

## Alternatives considered

- **tmux control mode (`-CC`)** — rejected: gc ships years of production heuristics against the argv interface; control mode is a different (and quirkier) protocol with no test corpus behind it.
- **PTY-based supervision instead of tmux** (`dart:io` + a pty package) — rejected as primary: loses user attachability and session survival across orchestrator restarts — both load-bearing for an agent city. It is effectively what `SubprocessProvider` offers where those don't matter.
- **Porting all 23 verbs + every heuristic up front** — rejected: Tier 1 dispatches real work; tiers 2–3 are sequenced by observed failure modes, with gc's tests as the map.
- **k8s/ACP/cloud providers** — out of scope until a concrete deployment need exists (PDR non-goal: no parity-first).
