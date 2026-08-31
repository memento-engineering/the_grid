# Stage-0 measurement harness

Seven standalone Dart scripts, one per open item in
[`docs/design/trajectory/storage-call.md`](../../../../docs/design/trajectory/storage-call.md)'s
"What stage 0 must still measure". The numbers they produced, with method and
verdicts, are in
[`docs/design/trajectory/stage0-measurements.md`](../../../../docs/design/trajectory/stage0-measurements.md).

These are **not tests**. A test asserts a contract and goes red when it breaks;
these produce numbers a human reads. The contracts these numbers justify are
pinned by the guard suite (`test/integration/`, `dart test -t integration`).

Run each from the package root:

```bash
cd packages/grid_trajectory
dart run tool/measurements/m1_bd_sibling_db.dart     # + --skip-copy / --only-copy
dart run tool/measurements/m2_online_gc.dart
dart run tool/measurements/m3_append_latency.dart
dart run tool/measurements/m4_fence_bounce.dart
dart run tool/measurements/m5_rebuild_duration.dart
dart run tool/measurements/m6_restore_drill.dart
dart run tool/measurements/m7_ci_guard_pin.dart
```

| script | measures |
|---|---|
| `m1_bd_sibling_db.dart` | bd's tolerance of a sibling `trajectory` database, fresh store and a copy of a real one |
| `m2_online_gc.dart` | `CALL DOLT_GC()` on one database while another is under load on the same server |
| `m3_append_latency.dart` | append cost with `proj_meta` + the Stage-1 P1 delta, against §5's 22–28/s band |
| `m4_fence_bounce.dart` | SIGKILL mid-transaction: typed failure, no hang, no double append, guarded reconnect |
| `m5_rebuild_duration.dart` | replay-fold wall clock at 25k / 50k / 100k records |
| `m6_restore_drill.dart` | quiesce → snapshot → destroy → restore the pair → mandatory replay → head re-stamp |
| `m7_ci_guard_pin.dart` | the CI dolt pin, local skew, and the guard suite on this tree |

Two environment variables, both optional:

| variable | effect |
|---|---|
| `GRID_TRAJECTORY_SCRATCH` | root for every temp data dir (default: `$TMPDIR/grid_trajectory_measurements`) |
| `GRID_TRAJECTORY_REAL_STORE` | the `.beads` dir M1b copies (default: the reference deployment's; an absent path skips M1b) |

## Rules these scripts hold

- **Hermetic.** Every server is a throwaway `dolt sql-server` on an ephemeral
  port over a temp dir under the session scratch root. Nothing here opens a
  real `.beads`/`.grid` store's server, pid, lock, or proxy files.
- **The one exception is loud.** M1b copies the live tranquility store. The
  source is read by `cp` only; the COPY is defanged before any process starts —
  listener port rewritten (the real child server holds the recorded port right
  now), pid/lock/log files deleted, `sync.remote` stripped.
- **`dolt` must be on `PATH`.** Absence fails the run rather than skipping it,
  matching the guard suite's fail-closed contract.
- **They print, they do not assert.** A result that contradicts the design
  still exits 0 and says so; the verdict is a human's, in the report.
