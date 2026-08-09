import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _Owned {
  const _Owned(this.value);
  final String value;
}

final class _Consumer extends StatelessSeed {
  const _Consumer(this.seen);
  final List<Object?> seen;

  @override
  Seed build(TreeContext context) {
    seen
      ..add(context.watch<_Owned>()?.value)
      ..add(context.watch<String>())
      ..add(context.watch<int>());
    return const _Leaf();
  }
}

final class _Leaf extends Seed {
  const _Leaf();
  @override
  Branch createBranch() => _LeafBranch(this);
}

final class _LeafBranch extends Branch {
  _LeafBranch(_Leaf super.seed);
}

void main() {
  test(
    'curated SDK provider API mounts both constructors and nullable watch',
    () {
      final seen = <Object?>[];
      final disposed = <String>[];
      final owner = TreeOwner();
      owner.mountRoot(
        ProviderScope(
          providers: <Provider<Object>>[
            Provider<_Owned>(
              create: () => const _Owned('created'),
              dispose: (value) => disposed.add(value.value),
            ),
            const Provider<String>.value('adopted'),
          ],
          child: _Consumer(seen),
        ),
      );
      expect(seen, ['created', 'adopted', null]);
      owner.dispose();
      expect(disposed, ['created']);
    },
  );
}
