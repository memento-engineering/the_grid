---
status: accepted
date: 2026-08-31
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: stage0-guards-gate-prs
  surfaces:
    - ".github/workflows/ci.yml"
    - "packages/grid_trajectory/test/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-hrxv
  legacy-id: null
---

# The Stage-0 guard tests gate PRs via a dolt-installed CI job; the self-skip pattern is rejected for them

## Context and Problem Statement

The trajectory schema's Stage 0 (§9) pins seven guard tests — status-clean
after fold writes, the `dolt add --force` ban, dolt_log-counted commits,
`--doltcfg-dir` handling, branch-change fail-closed, and the CHECK-refusal pin
across all seven constraints. They exist to put stage-cut evidence **on
record**.

The repo's existing integration-tagged tests (grid_exploration, grid_cli)
self-skip silently when no dolt/bd is present — and the PR-gating CI job
installs neither, so those tests currently prove nothing on PRs. Reusing that
pattern would make the guards decorative.

## Considered Options

* The existing self-skip pattern (guards run only on developer machines).
* A PR-gating CI job that installs dolt and runs the guards for real.

## Decision Outcome

The second. CI gains a job (modeled on publish.yml's `bd-compatibility` job,
which already installs Go + dolt) that stands up a real dolt sql-server and
runs `dart test -t integration` for `grid_trajectory` on every PR. The
seven guards must run — a skipped guard is a failed guard for stage-cut
purposes. The general self-skip pattern elsewhere in the repo is untouched;
this entry governs the trajectory guards only.
