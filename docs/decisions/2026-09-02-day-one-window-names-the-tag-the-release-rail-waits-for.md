---
status: accepted
date: 2026-09-02
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: day-one-window-names-the-tag-the-release-rail-waits-for
  surfaces:
    - "packages/beads_dart/bd_compatibility.yaml"
    - ".github/workflows/publish.yml"
    - "packages/beads_dart/test/tool/compatibility_workflows_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-1liv
  legacy-id: null
---

# `day_one_wait_through` names the tag the release rail WAITS FOR, and at-or-newer opens the gate

## Context and Problem Statement

D-BD1 (ratified 2026-08-08, stamped into ADR-0002 Decision 1) states the day-one
exception: "The fleet is committed to the HEAD lineage until the next upstream
tag catches up — the first release-rail gate therefore waits on that tag."
`bd_compatibility.yaml` encoded that as `day_one_wait_through: v1.1.2` and
`publish.yml` compared with a STRICT-newer test (`"$latest" != "$wait"`), so the
recorded value read as "the last tag known NOT to cover the fleet's stores".
Moving the value to `v1.3.0` — the tag the rail is actually waiting for — under
the strict comparison would hold releases until v1.3.1, one release PAST the tag
D-BD1 names.

## Considered Options

* Keep the strict-newer comparison and record `v1.2.2` (the last tag known not
  to cover the lineage).
* Keep the strict-newer comparison and record `v1.3.0`, accepting an off-by-one
  hold.
* Read the key as the tag the rail waits FOR and make the comparison
  at-or-newer.

## Decision Outcome

The third. `day_one_wait_through` names the published tag the release rail is
waiting for; the gate opens when GitHub's latest published non-prerelease tag is
that tag OR newer. `publish.yml` drops the `"$latest" != "$wait"` clause and
`compatibility_workflows_test.dart`'s mirror helper changes `<=` to `<`. The
value moves to `v1.3.0` on the receipt that the fleet binary `a45199a` is a
direct ancestor of `v1.3.0-rc.1` (829 commits behind, 0 ahead): v1.3.0 is the
first tag that provably covers the fleet's store lineage, and v1.2.2 does not.

This IMPLEMENTS D-BD1's day-one clause rather than overriding it; the key name
is kept (no dual-model, no alias) and its semantics are recorded here.

Consequence: with latest = v1.2.2 today, a beads_dart release is HELD. That is
the honest state — the day-one exception is a fact to burn down, and it burns
down when v1.3.0 publishes.

## Review log

* 2026-09-02 — authored by **agent** (specify stage of tg-1liv).
