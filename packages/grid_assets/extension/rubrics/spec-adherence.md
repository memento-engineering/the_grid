# spec-adherence

Does the change implement what the bead actually asked for — its Task, Design,
and Acceptance criteria (the architect's Implementation Plan)? Grade the DIFF
against the bead, nothing else. You are blind to the other lanes' concerns
(coverage, regression, the build) — weigh ONLY whether the work matches the spec.

## Bands
- **A** — implements every acceptance criterion as designed; no scope drift, no
  silent reinterpretation.
- **B** — implements the spec with minor, defensible deviations that do not
  change the outcome.
- **C** — implements the core intent but leaves a stated requirement partial or
  under-addressed.
- **D** — diverges materially from the Design or skips an acceptance criterion.
- **F** — does not implement the bead, contradicts it, or solves a different
  problem.

Grade against the bead's OWN words. If the bead is underspecified, grade what a
faithful reading would require — do not invent requirements it never stated.
