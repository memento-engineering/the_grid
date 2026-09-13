# Restore under cut: operator runbook

Restore under cut is a **quiesced void-and-redrive**. There is no head-stamp
detector: the restored ledger and trajectory are a paired snapshot, and every
session that was open at that snapshot is retired before execution resumes.

1. Halt new admission with the filed operator verb `tg-9ud2`.
2. Take the station down and verify its controller and trajectory harness have
   stopped.
3. Restore the paired state-store and trajectory-store snapshot. Never restore
   only one side.
4. From the restored state store, enumerate every open `type=session` bead on
   the station, across every seat and including operator-paused sessions.
5. Void each enumerated session with the filed session-void verb `tg-od2e`.
   Preserve the verb's retirement metadata and audit reason; do not hand-edit
   the session key.
6. Requery the complete state snapshot and verify that the station-wide open
   session set is empty.
7. Boot the station with trajectory discipline `cut`. A quiesce refusal here
   means the drain is incomplete; take the station down and return to step 4.
8. Resume admission with `tg-9ud2`. Normal bd readiness redrives the work whose
   restored sessions were voided.

This runbook consumes the two filed verbs; it does not re-file or replace
either one. Break-glass is not a substitute: it is a destructive shadow boot,
not a restore workflow or debugging posture.
