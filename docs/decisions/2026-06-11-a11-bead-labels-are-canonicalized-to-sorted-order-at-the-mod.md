---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a11-bead-labels-are-canonicalized-to-sorted-order-at-the-mod
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A11"
---
## A11 (2026-06-11) — Bead labels are canonicalized to sorted order at the model boundary

**Decision:** Sort `Bead.labels` on construction in **both** read paths — the bd-CLI decoder (`Bead.fromJson`, via a `SortedLabelsConverter`) and the SQL `beadFromRow` mapper.
**Why:** labels are a **set** upstream (the `labels` table PK is `(issue_id, label)`), so order carries no meaning, yet `Bead ==` (freezed, order-sensitive on lists) and the SQL-vs-CLI snapshot equivalence canary (ADR-0001 Decision 7) require the two read paths to agree byte-for-byte. Without a canonical order the canary fails on label ordering alone. The structural diff already compares labels order-insensitively (set equality), so this only makes `Bead ==` and the equivalence test reliable; no behavior is lost.
**Affects (if promoted):** ADR-0001 Decision 7 (note the canonicalization). Code: `models/converters.dart` (`SortedLabelsConverter`), `models/bead.dart`, `services/dolt_row_mapper.dart`.
**Status:** pending.

