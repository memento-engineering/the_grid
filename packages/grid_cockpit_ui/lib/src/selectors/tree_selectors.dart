import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

import '../models/view_state.dart';

/// Maps wire severity to a stable presentation token.
SeverityToken severityOf(DiagnosticsLevel level) => switch (level) {
  DiagnosticsLevel.fine => SeverityToken.fine,
  DiagnosticsLevel.info => SeverityToken.info,
  DiagnosticsLevel.warning => SeverityToken.warning,
  DiagnosticsLevel.error => SeverityToken.error,
};

/// Projects any diagnostics property into its display model.
PropertyRowModel propertyRowOf(DiagnosticsProperty property) =>
    switch (property) {
      DiagnosticsStringProperty(:final name, :final level, :final value) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.string(value),
        ),
      DiagnosticsIntProperty(:final name, :final level, :final value) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.integer(value),
        ),
      DiagnosticsDoubleProperty(:final name, :final level, :final value) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.decimal(value),
        ),
      DiagnosticsFlagProperty(:final name, :final level, :final value) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.flag(value),
        ),
      DiagnosticsEnumProperty(
        :final name,
        :final level,
        :final value,
        :final enumType,
      ) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.enumeration(value, enumType),
        ),
      DiagnosticsDurationProperty(:final name, :final level, :final value) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.duration(value),
        ),
      DiagnosticsTimestampProperty(:final name, :final level, :final value) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.timestamp(value),
        ),
      DiagnosticsReferenceProperty(
        :final name,
        :final level,
        :final referenceKind,
        :final value,
      ) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.reference(referenceKind, value),
        ),
      DiagnosticsObjectProperty(:final name, :final level, :final properties) =>
        PropertyRowModel(
          name: name,
          severity: severityOf(level),
          value: PropertyValue.object(
            List.unmodifiable(properties.map(propertyRowOf)),
          ),
        ),
    };

/// Projects a complete snapshot into overview state.
OverviewState overviewOf(TreeSnapshot snapshot) {
  final nodes = _nodesDepthFirst(snapshot.root).toList(growable: false);
  final substations = <SubstationSummary>[
    for (final node in nodes)
      if (node.seedType == 'Substation')
        SubstationSummary(
          nodeId: node.id,
          substationId:
              _textProperty(node.properties, 'substationId') ??
              node.key ??
              node.id,
          mountedWorkCount: _nodesDepthFirst(
            node,
          ).where((candidate) => candidate.seedType == 'WorkBead').length,
        ),
  ];
  var warningCount = 0;
  var errorCount = 0;
  for (final node in nodes) {
    for (final property in _propertiesDepthFirst(node.properties)) {
      switch (property.level) {
        case DiagnosticsLevel.warning:
          warningCount++;
        case DiagnosticsLevel.error:
          errorCount++;
        case DiagnosticsLevel.fine:
        case DiagnosticsLevel.info:
          break;
      }
    }
  }
  final workItems = nodes.where((node) => node.seedType == 'WorkBead');
  final activeWorkCount = workItems.where((node) {
    final state = _stepState(node);
    return state != StepVisualState.complete && state != StepVisualState.failed;
  }).length;
  return OverviewState(
    projectedAt: snapshot.projectedAt,
    substations: List.unmodifiable(substations),
    activeWorkCount: activeWorkCount,
    warningCount: warningCount,
    errorCount: errorCount,
  );
}

/// Projects all semantic work beads in depth-first order.
WorkListState workListOf(TreeSnapshot snapshot) => WorkListState(
  items: List.unmodifiable([
    for (final node in _nodesDepthFirst(snapshot.root))
      if (node.seedType == 'WorkBead')
        WorkItemView(
          nodeId: node.id,
          beadId:
              _textProperty(node.properties, 'beadId') ?? node.key ?? node.id,
          sessionId: _textProperty(node.properties, 'sessionId'),
          state: _stepState(node),
        ),
  ]),
);

/// Projects nodes carrying `stepState` into an ordered pipeline forest.
PipelineState pipelineOf(TreeSnapshot snapshot) =>
    PipelineState(roots: List.unmodifiable(_pipelineForest(snapshot.root)));

/// Projects one node into inspector state.
InspectorState inspectorOf(TreeSnapshot snapshot, String nodeId) {
  for (final node in _nodesDepthFirst(snapshot.root)) {
    if (node.id == nodeId) {
      return InspectorState(
        nodeId: node.id,
        seedType: node.seedType,
        key: node.key,
        properties: List.unmodifiable(node.properties.map(propertyRowOf)),
      );
    }
  }
  throw StateError('Diagnostics node not found: $nodeId');
}

/// Sums token and cost properties throughout the complete snapshot.
CostRollupState costRollupOf(TreeSnapshot snapshot) {
  int? inputTokens;
  int? outputTokens;
  double? costUsd;
  final grades = <String>[];
  for (final node in _nodesDepthFirst(snapshot.root)) {
    for (final property in _propertiesDepthFirst(node.properties)) {
      if (property.name == 'inputTokens') {
        final value = _integerValue(property);
        if (value != null) inputTokens = (inputTokens ?? 0) + value;
      } else if (property.name == 'outputTokens') {
        final value = _integerValue(property);
        if (value != null) outputTokens = (outputTokens ?? 0) + value;
      } else if (property.name == 'costUsd') {
        final value = _numericValue(property);
        if (value != null) costUsd = (costUsd ?? 0) + value;
      } else if (property.name == 'grade') {
        final value = _textValue(property);
        if (value != null) grades.add(value);
      }
    }
  }
  return CostRollupState(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    costUsd: costUsd,
    grades: List.unmodifiable(grades),
    hasData:
        inputTokens != null ||
        outputTokens != null ||
        costUsd != null ||
        grades.isNotEmpty,
  );
}

Iterable<TreeNode> _nodesDepthFirst(TreeNode node) sync* {
  yield node;
  for (final child in node.children) {
    yield* _nodesDepthFirst(child);
  }
}

Iterable<DiagnosticsProperty> _propertiesDepthFirst(
  List<DiagnosticsProperty> properties,
) sync* {
  for (final property in properties) {
    yield property;
    final children = switch (property) {
      DiagnosticsObjectProperty(:final properties) => properties,
      DiagnosticsStringProperty() ||
      DiagnosticsIntProperty() ||
      DiagnosticsDoubleProperty() ||
      DiagnosticsFlagProperty() ||
      DiagnosticsEnumProperty() ||
      DiagnosticsDurationProperty() ||
      DiagnosticsTimestampProperty() ||
      DiagnosticsReferenceProperty() => const <DiagnosticsProperty>[],
    };
    yield* _propertiesDepthFirst(children);
  }
}

List<PipelineNodeView> _pipelineForest(TreeNode node) {
  final projectedChildren = <PipelineNodeView>[
    for (final child in node.children) ..._pipelineForest(child),
  ];
  if (!_hasNamedProperty(node.properties, 'stepState')) {
    return projectedChildren;
  }
  final duration =
      _durationProperty(node.properties, 'duration') ??
      switch (_integerProperty(node.properties, 'durationMs')) {
        final milliseconds? => Duration(milliseconds: milliseconds),
        null => null,
      };
  return [
    PipelineNodeView(
      nodeId: node.id,
      label:
          _textProperty(node.properties, 'nodePath') ??
          node.key ??
          node.seedType,
      state: _stepState(node),
      incarnationDepth: node.properties
          .where(
            (property) =>
                property.name == 'supersedes' &&
                property is DiagnosticsReferenceProperty,
          )
          .length,
      duration: duration,
      children: List.unmodifiable(projectedChildren),
    ),
  ];
}

StepVisualState _stepState(TreeNode node) =>
    switch (_textProperty(node.properties, 'stepState')) {
      'pending' => StepVisualState.pending,
      'running' => StepVisualState.running,
      'ready' => StepVisualState.ready,
      'complete' => StepVisualState.complete,
      'failed' => StepVisualState.failed,
      'gated' => StepVisualState.gated,
      _ => StepVisualState.unknown,
    };

bool _hasNamedProperty(List<DiagnosticsProperty> properties, String name) =>
    properties.any((property) => property.name == name);

String? _textProperty(List<DiagnosticsProperty> properties, String name) {
  for (final property in properties) {
    if (property.name == name) return _textValue(property);
  }
  return null;
}

int? _integerProperty(List<DiagnosticsProperty> properties, String name) {
  for (final property in properties) {
    if (property.name == name) return _integerValue(property);
  }
  return null;
}

Duration? _durationProperty(List<DiagnosticsProperty> properties, String name) {
  for (final property in properties) {
    if (property.name == name) {
      return switch (property) {
        DiagnosticsDurationProperty(:final value) => value,
        DiagnosticsStringProperty() ||
        DiagnosticsIntProperty() ||
        DiagnosticsDoubleProperty() ||
        DiagnosticsFlagProperty() ||
        DiagnosticsEnumProperty() ||
        DiagnosticsTimestampProperty() ||
        DiagnosticsReferenceProperty() ||
        DiagnosticsObjectProperty() => null,
      };
    }
  }
  return null;
}

String? _textValue(DiagnosticsProperty property) => switch (property) {
  DiagnosticsStringProperty(:final value) => value,
  DiagnosticsEnumProperty(:final value) => value,
  DiagnosticsReferenceProperty(:final value) => value,
  DiagnosticsIntProperty() ||
  DiagnosticsDoubleProperty() ||
  DiagnosticsFlagProperty() ||
  DiagnosticsDurationProperty() ||
  DiagnosticsTimestampProperty() ||
  DiagnosticsObjectProperty() => null,
};

int? _integerValue(DiagnosticsProperty property) => switch (property) {
  DiagnosticsIntProperty(:final value) => value,
  DiagnosticsStringProperty() ||
  DiagnosticsDoubleProperty() ||
  DiagnosticsFlagProperty() ||
  DiagnosticsEnumProperty() ||
  DiagnosticsDurationProperty() ||
  DiagnosticsTimestampProperty() ||
  DiagnosticsReferenceProperty() ||
  DiagnosticsObjectProperty() => null,
};

double? _numericValue(DiagnosticsProperty property) => switch (property) {
  DiagnosticsIntProperty(:final value) => value.toDouble(),
  DiagnosticsDoubleProperty(:final value) => value,
  DiagnosticsStringProperty() ||
  DiagnosticsFlagProperty() ||
  DiagnosticsEnumProperty() ||
  DiagnosticsDurationProperty() ||
  DiagnosticsTimestampProperty() ||
  DiagnosticsReferenceProperty() ||
  DiagnosticsObjectProperty() => null,
};
