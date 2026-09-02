---
status: accepted
date: 2026-07-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a47-routing-is-a-first-class-engine-primitive-stepoutcome-re
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A47"
---
## A47 (2026-07-12) — routing is a first-class engine primitive: `StepOutcome.Rewind` (promotes M5 D-4's re-key clause) (tg-o90)

**Context.** `docs/M5-THE-CIRCUIT-BUILD-ORDER.md` D-4 (Nico-ratified 2026-06-28) already states: "The route capability returns a `StepOutcome` that advances/blocks/**re-keys** the formula cursor — it never writes the work bead", with "Bounded rework rounds (factoryskills' cap 3)". But the engine shipped only THREE arms {Ok, Failed, Gate}: the re-key half had no primitive. So the first attempt (tg-b3k, PR #48) encoded it as a gate-REASON STRING convention (`respec:`) that `SessionScope` parsed and auto-resolved — a machine loop wearing a human gate's clothes. Nico's ruling (2026-07-12): routing IS a core engine primitive — the dual of fan-out — not a reason-string convention.

**Decision (AI; `grid_engine` + a `grid_cli` de-dup):** promote D-4's re-key clause into the engine as a FOURTH `StepOutcome` arm, `Rewind({stepIds}, reason)`.
- **The arm.** `Rewind` names SIBLING steps of the rewinding node's OWN circuit. `CapabilityHost` writes `state=pending` + a bumped per-node `rewindCount` + `restartCount=0` on those steps ∪ every node transitively DOWNSTREAM of them ∪ ITSELF, in ONE merge-safe write through the chokepoint onto the_grid's OWN session bead (A37). A rewound `SubCircuitStep` expands to its WHOLE subtree (else its `complete` descendants keep satisfying the parent's dep and it never re-runs). The allocation layer maps it to a DISTINCT `AllocationRewound` report — never folded into `AllocationGated`/`AllocationFailed`.
- **`rewindCount` is a SECOND incarnation axis**, beside `restartCount` (D-5), and part of the reconcile key (`ValueKey('$path#$restartCount.$rewindCount')`). So a rewound node RE-KEYS: keyed reconcile disposes (KILLS — ADR-0009 D4) a still-mounted effect and re-runs it virgin, rather than leaving it alive under a stale incarnation. The bump is monotonic PER NODE (a shared round number could equal a node's existing count and silently skip its re-key). Two axes, not one: a rework round never spends the supervised-restart budget, and a crash never spends a rework round.
- **No gate bead, no session re-mint.** `Gate` (D-7) parks for a human and is UNTOUCHED — its park is non-lossy (the subtree keeps its cursor and re-mounts where it parked). `grid rework` (tg-x1j) retires a round and re-mints. `Rewind` is the third, in-session thing: a deliberately LOSSY, virgin re-run of a sub-DAG inside the LIVE session, in the same workspace, with no human in the loop.
- **Bounded (D-4's cap).** The host REFUSES a rewind from a node whose `rewindCount` reached `kMaxReworkRounds` (3) and parks at a human `Gate` instead — the BELT. An asset's route escalates on its own policy first, reading its own `rewindCount` back through the ambient `SiblingView` (D-5's sibling-read affordance; a read of already-observed state — no new subscription, no write). An empty/dangling `stepIds` routes to a supervised `Failed` naming the offending id — LOUD, never a silent "re-run only myself, forever" (ADR-0008 D3's guard principle).
- **Salvaged from PR #48:** the round contract (`kMaxReworkRounds` + the retired-round `work_bead` key shape) is lifted into `grid_engine`'s `src/domain/rework.dart` and `grid_cli`'s duplicate cap const + round regex are deleted, so the engine's `Rewind` and the operator's `grid rework` admit exactly the same number of rounds. **DROPPED from PR #48:** `kRespecGatePrefix`/`isRespecGate`/`machineActionableGate` (the engine never parses a gate reason) and the `SessionScope` gate auto-resolve; PR #48's `SessionProjection.openGates`/`reworkRounds` are NOT lifted either — nothing would read them, and ADR-0008 D3 rules out shipping unread state. Both are fenced by a structural test.
**Why:** the ratified clause named a cursor RE-KEY, and the engine had no primitive for it — so the first implementation reached for a string convention the spec committee graded D. Adding the arm is what the ratified sentence actually says; it also unifies landing/rework/escalate onto ONE primitive (the follow-up bead).
**Not this:** `Gate` semantics, the D-7 park/re-arm, and the `grid rework` verb are unchanged (a non-regression fence pins the human gate). `restForOne` transitive re-keying, `FanOutStep`, and restoration stay deferred.
**Affects:** `grid_engine` (`StepOutcome`/`AllocationReport` gain an arm; `NodeCursor.rewindCount` + its codec; the pure `rewindNodePaths` predicate; `StepMount` carries its `circuit`/`circuitPath`; the reconcile key carries both axes; `CapabilityHost._persistRewind`) + `grid_cli` (round-contract de-dup). **BREAKING for downstream exhaustive `StepOutcome` switches** — power_station's assets are the ASSET-SEAM follow-up bead (cross-store, ordered manually: `respec.dart`'s `SpecRespec -> Gate(respecGateReason(ledger))` flips to `Rewind({specifyStepId}, reason)`, and `specify` folds into the spec circuit as `route`'s sibling). grid_engine 325 offline tests + grid_cli 75 green (full workspace 325/75/63/129/164/13/15); `melos analyze` clean.
**Supersedes:** tg-b3k / PR #48 (the gate-reason-string workaround), held for salvage only.
**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into a home ADR (an ADR-0008 decision / the M5 D-4 clause) or dispose at will.

