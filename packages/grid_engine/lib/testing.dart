/// Public testing-support library for grid_engine.
///
/// The reusable, engine-only **Fakes** (not mocks) the offline suite drives the
/// reactive kernel with — a controllable [FakeRuntimeProvider], the recording
/// bd-write chokepoint ([RecordingBdRunner]/[GatedCreateBdRunner]), the land
/// ops ([RecordingGitRunner]/[FakePrOpener]), the observable [FakeSnapshotSource],
/// the [buildFakes]/[bead]/[sessionBead] builders, and the reentrant inflater
/// fakes ([RecordingCapabilityRegistry]/[FakeCapabilityHost]). Promoted to a
/// public library so downstream asset packages (grid_assets) reuse the SAME
/// fakes — the cross-package enabler for the opinion extraction (ADR-0007 §1).
///
/// The code-asset-specific helpers (`kCodeResolver`, the `code` circuit) are NOT
/// here — they reference the moved opinions and live in grid_assets's test
/// support. Pure-Dart: no live tg/gc/claude/git/network.
library;

export 'src/testing/engine_fakes.dart';
