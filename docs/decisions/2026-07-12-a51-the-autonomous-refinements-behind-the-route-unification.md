---
status: accepted
date: 2026-07-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a51-the-autonomous-refinements-behind-the-route-unification
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A51"
---
## A51 (2026-07-12) — the autonomous refinements behind the route unification (tg-6gn / M5 D-4a)

**Context.** M5 D-4a + D-4b (RATIFIED, Nico, 2026-07-12) promote routing to a first-class engine primitive: a `RouteCapability` returns a distinct sealed `RouteVerdict {advance, rewind, escalate}`, `StepOutcome` narrows to `{Ok, Failed}`, `CapabilityHost` becomes the ONE router, and `deliver` replaces `land` as the ACTUATION of a terminal `advance`. **That design is human-ratified and is NOT re-logged here.** What follows are only the choices the design left open, made autonomously while building it.

**Decisions (AI; `grid_engine` + `grid_sdk`).**

1. **`EscalationDecision` has TWO arms — `ParkAtGate` and `FailToSupervision`.** D-4a says an escalate "raises to a bound handler", but not what a handler may answer. A handler that cannot ABSORB an escalation (a full queue, an unreachable governor) could otherwise only park — and an escalation nobody owns would be indistinguishable from a park somebody does. The decline arm is LOUD (ADR-0008 Decision 3: LOUD or GONE): it routes the node to supervision instead of minting a gate bead nobody will resolve. A THROWING handler lands there too.

2. **`SourceControl` NARROWED to workspace provisioning.** `canLand`/`commitAll`/`push`/`openPr` and `PrRef` are DELETED from the engine SDK: commit / push / open-a-PR are DELIVERY detail, and they belong behind the substation's bound `DeliveryMethod` (ADR-0008 Decision 5 — the engine knows a domain in CONCEPT, never in DETAIL). The three literals join the opinion-free structural fence, so the engine now names no delivery detail *structurally*, not merely by convention. The four surviving members (`workspaceFor`/`branchFor`/`baseBranch`/`provisionWorkspace`) are the only ones the engine calls.

3. **A `DeliveryMethod`/`EscalationHandler` receives plain VALUES, never a `TreeContext`** (ADR-0013 items 1/4). The router reads every ambient value it needs SYNCHRONOUSLY at entry (the effect verb, on a still-mounted branch) and hands them over on a `DeliveryRequest`/`EscalationRequest`, so a long push/PR round-trip can never race an unmount into a thrown tree lookup. The `EscalationRequest` HOLDS the node's spent `rewindCount` (ADR-0013 item 2: the distinguishing identity rides IN the value), so a policy handler can tell "the route declined" from "the loop hit its cap" without probing the world. A MIS-COMPOSITION — a bound method under a tree that mounts no ambient `Bead`/`Workspace` — refuses LOUD to supervision rather than silently stranding the work.

4. **Delivery is keyed off `isDeliveryTerminal` = the ROOT circuit's `terminalStepId`** (`circuitPath == beadId`, since `SessionScope` mounts the root `CircuitScope` at the work bead id). A SUB-circuit's terminal advance therefore never delivers: only the work bead's own terminal route closes the work out of the station.

5. **The rework cap refuses THROUGH the bound handler.** A47's belt (`kMaxReworkRounds`) is PRESERVED and merely re-homed under the router: at the cap the router escalates instead of rewinding again, and the default `HumanGate` reproduces the old park EXACTLY (`state=gated` + one real `type=gate` bead through the chokepoint). The cap no longer assumes the authority is a human; it just refuses to spin the loop.

6. **`RouteAllocation` is a FOURTH allocation family**, added through ADR-0009 Decision 4's polymorphic `createAllocation` seam (an addition, not a core edit), with the graduated one-shot lifecycle of Decision 6. A throwing route body routes to supervision as `Failed` — never an unhandled zone error (the per-work fail-closed posture, ADR-0008 Decision 10).

**Why.** D-4a's doctrine is that the engine owns the VERBS and the asset owns the TARGETS. Each choice above pushes a domain detail out of the engine (the delivery destination, the escalation authority) while keeping the engine's own refusals loud and its writes on the one chokepoint.

**Not this.** No new authority is hardcoded: an unbound substation still parks at a human gate, and an unbound delivery is COMMIT-ONLY (the posture the retired `--land` flag expressed as "unarmed"). Retiring `buildLandOps` moves the ARMING from a station-level boolean to a per-substation binding — it does not change what landing does.

**Scope fence.** **ADR-0006 Decision 3 (branch-per-bead, push-to-PR, never auto-merge) is PRESERVED, not amended.** With no method bound a terminal advance is commit-only; with the asset's bound method it is still push → PR → nothing auto-merges. The three landing MODES (pr-no-merge / pr-merge-queue / direct-merge), the CI-status integration a merge-queue needs, the post-merge reaping, and the **D3 amendment that would reverse "never auto-merge"** are bead **tg-hlz** (P1, deferred) — which FILLS this seam. This bead only DEFINES it, and proves it admits two different methods under two different substations with no engine change.

**BREAKING — hand-landed with two downstream companions.** `StepOutcome` loses `Gate`/`Rewind` (A47 flagged this break in advance); `AllocationGated` → `AllocationAdvanced`/`AllocationEscalated`; `SourceControl` loses its four delivery members; `PrRef` and `buildLandOps` are deleted. The companions land BY HAND alongside this: **power_station** `grid_assets` (the Gate/Rewind construction sites → `RouteVerdict`; `LandCapability` → a `DeliveryMethod`) and **space_station** `up_command.dart` (drop the retired `--land` seam). A review gate on the breaking cross-repo surface is EXPECTED — it flags the hand-land, it is not a defect.

**Affects:** `grid_engine` (new `sdk/route.dart` — `RouteVerdict`/`Advance`/`Rewind`/`Escalate`, `RouteCapability`, `RouteAllocation`, `isDeliveryTerminal`, `DeliveryMethod`/`DeliveryRequest`, `EscalationHandler`/`EscalationRequest`/`EscalationDecision`/`ParkAtGate`/`FailToSupervision`/`HumanGate`; `sdk/capability.dart` narrowed + `ServiceBundle.delivery`/`.escalation`; `sdk/allocation.dart`; `sdk/lease.dart`; `domain/session_bead.dart` `ResultKeys.delivery`; `circuit/capability_host.dart` = THE ONE ROUTER; `testing/engine_fakes.dart` + 3 public fakes). `grid_sdk` (`work/work_assembly.dart` — `buildLandOps` deleted, `ghRunner` kept). New tests: `route_verdict_test.dart` (14 — the whole primitive end-to-end over the recording chokepoint), the ONE-ROUTER structural fence + its meaningfulness control, `land_seam_retired_test.dart`. grid_engine 418 / grid_sdk 81 offline green; whole-workspace `dart analyze` clean. NON-REGRESSED: the completion fence (A49/#54) and hot reload (A50/#55).

**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into a home ADR (M5's own doc, or ADR-0008's Decision 5 family) or dispose at will.

