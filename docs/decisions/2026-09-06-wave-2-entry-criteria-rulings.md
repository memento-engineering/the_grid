---
status: accepted
date: 2026-09-06
decision-makers: [nico, governor]
consulted: []
informed: []
register:
  spec: 1
  slug: wave-2-entry-criteria-rulings
  surfaces:
    - "docs/design/trajectory/cut-wiring.md"
    - "docs/design/trajectory/trajectory-schema.md"
  obsoletes: []
  updates: [wave-2-flip-scope-soak-and-kill-date]
  obsoleted-by: null
  updated-by: []
  bead: tg-dme1
  legacy-id: null
---

# The wave-2 entry criteria are ruled: one cut lever, a breaker under cut, quiesced restore, the ratified refusal key, fold-backed disposition on C3, the open-retired shape, the KEPT exception, and the break-glass contract

## Context and Problem Statement

The wave-2 entry worksheet (lunar_station
`docs/trajectory-spike/07-wave2-entry-worksheet.md`) turned each of the r2
judge blockers on the cut-wiring appendix into an entry criterion (E1–E10),
verified its premise against `main @ 3617066`, and put the rulings only the
owner can make on a twelve-row docket. Four rows were ruled on 2026-09-05
(`wave-2-flip-scope-soak-and-kill-date`: Q1, Q5, Q6, Q12). On 2026-09-06 the
owner approved the worksheet's recommendation on every remaining row. This
entry records those eight rulings so cut-wiring r6 can cite one ruling per
criterion instead of re-opening the docket.

## Decision Outcome

Eight rulings, numbered as in the worksheet's docket.

**Q2 — one cut lever (E1).** The cut is a single `TrajectoryConfig`
discipline `{shadow, cut}`, not a second lever beside `dualRead`. `cut`
implies `dualRead: primary` on both axes and `mode: required`; a boot whose
resolved posture disagrees refuses by name. C3/C4's rollback text becomes
pre-cut only; post-cut rollback is the flip-back, never a `dualRead`
demotion.

**Q3 — `compromised` under cut halts admission (E2, E5).** The harness
accounting splits into decision-bearing and fire-and-forget drops, and only
the first feeds health. Under `cut`, `compromised` is a breaker: no new work
is admitted, running sessions drain to terminal, a station gate opens, and
`trajectory.admissionHalted` flares. It never demotes onto the legacy carrier.
`appendAcked` returns a sealed `{Acked, Dropped, Suppressed}` that always
completes; a decision-bearing site treats `Dropped` or `Suppressed` as this
breaker, and `_rearm`'s failure path becomes a gate, not a flare. This is
also the storm budget the carried major O-M2 asked for.

**Name correction (2026-09-08, implementation verification).** The flare name
above corrects the original Q3 label without changing the ruling's substance.
`trajectory.halted` is already the one-shot signal for a presumed-damaged log;
that latch suppresses subsequent appends and therefore cannot also represent
the admission-only breaker needed while running sessions drain their terminal
records. The established corruption latch keeps its name and behavior, while
the admission breaker has its own cause and recovery.

**Q4 — restore under cut is a quiesced void-and-redrive (E3, shape b).** No
head-stamp detector is built. A restore is a quiesced event that voids every
session open at the snapshot and re-drives them from bd, so no in-flight
session crosses the restore boundary. The M6c head re-stamp stays parked at
Stage 4.

**Q7 — the `admission.refused` idempotency key is not amended (E7).** The
ratified level-shaped key (`refused:<bead>:<clause>:<snapshotRev>`, with the
`restored:` counterpart) stands as the tree has it. W2-B's barrier refusals
use it with `snapshotRev` from the joined snapshot the authority evaluated.
The r2 reason-keyed form was the error; A-M4, B-M3, and F-m3 close as "the
tree is right".

**Q8 — fold-backed disposition rides C3 now (E8).** `sessionDispositionOf`
and `staleFences` gain a fold-backed reading served from the P1 mirror with a
counted legacy fallback under `dualRead: primary`, as a C3 extension that can
soak today, not as wave-2 work. The empty-cursor voiding rule is re-derived
from P2 the same way.

**Q9 — the open-retired P1 shape is accepted (E9).** A session with a retired
round is open until its terminal; `AttemptRoundRetired` keeps bumping the
round and no head-closing record is added. Accretion is fixed at its source,
the missing terminals (delivered as the external-close obligation, tg-ffl6),
and P6 eviction is bounded on `last_seq` age, never on "open in P1".

**Q10 — the KEPT-writes coexistence is a named exception to §9.** Schema §9's
cuts-whole rule admits exactly one exception: under the narrow wave 2 the
`complete` and `failed` step writes stay KEPT while `running`, `pending`, and
`gated` retire. The KEPT table names that set and cites this entry; no other
partial cut is implied.

**Q11 — the break-glass contract.** `GRID_G1_BREAK_GLASS` is resolved once at
assembly, before any posture read, and both bypass targets read the resolved
value (one site, answering O-M7). Its use carries loud provenance in the
log, and the archaeology guard that records it is permanent, not a soak-era
scaffold.

The carried-majors table in the worksheet is adjudicated by these rulings as
written there; r6 folds it in and is re-judged as r2–r5 were.

### Consequences

* Good, because every entry criterion now has a ruling to cite, so r6 is a
  design round rather than a docket.
* Good, because the single lever and the breaker remove the two silent
  failure shapes the r2 judges found (a permitted incoherent boot, and a
  demotion onto a carrier with no writer).
* Bad, because quiesced restore costs a full void-and-redrive of every open
  session at the snapshot, with no detector to narrow it.
* Bad, because the §9 exception has to be carried honestly in the KEPT table
  and the schema text until Stage 2/4 retires the other half.

### Confirmation

cut-wiring r6 cites this entry beside each of E1–E5 and E7–E9, and the
adversarial re-judge finds no criterion without a ruling.
