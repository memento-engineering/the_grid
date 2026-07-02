// Track A1 — ProcessCapability.result() payload hook.
//
// A process step (e.g. a critic) contributes a result payload on a clean
// completion. The host reads result() AFTER latching `complete`, and writes the
// grade MERGED with `state=complete` in ONE chokepoint update — a null result
// writes state only. Zero I/O: fakes + the recording chokepoint.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

/// A process critic whose [result] returns [grade] (or null for no result).
class _GradingCritic extends ProcessCapability {
  const _GradingCritic(this.grade);
  final String? grade;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'echo grade'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async =>
      grade == null ? null : {'grade': grade!};
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

({TreeOwner owner, Fakes fakes}) _host(Capability cap) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: DateTime(2026)),
        child: InheritedSeed<ServiceBundle>(
          value: const ServiceBundle(),
          // The workspace is an AMBIENT value now (mounted by SessionScope in
          // the real tree) — the critic's spawn reads it with the effect verb.
          child: InheritedSeed<Workspace>(
            value: testWorkspace('tg-1'),
            child: CapabilityHost(
              capability: cap,
              mount: StepMount(
                step: const CapabilityStep(
                  stepId: 'critic',
                  capabilityId: 'critic',
                ),
                nodePath: 'tg-1/critic',
                session: const SessionHandle('tgdog-s'),
                node: const NodeCursor(),
                key: const ValueKey('tg-1/critic#0'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

void main() {
  group('Track A1 — ProcessCapability.result() merges into the complete write', () {
    test('a clean Exited(0) carries state=complete AND grid.result.<path>.grade '
        'in ONE update', () async {
      final h = _host(const _GradingCritic('B'));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/critic', exitCode: 0));
      await _pump();

      // EXACTLY one chokepoint update carrying both the cursor advance and the
      // namespaced grade — disjoint keys merge in one write (A1/invariant 2).
      expect(h.fakes.runner.callsFor('update'), hasLength(1));
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/critic.state': 'complete',
        'grid.result.tg-1/critic.grade': 'B',
      });
    });

    test('a null-result process writes state only (positive control: no grade '
        'key leaks)', () async {
      final h = _host(const _GradingCritic(null));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/critic', exitCode: 0));
      await _pump();

      expect(h.fakes.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/critic.state': 'complete'});
    });
  });
}
