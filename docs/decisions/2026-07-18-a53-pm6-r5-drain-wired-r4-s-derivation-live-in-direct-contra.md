---
status: accepted
date: 2026-07-18
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a53-pm6-r5-drain-wired-r4-s-derivation-live-in-direct-contra
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A53"
---
## A53 (2026-07-18) — `pm6-r5-drain` wired R4's derivation live in direct contradiction of A52's own recorded disposition; reverted during tg-pm6 remediation (tg-pm6 remediation pass)

**Context.** A52 (2026-07-17, rung `pm6-r4-frontier`) logged `derivedGeneration`'s WIDTH-vs-TEMPORAL-round gap as unresolved and recorded an explicit disposition: "`live_frontier.dart`'s doc comments... state plainly... that R5b/R5 must not wire `effectiveCursor`/`derivedEscalation` live before this is resolved." The subsequent rungs `pm6-r5b-host` (402ff1a / d3e9095) and `pm6-r5-drain` (fa72be4, the FINAL landed commit of the tg-pm6 build) wired exactly that: `SessionScope.build()` (`circuit/session_scope.dart`) called `effectiveCursor`/`invalidatedNodes`/`derivedEscalation` live for every molecule-mode session, directly contradicting A52's own already-recorded guard — caught by a post-hoc completeness review, not by the build's own gate (no test asserted the guard's absence-of-wiring; `test/molecule/drain_seam_test.dart`'s "R4 wired live" group instead PROVED the wiring was present and passing, which is exactly what should not have shipped).

**Decision (this pass, tg-pm6 remediation, no new design).** Reverted `SessionScope.build()`'s molecule arm to project the RAW `projectMoleculeCursor` output, unmodified — matching A52's disposition exactly, not resolving A52's underlying semantic question. Forward motion (dependency-driven eligibility) is unaffected; backward motion (rework/invalidation) is not yet live for molecule-mode sessions, exactly as A52 already specified it should not be. `drain_seam_test.dart`'s "the drain seam — end-to-end derivation (R4 wired live)" test is marked `skip:` (not deleted) with a comment pointing back here and to A52 — it remains the correct spec for once A52 resolves and the wiring is restored. `live_frontier.dart`'s functions and their own pure unit tests (`live_frontier_test.dart`) are untouched — they still fully and correctly exercise the (semantically unresolved) derivation in isolation.

**Why not fix the underlying semantics instead.** A52 already rules that out explicitly: both directions of a real fix (a new persisted temporal counter, or redefining what `kMaxReworkRounds` means for the molecule model) "cross a line only Nico can rule on," and picking either "would edit a ratified contract's meaning without ratification." Nothing in this remediation pass changes that calculus; reverting the wiring is the only move available that does not require making that call. `packages/grid_runtime`'s `StationProcessLeaseVendor` (R3) being uncomposed anywhere in production (a separate, independently-real gap: `CapabilityHost._persistStarted` only asserts the vendor's presence and never calls `leaseFor`/`acquire`, and no composer builds the real `ProcessSpawner`/`ProcessDispatcher`/`StepMetadataReader`) is left as-is for the same reason — actually wiring it is a substantial new feature build (routing `CapabilityHost`'s process allocation through `LeaseCapability` instead of the unchanged `ProcessAllocation` path), not a bug fix, and it is currently fully inert: `circuitMintMode` defaults to `flatCursor` and no shipped composition (grid_engine or space_station) ever sets it to `molecule`. Two stale comments claiming this wiring "lands at `pm6-r5-drain`'s kernel-root provision" (`process_lease_vendor.dart`, `capability_host.dart`) were corrected to say plainly that it did not, so a future reader is not misled into believing it already happened. *[Correction, Nico-directed 2026-07-19 (tg-eli, phase 2): the flat-cursor path (`CircuitMintMode`, `flatCursor`) was subsequently deleted; molecule is now the only circuit engine, so this entry's "defaults to `flatCursor`" description is historical, not current.]*

**A gap this surfaces beyond A52's original scope:** A52's disposition was recorded but never enforced by any test or lint — a rung landing AFTER the disposition was written violated it silently, and the build's own gate (analyze/test/format) had no way to catch a "should not be wired" contract. No such enforcement is added here either (a real check would need to distinguish "R4 functions called from tests" from "R4 functions called from production `SessionScope`," which is more machinery than this remediation pass should add unreviewed) — flagged as a possible follow-up, not built.

**Not this:** no persisted field is added; no new spawn/dispatch wiring for `ProcessLeaseVendor` is built; `kMaxReworkRounds` is unchanged; `live_frontier.dart`'s own semantics and tests are unchanged; the flat model is untouched.

**Affects (if promoted):** Same surface as A52 — `DESIGN-tg-pm6.md` §8/§12, `circuit/session_scope.dart`, `molecule/live_frontier.dart`, `test/molecule/drain_seam_test.dart`'s skipped test. Promoting A52 (either direction) should also re-wire `session_scope.dart`'s molecule arm and un-skip the test. Separately, actually landing R3's real process-lease wiring (`ProcessSpawner`/`ProcessDispatcher`/`StepMetadataReader` + routing `CapabilityHost` through `leaseFor`) is its own follow-up rung with its own design/build/review cycle — not scoped to this entry.

**Status:** **RESOLVED with A52 (Nico, 2026-07-18)** — the revert stands as the correct disposition; the re-wiring of `session_scope.dart`'s molecule arm and the un-skip of `drain_seam_test.dart` land with tg-43o's a2 implementation (supersedes-chain depth).

**Status:** **RESOLVED — Ratified (a2) by Nico, 2026-07-18.** Ruling: rework rounds become **successor incarnation beads on a `supersedes` chain** — when the derivation finds a step invalidated and the engine re-mounts it, it mints a NEW step bead that `supersedes` the prior incarnation; `derivedGeneration` = supersedes-chain depth, derivable from any snapshot. History is **graph structure, never a mutable counter** (Nico: "always prefer deriving state from state instead of managing it"). This preserves item 7 exactly (nothing bumps a counter; no route writes onto another node; the old bead stays terminal with its verdict), restores the ratified M5 D-4 temporal semantics (a single recurring critic → depth 1, 2, 3 → gates at the cap; a 3-critic committee failing the first draft → depth 1, three full rounds granted), and dissolves the R4 re-key residue (new bead id → new breadcrumb → new `ValueKey`). Implementation: tg-43o. Width may return only as a possible SECONDARY escalation trigger (unanimous hard failure → immediate human attention), never as the cap's axis.

