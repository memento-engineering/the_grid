## 0.3.0-rc.4

- Breaking: requires `leonard_contract ^0.2.2` (genesis_perception 0.3.0 / genesis_tree 0.3.0). Migration: consumers on genesis_tree 0.2 stay on rc.3; consumers on 0.3 bump `genesis_tree` to `^0.3.0`. This is the release that lets grid_cli resolve from pub.dev again (rc.9 pinned genesis_tree 0.3 while this package still reached genesis_tree 0.2 through leonard_contract 0.2.1).
- Deprecated: `DevModeSeat` is renamed to `DevModeHost` (#249). The deprecated `DevModeSeat` typedef remains throughout 0.3.x and will be removed in 0.4.0.

## 0.3.0-rc.3

- Fix: the published archive ships the DevTools extension bundle again — the
  rc.2 archive dropped it via an over-broad ignore (tg-tzf0, #203). No API
  changes.

## 0.3.0-rc.2

- Republished to close a version/content divergence (see note below).

  NOTE: the previous version was published and the package then kept accruing
  source without a bump, so the hosted archive and the in-repo sources at that
  version differed. Local builds passed on path overrides while hosted
  resolves got stale code. This release re-syncs them.

## 0.3.0-rc.1

- Breaking: tracks beads_dart 0.2.0-rc.1 — the `bd export` retirement. No
  exploration API change of its own; the constraint bump is the breaking part for
  resolvers.

## 0.2.0

- Breaking: the VM-service surface speaks `ext.leonard.*` (protocol version 2)
  via `leonard_contract`; `ext.exploration.*` is retired. Attach tooling must
  be on `leonard_*` 0.2.x.

## 0.1.1

- Added the reusable JIT dev-mode host composition — `JoinedWorkReader`,
  `DevModeSeat`, and `armDevMode` — so any JIT-launched station can arm
  hot reload/restart without copying the host half. Previously stranded in
  a downstream station package (the_grid #111).

## 0.1.0

- Initial release: exploration-protocol host exposing the ext.leonard.* wire protocol as Dart VM-service extensions.
