---
status: accepted
date: 2026-08-31
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: trajectory-direct-sql-scope
  surfaces:
    - "packages/grid_trajectory/**"
    - "packages/beads_dart/lib/src/services/dolt_query_service.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-bia4
  legacy-id: null
---

# The bd-CLI-only-writes rule is scoped to the ledger database; the trajectory database takes direct SQL from its sole appender

## Context and Problem Statement

The codebase carries a strong orthodoxy: all dolt mutations go through the bd
CLI, never SQL. `DoltQueryService` enforces it by construction
(`assertSelectOnly`), authenticates as a read-only user bd provisions, and its
class doc states the rule. The rule exists because bd owns the ledger
database's schema, invariants, and sync — a foreign SQL writer could corrupt
what bd cannot see.

The ratified trajectory/ledger split (tg-5l4p; `docs/design/trajectory/`)
introduces a second, grid-owned database on the same server whose sole appender
is the fenced transition service, writing per-append SQL transactions with a
counter-CAS fence. Routing those writes through bd is impossible (bd has no
trajectory schema) and extending bd's proxy would couple the trajectory to
bd's internals. The two rules would otherwise read as contradictory; this entry
records the boundary.

## Considered Options

* Route trajectory writes through bd (extend bd's CLI/proxy).
* Widen the existing read-only SQL path to allow writes.
* Scope the rule: bd-CLI-only for the ledger database; direct SQL — from
  exactly one component — for the trajectory database.

## Decision Outcome

The third. The bd-CLI-only-writes rule is a **ledger-database** rule and stays
absolute there. The trajectory database is written by direct SQL under these
constraints, all load-bearing:

* only the fenced transition service writes it (the sole-appender invariant of
  tg-5l4p; a second writer reopens the storage shape per the schema doc §12);
* it connects to the underlying dolt sql-server listener, never through bd's
  read-only proxy, and never touches bd's proxy pid/lock/secret files;
* it authenticates as a new write-capable credential provisioned by the grid
  and scoped to the trajectory database; `beads_dart`'s read-only secret is
  never widened or reused;
* it never writes the ledger database over SQL (bd-side effects ride bd's own
  surface, per the schema doc's derived-obligation rules).

Consequence: `grid_trajectory` documents this exception loudly at its write
path so a future reviewer does not "fix" it back to read-only or reroute it
through bd.

## Review log

* 2026-08-31 — authored by **agent** (governor seat, autonomous overnight mandate); force-from-write per decisions#0001 clause 3.
* 2026-08-31 — reviewed by **nico** (human, operator): **ratified as-is** (interview; the weight was questioned in discussion and the insurance argument accepted).
