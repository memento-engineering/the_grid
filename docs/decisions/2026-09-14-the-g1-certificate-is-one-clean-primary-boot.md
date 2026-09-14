---
status: accepted
date: 2026-09-14
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor (lunar station seat)"
informed: []
register:
  spec: 1
  slug: the-g1-certificate-is-one-clean-primary-boot
  surfaces:
    - "packages/grid_trajectory/lib/src/cli/soak_certificate.dart"
    - "packages/grid_trajectory/lib/src/cli/traj_certify_command.dart"
  obsoletes: []
  updates:
    - wave-2-flip-scope-soak-and-kill-date
  obsoleted-by: null
  updated-by: []
  bead: tg-78ft
  legacy-id: null
---

# The G1 certificate is one clean primary boot; the comparator counters are reported, never gating

## Context and Problem Statement

`wave-2-flip-scope-soak-and-kill-date` defined the G1 soak as three consecutive scoped primary boots certified by `traj certify --boots 3` with every row passing. Running that soak on lunar from 2026-09-13 to 2026-09-14 (epochs 73 through 82) found three real engine defects that the cut needs regardless (the terminal-sweep memo, the external-close obligation starving on ledger-absent heads, never-spawned void heads that nothing can close) and four defects in the certificate's own arithmetic (pending step nodes counted as misses, post-epoch head misses latched with no grace, a retired-round carve-out that fires on nothing, would-refuse gating). Roughly two thirds of the operating day went to making the measurement correct rather than to the migration that retires the legacy writes, and the counted window restarted three times because each certificate fix invalidated the boots before it. Stage 2 (`tg-ersi`), already ruled to start before the cut, had not moved.

On 2026-09-14 epoch 82 — the first boot under the clean recipe (adopted set empty, grid_engine 0.4.0-dev.8, the cgo bd fork) — `traj certify --boots 1` read PASS on every row: posture, clean (twelve gating counters at zero), shape-coverage, would-refuse, consecutive. Nico ruled that this is the certificate and that the effort goes to Stage 2 now.

## Decision Outcome

One clean primary boot certifies G1: a boot that serves `mode=primary` with the overlay engaged and health live throughout, whose twelve gating counters read zero, is the certificate the cut waits on. Epoch 82 on lunar is that boot; `lunar_station-2i9` closes on it and `lunar_station-bzt` cuts.

From this entry on the dual-read comparator's counters are REPORTED diagnostics: `traj certify` may keep printing them per boot, but no counter gates a cut, a release, or a stage boundary again. A counter that moves is filed as a bead with its receipt, never answered by another boot.

The migration's effort goes to Stage 2 (`tg-ersi`, retiring step and molecule bead creation) and then Stage 3, which delete the legacy writes the comparator reconciles; the stopgaps recorded today (`tg-lnyx`, `tg-62mf`, `tg-6u0f`) are removed on that path.

### Consequences

* Good, because the cut and Stage 2 start tonight on evidence already in hand instead of after two more boots of ceremony.
* Good, because a wrong counter can no longer cost a day: it becomes a bead, not a restart.
* Bad, because a single boot is a weaker statistical claim than three; a regression between boots is caught by the reported counters and the beads they raise, not by a gate.
* Bad, because the human-only checklist items (drills, `traj show` sample, shadow-diff, the W2.5 event-shape rows) are no longer tied to the cut; they remain Nico's to run when he chooses.
