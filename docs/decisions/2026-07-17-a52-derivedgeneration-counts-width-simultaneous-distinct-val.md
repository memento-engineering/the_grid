---
status: accepted
date: 2026-07-17
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a52-derivedgeneration-counts-width-simultaneous-distinct-val
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A52"
---
## A52 (2026-07-17) — `derivedGeneration` counts WIDTH (simultaneous distinct `validates`-source stamps), not the ratified TEMPORAL rework-round count — surfaced unresolved (tg-pm6 pm6-r4-frontier)

**Context.** R4's `live_frontier.dart` (`packages/grid_engine/lib/src/molecule/live_frontier.dart`) derives `derivedGeneration` — the value written into `NodeCursor.rewindCount` by `effectiveCursor` and read against the M5 D-4-ratified `kMaxReworkRounds` cap (`domain/rework.dart:36`, "Bounded rework rounds … cap 3"). `DESIGN-tg-pm6.md` §8's own pseudocode names the intended axis explicitly: "a deterministic count of the **invalidation rounds** observed against this node's stamps — NOT a persisted `rewindCount`" (§8 line 320-321), and its acceptance criteria call for `derivedGeneration` to "increment monotonically **on repeated invalidation**" (§8 line 368, Tests). The FLAT model's own `Rewind` mechanism (A47) counts this same axis TEMPORALLY and correctly — `capability_host.dart:588` bumps a per-node counter by **+1 on every rewind**, monotonic in time. The delivered R4 implementation instead counts **WIDTH**: the number of DISTINCT `validates`-source steps stamped `F` *simultaneously*, recomputed fresh from the snapshot every call (`live_frontier.dart:23-34`'s own doc comment states the reasoning: item 7 forbids a persisted counter, and a temporal round count "would require a persisted history item 7 forbids", so width was substituted as "a genuinely deterministic, snapshot-pure" stand-in). This substitution was made silently in code comments during the build, never logged here — the gap was only caught in R4's code review (rung `pm6-r4-frontier`).

**The two directions this inverts (both provable from the delivered fixture, `test/molecule/live_frontier_test.dart`):**
1. **Under-escalation.** A single critic that keeps failing the SAME build every round yields `width = 1` forever (only one distinct source), so `derivedEscalation` never fires — the exact non-terminating rework loop `kMaxReworkRounds` exists to bound never escalates. Worse: because `rewindCount` stays `1` across every round, the reconcile key `ValueKey('$path#$restart.$rewind')` (`circuit_scope.dart:100`) never changes past the FIRST invalidation either — the daemon re-key test at `live_frontier_test.dart:365` only proves the single `0→1` transition; a second successive round from the SAME recurring source cannot be proven to re-key at all under width semantics (the minor finding below).
2. **Over-escalation.** The committee shape is 2-3 simultaneous critics (`_committee`/`_codeCircuit`, the established swarm pattern). A bad first draft failing all 3 critics on its FIRST review yields `width = 3 = kMaxReworkRounds` and GATES immediately — zero rework rounds granted, violating the ratified 3-round budget on the very first pass. `live_frontier_test.dart:439` ("AT kMaxReworkRounds") encodes this as a passing golden today.

**Why this is not fixed here.** Both directions trace to the same root tension the design doc does not resolve: item 7 (DECIDED, conflict-5 resolution B, `DESIGN-tg-pm6.md` line 74) explicitly REMOVES a persisted `rewindCount` from the molecule model's key set — "incarnation is derived from stamps" — yet a genuine TEMPORAL round count is, by construction, a fact about history, and a snapshot with no persisted history cannot recover it. The two ways out both cross a line only Nico can rule on: (a) add a NEW durable per-step marker distinct from the flat `rewindCount` (e.g. a monotonic re-run/incarnation stamp) — which functionally reintroduces the persisted counter conflict-5 deliberately removed, just under a different key name; or (b) keep the snapshot-pure width derivation and explicitly RE-DECIDE what the cap means for the molecule model (a width cap is a real, different, and possibly still-useful bound — "too many simultaneous objections park for a human" — but it is not the ratified "3 rework rounds" contract from M5 D-4, and reusing `kMaxReworkRounds` for it silently overloads a cap two mechanisms (`Rewind` and this derivation) now disagree about the meaning of). Silently picking either would edit a ratified contract's *meaning* without ratification — exactly what this register exists to prevent.

**Disposition applied instead (this pass, tg-pm6 review-fix, no behavior change):** `live_frontier.dart`'s doc comments (library doc + `derivedGeneration` + `effectiveCursor`) now cross-reference this entry and state plainly that width is a stand-in, not the ratified axis, and that R5b/R5 must not wire `effectiveCursor`/`derivedEscalation` live before this is resolved. The suggested successive-round golden (`derivedGeneration` monotonic across TWO invalidation rounds from one recurring source) is NOT added as a failing test — it would red-gate the house build; its absence is called out in a code comment at `live_frontier_test.dart:365` instead, pointing here.

**Not this:** no persisted field is added; `kMaxReworkRounds` (`domain/rework.dart`) is unchanged; the flat model's `Rewind` mechanism (A47) is untouched and unaffected — this is scoped entirely to the molecule model's derivation.

**Affects (if promoted):** `DESIGN-tg-pm6.md` §8 (either the derivation gains a new durable signal, or its Tests section's "increments monotonically on repeated invalidation" acceptance criterion is corrected to describe width, and the cap comparison in `effectiveCursor`/`derivedEscalation` is decoupled from `kMaxReworkRounds` onto its own named constant). Code: `packages/grid_engine/lib/src/molecule/live_frontier.dart` (`derivedGeneration`, `effectiveCursor`, `derivedEscalation`), `test/molecule/live_frontier_test.dart` (the `AT kMaxReworkRounds` golden and the daemon re-key test would both need to change under either resolution).

