---
status: accepted
date: 2026-09-12
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: bd-silent-success-guardrails
  surfaces:
    - "packages/beads_dart/lib/beads_dart.dart"
    - "packages/beads_dart/lib/src/errors/bd_exception.dart"
    - "packages/beads_dart/lib/src/models/bd_query_result.dart"
    - "packages/beads_dart/lib/src/services/bd_cli_service.dart"
    - "packages/beads_dart/test/services/bd_cli_service_guardrails_test.dart"
    - "packages/beads_dart/test/integration/bead_text_transport_test.dart"
    - "packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart"
    - "packages/grid_sdk/lib/src/command/**"
    - "packages/grid_cli/lib/src/bead_command.dart"
    - "packages/grid_cli/lib/src/station_control.dart"
  obsoletes: []
  updates:
    - "adr-0001-technical-foundations"
    - "adr-0006-dogfood-rig-and-live-write-authorization"
    - "the-pour-gets-its-own-bd-deadline"
    - "bead-read-verbs-ride-the-resident-door"
  obsoleted-by: null
  updated-by: []
  bead: tg-h7y8
  legacy-id: null
---

# bd silent-success guardrails

## Context and Problem Statement

Several bd operations exit zero while returning a plausible but incorrect
result. A proxied export can be clean and empty, a notes replacement can erase
the existing field, a proxied ephemeral wisp can become unreachable, and an
argv NUL can truncate text. The historical 50-row query cap is fixed, but it
demonstrated the recurring empty-read ambiguity: no rows does not by itself
prove absence.

These failures share one shape: the caller cannot distinguish success from a
wrong result, and downstream code cannot reconstruct the lost evidence. The
guardrails therefore belong at `BdCliService`, the one bd-CLI choke point, not
in caller memory and not in a fork of bd.

## Decision Outcome

Nico Spencer ratified the following policy on 2026-09-12.

* `bd export --all` is refused. In proxied mode it can exit clean and empty;
  callers use a scoped `listScope` read or a positive-controlled query instead.
* `applyGraph(ephemeral: true)` is refused without override in proxied mode.
  Callers pour a persistent graph or use a direct store.
* A NUL in bead prose or metadata carried directly in argv is refused without
  override. File and stdin transports remain byte-safe and unchanged.
* A `--notes` write first reads the explicit target. Replacing a non-empty
  notes field is refused by default, naming the existing UTF-8 byte count, and
  proceeds only with the named `allowNotesReplacement` opt-in exposed to the
  operator as `--allow-notes-replacement`.
* Backticks, `$(...)`, and `$VAR` are legal prose. `ProcessBdRunner` executes
  argv directly with `runInShell: false`, so the wrapper preserves them rather
  than refusing them.
* Absence-bearing queries return typed positive-control evidence. An empty
  target is verified empty only when an independent control query returns at
  least one row; otherwise the read is unavailable.
* An explicit notes replacement is never transformed into an append. Refusal,
  deliberate replacement, and append remain three distinct outcomes.
* Every resident notes preflight and text-verification read uses the id-scoped
  `bd query id=<beadId> --all --json --limit 0` path. It never uses `bd show`,
  because `show` writes `.beads/last-touched` and self-triggers the controller
  watcher.

There is no override for export, proxied ephemeral graph apply, or argv NUL.
Notes replacement is the sole class with a legitimate override.

## Existing Seams Preserved

Commit `c1a2ff3` already retired export reads, so this decision adds a
refusal-only tombstone and does not recreate an export parser. Commit `dda2d42`
already pins query and list reads to `--limit 0`; positive control extends that
same argv builder. `ProcessBdRunner` already passes `runInShell: false`, which
remains the direct-argv correctness mechanism.

`BdCliService.applyGraph` keeps its explicitly threaded
`BdCliService.pourTimeout` of 60 seconds on every allowed path, and no other bd
call receives that deadline, preserving
`the_grid#the-pour-gets-its-own-bd-deadline`. The new proxied-ephemeral refusal
occurs before temp-file creation and therefore before that runner call.

The operator opt-in continues through the authenticated `grid/bead/set`
resident command. The CLI opens no work or state store, preserving
`the_grid#bead-read-verbs-ride-the-resident-door`; no direct-store fallback is
introduced.

## Consequences

* Silent-empty and silent-clobber cases become typed, inspectable outcomes.
* Legitimate notes replacement remains reachable only through explicit intent.
* Existing persistent and direct graph pours keep their atomicity and named
  deadline.
* bd remains upstream and foreign; no bd source, vendored tree, or pinned
  upstream fixture changes.
