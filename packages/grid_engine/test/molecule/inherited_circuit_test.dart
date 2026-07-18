// R2 — InheritedCircuit: the molecule model's ambient storage seam.
//
// Pure value-equality tests (mirrors the SessionHandle discipline
// `session_scope.dart:721`: `genesis_tree`'s `InheritedSeed.updateShouldNotify`
// is `value != oldSeed.value`, so `==` IS the notification contract) plus a
// FakeTreeContext wiring smoke test proving a step resolves its own bead id by
// nodePath through the same ambient-lookup pattern SessionHandle/Workspace
// already use.
//
// DESIGN-tg-pm6.md §6 / §14. Zero I/O.
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  group('InheritedCircuit', () {
    final root = BeadPathKey(['tgdog-work-1', 'tgdog-sess-2', 'tgdog-mol-3']);
    const cursorA = <String, NodeCursor>{
      'build': NodeCursor(state: StepState.complete),
      'test': NodeCursor(state: StepState.pending),
    };

    test(
      '== is true for independently-built instances with the same (root, cursor)',
      () {
        final first = InheritedCircuit(
          root: BeadPathKey(List.of(root.crumbs)),
          beadIdByNodePath: const {'build': 'tgdog-step-4'},
          cursor: Map.of(cursorA),
        );
        final second = InheritedCircuit(
          root: BeadPathKey(List.of(root.crumbs)),
          beadIdByNodePath: const {'build': 'tgdog-step-4'},
          cursor: Map.of(cursorA),
        );
        expect(first, second);
        expect(first.hashCode, second.hashCode);
      },
    );

    test(
      '== ignores beadIdByNodePath — a same-state re-provide with a freshly '
      'rebuilt lookup map never notifies',
      () {
        final first = InheritedCircuit(
          root: root,
          beadIdByNodePath: const {'build': 'tgdog-step-4'},
          cursor: cursorA,
        );
        final second = InheritedCircuit(
          root: root,
          // A structurally DIFFERENT lookup map (extra key, different value)
          // — still the same projected (root, cursor), so still equal.
          beadIdByNodePath: const {
            'build': 'DIFFERENT-STEP-ID',
            'extra': 'tgdog-step-9',
          },
          cursor: cursorA,
        );
        expect(first, second);
        expect(first.hashCode, second.hashCode);
      },
    );

    test('!= when a node in the cursor moves state (a real state change notifies)', () {
      final before = InheritedCircuit(
        root: root,
        beadIdByNodePath: const {},
        cursor: cursorA,
      );
      final after = InheritedCircuit(
        root: root,
        beadIdByNodePath: const {},
        cursor: {...cursorA, 'build': const NodeCursor(state: StepState.failed)},
      );
      expect(before, isNot(after));
    });

    test('!= when the cursor key set differs', () {
      final fewer = InheritedCircuit(
        root: root,
        beadIdByNodePath: const {},
        cursor: const {'build': NodeCursor(state: StepState.complete)},
      );
      final more = InheritedCircuit(
        root: root,
        beadIdByNodePath: const {},
        cursor: cursorA,
      );
      expect(fewer, isNot(more));
    });

    test('!= when root differs', () {
      final a = InheritedCircuit(
        root: root,
        beadIdByNodePath: const {},
        cursor: cursorA,
      );
      final b = InheritedCircuit(
        root: root.child('tgdog-submol-9'),
        beadIdByNodePath: const {},
        cursor: cursorA,
      );
      expect(a, isNot(b));
    });

    test('cursor equality is independent of Map insertion order', () {
      final insertedBuildFirst = InheritedCircuit(
        root: root,
        beadIdByNodePath: const {},
        cursor: const {
          'build': NodeCursor(state: StepState.complete),
          'test': NodeCursor(state: StepState.pending),
        },
      );
      final insertedTestFirst = InheritedCircuit(
        root: root,
        beadIdByNodePath: const {},
        cursor: const {
          'test': NodeCursor(state: StepState.pending),
          'build': NodeCursor(state: StepState.complete),
        },
      );
      expect(insertedBuildFirst, insertedTestFirst);
      expect(insertedBuildFirst.hashCode, insertedTestFirst.hashCode);
    });

    test(
      'a step resolves its own bead id by nodePath through '
      'FakeTreeContext.provide<InheritedCircuit>',
      () {
        final circuit = InheritedCircuit(
          root: root,
          beadIdByNodePath: const {
            'build': 'tgdog-step-4',
            'test': 'tgdog-step-5',
          },
          cursor: cursorA,
        );
        final ctx = FakeTreeContext()..provide<InheritedCircuit>(circuit);

        final resolved = ctx.dependOnInheritedSeedOfExactType<InheritedCircuit>();

        expect(resolved, isNotNull);
        expect(resolved!.beadIdByNodePath['build'], 'tgdog-step-4');
        expect(resolved.beadIdByNodePath['test'], 'tgdog-step-5');
      },
    );

    test(
      'absent InheritedCircuit resolves to null — the flat-mode fallback seam '
      '(R5b falls back to SessionHandle when nothing is provided here)',
      () {
        final ctx = FakeTreeContext();
        expect(ctx.dependOnInheritedSeedOfExactType<InheritedCircuit>(), isNull);
      },
    );
  });
}
