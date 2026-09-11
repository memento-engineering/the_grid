# Beads context

You are a seat of a resident the_grid station, or an operator working beside one.
Your task prompt already carries the bead you are working and what it needs. This
file is the `bd` reference and nothing else.

## The verbs that matter

Measured across a month of station sessions, these five are 91% of all `bd` use:

- `bd show <id>` — the bead, its fields, its graph. `--json` to parse. (48%)
- `bd dep list <id>` — blockers. There is no `blocked_by` field; this is the only
  typed view of them. (17%)
- `bd update <id> --<field> …` — write one field. (14%)
- `bd search <query>` — keyword search. Single distinctive tokens, never phrases. (6%)
- `bd list -t <type> --status <status>` — a scoped collection read. (2%)

## Traps that have each cost a round

- **`bd export` is banned.** Against a proxied store it exits clean and empty, which
  reads as "this store has no beads". Use a scoped `bd list -t` instead.
- **`--notes` REPLACES the field.** Use `--append-notes` to accrue. A clobbered field
  is recoverable only via `bd history --json`.
- **Never write a bead id you have not minted.** Create the bead first and capture the
  id from the `Created` line — not from surrounding prose, and never by guessing.
- **No NUL bytes or backticks in bead text.** They truncate or substitute at exec and
  `bd` reports success either way.
- **A bead id on a `Blocked-by:` line is parsed as an edge.** If you name one there,
  wire the dependency too.

## What this file deliberately does not do

It does not tell you to run `bd prime`. You are reading its output.

It sets no git policy. This repo's `AGENTS.md` is the single source of agent
instruction, and it governs commits, branches and landings here.

It does not prohibit markdown notes or `MEMORY.md`. A station seat's Agent Disc is
exactly that, by design.
