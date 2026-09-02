---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a9-beadstatus-is-an-extension-type-over-string-not-a-7-value
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A9"
---
## A9 (2026-06-11) — `BeadStatus` is an extension type over String, not a 7-value enum

**Decision:** Model `BeadStatus` (and uniformly `IssueType`, `DependencyType`) as a zero-cost extension type over the wire string with named constants for the built-ins, rather than a strict closed Dart enum. `category`/`isClosed`/`isBuiltIn` cover the seven built-ins; unknown values decode without throwing (`category → StatusCategory.unspecified`).
**Why:** the PDR plan and ADR-0001 Decision 1 framed status as an "enum, closed set of 7", but upstream beads supports **custom statuses** (`Status.IsValidWithCustom`, `internal/types/types.go`), so a strict enum would throw on a custom value during snapshot decode — a latent crash. Extension-type-over-String matches beads reality, keeps value equality/`hashCode` correct for free (a `BeadStatus` *is* its String at runtime), and is uniform with the already-open `IssueType`/`DependencyType`. The canonical seven remain enumerated as constants.
**Affects (if promoted):** ADR-0001 Decision 1 wording (status "enum" → extension type). Code: `packages/grid_controller/lib/src/models/bead_status.dart`.
**Status:** pending.

