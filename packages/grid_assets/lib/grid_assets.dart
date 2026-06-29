/// The_grid's opinion assets — the agent/verify/land [Capability] impls + the
/// `code` [Formula] + the git [SourceControl] (ADR-0008 D2 / M4-P1 §6).
///
/// These are the OPINIONS the opinion-free engine (grid_engine) must not carry
/// (ADR-0007 §1): the coding agent it spawns (`claude`), the check it runs, the
/// PR it opens. The composer (`grid_cli`) wires them via [buildCodeRegistry] +
/// a `FormulaResolver`. This is the in-repo home of the `power_station` assets
/// (D-1; the standalone-repo extraction is deferred).
library;

export 'src/assets/asset_loader.dart';
export 'src/code/code_capabilities.dart';
export 'src/code/committee.dart';
