# ADR-0013 — State-representing value types hold their own state

**Status:** **Draft — placeholder (direction only; specifics TBD).** Committed deliberately, ahead of a full write-up, so the *direction* is binding on future development even before the rule set and migration are filled in.

**Date:** 2026-07-12 · **Deciders:** Nico (ratified direction) · **Supersedes/relates:** genesis ADR-0001 D7 (the freezed-union house set); the_grid ADR-0008 D3 (guards LOUD or GONE); M5 D-4/D-4a/D-4b (the route primitive + uniform-recursive circuit).

---

## Context

The same failure keeps recurring: state that a value type *models* is **inferred from an out-of-band signal** — a file's presence, a deletion succeeding, a directory's layout, an `mtime`, the shape of a `nodePath` — instead of being **held in the value itself**. That inference is fragile and best-effort.

The exemplar is the A15(5) round-freshness residual: a spec-critic verdict's **round** was reconstructed from a best-effort wipe of `.grid/critique/` rather than carried by the verdict. A failed wipe plus a surviving same-path file misreads a *stale* verdict as *fresh*. The `nodePath` "freshness stamp" (ADR-0000 A4) couldn't help, because under `Rewind` the path is byte-identical across rounds — the state it needed (the round) was never in the value.

The substrate already leans the other way — freezed sealed unions, exhaustive `switch`, and "make the invalid state **unrepresentable** over guard against it." This ADR makes that stance explicit for state-bearing value types and sets the direction for a pass over the engine's own.

## Decision (direction — to be detailed)

1. **A value/union type that *represents* a piece of state MUST HOLD that state as data** — a field of the value, positively verifiable by a consumer — never reconstructed from a side channel (file existence, deletion success, path shape, a clock).
2. **The distinguishing identity rides in the type.** Whatever separates one incarnation of the state from another — round, version, incarnation key, freshness — is a field, not an inference (e.g. a verdict carries its `rewindCount`; a cursor carries its incarnation keys).
3. **Prefer unrepresentable over guarded.** Structure the type so the stale/invalid state cannot be formed or read, rather than adding a check that can be skipped or can fail (a wipe, a probe).
4. **Consumers read state *off the value*.** They do not probe the world to reconstruct what the value should have carried.
5. **Held state rides the persistence/restoration system — no side-channels (Nico, 2026-07-12).** The place a state-bearing value *lives* is the **persisted session/cursor state** — written through the chokepoint onto the_grid's OWN session bead, restored via `SessionScope` adopt-or-mint + `RestartReconciler` (the system we already have; `tg-5kb` extends it with pause/resume-near-close). NOT a worktree file, a ledger, an `mtime`, or any side-channel as the **source of truth**. A file may be agent-IO *transport* (a critic writes its verdict to a file the capability reads), but the **state-of-record is the persisted session state**, and it restores with the session — so a value's held state (its round, its version, its freshness) survives a bounce for free. As the persistence system matures (`tg-5kb`), state-bearing values ride it rather than re-inventing durability per feature.

## Consequences (to fill in)

- **Immediate instance (already filed):** the spec-committee verdict carries its `rewindCount` for positive round-verification; the critique wipe is demoted to a belt. *(the A15(5) fix bead.)*
- **A pass over the engine's state value types** — `StepOutcome`/`RouteVerdict`, the cursor, `SessionDisposition`, the committee verdicts — auditing where state is *inferred* vs *held*.
- **The full rule set + the migration:** LATER. This placeholder binds the direction; the specifics, exceptions, and the audit findings are TBD.

---

*This is an intentionally partial ADR. Fill in: the precise rule set (and its edges — where a side-channel is legitimately unavoidable), the audit of existing types, and the migration plan.*
