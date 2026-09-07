---
status: accepted
date: 2026-09-07
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor (agent seat)"
informed: []
register:
  spec: 1
  slug: station-control-is-the-operator-and-ui-wire
  surfaces:
    - "packages/grid_cli/lib/src/**"
    - "packages/grid_devtools/**"
    - "packages/grid_cockpit_ui/**"
  obsoletes: []
  updates:
    - adr-0014-the-resident-station
  obsoleted-by: null
  updated-by: []
  bead: tg-oz2y
  legacy-id: null
---

# No operator or UI contract depends on the VM service — StationControl is the wire

## Context and Problem Statement

The station has always been run JIT (`dart run --enable-vm-service`), and a
family of tools grew on the VM service that keeps open: hot reload, the
leonard/exploration host, the `grid_devtools` DevTools extension, and the
governor's own `evaluate` probes into private engine state. On 2026-09-07,
ruling on `tg-0edw` (grid_devtools web auto-connect) after learning that
`packages/grid_devtools` has no desktop target and is a `DevToolsExtension`
host that exists only inside a VM-service-attached DevTools, Nico ruled:
"add targets if we need to. The grid and the UI needs to work on AOT builds and
not just JIT builds with the vm service."

An AOT binary has no VM service. `space_station_assets`'s `dev_mode.dart`
already models this (`DevModeHost` is null when `vmServiceUri` is null on an
AOT binary), and the `engineering.memento.space` LaunchAgent template execs a
compiled binary that was never built — the intent existed, the proof never did.
ADR-0014 D-C2 defines `StationControl` as a dedicated HTTP surface and
ADR-0012 re-homes the cockpit server onto it; this entry names it the only
contract.

## Decision Outcome

Every operator and UI contract rides `StationControl` — the authenticated HTTP
`/status` door and the WS `/stream` door in
`packages/grid_cli/lib/src/station_control.dart` — and nothing else. Concretely:

* The VM service, hot reload, the leonard/exploration host, and DevTools
  extensions are DEV-MODE conveniences. A feature, a test, or an operator
  playbook that only works with `--enable-vm-service` is not a contract.
* Any fact an operator needs to run the station (today: admission
  reservations, mount-eligibility refusals, the cached read-failure set) must
  be served on `/status` before it can be relied on; reading it over the VM
  service is a stopgap, never the design.
* A standalone UI targets a desktop platform (macOS first) and speaks only
  `StationControl`; it carries no `vm_service`, `dtd`, or
  `devtools_extensions` dependency. `grid_devtools` stays a DevTools extension
  and is a JIT-side host of the same client layer.
* The station must boot and drive from an AOT binary (`dart compile exe`).
  lunar_station's "JIT only — never a compiled binary" operating rule is
  retired once that boot is proven.

### Consequences

* Good, because a compiled station can run under launchd/systemd with no VM
  service exposed, and one wire serves the CLI, the cockpit, and the extension.
* Good, because the UI stops depending on an IDE (DTD workspace roots) to find
  the station.
* Bad, because the governor's fastest diagnostics (VM-service `evaluate` into
  private engine fields) become dev-only; every such fact costs a `/status`
  field to keep.
* Bad, because hot reload — the reason the resident was JIT — is no longer a
  guaranteed operating mode; a bounce is the contract for picking up code.

### Confirmation

An AOT-compiled lunar boots `up --no-dry-run` from the binary, drives one
round to a landed PR, and `lunar status` reads it over `/status`; the beads
filed under `tg-oz2y` carry the receipts.
