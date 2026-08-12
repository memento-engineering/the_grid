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
