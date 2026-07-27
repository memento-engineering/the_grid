import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Unit proofs for the dispatch-side ownership gate (M3 Track 5; ADR-0006
/// Decision 1; ADR-0000 A32) — the bead-shaped analog of the M2 convergence
/// `OwnsSubstations` unit tests. The DoD: a ready bead whose prefix/label is NOT the
/// owned rig is not-owned (so the dispatcher observes it read-only and never
/// dispatches it); the shared allow-set is one `Set<String>`, never two copies.
void main() {
  Bead workBead(String id, {Map<String, dynamic> metadata = const {}}) =>
      Bead(id: id, metadata: metadata);

  group('BeadOwnershipPredicate.owns (issue-id prefix axis, A35 primary)', () {
    final predicate = BeadOwnershipPredicate({'tgdog'});

    test('an owned-prefix work bead is owned', () {
      expect(predicate.owns(workBead('tgdog-abc123')), isTrue);
    });

    test('a hyphenated owned-prefix work bead is owned', () {
      final predicate = BeadOwnershipPredicate({'swift-infer'});
      expect(predicate.owns(workBead('swift-infer-097')), isTrue);
      expect(predicate.ownsTarget(id: 'swift-infer-097'), isTrue);
      expect(
        predicate.substationOf(workBead('swift-infer-097')),
        'swift-infer',
      );
    });

    test('the longest complete owned prefix wins', () {
      final predicate = BeadOwnershipPredicate({'swift', 'swift-infer'});
      expect(
        predicate.substationOf(workBead('swift-infer-097')),
        'swift-infer',
      );
    });

    test('an owned prefix permits a hyphenated bead-id remainder', () {
      final predicate = BeadOwnershipPredicate({'tg'});
      expect(predicate.owns(workBead('tg-wisp-sgd')), isTrue);
      expect(predicate.ownsTarget(id: 'tg-wisp-sgd'), isTrue);
      expect(predicate.substationOf(workBead('tg-wisp-sgd')), 'tg');
    });

    test('an empty remainder after the owned boundary stays fail-closed', () {
      final predicate = BeadOwnershipPredicate({'tg'});
      expect(predicate.owns(workBead('tg-')), isFalse);
      expect(predicate.ownsTarget(id: 'tg-'), isFalse);
      expect(predicate.substationOf(workBead('tg-')), isNull);
    });

    test('partial prefix text stays fail-closed', () {
      final predicate = BeadOwnershipPredicate({'swift'});
      expect(predicate.owns(workBead('swiftish-097')), isFalse);
    });

    test('a NON-owned-prefix bead is NOT owned (fail-closed)', () {
      // gascity-prefixed work bead — gc's, never the_grid's.
      expect(predicate.owns(workBead('gascity-xyz')), isFalse);
    });

    test('a bare id with no dash prefix is NOT owned (fail-closed)', () {
      expect(predicate.owns(workBead('orphanid')), isFalse);
    });

    test('the empty allow-set owns nothing', () {
      final ownsNothing = BeadOwnershipPredicate(const <String>{});
      expect(ownsNothing.owns(workBead('tgdog-1')), isFalse);
    });
  });

  group('the metadata.rig marker axis (belt-and-suspenders, A35 optional)', () {
    final predicate = BeadOwnershipPredicate({'tgdog'});

    test(
      'an owned metadata.rig marker is owned even without an owned prefix',
      () {
        expect(
          predicate.owns(workBead('nodash', metadata: {'rig': 'tgdog'})),
          isTrue,
        );
      },
    );

    test('a non-owned metadata.rig marker is NOT owned', () {
      expect(
        predicate.owns(workBead('x-1', metadata: {'rig': 'gascity'})),
        isFalse,
      );
    });

    test('requireSubstationMarker demands BOTH the prefix AND the marker', () {
      final strict = BeadOwnershipPredicate({
        'tgdog',
        'swift-infer',
      }, requireSubstationMarker: true);
      // Prefix owned but no marker → not owned under the strict posture.
      expect(strict.owns(workBead('tgdog-1')), isFalse);
      // Both owned → owned.
      expect(
        strict.owns(workBead('tgdog-1', metadata: {'rig': 'tgdog'})),
        isTrue,
      );
      // Hyphenated prefixes remain subject to the same BOTH requirement.
      expect(strict.owns(workBead('swift-infer-097')), isFalse);
      expect(
        strict.owns(
          workBead('swift-infer-097', metadata: {'rig': 'swift-infer'}),
        ),
        isTrue,
      );
    });
  });

  group('the shared allow-set is ONE Set<String>, not a copy', () {
    test('BeadOwnershipPredicate exposes the IDENTICAL allow-set it was built '
        'from, so the write chokepoint can share the same instance (A32)', () {
      // ONE source of truth — the seed the dogfood uses.
      final allowSet = {'tgdog'};
      final dispatchGate = BeadOwnershipPredicate(allowSet);

      // The dispatch gate accepts the_grid's owned rig and rejects gc's.
      expect(dispatchGate.owns(workBead('tgdog-1')), isTrue);
      expect(dispatchGate.owns(workBead('gascity-1')), isFalse);
      // The dispatch gate exposes the allow-set so the write chokepoint can be
      // built from the IDENTICAL instance (the shared artifact is the set).
      expect(dispatchGate.substations, contains('tgdog'));
      expect(dispatchGate.substations, hasLength(1));
    });
  });

  group('substationOf / ownedPrefixOf helpers', () {
    test('ownedPrefixOf returns the longest complete known prefix', () {
      const known = {'swift', 'swift-infer'};
      expect(
        BeadOwnershipPredicate.ownedPrefixOf('swift-infer-097', known),
        'swift-infer',
      );
      expect(BeadOwnershipPredicate.ownedPrefixOf('nodash', known), isNull);
      expect(
        BeadOwnershipPredicate.ownedPrefixOf('swiftish-097', known),
        isNull,
      );
      expect(
        BeadOwnershipPredicate.ownedPrefixOf('swift-infer-', known),
        isNull,
      );
    });

    test('substationOf prefers the prefix, falls back to the marker', () {
      final p = BeadOwnershipPredicate({'tgdog'});
      expect(p.substationOf(workBead('tgdog-1')), 'tgdog');
      expect(
        p.substationOf(workBead('nodash', metadata: {'rig': 'tgdog'})),
        'tgdog',
      );
    });
  });
}
