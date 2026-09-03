---
status: accepted
date: 2026-09-03
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: agent-disc-file-shape-and-home
  surfaces:
    - ".gitignore"
    - ".grid/seats/**"
    - "docs/design/trajectory/**"
  obsoletes: []
  updates: ["agent-seat-and-agent-disc"]
  obsoleted-by: null
  updated-by: []
  bead: tg-1n4y
  legacy-id: null
---

# Agent Disc file shape and home: one file per fact under `.grid/seats/<name>/`, graduating through the decide skill

## Context and Problem Statement

`the_grid#agent-seat-and-agent-disc` fixed the nouns and the homes — memory home
`.grid/seats/<name>/` at the station grid home, a precedent corpus vended back to
the seat, resolution a union across pack / station disc / reserved machine tier /
vended corpus — and deliberately created no promote verb and specified no file
format. Three consumers now wait on that format (`pow-mta` committee precedent,
`space-fsx` the handoff skill, `space-4tc` the refiner seat), and each would
otherwise invent one.

The decisions register is not the answer. `dec-4rb` proposed a non-binding
observation kind plus a cross-layer rank rule so disc-shaped notes could live in
`docs/decisions/`; Nico closed it as rejected. An entry that binds nothing is a
proposed state through the back door of a binding-on-write register, and ranking
registers so that conflicting force resolves by configuration is exactly what the
register exists to prevent. The disc therefore needs its own shape, and the
boundary between the two has to be absolute.

`bd remember` / `bd recall` are ruled out: unsupported in proxied-server mode on
every fleet store, and carrying no author, date, scope, or edges.

## Considered Options

* A spec-2 register profile with a non-binding observation kind and a layer rank
  (`dec-4rb`) — closed as rejected, above.
* A disc format designed from scratch for this entry.
* The shape the governor seat has already run for two months, adopted as-is.

## Decision Outcome

Adopt the running shape. A disc file is **one non-binding fact** in markdown with
light front matter. The disc is **not** a register and is **not** MADR: it borrows
only the register's *identity* conventions (`name` as slug, `date`, `supersedes` /
`superseded-by` mirroring `obsoletes` / `obsoleted-by`). MADR enters exactly once,
at graduation.

### 1. File shape

One file per fact at `<disc>/<name>.md`: front matter, then prose.

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | Kebab slug; equals the file name without `.md`. |
| `description` | yes | One line. This is the recall key. |
| `seat` | yes | The authoring seat — the author of record (§4). |
| `date` | yes | UTC, `YYYY-MM-DD`. |
| `kind` | yes | `lesson`, `receipt`, `observation`, or `handoff`. |
| `bead` | no | The receipt this fact came off. |
| `supersedes` | no | An earlier disc slug this replaces. |
| `superseded-by` | no | The decision slug that graduated it (§3). |

`kind` is **informational only**. No kind binds, and nothing on a disc carries a
flag that says otherwise. `handoff` is the fourth kind on purpose: it is the one
note that is *consumed* rather than kept (§3), and naming it here means the
handoff skill invents no shape.

Harness-written front matter is **tolerated and never linted**. Claude Code stamps
a `metadata` block (`type`, `modified`, and its own bookkeeping) on every write and
keeps doing so; the grid's keys sit beside it at the top level. This coexistence is
observed rather than assumed — every file in the running governor disc already
carries top-level `name` and `description` alongside a harness-written
`metadata.modified`.

Lint is **front-matter presence only**: no JSON schema, no index code, no generator.

The index at the disc root is `MEMORY.md`, one pointer line per file
(`- [Title](file.md) — hook`), and it is the only thing loaded wholesale; the files
themselves load on relevance. The harness loads that index at session start and
caps it at its first 200 lines / 25 KB (`code.claude.com/docs/en/memory`). Keeping
the harness's own file name means the harness needs no projection at all.

### 2. Home

`.grid/seats/<name>/` at the station grid home, **tracked**. Two corrections to the
shape as filed.

**(a) The ignore edit is two lines, not one.** Git cannot re-include a path under an
ignored directory, so `.grid/` plus a negation does nothing. The bare `.grid/` line
is replaced by:

```gitignore
.grid/*
!.grid/seats/
```

Every other `.grid` child — `critique/`, `critique-incarnation/`, `discovery/`,
`spec/`, `telemetry/`, `worktrees/` — is a direct child of `.grid` and stays matched
by `.grid/*`.

**(b) The line is hand-landed per station, not vended.** The overlay materializer is
a path-preserving file copier that refuses hand-authored targets, and a root
`.gitignore` is hand-authored. This entry lands the edit in the_grid; `space_station`
and `lunar_station` take the same change in their own stores as companions. The seat
preflight `tg-qmkr` — which already checks that a work repo ignores `.grid/` — also
checks that `.grid/seats/` is **not** ignored at a station grid home. No vending path
is built.

The vended precedent corpus keeps this same file shape inside the seat's overlay pack.
Resolution stays the union fixed by `the_grid#agent-seat-and-agent-disc`, most-specific
wins, and a conflict between two disc files is **a note to the human, never a
resolver**.

### 3. Graduation

When a disc note hardens into a rule that must bind, the seat runs the `decide` skill
(`decisions_grid_assets`) against **the pack's register**, writing a real binding entry
that cites the disc slug in its body, and marks the disc file
`superseded-by: <decision slug>`. The decisions register never points back at a disc.
There is no promote verb and no docket disposition for the move: graduation **is** a
decision, so it rides the decision path already built. Human-authored disc notes
graduate the same way, with the human in `decision-makers`.

`kind: handoff` never graduates. A handoff is working memory — a hypertemporal artifact
that lives exactly one succession — so the successor **deletes** it in the turn that
reads it. The disc is tracked, so git history is the archive. There is no archive
directory.

### 4. Who writes where

One disc per seat. Seats stay independent even inside a single grid home, and the
`seat` key on every file records the author.

Per-seat independence is **one line per launch** — no symlink, no copy, no hook.
`autoMemoryDirectory` takes an absolute path, is honored from a project's
`.claude/settings.json`, and is honored at highest precedence from `--settings` on the
command line (`code.claude.com/docs/en/memory`, `code.claude.com/docs/en/settings`);
`--agent`, `--settings` and `--append-system-prompt-file` are interactive-session flags
(`code.claude.com/docs/en/cli-reference`). A seat therefore launches as

```sh
claude --agent <seat> --settings <settings json whose autoMemoryDirectory is <grid home>/.grid/seats/<seat>>
```

The reserved machine tier stays unbuilt. The projection itself — a seat-launcher verb
that composes the `claude` environment the station already spawns
(`power_station/packages/grid_assets/lib/src/agent/agent_harness.dart`,
`kBuiltinEnvironments`) with those two flags — is **not** this entry's deliverable; it
is the prime/launcher bead that follows.

Subagent memory is a different mechanism and is **not** a disc: it is separate from the
main session and lives under `.claude/agent-memory/<name>/` or its user/local siblings
(`code.claude.com/docs/en/sub-agents`). A seat is a main-session persona, so a disc rides
`autoMemoryDirectory` instead.

An interactive session launched without a seat — a bare `claude` in the grid home — writes
to the harness's default project memory, which is not a disc. The launcher is how a session
becomes a seat occupant.

### 5. Injection cost

The disc is loaded by the harness's native memory mechanics: the index at session start,
the files on relevance. **Nothing injects the disc, or disc-recording instructions, per
session.** The discipline lives once, in the seat's role definition — the vended agent def.

The only hook that touches the disc is `SessionStart` with the `compact` matcher, which
references the seat's newest `handoff` after a compaction: the one case where the process
survives its own context. There is **no `PreCompact` guard** — hooks cannot themselves
trigger, defer, or undo a compaction (`code.claude.com/docs/en/hooks`), and a blocking
guard is a nanny state.

Measured 2026-09-03: `bd prime` is empty at the lunar grid home (proxied store, 79-byte
hook payload) and 5524 bytes of generic bd boilerplate in the_grid, so the generated
`SessionStart` hook (`bd prime --hook-json`, matcher `""`) is dead weight here. Replacing
it with a grid prime verb that echoes `bd prime` when non-empty and otherwise injects only
the handoff is a follow-up bead, not this entry.

### 6. Trajectory identity is a substation, not a seat

The trajectory envelope's per-record ownership column is `substation`
(`docs/design/trajectory/trajectory-schema.md`, enforced by `ck_substation`), derived at
append time by the service from the work bead's **store prefix** and wired through
`BeadOwnershipPredicate.ownedPrefixOf` (`docs/design/trajectory/stage1-wiring.md` §2.2).
That column names a substation and has nothing to do with an Agent Seat: **a disc's author
of record is the `seat` front-matter key of §1, never a trajectory column**, and this entry
adds no trajectory column, key, or record type.

Verified while recording this entry: the `seat`-named column and `ck_seat` this bead was
filed against no longer exist — `tg-j1zn` renamed them to `substation`/`ck_substation` and
closed on 2026-09-03, so the schema holdover is already retired and there is nothing here to
rename. What survives is prose in sibling stores (`lunar_station/CLAUDE.md`,
`space_station/CLAUDE.md`, and three space register entries dated 2026-09-02 — named
environments, org app identity per seat, seat resolution) that still says *seat* for a
substation. That sweep is space's, not this entry's.

### The boundary

A disc file never binds. A decision entry always does. Nothing carries a flag that says
otherwise. The decisions register, spec 1 as shipped, is untouched: no spec 2 profile, no
observation kind, no layer rank.

### Consequences

* Good, because three waiting consumers get one shape none of them had to design.
* Good, because the shape already survived two months of daily use, so adopting it costs
  nothing and proves nothing new.
* Good, because the boundary is structural rather than declared: binding force follows
  *which store the file lives in*, not a field a writer can set.
* Bad, because tracked disc residue dirties the station tree; only review discipline and
  the graduation rule keep it small.
* Bad, because the ignore edit is hand-landed in three station repos and can drift, with
  `tg-qmkr` as the only backstop.
* Constraint: the harness does not document what it does with front-matter keys it did not
  write. Coexistence is observed in the running governor disc, not guaranteed; a harness
  change is what would reopen §1.

## Non-goals

No promote verb; no archive directory; no disc lint beyond front-matter presence; no index
code; no seat-launcher verb, prime verb, or handoff skill (each is its own bead); no overlay
vending path for the ignore line; no trajectory schema change; no change to the decisions
register spec; no edit to sibling stores.

## Review log

* 2026-09-02 — rescoped by **nico** from `dec-4rb`, closed as rejected; filed for
  refinement, not approved.
* 2026-09-03 — refined with **nico** in a backlog-refinement session: items 1–3 settled,
  plus who-writes-where, injection cost, and the trajectory holdover. Rulings taken there:
  `handoff` is a fourth disc kind and is deleted on consume; no `PreCompact` guard; per-seat
  independence rides `autoMemoryDirectory` per launch; the ignore edit is hand-landed per
  station with the `tg-qmkr` preflight as backstop, rather than vended.
* 2026-09-03 — recorded accepted and binding on write, `decision-makers` nico + agent. This
  entry departs from `the_grid#agent-seat-and-agent-disc`'s non-goal that it "does not edit
  the root ignore file": that entry's own review log records the tracked-disc call as
  "explicitly reversible at the ignore-policy line", and this is Nico taking that line rather
  than reversing it. §6 was corrected against the live tree at recording time.
