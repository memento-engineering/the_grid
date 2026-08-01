## 0.1.1

- Added the reusable JIT dev-mode host composition — `JoinedWorkReader`,
  `DevModeSeat`, and `armDevMode` — so any JIT-launched station can arm
  hot reload/restart without copying the host half. Previously stranded in
  a downstream station package (the_grid #111).

## 0.1.0

- Initial release: exploration-protocol host exposing the ext.leonard.* wire protocol as Dart VM-service extensions.
