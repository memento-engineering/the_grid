import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

part 'view_state.freezed.dart';

/// A display-ready diagnostics property value.
@freezed
sealed class PropertyValue with _$PropertyValue {
  /// A string value.
  const factory PropertyValue.string(String value) = StringPropertyValue;

  /// An integer value.
  const factory PropertyValue.integer(int value) = IntPropertyValue;

  /// A decimal value.
  const factory PropertyValue.decimal(double value) = DoublePropertyValue;

  /// A boolean value.
  const factory PropertyValue.flag(bool value) = FlagPropertyValue;

  /// An enum value and its declaring type.
  const factory PropertyValue.enumeration(String value, String enumType) =
      EnumPropertyValue;

  /// A duration value.
  const factory PropertyValue.duration(Duration value) = DurationPropertyValue;

  /// A timestamp value.
  const factory PropertyValue.timestamp(DateTime value) =
      TimestampPropertyValue;

  /// A navigable reference value.
  const factory PropertyValue.reference(ReferenceKind kind, String value) =
      ReferencePropertyValue;

  /// A recursively nested property group.
  const factory PropertyValue.object(List<PropertyRowModel> properties) =
      ObjectPropertyValue;
}

/// Stable semantic severity used by cockpit presentation.
enum SeverityToken { fine, info, warning, error }

/// Stable visual states for work and pipeline steps.
enum StepVisualState {
  pending,
  running,
  ready,
  complete,
  failed,
  gated,
  unknown,
}

/// One display-ready diagnostics property row.
@freezed
abstract class PropertyRowModel with _$PropertyRowModel {
  /// Creates a property row.
  const factory PropertyRowModel({
    required String name,
    required SeverityToken severity,
    required PropertyValue value,
  }) = _PropertyRowModel;
}

/// Overview information about a diagnostics substation.
@freezed
abstract class SubstationSummary with _$SubstationSummary {
  /// Creates a substation summary.
  const factory SubstationSummary({
    required String nodeId,
    required String substationId,
    required int mountedWorkCount,
  }) = _SubstationSummary;
}

/// State projected for the cockpit overview.
@freezed
abstract class OverviewState with _$OverviewState {
  /// Creates overview state.
  const factory OverviewState({
    required DateTime projectedAt,
    required List<SubstationSummary> substations,
    required int activeWorkCount,
    required int warningCount,
    required int errorCount,
  }) = _OverviewState;
}

/// One work item projected for display.
@freezed
abstract class WorkItemView with _$WorkItemView {
  /// Creates a work item view.
  const factory WorkItemView({
    required String nodeId,
    required String beadId,
    String? sessionId,
    required StepVisualState state,
  }) = _WorkItemView;
}

/// State projected for the work list.
@freezed
abstract class WorkListState with _$WorkListState {
  /// Creates work-list state.
  const factory WorkListState({required List<WorkItemView> items}) =
      _WorkListState;
}

/// One node projected into a pipeline.
@freezed
abstract class PipelineNodeView with _$PipelineNodeView {
  /// Creates a pipeline node view.
  const factory PipelineNodeView({
    required String nodeId,
    required String label,
    required StepVisualState state,
    required int incarnationDepth,
    Duration? duration,
    required List<PipelineNodeView> children,
  }) = _PipelineNodeView;
}

/// State projected for the pipeline.
@freezed
abstract class PipelineState with _$PipelineState {
  /// Creates pipeline state.
  const factory PipelineState({required List<PipelineNodeView> roots}) =
      _PipelineState;
}

/// State projected for the diagnostics inspector.
@freezed
abstract class InspectorState with _$InspectorState {
  /// Creates inspector state.
  const factory InspectorState({
    required String nodeId,
    required String seedType,
    String? key,
    required List<PropertyRowModel> properties,
  }) = _InspectorState;
}

/// Aggregated token, cost, and grade data.
@freezed
abstract class CostRollupState with _$CostRollupState {
  /// Creates cost rollup state.
  const factory CostRollupState({
    int? inputTokens,
    int? outputTokens,
    double? costUsd,
    @Default(<String>[]) List<String> grades,
    required bool hasData,
  }) = _CostRollupState;
}
