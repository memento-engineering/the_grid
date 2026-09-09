---
status: accepted
date: 2026-09-08
decision-makers: ["governor"]
consulted: []
informed: []
register:
  spec: 1
  slug: rework-clears-only-specify-authored-specification
  surfaces:
    - "packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart"
    - "packages/grid_runtime/test/lifecycle/station_bead_writer_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-vb4m
  legacy-id: null
---

# Rework clears only specify-authored specification

## Context and Problem Statement

Rework must retire prose authored for the prior SPECIFY round without erasing
human rulings written directly to a work bead. The rework predicate had been
changed to preserve only `spec.author=operator`, while the writer that stamped
`spec.author=specify` was removed. Direct `bd update --design-file` and
`--acceptance` writes carry no provenance, so an absent marker came to mean
both round-authored text and hand-authored text. Rework consequently erased
governor cures, and the resulting blank acceptance criteria caused approval
preflight to refuse a replacement approval.

An existing approval stamp can survive this loss and allow the round to mint,
but that does not recover the erased rulings. Provenance therefore has to
identify the text that rework is authorized to clear, rather than identify
only one class of text that rework should preserve.

## Considered Options

* Preserve only explicitly operator-authored specification and treat missing
  or unrecognized provenance as belonging to the retired round.
* Exempt a previously approved live round from the filing contract's
  acceptance-criteria requirement.
* Stamp SPECIFY writes explicitly and clear only specification carrying that
  exact marker.

## Decision Outcome

The third option is taken. `StationBeadWriter` owns the single SPECIFY prose
write and writes design, acceptance criteria, and `spec.author=specify` in one
guarded metadata-merge update. Rework clears design and acceptance criteria
and unsets `spec.author` only when the observed marker exactly equals
`specify`. Missing provenance, `operator`, and every other explicit author are
preserved and emit `rework.specPreserved`.

The clear remains one ownership-checked, per-id serialized update guarded by
the bead's observed assignee and status. It does not supply description or
notes, and it completes before the SDK re-keys the retiring session. Operator
design and acceptance writes continue to stamp `spec.author=operator` through
the same writer chokepoint.

The approval verb and filing contract are unchanged. Skipping the
acceptance-criteria row for previously approved live rounds would weaken the
only completeness gate that keeps a blank filing off the mount frontier, fail
to protect first approval, and leave the underlying loss of rulings unfixed.

### Consequences

* Good, because absent provenance is treated as unknown rather than as proof
  that the retired round authored the text.
* Good, because SPECIFY provenance and both specification fields cannot become
  partially visible through separate writes.
* Good, because hand-written and explicitly non-SPECIFY rulings survive rework
  and remain eligible for the unchanged approval preflight.
* Bad, because any SPECIFY implementation that bypasses the writer will leave
  prose conservatively preserved until it adopts the provenance seam.
