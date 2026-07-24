import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cockpit_contract/grid_cockpit_contract.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

enum _Mode { active }

void main() {
  group('typed properties', () {
    test('converts every property kind to the contract union', () {
      final timestamp = DateTime.utc(2026, 7, 23);
      final builder = DiagnosticsBuilder()
        ..add(const StringProperty('string', 'value'))
        ..add(const IntProperty('int', 7))
        ..add(const DoubleProperty('double', 1.5))
        ..add(const FlagProperty('flag', true))
        ..add(const EnumProperty('enum', _Mode.active))
        ..add(const DurationProperty('duration', Duration(seconds: 2)))
        ..add(TimestampProperty('timestamp', timestamp))
        ..add(
          const ReferenceProperty(
            'reference',
            'bead-1',
            kind: ReferenceKind.bead,
          ),
        )
        ..add(
          const ObjectProperty('object', [StringProperty('nested', 'value')]),
        );

      final properties = builder.build();
      expect(properties, hasLength(9));
      expect(
        () => properties.add(
          const DiagnosticsProperty.string(
            name: 'extra',
            level: DiagnosticsLevel.info,
            value: 'no',
          ),
        ),
        throwsUnsupportedError,
      );

      final kinds = <String>[];
      for (final property in properties) {
        kinds.add(switch (property) {
          DiagnosticsStringProperty(:final value) => 'string:$value',
          DiagnosticsIntProperty(:final value) => 'int:$value',
          DiagnosticsDoubleProperty(:final value) => 'double:$value',
          DiagnosticsFlagProperty(:final value) => 'flag:$value',
          DiagnosticsEnumProperty(:final value, :final enumType) =>
            'enum:$enumType.$value',
          DiagnosticsDurationProperty(:final value) =>
            'duration:${value.inSeconds}',
          DiagnosticsTimestampProperty(:final value) =>
            'timestamp:${identical(value, timestamp)}',
          DiagnosticsReferenceProperty(:final value, :final referenceKind) =>
            'reference:$referenceKind:$value',
          DiagnosticsObjectProperty(:final properties) =>
            'object:${properties.length}',
        });
      }
      expect(kinds, [
        'string:value',
        'int:7',
        'double:1.5',
        'flag:true',
        'enum:_Mode.active',
        'duration:2',
        'timestamp:true',
        'reference:ReferenceKind.bead:bead-1',
        'object:1',
      ]);
    });

    test('preserves base-before-derived super-chain order', () {
      final builder = DiagnosticsBuilder();
      const _DerivedDescription().debugFillProperties(builder);

      expect(builder.build().map((property) => property.name), [
        'base',
        'derived',
      ]);
    });
  });

  group('semantic tree walker', () {
    test('hoists semantic descendants through transparent plumbing', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _SemanticContainer('root', [
          InheritedSeed<Object>(
            value: Object(),
            child: _TransparentContainer([
              const _SemanticLeaf('first', key: ValueKey('first-key')),
              const _StatefulDescription(key: ValueKey('stateful-key')),
            ]),
          ),
        ], key: const ValueKey('root-key')),
      );
      final projectedAt = DateTime.utc(2026, 7, 23, 12);

      final snapshot = DiagnosticsTreeWalker().walk(
        root,
        projectedAt: projectedAt,
      );

      expect(snapshot.contractVersion, 1);
      expect(identical(snapshot.projectedAt, projectedAt), isTrue);
      expect(snapshot.root.seedType, '_SemanticContainer');
      expect(snapshot.root.id, '0');
      expect(snapshot.root.key, const ValueKey('root-key').toString());
      expect(snapshot.root.children.map((node) => node.seedType), [
        '_SemanticLeaf',
        '_StatefulDescription',
      ]);
      expect(snapshot.root.children.map((node) => node.id), ['3', '4']);
      expect(
        snapshot.root.children[1].properties.map((property) => property.name),
        ['seed', 'state'],
      );
    });

    test('rejects a tree with no semantic root', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(_TransparentContainer([const _Leaf()]));

      expect(
        () =>
            DiagnosticsTreeWalker().walk(root, projectedAt: DateTime.utc(2026)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('found 0'),
          ),
        ),
      );
    });

    test('rejects a tree with multiple semantic roots', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _TransparentContainer([
          const _SemanticLeaf('first'),
          const _SemanticLeaf('second'),
        ]),
      );

      expect(
        () =>
            DiagnosticsTreeWalker().walk(root, projectedAt: DateTime.utc(2026)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('found 2'),
          ),
        ),
      );
    });
  });
}

class _BaseDescription with Diagnosable {
  const _BaseDescription();

  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(const StringProperty('base', 'base'));
  }
}

class _DerivedDescription extends _BaseDescription {
  const _DerivedDescription();

  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(const StringProperty('derived', 'derived'));
  }
}

class _SemanticContainer extends MultiChildSeed with Diagnosable {
  _SemanticContainer(this.label, List<Seed> children, {super.key})
    : super(children: children);

  final String label;

  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(StringProperty('label', label));
  }
}

class _TransparentContainer extends MultiChildSeed {
  _TransparentContainer(List<Seed> children) : super(children: children);
}

class _SemanticLeaf extends Seed with Diagnosable {
  const _SemanticLeaf(this.label, {super.key});

  final String label;

  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(StringProperty('label', label));
  }

  @override
  Branch createBranch() => _LeafBranch(this);
}

class _Leaf extends Seed {
  const _Leaf();

  @override
  Branch createBranch() => _LeafBranch(this);
}

class _LeafBranch extends Branch {
  _LeafBranch(super.seed);
}

class _StatefulDescription extends StatefulSeed with Diagnosable {
  const _StatefulDescription({super.key});

  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(const StringProperty('seed', 'seed'));
  }

  @override
  State<_StatefulDescription> createState() => _DescriptionState();
}

class _DescriptionState extends State<_StatefulDescription> with Diagnosable {
  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(const StringProperty('state', 'state'));
  }

  @override
  Seed build(TreeContext context) => const _Leaf();
}
