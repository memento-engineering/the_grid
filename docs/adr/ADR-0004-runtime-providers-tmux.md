# ADR-0004 — M3 runtime providers: tmux first, tiered

**Status:** Proposed
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** M3 gives the_grid hands — spawning and supervising coding-agent sessions for ready work. Source assessed 2026-06-11: gc's tmux provider (`gascity/internal/runtime/tmux/`, ~5.9k LOC production + ~8.1k tests; PDR §7a) and the `runtime.Provider` contract (`gascity/internal/runtime/runtime.go`). gc's provider is pure subprocess invocation of the `tmux` binary — no library, no control mode — so the port is `Process.run` plus the reliability heuristics.

---

## Decision 1 — Provider contract: Futures for acts, Streams for observations

*(Amended 2026-06-11: the original sketch was all Futures — request/response only. A reactive orchestrator observes its runtimes the same way it observes the work graph: push. The rule of thumb is now explicit — **commands are Futures, observations are Streams**.)*

`grid_runtime` defines a Dart `RuntimeProvider` interface ported from gc's contract, trimmed to what M3 consumes, with a `capabilities` record so providers degrade explicitly rather than silently:

```dart
abstract interface class RuntimeProvider {
  // Acts — request/response:
  Future<void> start(String name, RuntimeConfig config);
  Future<void> stop(String name);                          // full process-tree kill
  Future<void> interrupt(String name);
  Future<void> nudge(String name, List<ContentBlock> content);
  Future<void> attach(String name);                        // capability-gated

  // Observations — push:
  Stream<RuntimeEvent> get events;          // sealed: SessionStarted/Exited/Died/Respawned/Attached/Detached/ActivityChanged
  Stream<String> output(String name);       // live transcript of a session

  // Point-in-time queries (for reconcile passes; derivable from events but cheap to ask):
  Future<bool> isRunning(String name);
  Future<bool> processAlive(String name, List<String> processNames);
  Future<String> peek(String name, int lines);
  Future<List<String>> listRunning(String prefix);
  Future<DateTime?> lastActivity(String name);

  RuntimeCapabilities get capabilities;
}
```

`RuntimeEvent` and session-output streams feed the same machinery as everything else: domain-event Transformers (ADR-0002), the reconciler's inputs (ADR-0003), and the exploration-protocol observation payload (ADR-0001 Decision 6). Two providers in M3: **`TmuxProvider`** (primary — attachable, survives the orchestrator, gc-compatible) and **`SubprocessProvider`** (plain `Process` supervision — CI/headless, no attach; its `output` stream is just stdout/stderr). Session lifecycle is tracked as session beads either way.

## Decision 2 — A standalone `tmux` package: argv commands + stream surfaces

*(Amended 2026-06-11: tmux support is extracted into its own general-purpose package — Nico.)*

The tmux client is **its own package, `tmux`** — zero grid dependencies, a candidate for pub.dev. `grid_runtime`'s `TmuxProvider` is a thin adapter over it. Two layers:

- **Command layer (Futures)** — typed argv invocations (`tmux -u -L <socket> …`), exactly gc's transport: `newSession`, `killSession`, `hasSession`, `listSessions`, `sendKeys`, `capturePane`, `displayMessage`, `listPanes`, `respawnPane`, `pipePane`, … with typed errors and format-string (`-F '#{…}'`) result parsing.
- **Reactive layer (Streams)**:
  - `Stream<String> paneOutput(target)` — **`pipe-pane` into a FIFO** (`mkfifo` + `pipe-pane -o 'cat >> fifo'`), read as a Dart stream: push-based, continuous, no capture-pane polling. This is the transcript stream the provider's `output()` exposes.
  - `Stream<TmuxEvent> events()` — server/session/pane lifecycle (created, died, attached, detached, activity). v1 implementation is **poll + diff** of `list-sessions`/`list-panes` on our isolated socket (~1s; the same sufficient-signal → authoritative-diff pattern as ADR-0001 Decision 5 — cheap because the socket is ours alone), upgraded with **tmux hooks** (`set-hook session-closed / pane-died / alert-activity` → `run-shell` writing into a control FIFO) as the push tier.

the_grid gets its **own tmux server socket** (`-L grid-<workspace-hash>`), isolating it from gc's sockets and the user's tmux during coexistence. Targets use `session:^.0` pane addressing (robust to `base-index` configs); session names validated `^[a-zA-Z0-9_-]+$`.

## Decision 3 — Tiered implementation; tiers are the M3 work plan

**Tier 1 — MVP (≈1.5–2k LOC):** new-session (detached, `-c` workdir, `-e` env), kill-session, has-session, list-sessions, capture-pane (`peek`), display-message attribute queries (pane PID/command/attached/activity), send-keys with literal mode + the "not in a mode" retry loop (exponential backoff 500ms→2s cap), **plus the v1 stream surfaces**: `paneOutput` via pipe-pane→FIFO and `events()` via poll+diff. Exit: dispatch an agent CLI into a session, feed it a prompt, *stream* its output, observe death as a `TmuxEvent`, kill cleanly.

**Tier 2 — Reliability (≈1.2k LOC):** copy-mode probe + cancel before *every* send (user scrollback must never swallow a nudge); per-session nudge serialization (mutex + 30s timed lock); paste-buffer path for payloads >8KB (load-buffer → paste-buffer → delete-buffer); paste→Enter debounce; poke-activity discounting (subtract our own keystroke echoes from activity signals); `WakePane` resize dance (SIGWINCH) for detached panes; find-agent-pane via `list-panes` enumeration + process-tree match; respawn-pane recovery.

**Tier 3 — Process hygiene:** full kill sequence — pane PID → recursive child walk (`pgrep -P`) → collect reparented descendants → SIGTERM → 2s grace → SIGKILL → kill-session; server-liveness probe before new-session (2s `has-session` probe; refuse on degraded server to avoid socket clobber).

**Tier 2 addendum:** the hook-based push upgrade for `events()` (`set-hook session-closed/pane-died/alert-activity` → control FIFO) lands here, replacing the poll+diff v1 where available.

**Deferred (explicitly out of M3):** approval-prompt detection/response, startup-dialog dismissal, Gemini turn-rewind / Codex abort markers, state caching, themes.

## Decision 4 — Agent quirks are data, not code

gc encodes per-agent timing/keying differences in code (Escape-before-Enter skip list for claude/codex/gemini/grok/kimi; 500ms default vs 1.5s Kimi paste debounce). `grid_runtime` ports these as a declarative **quirk table** (freezed value type keyed by agent family) seeded verbatim from gc's values, so new agents are a data change and the table is inspectable at runtime via the exploration tools.

## Decision 5 — Conformance and the test strategy

gc's 8.1k LOC tmux test suite is the porting spec; M3's conformance suite transliterates its highest-value scenarios: startup races ("not in a mode"), copy-mode interference, zombie/corpse detection, activity discounting, and the kill-sequence edge cases (reparented orphans). Unit tier fakes the tmux binary (scripted argv→stdout/exit transcripts); a tagged integration tier drives a real tmux server on an isolated socket. macOS first; Linux in CI; Windows out of scope (gc isolates it behind process-group files; we inherit the boundary, not the port).

---

## Alternatives considered

- **tmux control mode (`-CC`)** — rejected for v1, with a softer stance than before: control mode IS the genuinely push-native tmux interface (`%output`, `%session-changed`, …) and is the natural future transport for the `tmux` package's reactive layer. But gc ships years of production heuristics against the argv interface, control mode's event scope is bound to the attached session, and pipe-pane + hooks deliver the streams we need on the proven transport. Revisit inside the `tmux` package (its API is transport-agnostic) once v1 is in production.
- **PTY-based supervision instead of tmux** (`dart:io` + a pty package) — rejected as primary: loses user attachability and session survival across orchestrator restarts — both load-bearing for an agent city. It is effectively what `SubprocessProvider` offers where those don't matter.
- **Porting all 23 verbs + every heuristic up front** — rejected: Tier 1 dispatches real work; tiers 2–3 are sequenced by observed failure modes, with gc's tests as the map.
- **k8s/ACP/cloud providers** — out of scope until a concrete deployment need exists (PDR non-goal: no parity-first).
