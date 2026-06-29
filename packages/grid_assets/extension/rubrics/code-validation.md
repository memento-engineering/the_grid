# code-validation [GATING]

The hard gate. This lane does not weigh opinion — it RUNS the bead's own
**Validation Plan** (the `validation_plan` the bead carries) in the work tree and
grades on the exit codes alone. It is the answer to "a fixed `melos test` is not
verification": every bead declares the commands that prove ITS change, and this
lane runs exactly those.

## Bands
- **A** — every command in the Validation Plan exited zero. The change builds and
  its own checks pass.
- **F** — any command exited non-zero, OR the bead carries no Validation Plan at
  all (a plan-less bead never silently passes — it is a hard block until a plan
  is supplied).

A grade of **F** here is a hard block: the route parks the work at a gate. There
is no partial credit and no LLM judgement in this lane — a command either passed
or it did not.
