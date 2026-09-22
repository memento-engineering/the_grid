# JoinedSnapshot invalidation characterization

## Current seam

`WorkList` is the sole tree observer of its injected
`JoinedSnapshotNotifier`. Each substation owns that lifecycle subscription and
republishes its captured value as `Provider<JoinedSnapshot>`. Every mounted
`SessionScope` then watches the whole `JoinedSnapshot`. This preserves the
one-pipeline-subscription invariant while allowing an update relevant to one
session to invalidate session consumers beneath every rebuilt work list.

This note characterizes a narrower tree-facing projection. It is not evidence
of a measured performance regression and does not authorize a production or
admission rewrite.

## Method

The offline probe in
`packages/grid_engine/test/snapshot_invalidation_characterization_test.dart`
uses real `JoinedSnapshot` and `SessionProjection` values. Counts are taken
after initial mount, and every event uses a fresh tree. Child seed instances
remain stable so the counts report dependency invalidation rather than
configuration churn. Every lifecycle listener and tree owner is disposed.

The baseline mounts two WorkList-shaped subscribers to one injected notifier.
Each subscriber republishes the complete frame through a plain
`InheritedSeed`, with one whole-value SessionScope-shaped consumer beneath it.
The candidate mounts one subscriber and republishes through
`InheritedModelSeed<_ProjectionFrame, _SnapshotAspect>`. Each consumer watches
its fixed local-session aspect plus a station-capacity aspect and a
cross-store-blocker aspect.

The two integer revisions in the frame are deliberate correctness rails. They
model admission-relevant station-wide capacity and cross-store dependency
changes that cannot safely be inferred from one local session map entry.

## Measurement matrix

Each cell is `projector / consumer A / consumer B = total` and counts only
builds after initial mount.

| Event | Whole-value baseline | Aspect-scoped probe |
|---|---:|---:|
| Local session A cursor only | `2 / 1 / 1 = 4` | `1 / 1 / 0 = 2` |
| Equal input | `0 / 0 / 0 = 0` | `0 / 0 / 0 = 0` |
| Station-capacity revision | `2 / 1 / 1 = 4` | `1 / 1 / 1 = 3` |
| Cross-store-blocker revision | `2 / 1 / 1 = 4` | `1 / 1 / 1 = 3` |
| Session A disappears, wide revisions unchanged | `2 / 1 / 1 = 4` | `1 / 1 / 0 = 2` |

Aggregate: **16 → 10 synthetic builds**.

The probe demonstrates mechanical suppression for local-only changes and
dependency disappearance. It does not demonstrate a production latency, CPU,
or allocation benefit. Two of the candidate's wide-event savings also come
from modeling one station-level projector instead of the current two
per-substation subscribers, not from suppressing a session consumer.

## Correctness widening

Local aspects are insufficient for admission. A capacity release or
consumption can change whether work in either substation may mount, so every
consumer must also watch the station-capacity aspect. A remote capability or
external dependency transition can change readiness without changing either
local session entry, so every consumer must also watch the cross-store-blocker
aspect. The probe therefore rebuilds both consumers for both wide revisions.

This widening is mandatory even if a consumer's local session aspect is
unchanged. Any production projector would also need a bridge from authority
invalidations not carried by `JoinedSnapshot`; otherwise an aspect model could
hide a current admission answer behind a locally unchanged session.

## Decision alignment

`the_grid#light-dag-deferred-bodies-and-two-tier-change-signals` Decision 2
already fixes the resident graph's change doctrine: “Trigger granularity: per
store”, “Attribution granularity: per bead”, and no field-by-field value diff.
This characterization is consistent with that doctrine. It measures an
optional consumer-invalidation layer above the resident graph; it does not
replace store triggering or bead attribution. A future implementation bead
would explicitly extend the two-tier doctrine at the tree projection boundary
rather than silently introducing sub-bead attribution into the resident graph.

The other governing constraints remain unchanged: observation stays
out-of-band and build stays synchronous; station capacity remains a shared
joined-snapshot fact; cross-store blockers remain authoritative; and the
station-lifetime admission authority remains independent of `TreeContext` and
`InheritedModelSeed`.

## Prior art and complexity

Power station's `SubstationFactsModelSeed` proves that `InheritedModelSeed`
works for aspect-scoped tree values without adding a new grid-engine
dependency. Its facts are independently keyed per substation. This candidate
is materially harder because it must merge local session facts with mandatory
station-wide capacity invalidation and cross-store blocker invalidation.

Production adoption would require all of the following:

- a station-level projector replacing the current per-`WorkList`
  subscriptions;
- stable aspect keys for local sessions and every wide correctness rail;
- semantic comparison for every admission-relevant field, kept current as
  `JoinedSnapshot` evolves;
- a bridge from authority invalidations not carried by `JoinedSnapshot`;
- tests proving dependency disappearance and every global or cross-store
  transition cannot be hidden by an unchanged local aspect.

Those costs add a second invalidation vocabulary beside the already-ratified
store/bead change signal. Station-wide events necessarily remain wide, and
every current `WorkList` would still own a notifier subscription unless the
larger station-level projector change landed too.

## Recommendation

Retain the production `Provider<JoinedSnapshot>` projection and whole-value
`SessionScope` observation. The bounded probe establishes that aspect scoping
can remove six synthetic builds from this five-event matrix, but it establishes
no production benefit and does not remove the current per-`WorkList`
subscriptions. File a separate implementation bead only if production
profiling shows material local-only session churn and attributes meaningful
cost to these tree rebuilds.

## Non-goals

- No change to `WorkList`, `SessionScope`, `StationAdmissionAuthority`, or any
  production `grid_engine/lib` source.
- No admission-policy, capacity, or cross-store dependency redesign.
- No claim of a measured performance regression or production speedup.
- No duplication or modification of the terminal-drain retirement owned by
  `tg-lnyx`.
