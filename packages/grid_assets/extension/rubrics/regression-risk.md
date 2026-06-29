# regression-risk

What is the blast radius of this change — how likely is it to break behavior that
already worked? Grade the risk the diff introduces, independent of whether it
implements the spec or is tested (the other lanes own those). A correct change
can still be dangerous; a small change can still be safe.

## Bands
- **A** — isolated and additive; touches only new surface, or changes are fenced
  behind clear guards. No plausible path to breaking existing behavior.
- **B** — touches shared code but the change is local and the existing contracts
  are preserved.
- **C** — modifies a shared path with some unguarded edges; a regression is
  possible but not likely.
- **D** — broad or load-bearing changes with weak guards; a regression is likely
  without careful review.
- **F** — changes a critical shared invariant, a public contract, or a hot path
  with no guard — high chance of silent breakage.

Weigh what the change could break, not what it fixes. Name the riskiest edge in
your rationale.
