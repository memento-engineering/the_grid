# Changelog

## 0.2.0

- **Breaking:** `StationLockService.acquire` no longer takes a `pgid`
  parameter — the service now establishes the station's own process group
  itself (setsid-own-group before the lock write) and refuses via
  `StationRefusal` when the resolved pgid is not the station pid.
  Migration: drop the `pgid:` argument from `acquire(...)` call sites; if you
  were computing a group id to pass in, delete that code — the recorded
  `pgid` is now always the station's own, verified group.
- `stop()` gains a pgid-gated group signal: when the lock's recorded `pgid`
  matches the live process group, teardown signals the whole group; on
  mismatch it falls back loudly to the previous pid-scoped SIGTERM.
- New: `establishStationProcessGroup` (re-exported), with
  `ProcessGroupController.resolvePgid` as the single source of process-group
  identity; regression test boots from a non-leader parent and asserts the
  recorded group is the station's own tree.

## 0.1.0

- Initial tagged release (ADR-0003 tag-pattern version solving).
