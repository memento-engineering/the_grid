# Agent Disc roots

One directory per Agent Seat: `.grid/seats/<name>/`. Each holds that seat's disc
— one file per fact, plus a `MEMORY.md` index at the disc root. This tree is
tracked on purpose; every other child of `.grid/` is ignored runtime residue.

The file shape, the four kinds, graduation, and the per-seat launch projection
are fixed by `the_grid#agent-disc-file-shape-and-home`
(`docs/decisions/2026-09-03-agent-disc-file-shape-and-home.md`).

Nothing in a disc file binds. A rule that must bind is written as a decision
through the `decide` skill, and the disc file is then marked
`superseded-by: <decision slug>`.
