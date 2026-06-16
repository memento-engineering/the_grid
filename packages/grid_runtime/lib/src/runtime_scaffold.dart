/// Scaffold marker for the M3 runtime layer.
///
/// `grid_runtime` gives the_grid **hands**: it spawns and supervises a coding
/// agent (a `claude` subprocess) per ready bead, isolates each bead's work in
/// a git worktree, tracks each session's lifecycle **as a bead** (bd-only
/// writes through the single write chokepoint, `--actor grid-controller`,
/// never SQL), and lands finished work as a pushed branch / PR — never an
/// auto-merge (ADR-0004; M3-BUILD-ORDER Tracks 2–7).
///
/// This file is a placeholder so the package analyzes clean before any runtime
/// logic exists. **Track 2 fills it** with the `RuntimeProvider` contract and
/// `SubprocessProvider` impl; Tracks 3–7 add worktree isolation, the lifecycle
/// chokepoint, and the dispatch interactor. Nothing here performs IO, spawns a
/// process, or writes a bead.
library;

/// The package's identity, exposed so the empty scaffold has a referenced
/// symbol and downstream wiring can assert the package is on the path before
/// Track 2 lands. Replaced by the real runtime surface in Track 2.
const String gridRuntimeScaffold = 'grid_runtime';
