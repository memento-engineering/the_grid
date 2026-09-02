---
status: accepted
date: 2026-07-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a44-federated-work-sources-staleness-scope-member-removal-vs
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A44"
---
## A44 (2026-07-03) — federated work sources: staleness scope, member removal vs. connection blip, and the cross-store block predicate (tg-nsj)

**Decision (AI; `grid_engine` + `grid_cli`):** built `FederatedSnapshotSource` (D-F1) fanning N LOCAL beads workspaces into one `SnapshotSource`, plus the repeatable `--workspace <substation>=<path>` grammar (D-F4, mirroring `--root`). `docs/SCRATCH-multi-root-federation.md` D-F1..D-F7 + the §4b dynamic-membership frame (D-Z1..D-Z8) specified the shape; four judgment calls were left open and are recorded here:
- **Staleness (D-Z4) excludes the WHOLE member's ready ids, not just ids that are "new" since it went stale.** The brief's "mints no NEW ready ids" is ambiguous between "freeze the ready set as of last-known-good" and "stop advertising any of this member's ready ids while its truth is unverifiable." Chose the latter (full exclusion) as the more conservative fail-closed reading: a member whose truth can't be refreshed might just as easily have STOPPED being ready as started, so keeping its stale ready ids in the union risks minting on data that may already be wrong. Its beads stay visible in `beadsById` regardless (absence ≠ deletion, D-Z3) — only the readyIds contribution is withheld.
- **`removeMember` is a distinct, harder tier from a stream error.** D-Z3's "absence ≠ deletion" is written for presence flicker (a network blip, a station going dark); `removeMember` is the operator's own deliberate un-registration (e.g. reconfiguring `--workspace` across a restart), so it drops the member's beads/ready ids from the union immediately and entirely, rather than freezing them stale. Nothing in the SCRATCH names this second tier explicitly.
- **The exploration host (leonard attach) wires to only ONE representative controller — the first-registered store — not a per-store multi-host surface.** Federation's value is the work-graph union the tree mounts from; leonard's debug attach is a secondary concern (A40) the brief never asked to fan out, so it stayed pointed at one controller rather than inventing an N-host exploration surface. Documented as a known limitation in `buildControllers`, not attempted here.
- **The cross-store guard (D-F2) keys off `DependencyType.affectsBlocking`** (blocks | parent-child | conditional-blocks | waits-for — bd's own `AffectsReadyWork` set), not the literal `blocks` type alone, so it mirrors exactly what each store's own `bd ready` already excludes for same-store edges; a same-store edge is explicitly left untouched by the guard (`continue`s past it) since the origin store's own `is_blocked` maintenance already governs it — the guard only re-applies the block for a target in a DIFFERENT store, which bd's `is_blocked` recompute never reads (`depends_on_external`).
**Why:** the SCRATCH doc pins the contracts and the fail-closed POSTURE precisely but leaves these four specific behaviors — the ready-set staleness boundary, the removeMember/stream-error distinction, the exploration host's federation scope, and the exact blocking-edge predicate — to the implementer, exactly the kind of shape decision ADR-0000 exists to catch.
**Not this:** zero-conf discovery / the `MembershipSource`/trust-gate machinery (D-Z1/D-Z6/D-Z8) is NOT built here — `addMember`/`removeMember` exist as the mutable-membership seam the brief asked for, but the only membership SOURCE wired today is the static `--workspace` flag list at boot; a future zero-conf browser is a separate bead behind the same seam. Remote/assignment federation (ADR-0011, the claim/lease bus) is unrelated — this amendment is LOCAL work-source observation only (D-A2).
**Affects:** `grid_engine`: new `bridge/federated_snapshot_source.dart` (`FederatedSnapshotSource`, `MemberFreshness`), `testing/engine_fakes.dart` (`FakeSnapshotSource.raiseError`). `grid_cli`: `station_runner.dart` (`--workspace` → `addMultiOption` + `parseWorkspaceSpec`; `StationArgs.workspaces` replaces the single `workspacePath` getter, which is kept as a deprecated back-compat alias mirroring `rootPath`/`roots`; `discoverWorkspaces` returns `Map<String, BeadsWorkspace>` + a new `defaultSubstation` param; `buildControllers` builds one `GridRuntimeBundle` per store and unions them). New tests: `grid_engine/test/federated_snapshot_source_test.dart`, `grid_cli/test/workspace_flag_test.dart`, `grid_cli/test/discover_workspaces_test.dart`.
**Status:** **Ratified by Nico 2026-07-21; the WIRING CONVENTION reversed by Nico the same day.** Ratification (live session, governor seat: "wire it up, A44 is ratified" — on reviewing the cross-store block predicate against a live probe: bd accepts a raw foreign bead-id dep target and does not block locally on it; the guard re-applies the block across the federation union; the `external:<project>:<capability>` grammar is NOT the vehicle — its stored string prefix-routes to no store and would fail closed permanently). Reversal (same session, on the bd 1.1 adoption): **bd 1.1's `bd doctor --fix` classifies raw cross-store bead-id edges as "orphaned dependencies" and silently removes them** — a routine hygiene command must never be able to sever load-bearing blocking, so the raw-foreign-id wiring convention is REJECTED ("that gotcha is unacceptable"). The guard implementation itself stands as built (it correctly enforces whatever rows exist); cross-store parking returns to the manual note convention until the tooling treats foreign-prefix ids as first-class (filed upstream: gastownhall/beads#4943). The one live wiring (the_grid `tg-q9k` blocked-by power_station `pow-60g`, 2026-07-21) was unwired the same day. Promotion into a home ADR remains open.

