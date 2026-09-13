---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: ["governor (station seat)"]
informed: []
register:
  spec: 1
  slug: wave-2-kept-set-includes-gated-and-ready
  surfaces:
    - "docs/design/trajectory/cut-wiring.md"
    - "docs/design/trajectory/trajectory-schema.md"
    - "packages/grid_engine/lib/src/circuit/capability_host.dart"
  obsoletes: []
  updates:
    - "wave-2-flip-scope-soak-and-kill-date"
    - "wave-2-entry-criteria-rulings"
  obsoleted-by: null
  updated-by: []
  bead: tg-1q2s
  legacy-id: null
---

# The narrow wave-2 KEPT set includes `gated` and `ready`

## Context and Problem Statement

`wave-2-flip-scope-soak-and-kill-date` Q5 ruled wave 2 narrow: the flip retires
the `running`, `pending`, and `gated` step writes while `complete` and `failed`
stay KEPT on bd. `wave-2-entry-criteria-rulings` Q10 named that two-write set
as the single exception to schema §9's cuts-whole rule. cut-wiring round 6 then
verified two facts at the tree that the ruling had not seen (E4-a, E4-b): the
exhaustion park (`capability_host.dart:940-945`) is the SOLE carrier of the
exhausted `restartCount`, because the `failed` write is skipped on that branch
(`:860-866`), and the route park (`:1057-1062`) is the sole carrier of the route
verdict — both through `persistRaisedEscalation`; and `ready` was never named
by Q5 at all, while `_persistReady` (`:710-719`) merges a rendezvous payload via
`nodeResultMetadata`. With `gated` retiring, those two facts would need a
second carrier designed and built before W2-A could write that branch; the
retiring set was therefore undetermined (§W2.2, E4-a), which gated W2-A's item 4
and the cut itself.

## Decision Outcome

The KEPT set under the narrow wave 2 is `{complete, failed, gated, ready}`; the
retiring set is `{running, pending}`. Q5's first sentence and Q10's named set
are amended to say so, and the KEPT table in `trajectory-schema.md` names the
four. No second carrier is designed: the exhausted `restartCount`, the route
verdict, and the rendezvous payload keep their bd carrier until the stage that
retires `complete` and `failed` retires these with them. W2-A item 4's branch
list stands exactly as written — `running` and the rearm become acked under
cut; `complete`, `failed`, `gated`, and `ready` are untouched. This remains the
single §9 exception, now four writes wide.

Nico's caveat on this ruling and its two siblings, verbatim: "all of this smells of imperative code that shouldn't be".
It is recorded as an open observation on the shape of the cut-wiring work,
not as a ruling; no entry changes on its account.

### Consequences

* Good, because W2-A (`tg-j1vu.1`) is unblocked without a new carrier design, and the two sole-carrier facts stay where today's readers find them.
* Bad, because the narrow cut is wider than Q5 wrote it (round 6 measured the difference at about 1.5% of write churn), and the stage that retires `complete`/`failed` inherits four KEPT writes to retire instead of two.
