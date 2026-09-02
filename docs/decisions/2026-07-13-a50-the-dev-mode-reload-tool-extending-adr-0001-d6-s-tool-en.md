---
status: accepted
date: 2026-07-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a50-the-dev-mode-reload-tool-extending-adr-0001-d6-s-tool-en
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A50"
---
## A50 (2026-07-13) — the dev-mode `reload` tool: extending ADR-0001 D6's tool enumeration, and why it is not a second trigger surface (tg-zts / RS-9)

**Context.** Nico's standing instruction is that the main station runs JIT with the VM service open (`dart bin/space.dart up … --enable-vm-service`), not the AOT binary. Landed code changes therefore needed a down/up/recompile bounce to activate — which kills every running agent. The enabler already existed: genesis's keyed reconcile IS the re-mount machinery. What was missing was an operator affordance to trigger it.

**Decision (AI; `grid_exploration` + `grid_sdk` + `grid_cli`).** A sixth tool, `ext.exploration.grid.reload`, joins the `grid` namespace — the first that MUTATES the host process rather than observing it. It is contributed by an OPTIONAL `ReassembleTool` that a station composes only in dev mode, and it is registered and advertised by `GridExplorationHost` — the sole registrar — so a registered tool remains a discoverable tool. With no contributor (every AOT / non-dev composition) the host is byte-for-byte what ADR-0001 D6 ratified: `GridControllerPlugin.tools` stays the closed, read-only `requery`/`snapshot`/`ready`/`events`/`stats`.

Two modes, both re-composing through the EXISTING configuration scope (the tree's one root observer): `reload` re-runs the master build on the same delegate (new code bodies in place); `restart` re-runs a `runGrid(delegateFactory:)` and re-composes on a fresh delegate. Neither pokes the root (ADR-0007 Decision 2). **The trigger is explicit only** — an in-process filesystem watcher (an auto-reload-on-save would fire mid-build on a resident `--land` station) and a bare OS signal (un-introspectable) were both rejected.

**Session preservation is the whole point, and it FALLS OUT of reconcile — no adopt path was added.** A re-composition unmounts nothing, so no `CapabilityHost` disposes, so no `Allocation` is killed (**ADR-0009 D4** — `dispose` = KILL) and the running agent survives; `SessionScope` re-mounts under the same key and ADOPTS the persisted session bead with its cursor untouched (**ADR-0008 D-2** — adopt-or-mint ONCE). Only a genuinely re-keyed node re-runs. Proven at the transport (the fake provider's `stopped` stays empty across both verbs) with a positive control (teardown DOES kill).

**Where this belongs.** tg-zts is filed as **RS-9 under epic tg-3s8** (the resident-station ladder), because it extends that epic's own surfaces: RS-2's station lock (a new `vmServiceUri` field, advertised in the 0600 lock like the RS-4 bearer token — it carries the service auth code), RS-5b's verb family (a new `reload`), and the D-C1/D-C4 posture RS-4 was built to. The graduation of `docs/SCRATCH-resident-station.md` into **ADR-0013** (tracked as `tg-8gv.4`, deferred) is the promotion path for the two distinctions below: ADR-0013 should fold them in rather than leave them here. *[Correction, Nico-directed 2026-07-19 (D-P7, public-readiness pass): ADR-0013 was subsequently assigned to state-holding-value-types (2026-07-12), so the residency graduation target named here is now **ADR-0014**; the lifecycle-hooks ADR takes 0015.]*

**Why it is not a second trigger surface** (SCRATCH-resident-station D-C2: "the control plane cannot be a trigger"; D-C4: "One trigger surface in the whole system: a bead going ready in the owned store"). Those clauses govern WORK intake — the named failure is a drive-list flag or a control endpoint that lets a misbehaving agent or a confused human make the station work on something. `reload` triggers no work: it enqueues nothing, mints no bead, writes no store, and cannot change the ready set or the frontier. It re-composes the tree over the SAME observed work, and an unchanged frontier re-adopts every live node and spawns nothing — an ACCEPTANCE CRITERION with a test, not an argument (no new resolve, no new spawn, ZERO new bd writes across a reassemble). bd remains the only mutation surface, signals remain the only lifecycle surface, and `station_control.dart` is untouched: still GET-only, still no mutation route. What `reload` changes is the CODE the station runs, not the WORK it does.

**Why it rides the exploration wire** (D-C1: "the control plane does NOT ride perception/exploration … `GridExplorationHost` stays exactly as-is … no host changes in this pass"). D-C1's concern is that the CONTROL PLANE must not be built on the debugging surface; its own rationale calls perception "a fancy logger + tool calls for a debugger, and lenny is a dev tool" — and a hot reload IS a debugger tool call, the same class as Flutter's, reachable only where a debugger is (`--enable-vm-service`, exactly the dev-mode surface D-C1 reserves). This adds no transport seam and no control-plane route. It IS a host change, made knowingly in a LATER pass than the one D-C1 scoped, and it is strictly additive: absent the contributor, nothing about the host moves.

**Rails on a hot RESTART.** The fresh delegate takes the POST-MOUNT rails (`initGrid` → `onReady`) but NOT `didLaunch`: that rail is defined pre-tree and terminal ("nothing mounts" on failure), and a restart mounts no new tree — re-running it would let a fresh delegate's throw kill a live station with agents mid-build, which is precisely what this bead exists to prevent. The retired delegate is unsubscribed, then disposed; its `onTeardown` does NOT run (the grid did not tear down — the delegate was replaced).

**The client's ORDER is a safety property.** `reload` swaps the sources FIRST (`reloadSources`) and re-composes only once the VM ACCEPTED them; a compile error in the landed code REFUSES before the tool is ever invoked, so a broken tree is never composed and the running agents keep running.

**Alternatives rejected.** (a) Registering the extension from `grid_sdk` via `dart:developer`: the tool would be invocable but INVISIBLE to the handshake's tool list, and it would put the `ext.exploration.*` namespace in a package ADR-0002 does not make its owner. (b) Adding `reload` to `GridControllerPlugin.tools`: it would make the read-only observation plugin a mutating one — the scoping D6 gives it.

**Affects:** `grid_exploration` (`reassemble_tool.dart` — `ReassembleTool`/`StationReassemble`/`stationVmServiceUri`; the host's optional contributor + the union `toolNames` the handshake AND the registrar read + the construction-time collision refusal). `grid_sdk` (`run/reassemble.dart` — `ReassembleMode`/`ReassembleRequest`/`ReassembleBus`/`ReassembleReport`; `runGrid(delegateFactory:)` + `GridHandle.hotReload`/`hotRestart`; the configuration scope observes the reassemble axis). `grid_cli` (`StationLockRecord.vmServiceUri` + `withVmService`/`updateVmService`; `station_reload.dart`; `reload_command.dart`; `vm_service` dep). New tests: `hot_reload_test.dart` (5, incl. the adoption proof + the positive control), `station_reload_test.dart` (7), `reload_command_test.dart` (4), `reassemble_mode_pin_test.dart` (1, the cross-package wire pin), `reload_vm_roundtrip_test.dart` (1, `integration` — a REAL VM service re-composes a REAL tree), + 4 host gates. grid_sdk 80 / grid_exploration 17 / grid_cli 101 offline green; `melos analyze` clean. The companion (space_station's `up` composing the tool + advertising the URI, and binding the verb) is its own bead, in its own store.

**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into a home ADR (ADR-0013's graduation of the resident-station doc is the natural home; the D6 extension may also warrant an ADR-0001 amendment) or dispose at will.

---

