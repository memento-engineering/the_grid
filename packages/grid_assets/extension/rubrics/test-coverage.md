# test-coverage

Are the changes covered by MEANINGFUL tests — tests that would actually fail if
the change were wrong? Grade the tests in the diff, not the production code's
correctness (spec-adherence owns that). A passing suite that would still pass
with the feature broken is not coverage.

## Bands
- **A** — the new behavior is covered by tests that exercise it directly, with
  positive controls (a test that would fail if the change regressed) and the
  edge/failure cases.
- **B** — the main path is covered meaningfully; some edges are untested.
- **C** — partial coverage; the happy path is tested but failure modes are not.
- **D** — token coverage only, or tests that assert little (would pass even if
  the behavior were broken — vacuous).
- **F** — no tests for the change, or tests deleted/skipped to make the suite
  green.

Distrust a green suite. Ask of each test: would this FAIL if the change were
wrong? Vacuous tests grade no better than none.
