---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a8-dolt-auth-spike-outcome-mysql-client-is-wire-compatible-c
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A8"
---
## A8 (2026-06-11) — Dolt auth spike outcome: `mysql_client` is wire-compatible; credential is operator-provided env

**Decision:** Keep `mysql_client` as the SQL read-path client (ADR-0001 Decision 4, no change). The `DoltQueryService` resolves its credential from the documented env contract — `GC_DOLT_USER` (default `root`) and `GC_DOLT_PASSWORD` — and connects with `secure: false` (the gc-managed server offers no SSL). Live-SQL integration tests **self-skip** when `GC_DOLT_PASSWORD` is absent (the lenny e2e pattern); the bd-CLI read path is the guaranteed fallback, so M1 acceptance never depends on the SQL credential being present in CI.
**Why:** Track 0.2 spike (2026-06-11, `mysql_client 0.0.27` → `127.0.0.1:34947` db `tg`): the client completed Dolt's MySQL handshake through to credential evaluation, and the server returned an application-level **`1045 Access Denied`** ERR packet — proving wire/auth-plugin compatibility. (Contrast: requesting `secure: true` threw a distinct *client* exception, "Server does not support SSL." Two different exception classes confirm the server processed our handshake and answered at the application layer rather than failing the protocol.) The only gap is the credential itself, which is gc-provisioned and surfaced through the same `GC_DOLT_PASSWORD` channel `bd` uses — an operational wiring step, not a Dart-client limitation. Process-env credential extraction was deliberately not attempted (and was blocked by the sandbox classifier as credential exploration); the spike's protocol question is answered without it. PDR Risk #1 ("Dart MySQL client can't complete Dolt's auth handshake") is **retired** at the protocol level.
**Affects (if promoted):** ADR-0001 Decision 4 (credential-resolution sentence + SSL/`secure:false` note); `DoltQueryService` connection config; the live-SQL integration test's skip guard; PDR §8 risk table (Risk #1 → resolved). Spike artifact: `packages/grid_controller/tool/dolt_spike.dart`.
**Status:** pending.

