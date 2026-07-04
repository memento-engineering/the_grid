// DefaultCapabilityRegistry — requirement-slot resolution at the
// CapabilityRegistry seam (D-B5 hook #2, the honesty-pass, 2026-07-03): a step
// whose declared requirement the station cannot fulfill (CapabilityFacts
// containment) resolves to an asset-provided claim capability instead of its
// local spawn. Zero I/O — pure value-types + a bare `host()` call (no tree
// mount needed to observe WHICH capability got wrapped).
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// A capability that is never actually driven in this file — only its
/// IDENTITY matters (which one `host()` wrapped).
class _NamedCapability extends Capability {
  const _NamedCapability(this.name);
  final String name;

  @override
  Allocation createAllocation(AllocationContext ctx) =>
      throw UnimplementedError('never driven in this test');
}

StepMount _mount(CapabilityStep step) => StepMount(
  step: step,
  nodePath: 'tg-burn/follower',
  session: const SessionHandle('tgdog-s'),
  node: const NodeCursor(),
  key: const ValueKey('tg-burn/follower#0'),
);

const _macos = CapabilityFacts(
  sets: {
    kSystemOs: {'macos'},
    kRadio: {'ble'},
  },
);

const _linuxRequirement = CapabilityFacts(
  sets: {
    kSystemOs: {'linux'},
    kRadio: {'ble'},
  },
);

void main() {
  group('DefaultCapabilityRegistry — requirement-slot resolution', () {
    test('no declared requirement → resolves to the LOCAL capability '
        '(today\'s P1-only behavior, unchanged)', () {
      const local = _NamedCapability('local');
      const claim = _NamedCapability('claim');
      final registry = DefaultCapabilityRegistry(
        capabilities: const {'burn-follower': local},
        stationFacts: _macos,
        claimCapabilityFor: (_) => claim,
      );
      final host = registry.host(
        _mount(const CapabilityStep(stepId: 'follower', capabilityId: 'burn-follower')),
      ) as CapabilityHost;
      expect(host.capability, same(local));
    });

    test('a declared requirement the station SATISFIES → resolves LOCALLY, '
        'never to the claim capability', () {
      const local = _NamedCapability('local');
      const claim = _NamedCapability('claim');
      final registry = DefaultCapabilityRegistry(
        capabilities: const {'burn-host': local},
        stationFacts: _macos,
        claimCapabilityFor: (_) => claim,
      );
      final host = registry.host(
        _mount(
          const CapabilityStep(
            stepId: 'follower',
            capabilityId: 'burn-host',
            requires: _macos,
          ),
        ),
      ) as CapabilityHost;
      expect(host.capability, same(local));
    });

    test('a declared requirement the station CANNOT satisfy → resolves to '
        'the asset-provided claim capability, NEVER the local spawn', () {
      const local = _NamedCapability('local');
      const claim = _NamedCapability('claim');
      final registry = DefaultCapabilityRegistry(
        capabilities: const {'burn-follower': local},
        stationFacts: _macos, // this station is macOS — cannot fulfill linux.
        claimCapabilityFor: (mount) {
          expect(mount.step.capabilityId, 'burn-follower');
          expect(mount.step.requires, _linuxRequirement);
          return claim;
        },
      );
      final host = registry.host(
        _mount(
          const CapabilityStep(
            stepId: 'follower',
            capabilityId: 'burn-follower',
            requires: _linuxRequirement,
          ),
        ),
      ) as CapabilityHost;
      expect(host.capability, same(claim));
      expect(host.capability, isNot(same(local)));
    });

    test('an EMPTY declared requirement matches vacuously → resolves '
        'LOCALLY (no claim capability consulted)', () {
      const local = _NamedCapability('local');
      var claimConsulted = false;
      final registry = DefaultCapabilityRegistry(
        capabilities: const {'agent': local},
        stationFacts: const CapabilityFacts(),
        claimCapabilityFor: (_) {
          claimConsulted = true;
          return const _NamedCapability('claim');
        },
      );
      final host = registry.host(
        _mount(
          const CapabilityStep(
            stepId: 'follower',
            capabilityId: 'agent',
            requires: CapabilityFacts(),
          ),
        ),
      ) as CapabilityHost;
      expect(host.capability, same(local));
      expect(claimConsulted, isFalse);
    });

    test('stationFacts defaults to empty — an unspecified profile makes '
        'every non-empty requirement unfulfillable locally', () {
      const claim = _NamedCapability('claim');
      final registry = DefaultCapabilityRegistry(
        capabilities: const {'burn-follower': _NamedCapability('local')},
        claimCapabilityFor: (_) => claim,
      );
      final host = registry.host(
        _mount(
          const CapabilityStep(
            stepId: 'follower',
            capabilityId: 'burn-follower',
            requires: _linuxRequirement,
          ),
        ),
      ) as CapabilityHost;
      expect(host.capability, same(claim));
    });
  });
}
