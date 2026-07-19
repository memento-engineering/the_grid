# SCRATCH — third-party harness support (inference providers · structured channels · the tmux fallback)

**Status: DESIGN — decision-complete (design session with Nico, 2026-07-02); awaiting
ratification.** Graduation target: **ADR-0008 Decision 10 amendments** (the agent scope — this doc
extends it; numbering/stamps are Nico's at ratification, never silent). Build: **grid agents, per
fully-briefed beads (§7) — not hand-written.** Beads are drafted only after ratification and file
**deferred** (the intake convention: Nico's bless flips them open).

**Ground truth re-accounted 2026-07-07** against the merged v3 / code-as-config refactor
(`grid_sdk` `runGrid`+`GridDelegate`, Track F composition assets, RS-8 `CodeRunCommand` deletion,
tg-33n `SpaceDelegate`). **The decisions D-1..D-6 are unchanged** — the seam itself did not move;
its *mounting* did. §1 reflects the post-refactor homes; §1b records the refactor deltas.

**Out of scope, explicitly:** the grid's OWN harness (`GridHarness` / the own agent — the D-B′
parked epic). Its recorded bounds are untouched, including OQ-b ("all agentic work is a spawned
process"), which this pass does **not** re-rule. Parked by Nico this session ("forget effort 3 for
now").

---

## 0. The theme, precisely

ADR-0008 D10 shipped the harness seam (`AgentHarness` → `RuntimeConfig`, the registry, `ModelTarget`,
two-moment validation, the D-C config ladder) with four registered harnesses — but three of them
carried "exact flag shape confirmed at the live arm" markers, the non-managed `ModelTarget`s are
transported as env vars no real tool reads, and every harness is a one-shot argv spawn
(`Lifecycle.oneTurn`, brief on the command line). Three separate efforts under this theme,
dependency-ordered:

- **Effort A — inference providers:** swift-infer (and llama.cpp) as real inference backends,
  **opencode first, pi second** (Nico). Payoff: committee critics on free local inference (the
  RS-3 finding: committee ≈2.6× coder cost on opus).
- **Effort B — structured channels:** every rostered harness has a machine-readable interactive
  channel; these are **the preferred transport** (Nico), replacing prompt-and-pray one-shots.
- **The tmux fallback:** a documented lane, not a build — see D-5.

## 1. Ground truth (scouted + probed 2026-07-02; re-verified 2026-07-07 post-refactor, all repos at origin/main)

### The seam as coded (power_station `grid_assets/lib/src/agent/agent_harness.dart`)

| fact | where |
|---|---|
| `AgentHarness{supports, spawnFor, interpret}` → `RuntimeConfig`; pure description, engine spawns | `agent_harness.dart:206-231` |
| All four impls `Lifecycle.oneTurn`, brief via argv; `interpret` delegates to shared `jobSignal` (exit-code semantics, `:282`); the doc comment reserves the override for a future non-one-shot harness | impls `:309,387,425,464` |
| Support matrix: claude/copilot = `ProviderManaged` only; pi = `OpenAiCompatible`\|`SwiftInfer`; opencode = `ProviderManaged`\|`OpenAiCompatible` | `:314,392,430-432,469-471` |
| `_targetEnv`: `OpenAiCompatible`→`OPENAI_BASE_URL`, `SwiftInfer`→`SWIFT_INFER_BASE_URL` env — **neither pi nor opencode reads these** (fiction; both configure providers via their own config files) | `:290`, consumed pi `:449` / opencode `:488` |
| Usage capture (`_usageWrapperScript` `sh -c` wrapper + `--output-format json` → `usageOut`, read back via sibling `usage_report.dart`) is claude-only; copilot/pi/opencode ignore `usageOut` | `:372`; `usage_report.dart` |
| D-C ladder, post-refactor: **station rung = space_station** — `space up` flags `--harness/--model/--openai-base/--swift-base` build the station-default `AgentConfig` (`up_command.dart:53-82,123-126`), mounted STATION-scoped via the Track F **`HarnessProvider`** composition asset in `SpaceDelegate.build()` (`space_delegate.dart:165-166`; provides `InheritedSeed<AgentHarnessRegistry>`+`<AgentConfig>`, `composition_assets.dart:189-193`) and via `delegate.wrapRoot` on the transitional composeStation path (`space_delegate.dart:214-216`). **Substation rung still unwired** — but Track F makes the mechanism obvious (a `HarnessProvider`-analogue under `Substation` scope). Bead `grid.agent` envelope + step-params rungs live: `resolveAgentConfig` precedence step params > envelope > ambient, fail-closed | `agent_domain.dart:34,55,131` |
| Two-moment validation wired: boot-eager `harnesses.validate` at `space up`, refuses loud; per-work `StateError`→`AllocationFailed`→supervision | `up_command.dart:128-134`, `agent_domain.dart` |

### 1b. The refactor deltas (merged 2026-07-03 → 07-08; what moved around the unmoved seam)

- **`CodeRunCommand` is DELETED** (RS-8 wave 2, tg-opp) — the old §1 anchor for the station rung
  and boot-eager validation. `grid_cli` now carries exactly four generic verbs
  (`watch`/`gate`/`rework`/`demo`, store-at-roots addressing) with **zero harness/model surface**;
  the only selection surface is `space up`'s flags (above).
- **`runGrid(GridDelegate)` is the ratified boot shape** (config-model v3 §5/§6, Nico 2026-07-06;
  grid_sdk Tracks B/C/D). space_station is authored as **`SpaceDelegate extends GridDelegate`**
  (tg-33n): `build()` = `RawAssetGrid → Station → HarnessProvider → Substations → Substation`.
  *Transitional:* `up` still drives through `composeStation` primitives sourced from the delegate
  until the composition tree binds to live driving ("Track G runner work", deferred).
- **Track F composition assets replace the ServiceBundle map** (tg-5r9): harness **station-scoped**
  (`HarnessProvider`), git/github **substation-scoped**, resolved by tree position
  (`sourceControlOf`). `ServiceBundle` itself still exists (the ambient value the assets provide)
  but the map + `serviceBundleMapFor` + the `--root` grammar + `metadata.grid.root` are all on the
  config-model **§7 kill-list** (Q3′: beads carry no root stamp; briefs resolve from the
  activation). A-1/A-3 specs must target the composition-asset surface, not the runner ladder.
- **Every spawned agent now receives the D-H doctrine block** in `buildAgentBrief`'s working
  agreement (tg-kx1, static text — the Q3′ reference-inflation fence untouched).
- **tg-ucz landed + proven**: `AgentCapability` materializes the bead's `grid.dart` pub linkage
  into the worktree at provision time (`code_capabilities.dart:142-156`, fail-closed via
  supervision). The `code` circuit is `kCodeCircuit` (`code_capabilities.dart:48-60`):
  `agent → review (sub-circuit) → land (landing sub-circuit)`; Formula→Circuit rename fully
  applied (zero `Formula` remnants).
- **The org already speaks ACP — on a different method surface.** `federated_grid_assets`
  (tg-043) adopted **Zed's Agent Client Protocol** for the federation bus: JSON-RPC 2.0 envelope +
  method namespacing + initialize-time capability negotiation ONLY, with grid-own methods
  (`grid/presence`, `grid/claim/*`), **deliberately not using ACP's agent-session methods**
  (`session/new`, `session/prompt` — `acp_envelope.dart:10-14` calls those "a different protocol
  for a different problem"). Effort B's B-2 adapter uses exactly those agent-session methods. Same
  protocol family, two method surfaces in one codebase — B-2's spec must disambiguate (and may
  share the JSON-RPC envelope codec as a precedent, not a dependency).

### The tools (probed live this session; pi + copilot installed under Nico's authorization)

| tool | version | one-shot | structured channel | custom endpoint |
|---|---|---|---|---|
| claude | installed | `-p` (+`--output-format json`) | `-p --input-format stream-json --output-format stream-json` (bidirectional JSONL) + `--resume`/`--continue` | ❌ provider-managed (keychain, A38) |
| copilot | **1.0.68** | `-p` + `--allow-all-tools` + `--model` (the coded guesses were RIGHT) + `-s/--silent` (response-only) | **`--acp`** (ACP server — the official replacement after `--headless --stdio` was REMOVED Feb 2026, no deprecation); Copilot SDK GA 2026-06 (Node/Python/.NET, JSON-RPC); TCP server mode (`cliUrl`); `--connect[=sessionId]` remote attach; `--continue`/`--resume`/`--session-id` | ❌ provider-managed (`gh` auth; `--model`/`COPILOT_MODEL` selects) |
| pi | **0.73.1** | `-p` confirmed (+`--mode json`) | **`--mode rpc`** — documented JSONL protocol over stdio (commands in: prompt/steer/interrupt; events out; strict LF framing) | ✅ `~/.pi/agent/models.json` (GLOBAL-only): per-provider `baseUrl` + `api: openai-completions`\|`anthropic-messages` + custom headers. Project `.pi/settings.json` overrides settings but NOT providers. Default provider `google`; NO providers configured on this machine yet. Note: auto-reads CLAUDE.md/AGENTS.md (`--no-context-files` exists) |
| opencode | **1.14.30** | `run [message]` (+`--format json`) | `serve` (headless HTTP) + `attach <url>` + **ACP** | ✅ `~/.config/opencode/opencode.json` — **swift-infer is ALREADY WIRED**: `@ai-sdk/openai-compatible` → `http://127.0.0.1:8080/v1`, `{env:SWIFT_INFER_AGENT_TOKEN}`, `X-Swift-Infer-Capture-Bodies: true`, 12 models, default `swift-infer/qwen3.6-35b-a3b-8bit`. Project-root `opencode.json` merges over global |

### The inference server + prior wires

- **swift-infer** (`~/development/com.nicospencer/swift-infer`, Hummingbird, default `0.0.0.0:8080`)
  serves **both wires**: OpenAI-compat `POST /v1/chat/completions` AND Anthropic-compat
  `POST /v1/messages`, plus `/v1/models`, embeddings, bearer tokens with scopes
  (`SWIFT_INFER_AGENT_TOKEN` = inference scope). Models: qwen3.6-35b-a3b(-8bit) + bge-small.
- Two swift-infer client implementations already exist in the org — genesis's console loop
  (OpenAI wire; **A39 caveat: `tool_choice: required` NOT enforced, auto only** → strong system
  prompt needed) and lenny's `SwiftInferChatModel` (Anthropic wire + Qwen extensions; lenny is a
  DEV TOOL, never the production path). **This theme adds NO third wire** — third-party harnesses
  bring their own clients; the grid only selects.
- **`genesis_tmux` 0.1.0 is BUILT + PUBLISHED to pub.dev** (sessions, send-keys with >4096
  paste-buffer fallback, capture-pane, poll + control-mode observation, injection guards);
  `leonard_tmux` 0.1.1 consumes it. the_grid's `TmuxProvider` (ADR-0004 Track 1) and the ADR-0009
  tmux allocation family ("update in place, own re-find + marker") remain reserved, unbuilt; the
  `tmux` provider enum aliases `SubprocessProvider` today.
- **tg-291** (live, 2026-07-02): a Sonnet critic wrote its verdict to stdout instead of the file —
  transport-by-instruction is brittle. Structured channels kill this failure class structurally.

## 2. Decisions (rulings by Nico, 2026-07-02, interactive)

**D-1 — Roster order: opencode leads Effort A; pi second; copilot is coworker-priority and rides
the channel effort.** pi was not installed anywhere when this theme opened (the `PiHarness` was
speculation); Nico authorized the install (done, 0.73.1). Copilot cannot reach swift-infer
(provider-managed) so it is not on Effort A's path; its one-shot flags are now verified by probe
and its live confirmation rides the first arm of either effort. claude stays the operative harness,
unchanged.

**D-2 — `ModelTarget` transport is harness-native SELECTION, not wiring; the env-var transport is
deleted.** `_targetEnv` dies. A harness maps the target to its own selection surface: opencode
`-m <provider>/<model>`, pi `--provider <name> --model <id>`, managed tools `--model`. The target
names WHERE inference runs; the machine config (D-3) owns HOW to reach it. The exact `ModelTarget`
value-type refactor (does `SwiftInfer(base)` slim to a named provider reference? does the carried
`base` become validation data for the D-3 probe?) is spec-level detail for the bead — the principle
(selection ≠ wiring) is what's ratified here.

**D-3 — Config ownership: HYBRID (Nico: option c).** Provider entries + auth stay
**operator-owned machine config** in each tool's native file (`~/.config/opencode/opencode.json`,
`~/.pi/agent/models.json` — baseUrl, api kind, `{env:…}` token refs; secrets never in worktrees,
never argv). The grid owns **selection**, riding the EXISTING D-C `AgentConfig` ladder as
`InheritedSeed` values — station `main()` default (per-machine posture: "swift-infer here,
llama.cpp on the dashboard") → **substation override (the dormant rung gets wired)** → the
fail-closed `grid.agent` bead envelope → step params. **Boot-eager validation grows a probe**: the
station checks the named provider actually exists in the tool's config (`opencode models` /
`pi --list-models`) and refuses LOUD at boot on a fresh/misconfigured machine — never mid-work.
*(Post-refactor home: the probe rides `AgentHarnessRegistry.validate` — the boot-eager moment at
`space up` today, the `HarnessProvider`/delegate rails at `runGrid` tomorrow — so it holds on both
the transitional composeStation path and the v3 end state.)*
Hermetic per-worktree config injection (project `opencode.json`; pi can't fully — providers are
global-only) is recorded as available later hardening, not built now.

**D-4 — Structured channels are the PREFERRED transport (Nico), behind ONE grid-side session seam
with PER-HARNESS adapters; ACP adapter FIRST.** The ratified OQ-a principle (transport is
harness-owned) extends to channels: the grid does NOT standardize on any single protocol — GitHub
already broke `--headless --stdio` once without deprecation; pi speaks its own RPC; claude its own
stream-json. The seam: a long-lived spawn (`Lifecycle.longLived`), the brief sent OVER the channel
(never argv), `StepSignal` interpreted from protocol events instead of exit codes (the reserved
`interpret()` override grows into its purpose), steerable mid-run sends, and structured
result/usage from events (kills the tg-291 class; usage-capture parity stops needing `sh`
wrappers). Adapter order: **ACP first** — one landing proves the seam against TWO harnesses
(copilot = the coworker priority, opencode = already swift-infer-wired, so the loop tests on free
local inference) — then **pi RPC** (simplest documented protocol; the seam's cheapest conformance
test), then **claude stream-json**. Session residency/attach interplay (a stdio child dies with
the controller) is designed inside the seam bead with the existing daemon-family and RS
primitives; adopt-across-restart for channel sessions is NOT promised this pass.

**D-5 — tmux is the FALLBACK lane: documented, not built (Nico).** Its role is
**ToS-preservation** — when providers lock down subscriptions/automation, driving the
human-shaped TUI through tmux is the way to stay within terms. Brittleness acknowledged
(pane-scraping, completion heuristics). Everything needed is already on the shelf:
`genesis_tmux` 0.1.0 published, ADR-0004 Track 1 + ADR-0009 tmux-family reservations stand.
The hybrid shape (harness process inside a tmux pane, driven over its structured channel) was
raised and parked: "interesting — not at the moment." **No bead.**

**D-6 — Dependency order: A → B; within A, opencode → pi.** Not because B can't start — because
B's ACP-first proof wants opencode+swift-infer live so channel development runs on local
inference. Efforts are tracked as separate epics under the theme with a blocks edge.

## 3. Non-goals (this pass)

The own harness / `GridHarness` / in-process agentic work (D-B′ parked epic; OQ-b stands
un-re-ruled); any new inference wire implementation (the org has two; the third is forbidden);
tmux build (D-5); hermetic config injection (D-3, later hardening); copilot BYOK/custom endpoints
(doesn't exist); ACP as the grid's standard protocol (D-4 — it's one adapter); channel-session
adopt-across-restart; TUI anything.

## 4. Supersede/stamp ledger (applied only on ratification, never silent)

- **ADR-0008 D10** — amended by D-2/D-3/D-4 (env-var transport → native selection; the hybrid
  config-ownership ruling; the channel seam + adapter order). Quote-and-supersede on the
  `_targetEnv` clause.
- **ADR-0004 Track 1 / ADR-0009 tmux family** — untouched; D-5 cites them as the ready shelf for
  the fallback lane (cite-only stamps).
- **D-B′ (ADR-0008)** — untouched; §0 re-affirms the park.

## 5. The effort ladder (beads drafted AFTER ratification; filed deferred; full tg-9fl-grade briefs)

| # | Bead (working title) | Scope | Depends on |
|---|---|---|---|
| A-1 | ModelTarget → native selection: delete `_targetEnv`, per-harness selection mapping, boot-probe validation (`opencode models`/`pi --list-models`), `-s` added to copilot one-shot | power_station `grid_assets` agent seam | ratification |
| A-2 | opencode live: flag confirm, `--format json` usage capture parity, swift-infer proof through the code circuit | power_station | A-1 |
| A-3 | Substation `AgentConfig` rung: a Track F-style composition asset under `Substation` scope (the `HarnessProvider` precedent — station-scoped today, this adds the substation-scoped override) | power_station | A-1 |
| A-4 | pi live: author `models.json` swift-infer entry (openai-completions default, A39 precedent), `--mode json` usage capture, live confirm | power_station + operator machine config | A-2 |
| B-1 | The channel session seam: longLived agent sessions, brief-over-channel, `StepSignal` from protocol events, steer/send, structured result/usage | power_station seam + the_grid runtime edges as needed | A-2 |
| B-2 | ACP adapter: copilot + opencode over one adapter (the `session/new`+`session/prompt` half of ACP; disambiguate from federated_grid_assets' claim envelope, §1b); first channel proof on both | power_station | B-1 |
| B-3 | pi RPC adapter | power_station | B-1 |
| B-4 | claude stream-json adapter | power_station | B-1 |

Copilot's one-shot live confirmation is an acceptance line on A-2's or B-2's arm, not its own bead.

## 6. First proofs

- **Effort A:** a live one-shot through the code circuit on `opencode` × `swift-infer/qwen3.6…` —
  work done, usage captured structurally, **zero Anthropic tokens spent**; then the same via `pi`.
  A committee lane on local inference is the economic headline (critics ≈2.6× coder cost today).
- **Effort B:** the same work driven over an ACP session — brief sent on the channel, completion
  signaled by protocol events (no exit-code inference), result + usage read structurally, one
  mid-run steer demonstrated — against BOTH copilot and opencode with the one adapter.

## 7. Rulings log (Nico, 2026-07-02)

- opencode first; "you can install pi" (installed 0.73.1; copilot installed 1.0.68 same pass).
- Copilot is coworker-priority; "I believe it supports RPC" — confirmed (ACP + GA SDK + TCP).
- tmux: "brittle… mostly a fallback for when the providers start locking down subscriptions —
  the only way to stay within the ToS, kinda" → D-5.
- Structured channels: "I didn't realize all these harnesses had this offering. Yes, these should
  be the preferred transport" → D-4.
- Hybrid tmux+channel: "interesting idea. But not at the moment."
- "Forget effort 3 for now. Let's focus on the 3rd-party support."
- Config ownership: "c, hybrid — we use InheritedSeed to project values into the tree… station …
  substation … down to the work tree, configured by the bead" (the D-C ladder, same shape as the
  `grid.dart`/`grid.agent` domain-envelope discussions of the past 48h) → D-3.
- "Yes, per-harness with ACP-first" → D-4.

**Remaining open (deliberately small):** pi's wire choice for swift-infer defaulted to
`openai-completions` (the A39 precedent; `anthropic-messages` also available — flag at A-4 if
preferences differ); the exact `ModelTarget` value-type shape (D-2, spec-level, settled in A-1's
brief/spec); whether B-1's session seam needs a `grid_runtime` `RuntimeProvider` extension for
stdio conversation or rides the existing provider surface (settled in B-1's spec).
