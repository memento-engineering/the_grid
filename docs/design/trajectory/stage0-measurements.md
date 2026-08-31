# Stage-0 measurements — the seven the probe could not run

**Status:** measured 2026-08-31, this machine, hermetically. Closes
[`storage-call.md`](storage-call.md)'s "What stage 0 must still measure" list
(items 1–7). Every number below was produced by a committed script under
`packages/grid_trajectory/tool/measurements/`; re-running the script
regenerates it.

**Reproduce:**

```bash
cd packages/grid_trajectory
dart run tool/measurements/m1_bd_sibling_db.dart
dart run tool/measurements/m2_online_gc.dart
dart run tool/measurements/m3_append_latency.dart
dart run tool/measurements/m4_fence_bounce.dart
dart run tool/measurements/m5_rebuild_duration.dart
dart run tool/measurements/m6_restore_drill.dart
dart run tool/measurements/m7_ci_guard_pin.dart
```

Each script picks its own temp data dirs under `$TMPDIR`;
`GRID_TRAJECTORY_SCRATCH` pins them elsewhere (the recorded run used a
session-local scratchpad). `GRID_TRAJECTORY_REAL_STORE` names the `.beads`
directory M1b copies and has **no default** — M1b runs only when it is set,
and skips (saying so) when it is not. The recorded M1b numbers below came from
a run with it pointed at the reference deployment's store:

```bash
GRID_TRAJECTORY_REAL_STORE=/path/to/<station>/.grid/.beads \
  dart run tool/measurements/m1_bd_sibling_db.dart
```

`dolt` must be on `PATH`: its absence fails a run rather than skipping it,
matching the guard suite's fail-closed contract.

**Environment.** macOS 26.6.2, Apple M3 Ultra (28 cores), 96 GB, APFS.
`dolt 2.2.2` (the version CI pins; 2.3.1 exists and the pin is deliberate).
`bd HEAD-a45199a` (Homebrew). Dart SDK 3.12.2. Every server is a throwaway
`dolt sql-server` on an ephemeral port over a temp data dir; the single
exception — M1b's copy of the live tranquility store — reads the source with
`cp` only and defangs the copy before any process starts.

---

## Verdicts at a glance

| # | Measurement | Result | Verdict against the design |
|---|---|---|---|
| M1 | bd sibling-db tolerance | bd wholly unaffected by a sibling `trajectory` database, on a fresh store AND on an 18 GB copy of the live one — **and bd's own commit is `-a`-shaped** | Separate-db safety gate **PASSES**. Same-db flip condition 2 **FAILS PERMANENTLY** — the flip can never fire |
| M2 | online gc, shared server | `CALL DOLT_GC()` on `trajectory`: ~120 ms, reclaims ~98%, **zero** connection kills, **zero** ledger or append failures | Separate-**store** flip condition 1 does **NOT** fire. gc runs online on a steady cadence; no quiesced window needed |
| M3 | append latency, full synchronous set | **62.3 appends/s** (mean 16.05 ms) with `proj_meta` + P1, under concurrent ledger load | 2.2× above the top of §5's 22–28/s band. Retreat **not authorized**. §6's "plausibly 35–45 ms" is **refuted** |
| M4 | fence across a mid-transaction bounce | Typed `AppendInternalError` in 17–20 ms, no hang, **no double append**, guarded reconnect resumes or goes inert correctly | Contract **HOLDS**. One recorded gap — a raw throwable escaped while the server was down — **closed in this change** |
| M5 | rebuild duration | 100k records replayed in **3.9 s** (25,458 rows/s), linear from 25k | **7%** of the stated 60 s recovery budget. Epoch-boundary snapshot contingency **not triggered** |
| M6 | two-database restore drill | Paired snapshot/restore works; mandatory replay, staleness warning and liveness-unknown all behave as written. The head re-stamp was drilled **in the harness, against a table the harness invents** — the shipped repair does not exist yet | Contract **HOLDS** for everything shipped; one wording amendment needed (snapshot vs backup restore); the re-stamp repair is specified, not delivered |
| M7 | CI guard pin | CI pins dolt 2.2.2, local is 2.2.2 (**no skew**); 23 guards green on this tree in 10.7 s; PR #241's job is SUCCESS | Pin is **real and gating** |

**Net:** the ratified storage call — a separate `trajectory` database on bd's
own server — survives every one of the seven. One measurement (M1's `-a`
finding) upgrades it from "the better of two live options" to "the only option
that was ever available".

---

## M1 — bd's tolerance of a sibling database

**Question (storage-call item 1).** Does bd tolerate `CREATE DATABASE
trajectory` under its data dir? Is `@@dolt_transaction_commit` set in bd's
config? Is bd's write path `-a`-shaped? This is the same-db flip's factual
gate and the separate-db safety gate at once.

### Method

`dart run tool/measurements/m1_bd_sibling_db.dart` — two halves.

**M1a, fresh store.** `bd init --prefix m1p --proxied-server --skip-agents
--skip-hooks --non-interactive` in a scratch git repo — `--proxied-server` is
the REAL deployment mode (proxy + child dolt rooted at `.beads/dolt/`, exactly
the tranquility layout). 200 synthetic beads via `bd create`. A six-operation
sweep (`list`, `list --json`, `ready`, `count`, `create`, `stats`) before and
after the sibling appears. Then `CREATE DATABASE trajectory` +
`applyTrajectorySchema` on the same child server, ten records through the real
fenced appender, and the sweep again.

**M1b, copy of the live store.** `cp -Rc` (APFS `clonefile`) of
`lunar_station/.grid/.beads` — 18 GB, source read-only, its running server and
pid/lock/proxy files never opened. The copy is defanged before any process
starts: listener port rewritten (**the source's child server holds the
recorded port 63412 right now** — an unrewritten copy would have bd's proxy
dial the LIVE store), `proxy.pid`/`proxy-child.pid`/`*.lock`/`*.log` deleted,
`sync.remote` stripped from `config.yaml`. Then `bd -C <copy> --sandbox list`,
`count`, the same sweep, the same sibling experiment.

### Observed

**Credentials — a real cost, found immediately.** bd's child server has
exactly one user, the auto `root@localhost`, and it **cannot authenticate over
the 127.0.0.1 TCP address** any client dials (`1045 Access denied` over both
`127.0.0.1` and `localhost`), with no unix socket open. A wildcard-host
credential can therefore only be seeded **offline, with the server stopped**:

```bash
dolt --doltcfg-dir .beads/dolt/.doltcfg sql \
  -q "CREATE USER IF NOT EXISTS 'gridboot'@'%' IDENTIFIED BY '…'; GRANT ALL ON *.* TO 'gridboot'@'%';"
```

**M1a sweep, before → after the sibling database:**

| bd operation | before | after | verdict |
|---|---|---|---|
| `list --limit 50` | exit 0, 133 ms | exit 0, 144 ms | unchanged |
| `list --json` | exit 0, 131 ms | exit 0, 130 ms | unchanged |
| `ready` | exit 0, 141 ms | exit 0, 142 ms | unchanged |
| `count` | exit 0, 121 ms | exit 0, 122 ms | unchanged |
| `create` | exit 0, 151 ms | exit 0, 150 ms | unchanged |
| `stats` | exit 0, 122 ms | exit 0, 124 ms | unchanged |

`SHOW DATABASES` went `[dolt, information_schema, m1p, mysql]` →
`[…, trajectory]`. bd never noticed. Ten records landed through the fenced
append path while bd worked.

**The boundary, asserted not assumed.** `provisionTrajectoryUser` grants on
`trajectory.*` only, and bd's own database refuses that credential:
`MySQLServerException [1105]: Access denied for user 'trajectory'@'%' to
database 'm1p'`.

**bd's commit behavior.**

- `bd config get dolt.auto-commit` = **`on`** (bd commits after each write —
  not the CLI default `off`).
- bd's server `config.yaml` carries `user_session_vars: []` — **no
  `dolt_transaction_commit`** is set server-side.
- 269 dolt commits for ~201 bd writes; messages are `bd: create <id>`.
- **`bd`'s commit IS `-a`-shaped.** A stand-in table `traj_standin` was
  created and dirtied inside bd's database by a third-party connection; the
  next `bd create` swept it into bd's own commit. `dolt_diff` names it
  directly:

  ```
  dolt_diff: traj_standin in "bd: create m1p-y0oz"
  dolt_diff: events       in "bd: create m1p-y0oz"
  dolt_diff: issues       in "bd: create m1p-y0oz"
  ```

**M1b, the live copy.** `cp -Rc` copied 18 GB in **38–87 ms** (clonefile:
copy-on-write, near-zero space, source blocks untouched). The hot copy
**loaded cleanly** — `bd list` exit 0, `bd count` = **7,258** issues. No
live-copy inconsistency. `SHOW DATABASES` on the copy:
`[dolt, information_schema, mysql, tranquility, tranquility.fresh-empty]` →
`+ trajectory` after the §4 schema applied beside the real tranquility
database. Sweep before → after:

| bd operation | before | after | verdict |
|---|---|---|---|
| `list --limit 50` | exit 0, 159 ms | exit 0, 190 ms | unchanged |
| `list --json` | exit 0, 206 ms | exit 0, 216 ms | unchanged |
| `ready` | exit 0, 323 ms | exit 0, 188 ms | **warm-up, not a sibling effect** — see below |
| `count` | exit 0, 132 ms | exit 0, 132 ms | unchanged |
| `create` | exit 0, 178 ms | exit 0, 169 ms | unchanged |
| `stats` | exit 0, 146 ms | exit 0, 144 ms | unchanged |

**Read the verdict column exactly as the harness computes it:** `_bdSweep`'s
comparison is **exit-code equality** — "unchanged" means bd still worked, not
that the timing held. The timings are informational, and one of them did move.

`ready` is the only operation whose time changed materially, and it moved the
wrong way for a regression: 323 → 188 ms, **faster** after the sibling
appeared. That is a **warm-up delta, not a sibling effect**. `ready` is bd's
heaviest read shape (dependency-aware readiness over 7,258 issues) and the
"before" number is its first invocation on a just-started server over a
freshly cloned 18 GB store; the "after" number is the same query on a warm
one. Calling it "unchanged" would be wrong in both directions — it is not
unchanged, and it is not evidence about the sibling. The sweep is one
before/after pair per operation with no repeats: enough to catch a
sibling-sized regression, not enough to characterize a 135 ms delta.

### Verdict

**Separate-database safety gate: PASSES.** bd tolerates the sibling on a fresh
store and on a copy of the real 18 GB one, with no measurable effect on any of
its read or write surfaces. The `CREATE DATABASE` is invisible to bd's
enumeration; no nil-store-class regression appeared.

**Same-db flip condition 1 (bd cannot tolerate a sibling): NOT MET** — bd
tolerates it fine.

**Same-db flip condition 2 (bd's commits are never `-a`-shaped): FAILS, and
fails permanently.** This is the load-bearing result. The storage call
recorded T4's re-scoped flip condition as "checkable once, but it must stay
true across every future bd release". It is not even true *now*: bd's write
path commits everything dirty in its database, including tables it does not
own. Under the same-database shape, every trajectory row in flight would be
swept into a `bd: create …` commit at bd's cadence, destroying both the
service's own commit cadence and the operator's commit-by-commit attribution
practice — the practice that produced the 81%-retry-churn diagnosis this whole
decision rests on.

The flip requires **all three** conditions; two of the three are now dead. The
same-database option cannot return without a change in bd itself.

### Implications

1. **The storage call's "flip back to the same database" clause is now
   unreachable.** Amend §10.2 / the flip-conditions block to record condition 2
   as measured-false with this receipt, rather than as an open check.
2. **Provisioning needs a documented stop/start window.** The trajectory SQL
   user cannot be created over the network on bd's server, because the only
   account that exists cannot authenticate over TCP. First-boot provisioning
   is: quiesce the service → stop bd's proxy and child (standing pid/lock
   cleanup) → offline `dolt sql -q "CREATE USER …"` with `--doltcfg-dir` →
   restart → `createTrajectoryDatabase` + `provisionTrajectoryUser` over the
   bootstrap credential. This belongs in the operational contract; today it is
   nowhere.
3. **A hot copy of the store is a usable artifact on APFS.** `cp -Rc` of an
   18 GB store under active write took 87 ms and loaded. That is a cheap
   pre-flight for any risky operation against the real store, and it should be
   the standard first step of one.

---

## M2 — online gc on a shared multi-database server

**Question (storage-call item 2).** Does `CALL DOLT_GC()` on `trajectory`
terminate connections serving the ledger database? Does the proxy recover, or
does it need the standing pid/lock cleanup? Is there a mode or window that
leaves bd undisturbed? This sets the gc schedule and is separate-**store**
flip condition 1.

### Method

`dart run tool/measurements/m2_online_gc.dart`. One hermetic server, two
databases. `ledger` (2,000 issues + an event log) under a continuous
read+write loop on its own connection. `trajectory` under the real fenced
appender writing Family-1 lifecycles continuously. A third connection calls
`DOLT_GC()` on `trajectory` twice — once after a 12 s soak, once after a
further 20 s so the second pass faces a real journal, not a thin one.

### Observed

```
pre-gc:  ledger reads=1494 writes=1494 failures=0 | trajectory appends=720
trajectory dir before gc: 26.0 MB
DOLT_GC() on trajectory (pass 1): returned normally in 119ms
trajectory dir immediately after gc pass 1: 0.6 MB (at 730 appends)

mid-soak: ledger reads=4029 | trajectory appends=1989
trajectory dir before gc pass 2: 57.9 MB (at 1990 appends)
journal growth between the passes: 57.3 MB over 1260 appends ⇒ 46.6 KB/append
DOLT_GC() on trajectory (pass 2): returned normally in 117ms
trajectory dir immediately after gc pass 2: 1.6 MB

post-gc: ledger reads=5038 (+3544) writes=5038 (+3544) failures=0 (+0)
post-gc: trajectory appends=2481 (+1761) append failures=0
appender state: inert=false halted=false
trajectory dir at the end: 24.6 MB    ledger dir at the end: 37.1 MB
old ledger session after gc:   OK (2000 issues)
fresh ledger session after gc: OK (2000 issues)
old trajectory session after gc: OK (2481 rows)
server log lines mentioning "kill": 0
```

**Journal growth and reclaim, as a by-product.** Between the two gc passes
1,260 appends grew the trajectory dir by 57.3 MB — **46.6 KB per append**,
about twice the probe's T8 estimate of 22–24 KB (T8 measured a bare append;
this figure carries the whole §5 write path — fence CAS, belt read, the row,
the terminal guard, and `proj_meta`). gc reclaims essentially all of it:
26.0 MB → **0.6 MB**, and 57.9 MB → **1.6 MB**. That is ~98% reclaimable,
matching T8's "~99% is gc-reclaimable" and confirming gc is mandatory rather
than hygienic.

### Verdict

**Separate-store flip condition 1 does NOT fire.** Online gc against
`trajectory` on a shared server killed nothing: zero connection terminations
in the server's own log, zero ledger read or write failures, zero append
failures, the appender neither inert nor halted, and every pre-existing
session — ledger and trajectory alike — still usable afterwards. Both passes
cost ~120 ms and reclaimed ~98% of the directory.

### Implications

1. **gc runs on a steady online cadence.** The storage call left this open
   ("steady interval if online gc proves non-disruptive, service-quiesced
   windows if not"). It is non-disruptive: choose the steady interval and drop
   the quiesced-window contingency.
2. **Size the interval by the journal budget, not by the clock.** At the
   measured 46.6 KB/append and M3's ~62 appends/s storm tempo the trajectory
   working set grows **~2.9 MB/s** — ~170 MB/minute at full storm. A 5-minute
   gc cadence caps the directory near 900 MB; a 1-minute cadence near 180 MB.
   Each pass costs ~120 ms, so cadence is essentially free and should be chosen
   for the size ceiling the operator wants, not for the cost. Note the storage
   call budgeted "~1 MB/s at storm tempo" from T8's number; the real figure is
   ~3× that, and the gc schedule should be set from this one.
3. **The bd proxy was never involved.** gc against a sibling database does not
   reach bd's pid/lock/proxy files at all, so the standing kill/cleanup hazard
   does not apply to the trajectory gc schedule.

---

## M3 — append latency with the current synchronous projection set

**Question (storage-call item 3).** T7's 42 appends/s carried one projection
upsert; §6 wants P1–P6+P8 in-transaction, "plausibly 35–45 ms/append". Measure
on a shared server with live ledger traffic, at 8-attempt storm shape, against
§5's pre-authorized-retreat threshold of 22–28 appends/s.

### Method

`dart run tool/measurements/m3_append_latency.dart`. One hermetic server,
`ledger` under continuous read+write load throughout, `trajectory` written by
ONE appender (§12: there is only ever one). Eight logical writers' lifecycles
are interleaved round-robin into that single serialized stream — 8 × 26 × 10 =
**2,080 appends** per run.

The Stage-1 shape is spliced in without forking the Stage-0 appender: a
`TrajectoryDb` decorator recognises the appender's own `proj_meta` upsert
(its step 5, the only `proj_meta` statement it issues, carrying the
just-assigned `seq`) and runs seat A's `sessionHeadSqlFor` immediately after
it, **inside the same transaction, at the same seq**. Three runs:

- **control** — today's Stage-0 appender, `proj_meta` only;
- **Stage-1** — `proj_meta` + the P1 delta, the real incremental-mode SQL;
- **§6 proxy** — the P1 statement seven times. This is a *statement-count*
  proxy and nothing more: it buys the right number of in-transaction round
  trips and writes, and proves nothing about P2–P8's own row shapes.

### Observed

| run | n | mean | p50 | p90 | p99 | max | rate |
|---|---|---|---|---|---|---|---|
| control (`proj_meta`) | 2080 | 16.03 ms | 15.87 | 20.07 | 23.89 | 44.55 | **62.4/s** |
| Stage-1 (`proj_meta` + P1) | 2080 | 16.05 ms | 15.80 | 20.91 | 24.93 | 99.14 | **62.3/s** |
| §6 proxy (+7 upserts) | 2080 | 16.29 ms | 15.89 | 20.18 | 23.80 | 155.88 | **61.4/s** |

All three landed 2,080 of 2,080 with zero refusals; the P1 run produced 208
`proj_session_head` rows (26 lifecycles × 8 writers), exactly as folded.
Concurrent ledger traffic across the whole run: **13,248 reads and 13,248
writes, zero failures**. Three verified dolt commits per run under the §5
cadence.

### Verdict

**No retreat.** 62.3 appends/s with the full current synchronous set is
**2.2× the top** of §5's 22–28/s band. Separate-store flip condition 2 does
not fire.

**§6's cost estimate is refuted, and interestingly so.** Adding the P1 delta
cost 0.02 ms — noise. Adding seven statements cost 0.26 ms. The per-append
cost is **not** statement-bound: ~16 ms is the fixed price of the transaction
itself (dolt's commit / working-set write), and the projection set rides
almost free inside it. The draft's "plausibly 35–45 ms/append" assumed a cost
model that does not hold on this engine.

### Implications

1. **The projection set's cost is bounded by the transaction, not by the
   statements in it — as far as a statement-count proxy can show.** What was
   measured is P1 for real, and then the P1 statement run seven times. That
   buys the right number of in-transaction round trips and writes and
   **nothing about P2–P8's actual row shapes**: a projection with wider rows,
   more indexes, or a read-modify-write inside the transaction is not this
   measurement. So the honest form of the implication is conditional — §6's
   full set is expected to ride nearly free *if* its statements resemble
   P1's, and the ~16 ms transaction floor leaves 2× headroom to absorb a fair
   amount of divergence. The latency caveat in §6's framing should be
   re-based on this number rather than deleted outright, and the real set
   re-measured with this harness once P2–P8's shapes exist.
2. **The throughput lever is transactions, not statements.** If a future storm
   ever needs more than ~60 appends/s, the only lever that moves is batching
   several records into one transaction — and that trades away the per-record
   fence granularity §5 depends on. It should not be reached for speculatively.
3. **The tail is worth watching, not acting on.** p99 stayed under 25 ms in
   every run, but max jumped 44 → 99 → 156 ms as statements were added. Tail
   growth is real even where the mean is flat; if a Stage-1 storm ever shows
   the tail mattering, this harness is the instrument.

---

## M4 — the fence across a server bounce mid-transaction

**Question (storage-call item 4).** Kill the server between an appender's
UPDATE and COMMIT: does the service fail the fence guard **loudly** rather
than hanging or double-appending, and does the reconnect land in §10.1's
guarded-reconnect contract?

### Method

`dart run tool/measurements/m4_fence_bounce.dart`. A `TrajectoryDb` decorator
SIGKILLs the real `dolt sql-server` process **before** the named statement
reaches the wire, so the client is talking to a socket that is already gone.
Three scenarios, each preceded by a healthy ten-record warm-up:

- **S1** — kill after the fence CAS, before the row INSERT;
- **S2** — kill at COMMIT, transaction otherwise complete (the worst case);
- **S3** — S2, but a successor appender claims the next epoch during the
  outage.

Every append is wrapped in a 30 s timeout: the guard exists so "hung" is a
recorded outcome and not an unbounded wait.

### Observed

| | S1 (before INSERT) | S2 (at COMMIT) | S3 (successor claims) |
|---|---|---|---|
| outcome | `AppendInternalError` | `AppendInternalError` | `AppendInternalError` |
| elapsed | 20 ms | 20 ms | 17 ms |
| hang? | no (30 s guard never fired) | no | no |
| appender state | inert=false halted=false | inert=false halted=false | inert=false halted=false |
| append while server DOWN | **THREW `MySQLClientException`** | **THREW `MySQLClientException`** | **THREW `MySQLClientException`** |
| reconnect | `ReconnectResumed` | `ReconnectResumed` | `ReconnectInert(stale 1, live 2)` |
| fence cell | 4294967306 → 4294967296 (re-seeded) | 4294967306 → 4294967296 (re-seeded) | 8589934592 → 8589934592 (**untouched**) |
| rows for the station | 10 → 10 | 10 → 10 | 10 → 10 |
| rows under the victim's idem key (all epochs) | **0** | **0** | **0** |
| boot belt full-scan | clean | clean | clean |
| after reconnect | re-append → `Appended`, again → `AppendDeduped`, rows 10 → 11 | same | append → `AppendFencedOut` |

### Verdict

**The contract holds.** In all three scenarios the interrupted append returned
a sealed, typed `AppendInternalError` in under 20 ms with the transaction
rolled back server-side; the row never landed (zero rows under the victim's
idem key, computed across every epoch the station ever claimed, since the idem
key is epoch-scoped); the belt full-scan came back clean; and re-presenting the
record after a resumed reconnect landed it exactly once, with a second
presentation deduping.

The guarded reconnect discriminates correctly: with our epoch still live it
resumes and re-seeds the fence cell (the low 32 bits — the CAS counter —
reset while the epoch in the high bits is preserved); with a successor holding
epoch 2 it goes **inert without touching the cell** (8589934592 unchanged),
emits the `reconnectInert` service event, and every subsequent append is
`AppendFencedOut`.

### Implications

1. **RECORDED GAP — one path escaped the sealed hierarchy. CLOSED in this
   change.** An append attempted while the server was still down threw a raw
   `MySQLClientException` instead of returning a typed outcome. The cause was
   structural: `append()` called `_assertBranchPin()` **before** entering its
   try/catch, so a dead socket surfaced there as an unclassified throwable,
   and §5's error contract ("no raw throwable escapes the sealed hierarchy")
   held for `_appendInTransaction` but not for `append`. The assertion now
   runs inside `append()`'s classification boundary: a dead connection returns
   `AppendInternalError`, an off-main session returns `AppendCorruptionHalt`
   (the pin still halts first, so fail-closed is unchanged), and a DIRECT
   `doltCommitIfDue()` still throws — that path has no outcome to carry, and
   guard 5 pins it. Pinned by unit guards in
   `test/append/trajectory_appender_test.dart`.
2. **The 20 ms failure is the honest bounce cost.** There is no hang risk to
   design around: the client sees the dead socket immediately. The §10.1
   "reconnect-with-fence-recheck" path can be driven eagerly.
3. **The dry-arm lock semantics on record are consistent with this.** A
   refused live boot buffers its refusal; here a fenced-out appender goes
   inert and appends nothing further, "not even its refusal" — the two
   behaviors agree.

---

## M5 — rebuild duration at realistic log size

**Question (storage-call item 5).** Golden replay from seq 0 at ≥100k rows
(the probe managed 2k), against a stated recovery budget. The epoch-boundary
snapshot contingency triggers on this number.

### The budget, stated

**60 seconds.** That is one station bounce. The station cannot `reload` (the
snapshot-resident rule), so every code change is a bounce, restore is a
bounce, and a fold rebuild that outruns the bounce is a rebuild the operator
will start skipping. 60 s also sits comfortably inside the 90 s liveness
threshold the harness already uses, so a rebuild inside budget cannot itself
make a station look dead.

### Method

`dart run tool/measurements/m5_rebuild_duration.dart`. Rows are seeded by bulk
INSERT, deliberately — the measurement under test is the REPLAY, and M3
already measures what the fenced append path costs; a 100k-row seed through
the appender would take ~27 minutes and would measure M3 again. Three
tranches, with a full `replaySessionHeads` after each so the scaling curve is
visible rather than assumed. Each replay's cost is also split into the
whole-log SELECT, the pure in-memory fold, and the truncate-and-rewrite.

### Observed

| rows | sessions | replay | rate | read | pure fold | % of 60 s budget | dir |
|---|---|---|---|---|---|---|---|
| 25,000 | 2,500 | 1.0 s | 25,278 rows/s | 0.2 s | 0.04 s | 2% | 82.9 MB |
| 50,000 | 5,000 | 2.0 s | 25,329 rows/s | 0.4 s | 0.04 s | 3% | 98.2 MB |
| 100,000 | 10,000 | 3.9 s | 25,458 rows/s | 0.8 s | 0.06 s | **7%** | 181.1 MB |

`appliedSeq` reached the log head every time, `skipped` was empty every time,
head counts matched the session counts exactly, and `foldStaleness` reported
`lag=0` after each replay.

### Verdict

**Inside budget by a wide margin, and linear.** 100k records rebuild in 3.9 s —
7% of the stated 60 s. At this rate the budget holds to roughly **1.5 million
records**, which at the §5 storm tempo is on the order of a week of continuous
8-attempt storming without a single gc-independent concern. **The
epoch-boundary snapshot contingency is not triggered and should stay
unbuilt.**

### Implications

1. **The fold itself is free; the write-back is the cost.** At 100k rows the
   pure in-memory fold took 0.06 s and the whole-log SELECT 0.8 s — the
   remaining ~3.0 s is the truncate plus 10,000 single-row `proj_session_head`
   INSERTs. Rebuild cost therefore scales with **session count**, not record
   count. If the number ever matters, multi-row INSERT batching in
   `replaySessionHeads` is a ~10× lever sitting untouched.
2. **The §6 projection expansion is safe from this angle too.** More
   projections mean more write-back rows, but the budget has 14× headroom.
3. **Storage, not rebuild time, is the growth pressure.** 100k records
   occupied 181 MB of working set before gc — which is M2's story, not M5's.

---

## M6 — the two-database restore drill

**Question (storage-call item 6).** Restore both databases from a paired
snapshot, run mandatory `traj replay`, verify liveness renders `unknown`, and
exercise the head re-stamp repair for `grid.head.last_seq` pointers that
outrun a restored trajectory — the only cross-database consistency seam this
shape has.

### Method

`dart run tool/measurements/m6_restore_drill.dart`, in three acts.

**M6 (the drill as written).** Seed both databases — 700 trajectory rows
through the real appender, 500 ledger issues, a `traj_pulse` beat, a
ledger-side `grid_head.last_seq` stamp. Quiesce the server (SIGTERM, port
freed). Snapshot the WHOLE data dir as one unit. Restart, write 200 more rows,
advance the head stamp. Destroy both database directories. Restore the pair.
Restart. Run the mandatory replay and read every surface.

**M6b (the history-only shape).** A filesystem snapshot carries the working
set; a `dolt backup`/`dolt clone` restore carries committed history only, so
the `dolt_ignore`'d projections arrive **empty**. Emptying `proj_session_head`,
`proj_meta` and `traj_pulse` reproduces that restore exactly.

**M6c (the divergence that causes the repair).** A paired restore puts both
databases at the same instant, so the head pointer *cannot* outrun the log.
The pointer only outruns when the two are recovered to different instants —
trajectory rolls back while the ledger survives. That is the case the repair
pass exists for, so that is the case drilled.

### Observed

```
seeded: 700 trajectory rows, head stamped at seq 700
server quiesced
snapshot of the whole data dir: exit=0 in 15ms          (cp -Rc, clonefile)
post-snapshot writes: log head now 900, head stamp advanced to match
both databases destroyed
restored trajectory: exit=0     restored ledger: exit=0
restored log head: 700 (snapshot was 700, pre-destroy was 900)
foldStaleness BEFORE the mandatory replay: lag=0 applied=700
mandatory replay: 70 heads in 84ms, appliedSeq 700, skipped {}
foldStaleness AFTER replay: lag=0 (sane)
traj show on the restored store: exit=0, 7 records, no staleness warning
traj_pulse rows after restore: 1        traj_fence after restore: 4294967996
ledger head stamp 700 vs restored log head 700 — within the log
ledger after restore: 500 issues (the pair came back to the same instant)

M6b — history-only restore shape
foldStaleness with empty projections: lag=700
traj show: "warning — the fold lags the log by 700 records (applied_seq 0,
            head 700); §5 bounds staleness at 512. Stage-1 projection
            readers refuse here."   ← and it still rendered the log
mandatory rebuild restored 70 heads; foldStaleness lag now 0
traj_pulse after the rebuild: 0

M6c — trajectory rolled back alone
ledger head stamped at 850
trajectory alone rolled back to the snapshot: exit=0
ledger head 850 vs restored log head 700 — OUTRUNS: repair REQUIRED
repair pass: head re-stamped to 700 (the log head), after the mandatory replay
```

### Verdict

**The restore contract holds, clause by clause.** The pair came back to the
same instant (log head 700, ledger 500 issues, head stamp 700). The mandatory
replay ran in 84 ms and drove `foldStaleness` to 0. `traj show` rendered on the
restored store. The §5 staleness bound behaves exactly as specified — silent at
lag 0, and at lag 700 (> the 512 bound) it warns with the applied/head numbers
and **still renders the log**, because the log is the truth and the projections
are derived. `traj_pulse` came back empty from a history-only restore and
stayed empty after the rebuild — unrebuildable by design, so liveness reads
`unknown` until the next beat.

**The head re-stamp is the one clause this drill did NOT verify in the
product.** There is no shipped repair pass to run: `grid_head` is a table
`m6_restore_drill.dart` **invents** (`CREATE TABLE IF NOT EXISTS grid_head`)
and the "repair" is the harness's own `UPDATE grid_head SET last_seq = <log
head>`. So what M6/M6c establish is that the *divergence* is real and
detectable — a ledger head pointer can outrun a rolled-back trajectory, the
condition is a one-query comparison, and clamping it to the log head is
sufficient — and nothing at all about a shipped implementation. The real
repair arrives with the Stage-1 head-stamp obligations that create and
maintain the pointer in the first place; this measurement is its
specification, not its receipt.

### Implications

1. **AMENDMENT — the storage call conflates two restores.** Its restore clause
   says "restore = both databases to the paired time, **then mandatory fold
   rebuild**". Measured: a *filesystem snapshot* carries the working set, so
   `proj_*`, `traj_pulse` and `traj_fence` all came back and `foldStaleness`
   was **already 0 before the replay**. The mandatory rebuild is belt-and-braces
   for a snapshot restore and genuinely load-bearing only for a `dolt
   backup`/`dolt clone` restore, which carries committed history alone. The
   contract should say so — both because it is true and because the "and
   `proj_*` are in no backup by design" sentence is only true of the
   dolt-native path.
2. **`traj_fence` survives a snapshot restore with a stale value** (4294967996
   here). It is working-set state and the claim path re-seeds it via UPSERT, so
   nothing breaks — but a restored store carries a fence cell for an epoch
   whose process is long dead, and the first claim after a restore is what
   corrects it. Worth a sentence in the operational contract.
3. **The head re-stamp repair only ever fires on an unpaired restore — and it
   is still unbuilt.** M6c shows the condition is real and the clamp is
   sufficient, but on a table the harness invented, so this is a
   specification for the Stage-1 head-stamp obligation to satisfy, not
   evidence that anything ships today. Two things to carry forward: the
   contract should note that a correctly-paired restore never needs the pass
   (it is a partial-recovery tool, not a routine step), and the Stage-1
   obligation owes the pass itself plus a guard over it.
4. **The whole drill takes about eleven seconds.** Snapshot 15 ms, restore
   ~20 ms, replay 84 ms at this size. There is no reason for the restore
   procedure to be feared or deferred; it should be rehearsed on a schedule.

---

## M7 — the CI guard pin

**Question (storage-call item 7).** The guard tests the probe designed but
stage 0 must pin in CI: `dolt status` clean after every fold write;
`@@dolt_force_transaction_commit` never set; dolt-commit counting via
`COUNT(*) FROM dolt_log` rather than `DOLT_COMMIT`'s return; `--doltcfg-dir`
handling for CLI ops inside the data dir; the service pinned to `main` with
fail-closed branch-change detection.

### Method

`dart run tool/measurements/m7_ci_guard_pin.dart`. Reads the pinned version
out of `.github/workflows/ci.yml` rather than repeating it (so the two cannot
drift), compares it to the local `dolt version` and to the newest release dolt
reports, then runs the tagged guard suite on the current tree.

### Observed

```
evidence PR:  https://github.com/memento-engineering/the_grid/pull/241
evidence job: https://github.com/memento-engineering/the_grid/actions/runs/
              33373506246/job/99429681833
CI pins DOLT_VERSION = 2.2.2
CI guard command: dart test -t integration (the tagged guard suite)
local dolt version = 2.2.2
dolt reports a newer release available: 2.3.1 (the pin is deliberate)
SKEW: none — the guards run here on exactly the version CI pins
00:09 +23: All tests passed!
guard suite exit=0 in 10.7s
```

PR #241 (“feat(trajectory): Stage 0 substrate — grid_trajectory package,
fenced appender, traj verbs, guard CI (tg-zfek)”) merged 2026-08-31T08:40:39Z;
its **Stage-0 trajectory guards (dolt)** job completed SUCCESS in 85 s. The job
is a separate CI job from the Dart job, installs dolt from the pinned release
tarball, and runs `dart test -t integration` — which **fails closed** without
dolt (decision: stage0-guards-gate-prs), so it cannot silently no-op.

**Item-7 tripwire coverage**, in `test/integration/`:

| item-7 tripwire | guard |
|---|---|
| `dolt status` clean after every fold write (the T3 force-trap tripwire) | `stage0_seven_guards_test.dart` guard 1 |
| `dolt add --force` banned; the sprung trap is visible | guard 2 |
| dolt commits counted from `dolt_log`, never `DOLT_COMMIT`'s return (the T7 trap) | guard 3 |
| `--doltcfg-dir` for CLI ops inside the data dir (the T1 trap) | guard 4 |
| service pinned to `main`, fail-closed on branch change (the T3 branch-vanish finding) | guard 5 |
| `@@dolt_force_transaction_commit` refused on a live session (T6f) | guard 6 |
| 1213 vs 1062 arbitration, steal interleavings, `uq_idem` dedupe, terminal guard, `proj_meta` | `stage0_guards_integration_test.dart` |
| fold + read coherence at **1,000** records through the real fenced appender (100 sessions × 10) | `fold_replay_integration_test.dart` |

The CI guard's scale is 1,000 records, not 100k: 100k-scale is **M5's
harness** (`m5_rebuild_duration.dart`, bulk-INSERT seeded), which is not a test
and does not run in CI. The guard proves coherence; M5 proves the curve.

### Verdict

**The pin is real, gating, and currently skew-free.** 23 guards pass locally in
10.7 s on the same dolt version CI installs, on the current tree (which
includes seat A's fold commit, landed after PR #241). All five item-7
tripwires are pinned, plus the error-contract and scale guards.

### Implications

1. **A local green means what it looks like it means — for now.** Zero skew
   today; the moment someone upgrades local dolt to 2.3.1 without moving
   `DOLT_VERSION`, that stops being true. `m7_ci_guard_pin.dart` is the
   cheapest way to notice, and it is worth running before trusting a local
   guard pass.
2. **Bump the pin deliberately, and with this harness.** The guards assert
   dolt's own observed behavior (1213 arbitration, `dolt_ignore` suppression,
   the force-add trap), and several of this document's measurements are
   version-specific too — M1's `-a` finding, M2's gc-kills-nothing result,
   M4's error codes. A dolt bump should re-run M1–M6, not only the guards.

---

## What this changes

**Confirmed, no action.** The ratified storage call stands on every axis
measured: bd tolerates the sibling (M1), online gc is non-disruptive (M2),
throughput has 2× headroom (M3), the fence survives a bounce (M4), rebuild is
7% of budget (M5), the restore drill works (M6), and the guards gate PRs (M7).

**Amendments the design documents should take:**

1. **`storage-call.md` flip conditions** — record same-db condition 2 as
   **measured false** (M1: bd's commit is `-a`-shaped, receipt in
   `dolt_diff`). The "flip back to the same database" path is unreachable
   without a change in bd.
2. **`storage-call.md` gc clause** — replace "steady interval if online gc
   proves non-disruptive, service-quiesced windows if not" with the steady
   interval, and re-budget the journal: the measured cost is **46.6 KB per
   append** (~2.9 MB/s at storm tempo), not the ~22–24 KB / ~1 MB/s the clause
   carries from T8 (M2).
3. **`storage-call.md` restore clause** — distinguish a filesystem snapshot
   restore (carries the working set; the rebuild is belt-and-braces) from a
   `dolt backup`/`dolt clone` restore (history only; the rebuild is
   mandatory). Note that `traj_fence` returns stale from a snapshot and is
   corrected by the next epoch claim (M6).
4. **`storage-call.md` operational contract** — add the first-boot
   provisioning window: bd's server has only `root@localhost`, which cannot
   authenticate over TCP and has no socket, so the trajectory credential must
   be seeded offline with the server stopped (M1).
5. **Schema §6** — re-base the "plausibly 35–45 ms/append" cost framing on the
   measured floor. Marginal cost of the P1 delta is 0.02 ms and of seven
   P1-shaped statements 0.26 ms; the ~16 ms is the transaction's fixed cost
   (M3). The seven-statement figure is a statement-count proxy, so the
   re-based framing should say the cost model is transaction-bound and name
   P2–P8's real shapes as still unmeasured.
6. **Schema §5 error contract** — the gap M4 found is **already closed**:
   `append()`'s branch-pin assertion now runs inside the classification
   boundary, so a dead connection returns a sealed `AppendInternalError` and
   an off-main session an `AppendCorruptionHalt`. §5's clause needs no change
   beyond noting that the typed-outcome guarantee covers the whole verb, not
   only its transaction.

**Not to be built:** the epoch-boundary snapshot contingency (M5 — 7% of
budget, linear, ~14× headroom) and the service-quiesced gc window (M2 — gc
kills nothing).
