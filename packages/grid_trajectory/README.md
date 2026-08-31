# grid_trajectory

The trajectory log substrate (tg-zfek Stage 0): one append-only `trajectory`
table in a separate `trajectory` database on the grid home's dolt server, with
the machinery to write it safely and read it forensically. The contract is
`docs/design/trajectory/trajectory-schema.md` at the repo root — §1 envelope,
§2 record types, §4 DDL, §5 append discipline.

A **leaf package** by decision (`docs/decisions/2026-08-31-grid-trajectory-leaf-package.md`):
zero `grid_*` dependencies. Stations compose it explicitly — `grid_cli` wires
the `traj` command group; nothing here mounts itself.

## The direct-SQL exception

This package **writes a dolt database over direct SQL**. That is designed, not
drift: the bd-CLI-only-writes rule governs the LEDGER database only, and the
`trajectory` database's sole appender is this service. The scope and its
limits are pinned in
`docs/decisions/2026-08-31-trajectory-direct-sql-scope.md` — never bd's proxy,
never bd's pid/lock/secret files, a dedicated `trajectory` SQL user granted on
`trajectory.*` only.

## Barrel sections (`lib/grid_trajectory.dart`)

| Section | What it holds |
|---|---|
| `codec` | §1 envelope, the sealed §2 record types (50), idem-key grammar, `(record_type, type_version)` registry |
| `connect` | server-listener resolution, the write-capable session + connect-time guards (force-commit ban, branch pin), §5 error-code classifiers |
| `ddl` | §4 DDL verbatim (dolt_ignore-first, idempotent), SQL-user provisioning |
| `append` | the fenced append client: epoch claim, T6i counter-CAS, belt predicates, the §5 error contract, the stdout+flare event seam |
| `tick` | the §5 service-tick skeleton: interval loop, fence skip, run-to-fixpoint |
| `cli` | the `traj` verbs (`show`, `shadow-diff`) and the read seam they run over |

## Testing

`dart test` runs the offline suites; `dart test -t integration` additionally
drives a hermetic `dolt sql-server` (fail-closed: no dolt on PATH is a RED
run, per `docs/decisions/2026-08-31-stage0-guards-gate-prs.md`).
