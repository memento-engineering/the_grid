// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cockpit_contract/grid_cockpit_contract.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

enum _Mode { active }

class _IdleSessionResolver implements SessionResolver {
  const _IdleSessionResolver();

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _joinedOne(Bead bead) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [bead],
    dependencies: const [],
    readyIds: {bead.id},
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: const {},
);

TreeNode _onlyChild(TreeNode node) {
  expect(node.children, hasLength(1));
  return node.children.single;
}

List<DiagnosticsProperty> _propertiesOf(Diagnosable value) {
  final builder = DiagnosticsBuilder();
  value.debugFillProperties(builder);
  return builder.build();
}

const _diagnosticsCircuit = Circuit(
  id: 'build',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

const _diagnosticsSession = SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-s',
);

class _PendingServiceCapability extends ServiceCapability {
  _PendingServiceCapability(this.pending);

  final Completer<StepOutcome> pending;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) => pending.future;
}

List<Branch> _allBranches(Branch root) {
  final branches = <Branch>[];
  void visit(Branch branch) {
    branches.add(branch);
    branch.visitChildren(visit);
  }

  visit(root);
  return branches;
}

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
    test('projects the mounted engine topology and removes plumbing', () {
      final bead = _task('tg-1');
      final joined = JoinedSnapshotNotifier(_joinedOne(bead));
      final fakes = buildFakes();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        InheritedSeed<JoinedSnapshotNotifier>(
          value: joined,
          child: InheritedSeed<StationServices>(
            value: fakes.ctx,
            child: InheritedSeed<SessionResolver>(
              value: const _IdleSessionResolver(),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(
                    const SubstationConfig(
                      substationId: 'tg',
                      ownedSubstations: {'tg'},
                    ),
                  ),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      );

      final snapshot = DiagnosticsTreeWalker().walk(
        root,
        projectedAt: DateTime.utc(2026, 7, 24),
      );
      final scope = _onlyChild(snapshot.root);
      final substation = _onlyChild(scope);
      final workList = _onlyChild(substation);
      final workBead = _onlyChild(workList);

      expect(
        [
          snapshot.root.seedType,
          scope.seedType,
          substation.seedType,
          workList.seedType,
          workBead.seedType,
        ],
        ['Station', 'SubstationScope', 'Substation', 'WorkList', 'WorkBead'],
      );
      expect(
        snapshot.toJson().toString(),
        isNot(anyOf(contains('InheritedSeed'), contains('_WorkBeads'))),
      );
    });

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

  group('engine descriptions', () {
    test('WorkBead emits bead and guarded session references', () {
      final bead = _task('tg-1');
      expect(_propertiesOf(WorkBead(bead: bead)), [
        isA<DiagnosticsReferenceProperty>()
            .having((p) => p.name, 'name', 'bead')
            .having((p) => p.referenceKind, 'kind', ReferenceKind.bead)
            .having((p) => p.value, 'value', 'tg-1'),
      ]);
      expect(
        _propertiesOf(WorkBead(bead: bead, session: _diagnosticsSession)),
        [
          isA<DiagnosticsReferenceProperty>().having(
            (p) => p.name,
            'name',
            'bead',
          ),
          isA<DiagnosticsReferenceProperty>()
              .having((p) => p.name, 'name', 'session')
              .having((p) => p.referenceKind, 'kind', ReferenceKind.session)
              .having((p) => p.value, 'value', 'tgdog-s'),
        ],
      );
    });

    test('SessionScope emits bead and guarded session references', () {
      final bead = _task('tg-1');
      expect(
        _propertiesOf(SessionScope(bead: bead, circuit: _diagnosticsCircuit)),
        [
          isA<DiagnosticsReferenceProperty>().having(
            (p) => p.name,
            'name',
            'bead',
          ),
        ],
      );
      expect(
        _propertiesOf(
          SessionScope(
            bead: bead,
            circuit: _diagnosticsCircuit,
            existingSession: _diagnosticsSession,
          ),
        ),
        [
          isA<DiagnosticsReferenceProperty>().having(
            (p) => p.name,
            'name',
            'bead',
          ),
          isA<DiagnosticsReferenceProperty>()
              .having((p) => p.name, 'name', 'session')
              .having((p) => p.referenceKind, 'kind', ReferenceKind.session)
              .having((p) => p.value, 'value', 'tgdog-s'),
        ],
      );
    });

    test('CircuitScope emits its node path as a string property', () {
      expect(
        _propertiesOf(
          const CircuitScope(
            circuit: _diagnosticsCircuit,
            cursor: {},
            nodePath: 'tg-1/sub',
          ),
        ),
        [
          isA<DiagnosticsStringProperty>()
              .having((p) => p.name, 'name', 'nodePath')
              .having((p) => p.value, 'value', 'tg-1/sub'),
        ],
      );
    });

    test(
      'CapabilityHostState exposes allocation as one typed object property',
      () async {
        final pending = Completer<StepOutcome>();
        final fakes = buildFakes();
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        final mount = StepMount(
          step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
          nodePath: 'tg-1/agent',
          circuit: _diagnosticsCircuit,
          circuitPath: 'tg-1',
          session: const SessionHandle('tgdog-s'),
          node: const NodeCursor(),
          key: const ValueKey('tg-1/agent#0.0'),
        );
        final root = owner.mountRoot(
          InheritedSeed<StationServices>(
            value: fakes.ctx,
            child: InheritedSeed<CapabilityRegistry>(
              value: RecordingCapabilityRegistry(clock: DateTime(2026)),
              child: InheritedSeed<InheritedCircuit>(
                value: InheritedCircuit(
                  root: BeadPathKey(const ['tg-1', 'tgdog-s', 'tgdog-step1']),
                  beadIdByNodePath: const {'tg-1/agent': 'tgdog-step1'},
                  cursor: const {},
                ),
                child: CapabilityHost(
                  capability: _PendingServiceCapability(pending),
                  mount: mount,
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final host = _allBranches(
          root,
        ).singleWhere((branch) => branch.seed is CapabilityHost);
        final properties = _propertiesOf(
          (host as StatefulBranch).state as CapabilityHostState,
        );

        expect(properties, hasLength(1));
        final allocation = properties.single as DiagnosticsObjectProperty;
        expect(allocation.name, 'allocation');
        expect(allocation.properties, hasLength(1));
        final nested = allocation.properties.single;
        final observed = switch (nested) {
          DiagnosticsStringProperty() => 'string',
          DiagnosticsIntProperty() => 'int',
          DiagnosticsDoubleProperty() => 'double',
          DiagnosticsFlagProperty() => 'flag',
          DiagnosticsEnumProperty(:final name, :final value, :final enumType) =>
            '$name:$enumType.$value',
          DiagnosticsDurationProperty() => 'duration',
          DiagnosticsTimestampProperty() => 'timestamp',
          DiagnosticsReferenceProperty() => 'reference',
          DiagnosticsObjectProperty() => 'object',
        };
        expect(observed, 'state:Enum.live');
      },
    );
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
