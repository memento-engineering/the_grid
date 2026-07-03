import 'package:freezed_annotation/freezed_annotation.dart';

part 'projection_error.freezed.dart';

/// A typed decode failure surfaced by a projection's `project` factory.
///
/// Projections never throw past their boundary and never silently drop a bead:
/// when a bead cannot be decoded into its domain value type (wrong issue type,
/// missing required field, malformed metadata), the projector returns a
/// [ProjectionError] instead. Consumers can fold the failures into diagnostics
/// while the successful projections flow through.
@freezed
abstract class ProjectionError with _$ProjectionError {
  const ProjectionError._();

  const factory ProjectionError({
    /// The bead the projector was decoding.
    required String beadId,

    /// The bead's issue type wire string (for context in diagnostics).
    required String issueType,

    /// The projection that was attempted (e.g. `AgentSession`, `Molecule`).
    required String projection,

    /// Human-readable reason the decode failed.
    required String reason,
  }) = _ProjectionError;

  @override
  String toString() =>
      'ProjectionError($projection <- $beadId [$issueType]: $reason)';
}

/// The outcome of projecting a single bead: either the value [T] or a typed
/// [ProjectionError]. A lightweight sealed result so projectors stay total —
/// no thrown exceptions cross the boundary.
sealed class ProjectionResult<T> {
  const ProjectionResult();

  /// The projected value when this is an [ProjectionOk], else null.
  T? get valueOrNull => switch (this) {
    ProjectionOk<T>(:final value) => value,
    ProjectionFailed<T>() => null,
  };

  /// The error when this is a [ProjectionFailed], else null.
  ProjectionError? get errorOrNull => switch (this) {
    ProjectionOk<T>() => null,
    ProjectionFailed<T>(:final error) => error,
  };

  bool get isOk => this is ProjectionOk<T>;
}

/// A successful projection.
final class ProjectionOk<T> extends ProjectionResult<T> {
  const ProjectionOk(this.value);
  final T value;
}

/// A failed projection carrying its typed [error].
final class ProjectionFailed<T> extends ProjectionResult<T> {
  const ProjectionFailed(this.error);
  final ProjectionError error;
}
