---
status: accepted
date: 2026-07-14
decision-makers:
  - "nico"
consulted: []
informed: []
register:
  spec: 1
  slug: adr-0008-decision-10-is-superseded-by-the-agent-environment-layer
  surfaces:
    - "packages/**"
  obsoletes: []
  updates:
    - adr-0008-authoring-sdk-and-reentrant-engine
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# ADR-0008 Decision 10 is superseded by the agent-environment layer

## Context and Problem Statement

`adr-0008-authoring-sdk-and-reentrant-engine`'s Decision 10 (added by the
2026-07-02 amendment, `docs/SCRATCH-agent-scope.md`) recorded "the agent
scope": a harness roster, a D-C config ladder, and a `ModelTarget` value —
the_grid's own model of which harness runs an agentic step and with what
configuration.

`power_station`'s `adr-0002-agent-environment-layer`
(`docs/decisions/2026-07-14-adr-0002-agent-environment-layer.md`, ratified by
Nico 2026-07-13, recorded 2026-07-14) replaces that model with named
inference environments `{harness, target, model}`. That entry's own front
matter already states **"Supersedes: the_grid ADR-0008
(authoring-sdk-and-reentrant-engine) Decision 10"**, and
its prose says explicitly that the cross-repo stamp recording this on the
the_grid side is **not** made from power_station's own repo — a companion
the_grid bead was left to perform it.

This entry is that companion stamp. It was recorded as part of `tg-vmtd`
(retiring the orphaned ADR-numbered originals directory), per the governor's 2026-09-13
ruling on that bead: record the supersession in the_grid's own register
before the ADR originals are deleted, citing power_station's entry in prose
rather than inventing a cross-repository register edge — that capability
does not exist in the `decisions` CLI yet (only `index`/`search` compose a
multi-register union; the mutation commands read one register) and is out of
scope here.

## Decision Outcome

`adr-0008-authoring-sdk-and-reentrant-engine`'s Decision 10 is superseded.
`power_station#adr-0002-agent-environment-layer` is the current, binding
decision for the agent scope — the harness roster, the D-C config ladder,
and `ModelTarget` all read as history against it. This entry records that as
an `updates` edge onto `adr-0008-authoring-sdk-and-reentrant-engine` within
this register (Decision 10 is superseded; the rest of ADR-0008 is
unaffected and remains in force). No edge is authored to
`power_station`'s register — the cross-repo pointer is this prose citation
only, until a cross-register mutation capability is built (filed separately
in the `decisions` repo, per the same ruling).

### Consequences

* Good, because the_grid's own register graph now shows that Decision 10 is
  superseded, instead of that fact living only in power_station's prose and
  in the now-deleted ADR-0008 original document.
* Bad, because the pointer to the actual successor decision is a slug
  citation in prose, not a linted graph edge — a reader has to follow it by
  hand until the decisions CLI grows a cross-register `updates`/`obsoletes`
  capability.
