/// The RS-1 signal-smoke child (`station_signals_test.dart`): boots a DRY
/// station over injected EMPTY sources — nothing live (no `.beads/` on disk,
/// no real `bd`/`git`/`claude`; `buildLiveWiring` under `--dry-run` wires the
/// recording no-op transport, the no-op bd runner, and the inert git service)
/// — and parks on the DEFAULT termination binding ([terminationSignals]).
///
/// The harness waits for the `SMOKE_ARMED` sentinel, sends a real OS SIGTERM,
/// and asserts exit 0 + the shutdown banner. `main` RETURNS instead of calling
/// `exit()` so the smoke also proves the drained VM exits on its own — a
/// leaked signal subscription would hang the child and fail the bounded wait.
library;

import 'dart:async';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

Future<void> main() async {
  const args = StationArgs(substations: {'smoke'}, dryRun: true);
  final sources = StationSources(work: const EmptySnapshotSource());
  final live = await buildLiveWiring(args: args, sources: sources);
  final wiring = composeStation(
    work: sources.work,
    state: sources.state,
    stationServices: live.stationServices,
    substations: const [
      SubstationConfig(substationId: 'smoke', ownedSubstations: {'smoke'}),
    ],
    git: live.git,
    workRoot: live.workRoot,
    groups: live.groups,
    freshnessBarrier: live.freshnessBarrier,
    resolver: const FormulaResolver(_formulaFor),
    registry: DefaultCapabilityRegistry(
      capabilities: const {'noop': _NoopCap()},
      formulas: const {'noop': _noopFormula},
    ),
  );
  exitCode = await driveStation(
    wiring: wiring,
    sources: sources,
    args: args,
    signals: _announcingSignals(),
  );
}

/// Pass-through over the DEFAULT [terminationSignals] binding that announces
/// `SMOKE_ARMED` the moment `driveStation` subscribes — i.e. the moment the
/// real OS watches are attached, the deterministic "safe to SIGTERM" sentinel.
/// The signal itself still travels OS → [ProcessSignal.watch] → driveStation.
Stream<ProcessSignal> _announcingSignals() {
  StreamSubscription<ProcessSignal>? inner;
  late final StreamController<ProcessSignal> controller;
  controller = StreamController<ProcessSignal>(
    onListen: () {
      inner = terminationSignals().listen(controller.add);
      stdout.writeln('SMOKE_ARMED');
    },
    onCancel: () => inner?.cancel(),
  );
  return controller.stream;
}

// The empty work source mounts nothing, but the composer requires an asset
// trio (ADR-0008 D1: no framework default) — a minimal never-run one.
const Formula _noopFormula = Formula(
  id: 'noop',
  terminalStepId: 'noop',
  steps: [
    CapabilityStep(stepId: 'noop', capabilityId: 'noop', kind: StepKind.job),
  ],
);

Formula _formulaFor(Bead bead) => _noopFormula;

class _NoopCap extends ProcessCapability {
  const _NoopCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: '.',
    command: 'sh',
    args: const ['-c', 'true'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => StepSignal.none;
}
