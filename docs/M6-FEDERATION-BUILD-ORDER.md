# M6 — Federation + Asset Management (build order)

**Status:** READY TO BUILD (offline) — **ADR-0011 Accepted 2026-06-29.** Source of
decisions: **`docs/adr/ADR-0011-federation-and-asset-management.md`** + the design
surface `docs/SCRATCH-asset-management.md`. **Starting point:** the parked
point-to-point spike on branch **`m6-federation`** (`grid_federation` pkg + `grid
serve`/`grid lease`) — M6 HARDENS the spike into the ADR-0011 design; it is not a
greenfield.

**Thesis (ADR-0011):** the grid manages a portfolio of **assets**; federation
**leases + coordinates** them across stations. Engine = primitives (lease lifecycle,
bus, membership, presence); each **domain** owns its contract (capacity predicate,
"use", payload). Owner-authoritative truth; static membership; capabilities are
cascading config matched by containment, probed/dynamic for toolchain targets.

## Safety rails (carried from ADR-0006 / M3 / M5 — non-negotiable)

- **OFFLINE-first.** Tracks A–G build with fakes + loopback (two `grid` procs on one
  box) + temp repos. **The first LIVE cross-machine arm (Track H) is the HUMAN GATE**
  (Nico present). No real `claude`, no real cross-machine burn until then.
- **Coexistence:** A37 (write only your own store); a remote lease **never** writes a
  peer's store except via the federation protocol; single-writer-per-bead; the codec
  boundary + gc rigs untouched.
- **No broad process-kill** ([[feedback-no-broad-process-kill-coexistence]]): scope
  every kill to the_grid's own worktree/session/pgid; a live `llama-server` runs on
  the Dashboard.
- **Deploy via git over the LAN** (a peer's bare repo over SSH) — `rsync` of the tree
  is blocked as exfiltration; that's correct, use git.

## Tracks (dependency-ordered; A–G are offline + workflow-implementable)

| Track | Scope | ADR refs | Depends on |
|---|---|---|---|
| **A — federation core hardening** (`grid_federation`) | Harden the spike's lease lifecycle into the ADR shape: **lease ≈ Capability** (mount=acquire/dispatch, unmount=release) composable at the engine `EffectResolver` seam; the **abstract bus seam** (`StationClient`) kept kind-agnostic. **Hazard bake-ins:** a **monotonic fencing token** in `LeaseGrant` (owner rejects stale dispatch/release); **max-lease-lifetime + a FIFO wait-queue** (starvation); **owner-clock reaping** (no cross-machine time math); a **client idempotency key** on lease/dispatch (owner dedups). | D3, D7, Hazards | — (the spike) |
| **B — membership + presence/heartbeat + reaping** (`grid_federation`) | **Static peer config** (peer list: address + token). The **presence** endpoint carries the capability profile + **ephemeral capacity** (the gossip half); **heartbeat**; the owner **reaps a lease on heartbeat loss by its own clock**; disconnect handling. | D4, D5, D7 | A |
| **C — capability model: facts, cascade, matching, probes** (`grid_federation` + engine) | Capability **fact** value types with **per-fact composition** (scalar=override, set=union; **targets are sets**); facts as **`InheritedSeed` config** (the cascade; derived defaults `flutter-target ⟸ dart-target ⟸ system-os`); **containment matching** (`station.facts ⊨ order.requires`); the **dart/flutter probes** (probe os/dart-target/flutter-target dynamically); **TTL re-validation** of a held lease against shifted capabilities (depth #2 → lapse + re-place). Ship a **dynamic-shift test** (probe changes → re-match → reconcile). | D6 | A; engine `InheritedSeed` |
| **D — the compute asset domain** (`grid_assets`) | Move the spike's `DispatchCommand`/`CommandResult` + the compute lease's **"use"** (run a **bounded** command) + the compute **capacity predicate** OUT of the federation core into a compute domain — the federation core stays kind-agnostic. The domain **bounds "use"** (not raw shell-as-a-service; the RCE-bounds note). | D2, D3, Hazards | A |
| **E — git-over-LAN asset/code sync** | Formalize the spike's manual bare-repo push into a small capability: a station distributes code/assets to a peer via **git push over SSH** to the peer's bare repo (the federation-native sync channel, distinct from the lease bus). | D7 (finding #1) | — |
| **F — the burn formula** (`butane_grid_assets`) | The burn = **two capability-scoped orders** (`burn-host` local + `burn-follower` leased to a match) + **two channels** (bus rendezvous + endpoint handoff; `leonard_drive` **direct** perception). Follower execution: provision `butane_flutter` from the substation, build for target, **launch exposing `ext.exploration.*`** (embeds `leonard_flutter`), publish endpoint, **teardown via the M4 `terminateGroup`/pgid reaper**. Host: await endpoint, attach `leonard_drive`, run a **SCRIPTED** scenario, assert, collect a (domain-defined) **TestReport**. Offline: fake lease + headless/fake app + scripted scenario. | D9 | A,B,C,D + leonard, butane |
| **G — conformance / federation invariants** (mutation-tested) | The invariants hold AT DEPTH: **owner-authoritative ⇒ no double-grant**; **fencing ⇒ no zombie double-use** after reap+reissue; **starvation bounded** (max-lifetime + FIFO fairness); **idempotency** (dup messages don't double-grant); **A37/coexistence** (a lease never writes a peer's store except via the protocol). | all | A–F |
| **H — the LIVE cross-machine arm (HUMAN GATE)** | Loopback burn green (offline) → the **real cross-machine burn**: Studio (host) + `linux-dashboard.local` (follower) run a butane burn end-to-end. **Nico present.** | all | A–G |

## Placement decisions (resolved here; minor, not ADR-class)

- The **compute domain** lives in **`grid_assets`** for M6 (the baseline pack; "grid_assets first lives in the_grid", ADR-0008) — extract to `power_station` later.
- The **probes** live in `grid_federation` for M6; they **belong in `dart_grid_assets`/`flutter_grid_assets`** (their domains) and move there at the asset-repo split.
- **`butane_grid_assets`** lives in the_grid `packages/` for M6; sibling-to-`butane_flutter` placement is the later split.

## Definition of done

1. **Core hardened** (A): lease-as-Capability + fencing token + max-lifetime + FIFO queue + owner-clock reaping + idempotency key; loopback + fakes green.
2. **Membership/presence/reaping** (B): static peers; presence carries profile+capacity; owner reaps on heartbeat loss; loopback green.
3. **Capability model** (C): facts/cascade/containment-match/dart-flutter-probes/TTL-revalidation; the **dynamic-shift test** green.
4. **Compute domain** (D): command/result + bounded "use" owned by the domain; the engine names no compute detail (structural fence).
5. **Burn** (F) offline end-to-end: two orders + two channels + scripted drive + TestReport + guaranteed teardown.
6. **Invariants** (G) mutation-tested and non-vacuous.
7. **`melos analyze` clean + the full offline suite green** across all packages.
8. **LIVE cross-machine burn** (H): Studio↔`linux-dashboard` run a real butane burn; human gate, Nico present.

## Deferred (explicit — do NOT build in M6)

MQTT/pub-sub bus (HTTP/WS first); `zero_conf_grid_assets` dynamic discovery;
authentication/authorization (`Trust` impls) + sandboxing; **gang scheduling** for
multi-remote-asset formulas; **continuous lease migration** (depth #3);
priority/aging fairness (FIFO only); the **agent-to-agent BLE burn**; the
`the_grid`/`grid_sdk` package split.

## How to build (the workflow plan)

A–G are offline + independently verifiable → a **workflow** fans them out
(implement → read-only-`Explore` adversarial verify → fold), the M4-P1/Circuit
pattern. Honor the order: **A first** (the core + invariants substrate), then **B∥C∥D∥E**,
then **F**, then **G**. **Track H is the human gate — never workflow-built.** Reviewers
are **read-only `Explore`** ([[feedback-review-agents-read-only]]); prefer flat
schemas / plain-text returns for review agents (the Circuit's nested-schema lesson).
