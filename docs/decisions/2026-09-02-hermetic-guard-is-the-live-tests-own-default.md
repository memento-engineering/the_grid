---
status: accepted
date: 2026-09-02
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: hermetic-guard-is-the-live-tests-own-default
  surfaces:
    - "packages/beads_dart/test/support/fleet_binary_guard.dart"
    - "packages/beads_dart/test/integration/sql_cli_equivalence_test.dart"
    - "packages/beads_dart/test/integration/cross_workspace_probe_test.dart"
    - "tool/bd_compatibility/run.sh"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-1liv
  legacy-id: null
---

# The foreign-binary guard is the live tests' own default, not an invoker-selected mode

## Context and Problem Statement

A compatibility run passes an ARBITRARY bd to `run.sh`, and two of the selected
tests resolve whatever live store `BeadsWorkspace.discover()` finds. At rc.1
that binary refused the fleet's proxied store and left a
`.beads/proxieddb.gate.lock` behind; `set -e` then aborted the run before the
corpus-replay step.

A harness whose binary under test can be foreign must not touch a live store.
The safety rule has to hold before either test resolves an endpoint.

## Considered Options

* A third `run.sh` argument selecting hermetic versus live.
* An environment-variable opt-in.
* The tests' own default.

## Decision Outcome

The third. A guard an invoker can turn off is not a guard. The two live tests
compare `bd version` on PATH with the store's `.beads/.local_version` stamp
BEFORE resolving an endpoint and call `markTestSkipped` on a mismatch or an
unstamped store, failing closed. `run.sh` keeps its two-argument form and gains
NO mode argument, pinned in test.

This applies D-BD1's store-migration rule and ADR-0003 Decision 6's coexistence
partition to the TEST harness: a harness whose binary under test can be foreign
must never touch a live store.

## Review log

* 2026-09-02 — authored by **agent** (specify stage of tg-1liv).
