# SCRATCH — the bd contract re-pin + alignment backlog

**Status:** BLESSED + FILED (Nico, 2026-08-08). Epic **tg-8cuu**; children tg-lea2 (A1),
tg-7ukf (A2), tg-rnd8 (A3), tg-4rf6 (A4), tg-f9h0 (B5), tg-w1qo (B6), tg-u7b5 (B7),
tg-5616 (C8), tg-u47r (C9), tg-4wbv (C10), tg-l6r7 (D11), tg-uv69 (D12). The filing script
in §6 is now a record of what ran, not a pending action.
**Scope:** the_grid + beads_dart (+ two org-level env chores that fall out).
**Filing target:** the `tg` store, `--actor nico`, individual `bd create`/`bd dep add` —
**never `bd batch`** (the proxied server refuses it; the tg-ehht scar).

---

## 1. The finding that reshaped this from "migration" to "reconciliation"

the_grid's **paper contract** is pinned at **bd 1.0.5 (f9fe4ef2a)** — the fixtures
(`fixtures/upstream/2026-06-11-bd-1.0.5/`), the codec assumptions, and the CLAUDE.md
environment facts all say so. The **operational reality** (verified 2026-08-08):

- The machine's bd is a **Homebrew HEAD tap: `HEAD-a45199a546f9`** — an untagged build sitting
  past v1.1.2, at the claim-verify commit itself.
- **Every org store is already migrated to match**: `.local_version = HEAD-a45199a` in
  the_grid, genesis, lenny, power_station, space_station, archive-tgdog. The 0050
  dependencies-PK reshape and its ordered-migrator ceremony are **already behind us**.
- Every repo runs its own **`proxieddb`** dolt sql-server (bd's dbproxy-managed mode). The
  CLAUDE.md fact "db `tg` at `127.0.0.1:34947`" is a fossil — 34947 is the **gascity city's**
  dolt server, and the only live reference to it anywhere in the org is a historic log line in
  lenny's `interactions.jsonl`.
- `the_grid/.beads/.env` still carries `GT_ROOT=/Users/nico/gascity` — read by nothing we
  could find; another fossil.

**So the risk is inverted from what a "we're pinned behind" story implies.** We are not
conservatively behind; we are **running HEAD in production against a contract written for
1.0.5**, and `brew upgrade` moves the fleet without a decision. The project is: (a) make
main↔main compatibility a *tested, continuously verified* claim instead of an accident,
(b) gate production releases on upstream's published tags, (c) adopt the new primitives that
let us delete defensive machinery, (d) burn the fossils.

## 2. Upstream deltas that bear on us (evidence base)

From a read of `gastownhall/beads@869020c22` (origin/main, 2026-08-08), gascity origin/main,
and the shipped bd binary. Load-bearing items only; the full survey lives in the session
transcript.

**Fixes we inherit (the June flake, quantified and closed upstream):**
- **Claim-verify** (`a45199a54` — our exact binary): claim-family writes re-read on a fresh
  connection in Dolt server mode; phantom claims under a degraded sql-server fail loudly.
- **`row_lock` serialization fence + retry** on the work-queue hot paths: concurrent
  status/ownership writers get a replayed serialization conflict, not a silent cell-merge.
- **The metadata RMW race is fixed server-side** (#4732, `8ebd53e88`, 2026-07-19): merge-shaped
  metadata edits resolve against a re-read **inside** the mutation transaction
  (`SELECT … FOR UPDATE`). Upstream's own hammer: *7 of 200 exit-0 `--set-metadata` writes
  vanished under 8 writers* on the old binary. This is `StationBeadWriter` D-1's exact threat
  model. **Verified: `8ebd53e88` is an ancestor of `a45199a54`** — `git merge-base --is-ancestor`
  against the upstream beads history exited 0, so the shipped `HEAD-a45199a546f9` binary
  contains the server-side metadata RMW fix required by the `StationBeadWriter` D-1 threat model.

**New primitives worth adopting:**
- **CAS guards:** `bd update --if-assignee` / `--if-status` — atomic, nothing written on
  mismatch, **exit 13** + `"guard_mismatch": true`; composes with the `revision` token
  (`row_lock` exposed read-only on `bd show --json`).
- **Atomic metadata ops:** `MergeMetadata` / op-shaped `--set-metadata`/`--unset-metadata`.
- **`storage_class`** (`versioned|unversioned|ephemeral`, migration 0060) — a marker, no
  behavior change upstream; possible fit for molecule/step/session beads.
- **`bd serve` v0** — the HTTP API, built explicitly for orchestrators that shell per-op.
  **Unreleased-only** (no tag contains it), loopback-trust, bare-JSON bodies (no envelope),
  RFC 9457 errors, capability probing; **no `graph apply`, no `bd batch`, no watch endpoint**
  (snapshot-and-requery — compatible with our diff-is-authority stance).
- **The cross-version contract corpus** (`cmd/bd/protocol/`): golden JSON blobs, flat +
  envelope variants, byte-compared in upstream CI — explicitly *"the producer half of the
  Beads ↔ consumer cross-version contract-test system. A downstream consumer vendors this
  corpus and replays it against its own decoder."* **No consumer half exists anywhere yet.**

**Breaking behavior a 1.0.5-era consumer must absorb:**
- `bd update --status <done>` / `bd close` now **enforce close policy** (refuse on open
  children / live blocker); an unforced refusal **rolls back the whole batch**. Our
  `reapMolecule` closes a molecule root that has `parent-child` step children → leaves-first
  ordering or `--force`, plus a test (bead B5).
- Multi-ID `bd update` exits **nonzero on partial failure** with a machine-parseable failure
  report on the **last stderr line**.
- The no-ID "last touched" fallback is interactive-only; `BD_NON_INTERACTIVE=1` kills it dead
  — set it in every service environment (bead A4).
- `bd list --ready` now **refuses** ~20 filter combinations it used to ignore; `bd search`
  includes closed by default; dependency-type strings bounded at 32 chars.
- Envelope: `schema_version` **still 1** (verified against the v1.0.5 tag). Additive only:
  `pagination` metadata on truncated envelope output; `revision` on `bd show --json`.

**Coexistence-rule reality check (gc origin/main):**
- gc **deleted** its `.beads/hooks` event hooks — `installBeadHooks` now only uninstalls.
  Our "never touch `.beads/hooks/` (gc owns them)" rule's premise is gone.
- gc's convergence layer is **CAS-everywhere, explicitly not enforcing single-writer fleets**
  ("it does not enforce single-writer fleets" — their feature-flags design doc). Our
  read-only posture stands; its stated *reason* needs rewording.
- No gc process runs on this machine; no org store binds gc's dolt server.

## 3. Decided (this session, Nico)

- **D-BD1 — No pin. Two compatibility rails.** *(Label renamed from D-R1 post-filing: ADR-0014
  already owns a ratified "D-R1" for station residency; the §6 filing record below keeps the
  original label verbatim. Revised same session; the first draft said
  "freeze at HEAD-a45199a" — superseded by Nico before filing.)* the_grid does not pin bd.
  Instead:
  - **The main rail:** beads_dart `main` stays compatible with bd `main`. A scheduled CI job
    builds bd at upstream main, replays their contract corpus through our decoder, and runs
    our integration suite against it. A failure is a **drift alarm that files ready work** —
    never a silent break discovered mid-task.
  - **The release rail:** a production beads_dart release **never ships** until the full
    suite has passed against bd's **latest published (tagged) release**. Each release states
    the bd floor it requires. Features that exist only past the latest tag (today: `bd serve`,
    #4732 atomic metadata) stay behind the gate or degrade.
  - **Store-migration rule:** production stores move on the release rail only — a dev binary
    tracking main must never migrate a production store as a side effect. (CI uses throwaway
    stores exclusively.)
  - **Day-one exception, stated honestly:** the fleet's stores are *already* migrated past
    the latest published tag (`HEAD-a45199a` schema; old binaries fail fast on schema-newer
    DBs, so v1.1.2 cannot write them). The fleet is committed to the HEAD lineage until the
    next upstream tag catches up — the first release-rail gate therefore waits on that tag.
    This is a fact to burn down, not a precedent.
- **D-R2 — Backlog staged as this SCRATCH first**; filing happens only after Nico blesses,
  via §6 verbatim, `--actor nico`.
- **D-R3 — Strategic frame:** the_grid keeps moving, deliberately **more inline with bd** —
  consume bd's primitives natively (corpus, CAS, serve), keep policy derived, never
  parallel-name a bd concept (the existing naming law). Alignment work that doubles as a
  community artifact (A2) is preferred over private machinery.

**Ratification points embedded below** (collaborative-session decisions, carried out on
Nico's word, per the register rule — no ADR-0000 traffic): B6 amends ADR-0007 D-1's rationale
(corrected 2026-08-08 — the filing said ADR-0008, a same-name D-1 collision across the M4-P1/M5
build-order promotions; the serialization-queue D-1 lives in ADR-0007 ~line 189);
C10's outcome lands as a short decision note wherever it concludes.

## 4. The backlog

Phases order risk: **A = re-derive the contract** (no behavior change), **B = behavior fixes
under the new contract**, **C = opt-in evaluations**, **D = docs/env burn-down**. Blocking
edges only where real.

### Phase A — contract

- **A1 · Stand up the two rails.** (a) The **drift job**: scheduled CI that checks out
  `gastownhall/beads@main`, builds bd, and runs A2's replay harness + the integration suite
  against it; red files ready work with the failing upstream SHA. (b) The **release gate**:
  the beads_dart publish workflow refuses to ship unless the same suite is green against
  bd's latest published tag (and the release's declared bd floor). (c) Rewrite the
  grid-porting skill's version-*pin* record as a version-*policy* record — the skill's
  re-capture procedure becomes ref-parameterized instead of pin-anchored. The local brew
  HEAD tap stops being a hazard the moment the drift job exists: dev tracks main *on
  purpose*, and CI says whether that's currently true. *Blocks: A2, A3.*
- **A2 · The corpus replay harness in beads_dart — parameterized by upstream ref.** Fetch
  `cmd/bd/protocol` goldens at the ref under test (main on the drift rail, the tag on the
  release rail; an optional vendored snapshot for offline dev) and replay every blob (flat +
  `BD_JSON_ENVELOPE=1` variants) through beads_dart's decoder; a diff is a hard failure.
  This is the flagship: it is the mechanism that makes "our main is compatible with their
  main" a tested claim instead of an intention — and the cleanest possible first community
  contribution, completing the consumer half upstream built that nobody consumes.
- **A3 · Ref-parameterized fixture capture.** `fixtures/upstream/<date>-bd-<ref>/` per the
  grid-porting procedure, capturable on either rail; first run at current main, drift-diff
  against the 1.0.5 set; record deltas (known: `revision`, `pagination`).
- **A4 · Envelope/exit-code audit in beads_dart:** exit 13 (guard mismatch) as a typed
  outcome; multi-ID partial-failure report (last stderr line) parsed, never swallowed;
  `--ready` filter-refusal surfaced as a usage error; `BD_NON_INTERACTIVE=1` set in every
  spawned bd environment; audit any `bd search` callers for the closed-by-default flip.
  Verify whether `8ebd53e88` (#4732) is in the pinned binary and record the answer.

### Phase B — behavior

- **B5 · `reapMolecule` vs close-policy enforcement.** Leaves-first close ordering (steps
  before molecule root) or explicit `--force`, chosen deliberately; regression test that
  closes a poured molecule with open children under the pinned binary. Revisit the tg-ehht
  per-bead-close fallback while in there. *Blocked by: A1.*
- **B6 · Adopt CAS in `StationBeadWriter` guarded transitions** — `--if-assignee`/`--if-status`
  (+ `revision` where a read is already in hand) on ownership-sensitive writes; on mismatch,
  surface exit 13 as `OwnershipRefused`-adjacent, never retry blind. Then **re-scope D-1**:
  the per-target serialization queue's stated rationale (client-side RMW last-writer-wins) is
  fixed upstream; the queue stays as defense-in-depth + ordering guarantee, and ADR-0007's
  D-1 note gets a one-line amendment saying so (Nico ratifies; quote-and-supersede, never
  silent). *Blocked by: A4.*
- **B7 · Atomic metadata ops.** Where the writer does merge-shaped metadata edits, move to the
  op-shaped surface (`MergeMetadata` semantics) so the transaction owns the merge. **Release-rail
  gated:** #4732 is past the latest published tag, so this rides main-rail code behind the
  release gate (or a declared bd floor ≥ the tag that includes it). *Blocked by: A4's #4732
  ancestry check.*

### Phase C — opt-in evaluations (each ends in a decision note, not necessarily code)

- **C8 · `storage_class` for our bead families.** Molecule/step (durable-until-close),
  session (durable), gate/link — does marking them buy reap/sync behavior we want, or is it
  a no-op marker we skip? Small spike.
- **C9 · `bd serve` transport in beads_dart.** Hybrid shape: HTTP for the hot read/update/
  close path, CLI for pour (`graph apply` is not on the wire) and anything batch-shaped.
  **Gated on an upstream tag containing serve** — we do not ride Unreleased. Design note now,
  code later.
- **C10 · bd native leases vs `grid.lease.*`.** Likely outcome: **do not adopt; document
  why** — bd's lease is bead-claim liveness (assignee-shaped), ours is process/resource
  identity granted by a vendor (allocation-shaped); they answer different questions and the
  namespaces already don't collide. The bead exists so the "why" gets written where the next
  person will look.

### Phase D — docs/env burn-down

- **D11 · CLAUDE.md environment-facts + coexistence rewrite.** Kill the 34947 fact (per-repo
  `proxieddb` is the reality); recheck the 30s-idle-reap / ≤2-connections folklore against
  the current server mode; rewrite the two stale coexistence rules — hooks (gc deleted
  theirs; ours is a file-watch advisory signal, keep the *don't write* posture on principle)
  and single-writer (their reason changed: unenforced CAS ecosystem, our read-only stance
  unchanged).
- **D12 · Burn the fossils; unblock the gascity teardown.** Remove `GT_ROOT` from
  `.beads/.env`; sweep the org for any remaining `/Users/nico/gascity` / port-34947
  references; confirm nothing binds the gascity dolt server; hand the "safe to delete
  `~/gascity`" verdict to the machine-cleanup thread (which stalled on exactly this in
  June-era assumptions). *Blocked by: D11 (docs first, so the facts land before the ground
  moves).*

## 5. Explicit non-goals (this pass)

- No `bd serve` in production (C9 is a design note until upstream tags it).
- No adoption of bd claims/heartbeat/reclaim for grid work-driving (C10 documents the split).
- No molecule/pour schema changes; this is a substrate re-pin, not a circuit redesign.
- No gc re-integration of any kind — the RPP bridge exploration (same session) concluded
  unappealing; recorded in the session transcript, not pursued.

## 6. The filing script (run only after Nico blesses this doc)

From `~/development/engineering.memento/the_grid`, pinned-bd on PATH. Individual creates —
**no `bd batch`** (proxied server refuses it). Children hang off the epic with `parent-child`;
the only `blocks` edges are the real ones (A1→{A2,A3}, A4→{B6,B7}, A1→B5, D11→D12).

```sh
export BD_JSON_ENVELOPE=1
ACTOR="nico"
mk() { bd create "$1" -t "$2" -p 2 -d "$3" --actor "$ACTOR" --json | jq -r '.id // .data.id'; }

EPIC=$(mk "[epic] bd compatibility rails + alignment — main tracks bd@main, releases gate on published tags; adopt CAS/corpus/close-policy; burn the GT_ROOT/34947 fossils" epic \
  "Design surface: docs/SCRATCH-bd-repin.md (2026-08-08, D-R1 revised: no pin, two rails). Paper contract was pinned bd 1.0.5; fleet already runs HEAD-a45199a with all stores migrated (proxieddb mode). Phases: A contract rails, B behavior, C evaluations, D docs/env.")

A1=$(mk "A1: stand up the two compatibility rails (drift CI vs bd@main; release gate vs latest published tag)" task "No pin (D-R1 revised). Scheduled drift job builds bd@main + runs A2 harness + integration suite, red files ready work with the failing SHA. Publish workflow refuses release unless green vs latest published bd tag + declared floor. grid-porting version-pin record becomes a version-policy record; re-capture goes ref-parameterized. See SCRATCH-bd-repin §3 D-R1, §4 A1.")
A2=$(mk "A2: corpus replay harness in beads_dart, parameterized by upstream ref" task "Fetch cmd/bd/protocol goldens at the ref under test (main / tag; optional vendored snapshot for offline); replay flat + envelope variants through beads_dart's decoder; diff = hard failure. The missing consumer half of upstream's cross-version contract system; doubles as first community contribution. §4 A2.")
A3=$(mk "A3: ref-parameterized fixture capture; first run at bd@main; drift-diff vs 1.0.5 set" task "fixtures/upstream/<date>-bd-<ref>/ per grid-porting, capturable on either rail. Known deltas: revision on show --json, pagination metadata on truncated envelope output. §4 A3.")
A4=$(mk "A4: beads_dart envelope/exit-code audit (exit 13, multi-ID failure report, BD_NON_INTERACTIVE, #4732 check)" task "Typed exit-13 outcome; parse multi-ID partial-failure JSON on last stderr line; surface --ready filter refusals; set BD_NON_INTERACTIVE=1 in all spawned bd envs; audit bd search callers; verify 8ebd53e88 (#4732) ancestry in the pinned binary and record it. §4 A4.")
B5=$(mk "B5: reapMolecule vs upstream close-policy — leaves-first ordering + regression test" task "Close policy now refuses done-status on open children and rolls back unforced batches. Close steps before molecule root (or deliberate --force); regression test against pinned binary; revisit tg-ehht per-bead-close fallback. §4 B5.")
B6=$(mk "B6: adopt --if-assignee/--if-status CAS in StationBeadWriter; re-scope D-1 (ADR-0008 amendment, Nico ratifies)" task "CAS on ownership-sensitive writes; exit 13 surfaced, never blind-retried. D-1 queue stays as defense-in-depth; its RMW rationale is fixed upstream — one-line quote-and-supersede amendment. §4 B6.")
B7=$(mk "B7: adopt atomic metadata ops (MergeMetadata semantics) where the writer does merge-shaped edits" task "Gated on A4's #4732 ancestry verification. §4 B7.")
C8=$(mk "C8: eval storage_class for molecule/step/session/gate/link beads" task "Spike: does versioned/unversioned/ephemeral marking buy reap or sync behavior we want? Ends in a decision note. §4 C8.")
C9=$(mk "C9: design note — bd serve transport in beads_dart (HTTP hot path, CLI pour); GATED on upstream tag" task "No graph apply / batch / watch on the wire; bare-JSON + problem+json + capability probing contract. Do not ride Unreleased. §4 C9.")
C10=$(mk "C10: decision — bd native leases vs grid.lease.* (expected: do not adopt; document why)" task "bd lease = bead-claim liveness; grid lease = process/resource identity from a vendor. Write the why where the next person will look. §4 C10.")
D11=$(mk "D11: CLAUDE.md env-facts + coexistence rewrite (34947 fossil, proxieddb reality, hooks + single-writer rules)" task "Kill the 34947/GT_ROOT facts; recheck idle-reap/connection folklore under proxieddb; rewrite the hooks rule (gc deleted theirs) and the single-writer rationale (unenforced CAS upstream; our read-only stance unchanged). §4 D11.")
D12=$(mk "D12: burn GT_ROOT + gascity references; confirm nothing binds the gascity dolt server; unblock ~/gascity teardown" task "Remove GT_ROOT from .beads/.env; org-wide sweep for /Users/nico/gascity + port 34947; verdict handed to the machine-cleanup thread. §4 D12.")

for c in $A1 $A2 $A3 $A4 $B5 $B6 $B7 $C8 $C9 $C10 $D11 $D12; do
  bd dep add "$EPIC" "$c" --type parent-child --actor "$ACTOR"
done
bd dep add "$A2" "$A1" --type blocks --actor "$ACTOR"
bd dep add "$A3" "$A1" --type blocks --actor "$ACTOR"
bd dep add "$B5" "$A1" --type blocks --actor "$ACTOR"
bd dep add "$B6" "$A4" --type blocks --actor "$ACTOR"
bd dep add "$B7" "$A4" --type blocks --actor "$ACTOR"
bd dep add "$D12" "$D11" --type blocks --actor "$ACTOR"
```

**Arm-awareness note:** under a resident station, *ready = armed*. The `blocks` edges above
keep B/D dark until their gates clear, but A1 and the C evaluations are born ready. The tg
ready set already carries open planning beads sitting undriven, so this matches current store
behavior — but if a resident station is armed against tg before these file, bless the timing
deliberately.
