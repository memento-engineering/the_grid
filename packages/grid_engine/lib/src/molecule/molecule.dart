/// The molecule model (`DESIGN-tg-pm6.md`): a circuit instance persisted as a
/// molecule of durable beads — one `type=molecule` bead per instance, one
/// `type=step` bead per step — arriving ADDITIVELY alongside the existing flat
/// `grid.cursor.*` session-bead model, behind an explicit mint-mode. One
/// auditable directory (`lib/src/molecule/`) is the whole new model; `sdk/`
/// and `circuit/` are edited only by the wiring rungs (the join, the host
/// fork, the drain seam).
///
/// Not exported from the package root (`lib/grid_engine.dart`) until a wiring
/// rung needs it live — see `DESIGN-tg-pm6.md` §2 and §14 for build order.
library;

export 'bead_path_key.dart';
