import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  GraphNode node(String key, String type, {String? parentId}) =>
      GraphNode(key: key, title: key, type: type, parentId: parentId);

  CanonicalMoleculeGraph graph({
    Iterable<GraphNode>? nodes,
    Iterable<CanonicalMoleculeEdge>? edges,
  }) => CanonicalMoleculeGraph(
    formula: 'code',
    commitMessage: 'pour code',
    nodeDefinitions:
        nodes ??
        [
          node('work', GridIssueTypes.molecule.wire, parentId: 'session-1'),
          node('work/z', GridIssueTypes.step.wire),
          node('work/nested', GridIssueTypes.molecule.wire),
          node('work/nested/a', GridIssueTypes.step.wire),
        ],
    edges:
        edges ??
        [
          CanonicalMoleculeEdge(
            fromPath: 'work/z',
            toPath: 'work/nested/a',
            kind: DependencyType.validates.wire,
          ),
          CanonicalMoleculeEdge(
            fromPath: 'work/nested/a',
            toPath: 'work/z',
            kind: DependencyType.blocks.wire,
          ),
        ],
  );

  test(
    'derives a sorted immutable graph and stable digest from input order',
    () {
      final first = graph();
      final second = graph(
        nodes: first.nodeDefinitions.reversed,
        edges: first.edges.reversed,
      );

      expect(first.nodes, ['work/nested/a', 'work/z']);
      expect(first.nodeCount, 2);
      expect(first.graph, {
        'edges': [
          {'from_path': 'work/nested/a', 'kind': 'blocks', 'to_path': 'work/z'},
          {
            'from_path': 'work/z',
            'kind': 'validates',
            'to_path': 'work/nested/a',
          },
        ],
        'nodes': ['work/nested/a', 'work/z'],
      });
      expect(second.graphDigest, first.graphDigest);
      expect(first.graphDigest, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(() => first.nodes.add('x'), throwsUnsupportedError);
      expect(
        () => (first.graph['edges']! as List<Object?>).add('x'),
        throwsUnsupportedError,
      );
    },
  );

  test('changing an edge kind changes the graph digest', () {
    final validates = graph(
      edges: [
        CanonicalMoleculeEdge(
          fromPath: 'work/z',
          toPath: 'work/nested/a',
          kind: DependencyType.validates.wire,
        ),
      ],
    );
    final blocks = graph(
      edges: [
        CanonicalMoleculeEdge(
          fromPath: 'work/z',
          toPath: 'work/nested/a',
          kind: DependencyType.blocks.wire,
        ),
      ],
    );
    expect(blocks.graphDigest, isNot(validates.graphDigest));
  });

  test('invalid semantic edge kinds refuse loudly', () {
    expect(
      () => CanonicalMoleculeEdge(
        fromPath: 'work/a',
        toPath: 'work/b',
        kind: DependencyType.parentChild.wire,
      ),
      throwsArgumentError,
    );
  });

  test('invalid node and semantic-endpoint shapes refuse loudly', () {
    expect(
      () => graph(
        nodes: [
          node('work', GridIssueTypes.molecule.wire, parentId: 'session-1'),
          node('work/not-a-step', 'task'),
        ],
        edges: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => graph(
        edges: [
          CanonicalMoleculeEdge(
            fromPath: 'work/z',
            toPath: 'work/missing',
            kind: DependencyType.blocks.wire,
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => graph(
        nodes: [
          node('work', GridIssueTypes.molecule.wire, parentId: 'session-1'),
          node('other', GridIssueTypes.molecule.wire, parentId: 'session-1'),
        ],
        edges: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => graph(
        nodes: [
          node('work', GridIssueTypes.molecule.wire, parentId: 'session-1'),
          const GraphNode(
            key: 'work/a',
            title: 'a',
            type: 'step',
            parentKey: 'work',
          ),
        ],
        edges: const [],
      ),
      throwsArgumentError,
    );
  });

  test('snapshots mutable inputs and exposes structural equality', () {
    final metadata = <String, String>{'mutable': 'before'};
    final inputNodes = <GraphNode>[
      GraphNode(
        key: 'work',
        title: 'work',
        type: GridIssueTypes.molecule.wire,
        parentId: 'session-1',
        metadata: metadata,
      ),
      node('work/a', GridIssueTypes.step.wire),
      node('work/b', GridIssueTypes.step.wire),
    ];
    final inputEdges = <CanonicalMoleculeEdge>[
      CanonicalMoleculeEdge(
        fromPath: 'work/b',
        toPath: 'work/a',
        kind: DependencyType.blocks.wire,
      ),
    ];
    final canonical = CanonicalMoleculeGraph(
      formula: 'code',
      commitMessage: 'pour code',
      nodeDefinitions: inputNodes,
      edges: inputEdges,
    );
    final equivalent = CanonicalMoleculeGraph(
      formula: 'code',
      commitMessage: 'pour code',
      nodeDefinitions: inputNodes,
      edges: inputEdges,
    );

    metadata['mutable'] = 'after';
    inputNodes.add(node('work/c', GridIssueTypes.step.wire));
    inputEdges.clear();

    expect(canonical, equivalent);
    expect(canonical.hashCode, equivalent.hashCode);
    expect(canonical.nodeDefinitions, hasLength(3));
    expect(canonical.edges, hasLength(1));
    expect(canonical.nodeDefinitions.first.metadata['mutable'], 'before');
    expect(
      () => canonical.nodeDefinitions.first.metadata['mutable'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((canonical.graph['edges']! as List<Object?>).single!
                  as Map<String, Object?>)['kind'] =
              'validates',
      throwsUnsupportedError,
    );
  });

  test('the legacy adapter reconstructs nearest parent-child edges only', () {
    final canonical = graph();
    final plan = canonical.toGraphApplyPlan();
    expect(plan.commitMessage, canonical.commitMessage);
    expect(plan.nodes.map((value) => value.key), [
      'work',
      'work/z',
      'work/nested',
      'work/nested/a',
    ]);
    expect(
      plan.edges.map((edge) => (edge.fromKey, edge.toKey, edge.type)).toSet(),
      {
        ('work/z', 'work', DependencyType.parentChild.wire),
        ('work/nested', 'work', DependencyType.parentChild.wire),
        ('work/nested/a', 'work/nested', DependencyType.parentChild.wire),
        ('work/nested/a', 'work/z', DependencyType.blocks.wire),
        ('work/z', 'work/nested/a', DependencyType.validates.wire),
      },
    );
    expect(
      (canonical.graph['edges']! as List<Object?>).toString().contains(
        DependencyType.parentChild.wire,
      ),
      isFalse,
    );
  });

  test('a non-root node without a molecule ancestor refuses adaptation', () {
    final malformed = CanonicalMoleculeGraph(
      formula: 'bad',
      commitMessage: 'bad graph',
      nodeDefinitions: [
        node('root', GridIssueTypes.molecule.wire, parentId: 'session-1'),
        node('orphan', GridIssueTypes.step.wire),
      ],
      edges: const [],
    );
    expect(malformed.toGraphApplyPlan, throwsStateError);
  });
}
