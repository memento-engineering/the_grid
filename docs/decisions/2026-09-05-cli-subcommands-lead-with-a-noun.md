---
status: accepted
date: 2026-09-05
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor (agent seat)"
informed: []
register:
  spec: 1
  slug: cli-subcommands-lead-with-a-noun
  surfaces:
    - "packages/grid_cli/lib/src/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-d0d6
  legacy-id: null
---

# A CLI subcommand leads with a noun unless it acts on the agent itself

## Context and Problem Statement

The station's command surface has accumulated two grammars side by side. Reading
`lunar --help` on 2026-09-05 gives noun-domains that carry their own subcommands
— `assets`, `bead`, `dart`, `decisions`, `gate`, `traj` — sitting alongside bare
verbs: `approve`, `down`, `link`, `prime`, `reload`, `rework`, `search`,
`serve`, `unlink`, `up`, `watch`. A third shape, noun-form readers such as
`status`, `filing`, `seat` and `lease`, blurs the line further.

Nothing recorded which grammar a new command should join, so the choice was
being made per-command by whoever added one. Filing the held-session collection
verb (`tg-yz4p`) forced the question: `session collect` or a bare `collect`?
Answering it for one command without a rule would have left the next author in
the same position.

## Considered Options

Both options were genuinely weighed while filing `tg-yz4p`.

* **A noun-domain — `session collect`.** Matches the strongest existing
  precedent, `gate ls` / `gate resolve`, and the `traj` domain, where
  reclamation hangs off the domain that owns the thing being reclaimed. It also
  gives held-session listing an obvious home (`session ls`), which the operator
  cadence needs regardless.
* **A bare verb — `collect`.** Matches `approve` and `rework`: short, and the
  operator says what they are doing rather than where it lives.

## Decision Outcome

**Unless a command acts on the agent itself, its first token is a noun.** The
operator names the thing, then what to do to it.

* Acting on a domain object → `<noun> <verb>`: `session collect`, `session ls`,
  `gate resolve`, `bead …`.
* Acting on the running station or agent → a bare verb is correct and stays:
  `up`, `down`, `reload`, `serve`, `watch`, `prime`.

`tg-yz4p` is therefore `session collect`, under a new `session` domain. No third
grammar may be introduced.

### Consequences

* Good, because the rule is decidable without taste: ask whether the target is
  the agent or a thing the agent owns, and the shape follows.
* Good, because a noun-domain gives related operations a home instead of
  spending a scarce top-level name on each one — `session ls` arrives free
  beside `session collect`.
* Good, because it matches the surface's own strongest precedent (`gate`,
  `traj`) rather than inventing a convention.
* Bad, because it makes existing debt legible without paying it down:
  `approve`, `rework` and `filing` each act on a bead or a session rather than
  on the agent, and so read as violations from the moment this is accepted.
* Bad, because reconciling those three would break the commands operators type
  most, along with every document and skill that cites them. That reconciliation
  is deliberately left as a separate decision with its own compatibility cost,
  and is not authorized here.
